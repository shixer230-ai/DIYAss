// 方案上传云函数：登录校验 + 每日限额（普通 3 次 / 捐赠 5 次）+ 关键词内容合规检测 + 写入 cloud_plans
// 无需环境变量；内容检测用本地关键词过滤，不调 AI、不花 API 钱
// 用法：App 端调 callFunction('publishPlan', { plan: BuildPlan.toJson() })

const cloudbase = require('@cloudbase/node-sdk');

const app = cloudbase.init({ env: cloudbase.SYMBOL_CURRENT_ENV });

// 普通用户每天上传上限
const DAILY_LIMIT = 3;

// 捐赠用户每天上传上限
const DONATOR_DAILY_LIMIT = 5;

// 方案名最长
const MAX_NAME_LEN = 50;

// 单方案最多配件数（含多块硬盘）
const MAX_COMPONENTS = 16;

// 敏感词黑名单（色情/低俗/赌博/违禁等违规内容），命中即判违规
const SENSITIVE_WORDS = [
  // 色情 / 低俗
  '色情', '裸聊', '裸照', '黄片', '成人', '约炮', '援交', '卖淫', '嫖娼',
  '一夜情', '色情直播', '艳照', '走光', '萝莉', '幼女', '自慰', '性交',
  // 赌博
  '赌博', '博彩', '赌场', '六合彩', '时时彩', '老虎机',
  // 违禁
  '毒品', '冰毒', '大麻', '枪支', '军火', '假币', '代开发票', '办假证',
];

// 广告/引流/与 DIY 无关词黑名单，命中即判违规
const UNRELATED_WORDS = [
  '微信号', '加微信', '加v', '加群', '进群', 'qq群', '微信群', '加我',
  '兼职', '刷单', '刷钻', '代购', '代练', '贷款', '借贷', '投资理财',
  '加盟', '微商', '招收代理', '扫码领', '翻墙', '电报', 'vpn',
];

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

// 把方案转成一段供检测的文本（用中文品类名，便于关键词命中）
function planToText(plan) {
  const parts = ['方案名：' + String(plan.name || '')];
  const components = (plan.components && typeof plan.components === 'object') ? plan.components : {};
  for (const k in components) {
    const c = components[k] || {};
    parts.push(String(c.category || k) + '：' + String(c.model || '') + ' ' + String(c.brand || ''));
  }
  const storages = Array.isArray(plan.storages) ? plan.storages : [];
  for (const c of storages) {
    parts.push('硬盘：' + String(c.model || '') + ' ' + String(c.brand || ''));
  }
  return parts.join('\n');
}

// 关键词合规检测：命中敏感词或明显无关词则判违规，否则合规
function checkCompliance(text) {
  const t = String(text || '').toLowerCase();
  for (const w of SENSITIVE_WORDS) {
    if (t.includes(w.toLowerCase())) return false;
  }
  for (const w of UNRELATED_WORDS) {
    if (t.includes(w.toLowerCase())) return false;
  }
  return true;
}

exports.main = async (event, context) => {
  const uid = getUid();
  if (!uid) {
    return { error: '需要登录后才能上传方案' };
  }

  const plan = event && (event.plan || (event.data && event.data.plan));
  if (!plan || typeof plan !== 'object') {
    return { error: '方案数据无效' };
  }

  // 方案名校验
  const name = String(plan.name || '').trim();
  if (!name) return { error: '方案名不能为空' };
  if (name.length > MAX_NAME_LEN) return { error: `方案名过长（最多 ${MAX_NAME_LEN} 字）` };

  // 配件数量校验
  const components = (plan.components && typeof plan.components === 'object') ? plan.components : {};
  const storages = Array.isArray(plan.storages) ? plan.storages : [];
  const compCount = Object.keys(components).length + storages.length;
  if (compCount === 0) return { error: '方案还没有配件，无法上传' };
  if (compCount > MAX_COMPONENTS) return { error: '方案配件数量异常' };

  const db = app.database();

  // 每日限额：按用户 + 北京时间日期记次数
  const date = new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
  const quotaDoc = `${uid}_${date}`;
  const limit = (await isDonator(uid)) ? DONATOR_DAILY_LIMIT : DAILY_LIMIT;
  try {
    const usage = await db.collection('publish_logs').doc(quotaDoc).get();
    const row = usage && usage.data && usage.data[0];
    const count = (row && row.count) || 0;
    if (count >= limit) {
      return { error: `今日上传次数已用完（每天 ${limit} 次）` };
    }
  } catch (e) {
    // 查询失败不阻断
  }

  // 关键词内容合规检测（本地过滤，不调 AI）
  const text = planToText(plan);
  if (!checkCompliance(text)) {
    return { error: '方案内容未通过审核，请确保与 DIY 装机相关、不含色情或广告等无关内容' };
  }

  // 写入公开方案
  const id = `cloud_${uid}_${Date.now()}`;
  try {
    await db.collection('cloud_plans').doc(id).set({
      id,
      owner: uid,
      plan,
      likers: [],
      createdAt: Date.now(),
      date,
    });
    // 记一次上传次数
    const usage = await db.collection('publish_logs').doc(quotaDoc).get();
    const row = usage && usage.data && usage.data[0];
    const count = (row && row.count) || 0;
    await db.collection('publish_logs').doc(quotaDoc).set({ count: count + 1, uid, date });
    return { ok: true, id };
  } catch (e) {
    return { error: '上传失败，请重试' };
  }
};
