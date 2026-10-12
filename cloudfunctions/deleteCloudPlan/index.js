// 删除云方案：登录校验 + 只能删自己上传的方案（不占每日次数）
// 无需环境变量；用法：App 端调 callFunction('deleteCloudPlan', { planId })

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
    return { error: '需要登录后才能删除方案' };
  }

  const planId = event && (event.planId || (event.data && event.data.planId));
  if (typeof planId !== 'string' || !planId.trim()) {
    return { error: '方案 id 无效' };
  }

  const db = app.database();

  // 方案存在性 + 归属校验（只删自己的）
  let plan = null;
  try {
    const res = await db.collection('cloud_plans').doc(planId).get();
    plan = res && res.data && res.data[0];
  } catch (e) {}
  if (!plan) return { error: '方案不存在或已删除' };
  if (String(plan.owner || '') !== uid) {
    return { error: '只能删除自己上传的方案' };
  }

  try {
    await db.collection('cloud_plans').doc(planId).remove();
    return { ok: true };
  } catch (e) {
    return { error: '删除失败，请重试' };
  }
};
