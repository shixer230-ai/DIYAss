import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/default_plans.dart';
import '../models/build_plan.dart';
import '../utils/json_safe.dart';

/// 保存多个「整机方案」以及当前选中的方案 id
class BuildPlanStore {
  static const _plansKey = 'build_plans';
  static const _currentKey = 'build_plan_current_id';
  static const _pendingKey = 'build_plan_pending_delete'; // 待补删云端的方案 id
  static const _legacyKey = 'build_plan'; // 旧版单个方案，迁移后删除
  static const _seededKey = 'build_plan_defaults_seeded'; // 是否已写入默认配置

  Future<List<BuildPlan>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_plansKey);
    if (raw != null && raw.isNotEmpty) {
      final plans =
          decodeMapList(raw).map((e) => BuildPlan.fromJson(e)).toList();
      // 旧版本写入的默认方案价格全为 0：若用户尚未给它填过任何价格，自动升级为带参考价的新版默认方案；
      // 只要用户改过任一配件价格（total > 0），一律保留原样不覆盖。
      final defaultsById = {for (final d in kDefaultPlans) d.id: d};
      var upgraded = false;
      for (var i = 0; i < plans.length; i++) {
        final d = defaultsById[plans[i].id];
        if (d != null && plans[i].total <= 0) {
          plans[i] = BuildPlan.fromJson(d.toJson());
          upgraded = true;
        }
      }
      if (upgraded) await saveAll(plans);
      return plans;
    }
    // 迁移旧版单个方案（key = build_plan）
    final legacy = prefs.getString(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      final oldJson = decodeMap(legacy);
      if (oldJson != null) {
        final old = BuildPlan.fromJson(oldJson);
        final migrated = [
          BuildPlan(id: old.id, name: '方案 1', components: old.components),
        ];
        await prefs.remove(_legacyKey);
        await saveAll(migrated);
        await prefs.setBool(_seededKey, true);
        return migrated;
      }
    }
    // 首次启动且从未播种过：写入 5 套默认配置
    if (!(prefs.getBool(_seededKey) ?? false)) {
      await prefs.setBool(_seededKey, true);
      await saveAll(kDefaultPlans);
      // 返回新实例，避免多处共享同一 list 引用
      return kDefaultPlans.map((p) => BuildPlan.fromJson(p.toJson())).toList();
    }
    return [];
  }

  Future<void> saveAll(List<BuildPlan> plans) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(plans.map((e) => e.toJson()).toList());
    await prefs.setString(_plansKey, raw);
  }

  Future<String?> loadCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentKey);
  }

  Future<void> saveCurrentId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_currentKey);
    } else {
      await prefs.setString(_currentKey, id);
    }
  }

  /// 读取「待补删云端」的方案 id（离线删除时记下的墓碑）
  Future<Set<String>> loadPendingDeleteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // 坏数据直接当空，不影响主流程
    }
    return <String>{};
  }

  Future<void> savePendingDeleteIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, jsonEncode(ids.toList()));
    }
  }
}
