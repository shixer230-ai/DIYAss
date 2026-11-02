import 'dart:math';

import '../models/build_plan.dart';
import '../models/custom_item.dart';
import '../models/hardware_spec.dart';

/// 一个「分析项目」：某品类下的跑分项，或「整机功耗」这类整机指标
class ValueItem {
  final String label; // 显示名，如「CPU-Z 单核」
  final String category; // 所属品类：CPU / 显卡 / 整机
  final String benchLabel; // 硬件库 benchmarks 里的条目名（整机功耗无此项，占位）
  final bool lowerIsBetter; // 数值越小越好（整机功耗用）
  final bool weighted; // 用「指数权重」而非线性 bench/price（单核用）

  const ValueItem(this.label, this.category, this.benchLabel,
      {this.lowerIsBetter = false, this.weighted = false});
}

/// 可选的分析项目（跑分覆盖 CPU+显卡，另加整机功耗）
const kValueItems = [
  ValueItem('CPU-Z 单核', 'CPU', 'CPU-Z 单核', weighted: true),
  ValueItem('CPU-Z 多核', 'CPU', 'CPU-Z 多核'),
  ValueItem('Cinebench R23 多核', 'CPU', 'Cinebench R23 多核'),
  ValueItem('3DMark Time Spy', '显卡', '3DMark Time Spy'),
  ValueItem('3DMark Fire Strike', '显卡', '3DMark Fire Strike'),
  ValueItem('3DMark Port Royal', '显卡', '3DMark Port Royal'),
  ValueItem('整机功耗', '整机', '整机功耗', lowerIsBetter: true),
];

/// 一个方案在某性价比项目下的结果
class PlanValue {
  final String planName;
  final String partModel; // 参与评分的部件型号
  final double bench; // 该跑分项的数值
  final double price; // 方案总价
  final double index; // 性价比指数 = bench / price * 1000

  const PlanValue({
    required this.planName,
    required this.partModel,
    required this.bench,
    required this.price,
    required this.index,
  });
}

/// 把「约 16900」这类字符串解析成数字；失败返回 null
double? parseBench(String value) {
  final m = RegExp(r'\d[\d,]*\.?\d*').firstMatch(value);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', ''));
}

/// 按「品类+型号」匹配型号；先精确匹配，再互相包含，最后核心 token 兜底，找不到返回 null
HardwareSpec? findSpec(String category, String model, List<HardwareSpec> lib) {
  final normModel = _norm(model);
  if (normModel.isEmpty) return null;
  HardwareSpec? fallback;
  HardwareSpec? tokenMatch;
  for (final s in lib) {
    if (s.category != category) continue;
    final normSpec = _norm(s.model);
    if (normSpec == normModel) return s;
    if (fallback == null &&
        (normSpec.contains(normModel) || normModel.contains(normSpec))) {
      fallback = s;
    }
    // 非公版长名（如「蓝宝石 RX 6500 XT 白金版 OC」）既不等于也不包含库里型号，
    // 用核心数字 token（6500xt）做最后兜底
    if (tokenMatch == null && _shareCoreToken(normModel, normSpec)) {
      tokenMatch = s;
    }
  }
  return fallback ?? tokenMatch;
}

/// 取部件在指定跑分项下的数值；找不到返回 null
double? valueOf(PlanComponent comp, String benchLabel, List<HardwareSpec> lib) {
  final spec = findSpec(comp.category, comp.model, lib);
  if (spec == null) return null;
  for (final b in spec.benchmarks) {
    if (b.label == benchLabel) return parseBench(b.value);
  }
  return null;
}

/// 取配件功耗（W）：CPU 读「默认TDP」，显卡读「功耗」
double? powerOf(PlanComponent comp, List<HardwareSpec> lib) {
  final spec = findSpec(comp.category, comp.model, lib);
  if (spec == null) return null;
  String? label;
  if (comp.category == 'CPU') {
    label = '默认TDP';
  } else if (comp.category == '显卡') {
    label = '功耗';
  }
  if (label == null) return null;
  for (final s in spec.specs) {
    if (s.label == label) return parseBench(s.value);
  }
  return null;
}

/// 整机功耗：累加 CPU/显卡 功耗；数据不全返回 null（不该上榜）
double? totalPower(BuildPlan plan, List<HardwareSpec> lib) {
  var total = 0.0;
  var counted = 0;
  for (final comp in plan.components.values) {
    if (comp.category != 'CPU' && comp.category != '显卡') continue;
    final p = powerOf(comp, lib);
    if (p == null) return null;
    total += p;
    counted++;
  }
  return counted == 0 ? null : total;
}

