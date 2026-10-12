// 点赞云方案：登录校验 + 切换点赞（赞 / 取消赞），返回最新点赞状态与数量
// 用法：App 端调 callFunction('likePlan', { planId })

const cloudbase = require('@cloudbase/node-sdk');

const app = cloudbase.init({ env: cloudbase.SYMBOL_CURRENT_ENV });

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

exports.main = async (event, context) => {
  const uid = getUid();
  if (!uid) {
    return { error: '需要登录后才能点赞' };
  }

  const planId = event && (event.planId || (event.data && event.data.planId));
  if (typeof planId !== 'string' || !planId.trim()) {
    return { error: '方案 id 无效' };
  }

  const db = app.database();

  // 方案存在性 + 当前点赞人列表
  let plan = null;
  try {
    const res = await db.collection('cloud_plans').doc(planId).get();
    plan = res && res.data && res.data[0];
  } catch (e) {}
  if (!plan) return { error: '方案不存在或已删除' };

  const likers = Array.isArray(plan.likers) ? plan.likers.slice() : [];
  const idx = likers.indexOf(uid);
  const already = idx >= 0;
  if (already) {
    likers.splice(idx, 1);
  } else {
    likers.push(uid);
  }

  try {
    await db.collection('cloud_plans').doc(planId).update({ likers });
    return { ok: true, liked: !already, likeCount: likers.length };
  } catch (e) {
    return { error: '操作失败，请重试' };
  }
};
