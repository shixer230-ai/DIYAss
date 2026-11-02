// AI 分析云函数：校验登录 + 限流 + 用云端环境变量的 DeepSeek Key 调 AI
// Key 只存在这里的环境变量里，App 拿不到也不会打进安装包

const cloudbase = require('@cloudbase/node-sdk');
const https = require('https');

const app = cloudbase.init({ env: cloudbase.SYMBOL_CURRENT_ENV });

// 常规分析的系统提示词（改这里统一生效）
const SYSTEM_PROMPT = `你是一名资深 DIY 装机专家。请根据用户提供的整机配置做分析，务必遵守：
1. 最近内存和存储芯片价格上涨幅度较大，这方面金额偏高是正常现象，不要因此批评用户。
2. 一定不要评价「性价比」，只说说在哪些方面性价比较高即可。
3. 不要锐评用户的选择，给用户良好体验，只提出合理建议。
4. 如果配置里用了垃圾佬（二手/老旧高性价比）型号，侧重性价比分析；否则侧重稳定性分析。
5. 严格按以下固定格式输出（约 512 tokens），不要输出任何多余内容，每个板块下用「- 」分点罗列（每点单独一行，不要写成一整段）：
此方案的亮点是:
    - （要点1）
    - （要点2）

方案侧重:
    - （如单机游戏 3A、网游、内容创作、服务器主机等哪一方面）

注意:
    - （此方案的局限性；若没有则写「方案完备」）
    - （注意主板供电、兼容性等方面）

其它事项:
    - （超频潜力、稳定性等）`;

// 可靠性分析系统提示词（mode='reliability' 时用）
const RELIABILITY_SYSTEM_PROMPT = `你是一名资深 DIY 装机硬件检测专家。请根据用户提供的整机配置做「可靠性分析」，评估这套配置的稳定性与耐用风险，务必遵守：
1. 只分析可靠性：不评价价格、不评价性价比，也不比较各配件价格高低。
2. 功耗稳定性：评估整机功耗是否合理、电源（若有标注）功率是否足够、有无供电或散热隐患。
3. 硬件稳定性：
   - 识别「魔改 CPU」（笔记本 CPU 改台式、寨板、工程样品 ES 版等）及其潜在风险（无官方保修、温度/兼容性问题等）。
   - 判断显卡是否可能经历过「矿潮」（矿卡）：结合型号、年份、显存类型，判断翻新/矿卡风险，并给出选购建议。
   - 评估二手、洋垃圾、杂牌、翻新硬件的稳定性风险；注意语气客观，不要贬低「洋垃圾」——它们性价比高是事实，只客观说明风险即可。
4. 严格按以下固定格式输出（约 512 tokens），不要输出任何多余内容，每个板块下用「- 」分点罗列（每点单独一行，不要写成一整段）：
功耗稳定性:
    - （要点）

硬件稳定性:
    - （要点）

潜在风险:
    - （要点）

购买建议:
    - （要点）`;

// 配置单解析提示词（mode='parse' 时用）：从 OCR 文字提取硬件清单，返回 JSON
const PARSE_SYSTEM_PROMPT = `你是一名硬件配置单解析器。用户会给你一段从电商截图 OCR 识别出的文字，请提取出所有硬件配件的「品类、品牌、型号、价格」，并以严格 JSON 格式返回。
要求：
1. 品类 category 只能是这些值之一：CPU、主板、显卡、内存、硬盘、电源、机箱、散热。
2. 品牌 brand、型号 model 从原文提取，提取不到就填空字符串。
3. 价格 price 是数字（元），提取不到就填 0。
4. 只输出 JSON，不要输出任何解释文字，不要用 markdown 代码块包裹。

输出格式示例：
{"items":[{"category":"CPU","brand":"Intel","model":"酷睿 i9-14900K","price":1899}]}

识别不到任何硬件时返回 {"items":[]}`;

// 每人每天上限（防滥用）
const DAILY_LIMIT = 20;

// 捐赠用户每天上限
const DONATOR_DAILY_LIMIT = 50;

// 用户消息最大长度
const MAX_PROMPT_LEN = 4000;

// 取当前登录用户 uid；只用官方 API，不读 context 里的运行身份字段（防公网绕过登录）
function getUid() {
  try {
    const info = app.auth().getUserInfo();
    const v = info && (info.uid || info.customUserId || info.openId);
    return v ? String(v).trim() : '';
  } catch (e) {
    return '';
  }
}

// 是否捐赠用户（donators 集合里 enabled=true，文档 id 用 uid）
async function isDonator(uid) {
  try {
    const db = app.database();
    const res = await db.collection('donators').doc(uid).get();
    const row = res && res.data && res.data[0];
    return !!(row && row.enabled === true);
  } catch (e) {
    return false;
  }
}

// 用 https 直连 DeepSeek（无第三方依赖）
function callDeepSeek(apiKey, prompt, systemPrompt) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: 'deepseek-chat',
      stream: false,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: prompt },
      ],
    });
    const req = https.request(
      {
        hostname: 'api.deepseek.com',
        path: '/chat/completions',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: 60000,
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          let json = null;
          try { json = JSON.parse(data); } catch (e) {}
          if (res.statusCode !== 200) {
            const msg = (json && json.error && json.error.message) || `HTTP ${res.statusCode}`;
            reject(new Error(msg));
            return;
          }
          const content = json && json.choices && json.choices[0] &&
            json.choices[0].message && json.choices[0].message.content;
          if (!content) { reject(new Error('AI 未返回内容，请重试')); return; }
          resolve(content);
        });
      }
    );
    req.on('timeout', () => { req.destroy(new Error('调用 AI 超时，请重试')); });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

exports.main = async (event, context) => {
  // 登录校验
  const uid = getUid();
  if (!uid) {
    return { error: '需要登录后才能使用 AI 分析' };
  }

  // 输入合规
  const prompt = event && (event.prompt || (event.data && event.data.prompt));
  if (typeof prompt !== 'string' || prompt.trim().length === 0) {
    return { error: '方案内容为空，无法分析' };
  }
  if (prompt.length > MAX_PROMPT_LEN) {
    return { error: '方案内容过长，无法分析' };
  }

  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    return { error: '未配置 AI 接口 Key（请在云函数环境变量里填 DEEPSEEK_API_KEY）' };
  }

  // 限流：按用户+日期记次数，捐赠用户放宽到 50，失败不阻断
  try {
    const db = app.database();
    // 用北京时间（UTC+8）算日期
    const date = new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
    const docId = `${uid}_${date}`;
    const usage = await db.collection('ai_usage').doc(docId).get();
    const row = usage && usage.data && usage.data[0];
    const count = (row && row.count) || 0;
    const limit = (await isDonator(uid)) ? DONATOR_DAILY_LIMIT : DAILY_LIMIT;
    if (count >= limit) {
      return { error: `今日 AI 分析次数已用完（每天 ${limit} 次）` };
    }
    await db.collection('ai_usage').doc(docId).set({ count: count + 1, uid, date });
  } catch (e) {
    // 失败不阻断
  }

  // 调 DeepSeek 返回
  try {
    // reliability 走可靠性分析，否则常规
    const mode = event && event.mode;
    const systemPrompt =
      mode === 'reliability'
        ? RELIABILITY_SYSTEM_PROMPT
        : mode === 'parse'
        ? PARSE_SYSTEM_PROMPT
        : SYSTEM_PROMPT;
    const content = await callDeepSeek(apiKey, prompt, systemPrompt);
    return { content };
  } catch (e) {
    return { error: e && e.message ? e.message : String(e) };
  }
};