/// 按给定项目计算性价比并排序；缺数据或匹配不到跑分的方案跳过
List<PlanValue> rankPlans(
  List<BuildPlan> plans,
  ValueItem item,
  List<HardwareSpec> lib,
) {
  // 整机功耗：数值越小越好
  if (item.category == '整机') {
    final results = <PlanValue>[];
    for (final plan in plans) {
      final auto = totalPower(plan, lib);
      final custom = plan.customPower;
      // 用户自定义功耗优先，但不低于默认 CPU+显卡 功耗
      double? power;
      if (custom != null) {
        power = auto == null ? custom : (custom < auto ? auto : custom);
      } else {
        power = auto;
      }
      if (power == null || power <= 0 || plan.total <= 0) continue;
      results.add(PlanValue(
        planName: plan.name.isEmpty ? '未命名方案' : plan.name,
        partModel: '整机功耗',
        bench: power,
        price: plan.total,
        index: power,
      ));
    }
    results.sort((a, b) => a.index.compareTo(b.index));
    return results;
  }

  // 单核用「指数权重」算法（权重÷价格），不走线性 bench/price
  if (item.weighted) return rankWeightedPlans(plans, item, lib);

  final slotKey = item.category == 'CPU' ? 'cpu' : 'gpu';
  final results = <PlanValue>[];
  for (final plan in plans) {
    final comp = plan[slotKey];
    if (comp == null) continue;
    final bench = valueOf(comp, item.benchLabel, lib);
    if (bench == null || plan.total <= 0) continue;
    results.add(PlanValue(
      planName: plan.name.isEmpty ? '未命名方案' : plan.name,
      partModel: comp.model,
      bench: bench,
      price: plan.total,
      index: bench / plan.total * 1000,
    ));
  }
  results.sort((a, b) => b.index.compareTo(a.index));
  return results;
}

/// 单核性价比「指数权重」算法（权重 ÷ 整机价格）
/// 最低分权重 10000；相邻两两比较，每高 20% 权重翻倍：weight *= 2^(pct/0.2)
/// 缺 CPU、单核跑分匹配不到、或总价为 0 的方案跳过
List<PlanValue> rankWeightedPlans(
  List<BuildPlan> plans,
  ValueItem item,
  List<HardwareSpec> lib,
) {
  const baseWeight = 10000.0;
  const doublePerWeight = 0.2; // 每高 20% 权重翻倍

  final entries = <_WeightedEntry>[];
  for (final plan in plans) {
    final comp = plan['cpu'];
    if (comp == null) continue;
    final bench = valueOf(comp, item.benchLabel, lib);
    if (bench == null || bench <= 0 || plan.total <= 0) continue;
    entries.add(_WeightedEntry(plan, comp.model, bench));
  }
  if (entries.isEmpty) return const [];

  entries.sort((a, b) => b.bench.compareTo(a.bench));

  // 从最低分往上累加权值
  final n = entries.length;
  final weights = List<double>.filled(n, 0);
  weights[n - 1] = baseWeight;
  for (var i = n - 2; i >= 0; i--) {
    final pct = entries[i].bench / entries[i + 1].bench - 1;
    weights[i] = weights[i + 1] * pow(2.0, pct / doublePerWeight).toDouble();
  }

  final results = <PlanValue>[];
  for (var i = 0; i < n; i++) {
    final e = entries[i];
    results.add(PlanValue(
      planName: e.plan.name.isEmpty ? '未命名方案' : e.plan.name,
      partModel: e.model,
      bench: e.bench,
      price: e.plan.total,
      index: weights[i] / e.plan.total * 100,
    ));
  }
  results.sort((a, b) => b.index.compareTo(a.index));
  return results;
}

/// 指数权重算法里的中间记录：方案 + 单核分数
class _WeightedEntry {
  final BuildPlan plan;
  final String model;
  final double bench;

  const _WeightedEntry(this.plan, this.model, this.bench);
}

/// 按「自定义项目」算性价比（分数÷总价×1000）并降序；没填分数或总价为 0 的跳过
List<PlanValue> rankCustomPlans(List<BuildPlan> plans, CustomItem item) {
  final results = <PlanValue>[];
  for (final plan in plans) {
    final s = item.scoreOf(plan.id);
    if (s == null || plan.total <= 0) continue;
    results.add(PlanValue(
      planName: plan.name.isEmpty ? '未命名方案' : plan.name,
      partModel: item.scoreLabel,
      bench: s,
      price: plan.total,
      index: s / plan.total * 1000,
    ));
  }
  results.sort((a, b) => b.index.compareTo(a.index));
  return results;
}

/// 提取型号名里的「数字 + 字母后缀」核心 token（如 6500xt、14900k）
/// 用来把「蓝宝石 RX 6500 XT 白金版 OC」这类非公长名对齐到库里的标准型号
Set<String> _coreTokens(String norm) {
  return RegExp(r'\d+[a-z]*')
      .allMatches(norm)
      .map((m) => m.group(0)!)
      .where((t) => t.length >= 4)
      .toSet();
}

/// 两个型号名（已规范化）是否共享核心数字 token，用于非公型号兜底匹配
bool _shareCoreToken(String a, String b) {
  final tokens = _coreTokens(a);
  if (tokens.isEmpty) return false;
  return tokens.any((t) => b.contains(t));
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
