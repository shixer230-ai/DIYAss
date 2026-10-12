// 定时清理云方案：删除「0 赞 + 发布满 7 天」的旧方案，避免「云方案」栏目堆积无人问津的旧内容
// 由「定时触发器」调用（无登录态，以云函数身份运行，拥有全部集合读写权限），无需环境变量
// 部署后请在控制台给本函数配置「定时触发器」：每天跑一次（cron 见 config.json）

const cloudbase = require('@cloudbase/node-sdk');

const app = cloudbase.init({ env: cloudbase.SYMBOL_CURRENT_ENV });

// 点赞数低于该值才删（即「0 赞」）
const MIN_LIKES = 1;

// 发布满多少天才删
const MIN_AGE_DAYS = 7;

// 单次最多扫描多少条（每天跑一次，防止一次处理过多）
const MAX_BATCH = 200;

exports.main = async (event, context) => {
  const db = app.database();
  const _ = db.command;

  const cutoff = Date.now() - MIN_AGE_DAYS * 24 * 3600 * 1000;

  // 先按发布时间筛出足够老的方案（likers 是数组，无法直接按长度查，取回后逐个判断点赞数）
  let oldPlans = [];
  try {
    const res = await db
      .collection('cloud_plans')
      .where({ createdAt: _.lt(cutoff) })
      .limit(MAX_BATCH)
      .get();
    oldPlans = (res && res.data) || [];
  } catch (e) {
    return { error: '查询失败：' + (e && e.message ? e.message : e) };
  }

  let deleted = 0;
  let skipped = 0;
  for (const p of oldPlans) {
    const likers = Array.isArray(p.likers) ? p.likers : [];
    // 有赞的保留，只删 0 赞的老方案
    if (likers.length >= MIN_LIKES) continue;
    const id = p._id || p.id;
    if (!id) continue;
    try {
      await db.collection('cloud_plans').doc(id).remove();
      deleted++;
    } catch (e) {
      // 单个删除失败跳过，不影响整体
      skipped++;
    }
  }

  return { ok: true, scanned: oldPlans.length, deleted, skipped };
};
