import 'dart:math' as math;

import '../models/build_plan.dart';
import '../models/hardware_spec.dart';
import 'compat_check.dart';
import 'value_index.dart';

/// 六维雷达图的一根轴：score 统一为 0..1，越大越好
class RadarAxis {
  final String label; // 轴名（图内显示）
  final double score; // 0..1，越大越好
  final String rawText; // 原始值文字（如「760」「180W」「4 级」）
  final double? numValue; // 原始数值大小，载入动画时从 0 数到它；非数值轴为 null

  const RadarAxis({
    required this.label,
    required this.score,
    required this.rawText,
    this.numValue,
  });

  /// 是否超过 100%（用于高亮显示「附加分」）
  bool get over => score > 1.0;

  /// 载入动画中的原始值文字：数值轴从 0 数到目标值；非数值轴原样返回
  String animatedRaw(double progress) {
    final v = numValue;
    if (v == null) return rawText;
    final n = v * progress;
    final s = _fmt(n);
    if (label == '功耗') return '${s}W';
    if (label == '性价比') return '综合 ${n.round()}';
    if (label == '单核性能' || label == '多核性能') return '多基准 ${n.round()}';
    return s;
  }
}

/// 兼容性等级结果（1-5 级）
class CompatLevel {
  final int level; // 1-5，越大越好
  final String note; // 一句话结论
  final List<String> issues; // 明显兼容问题文案
  final List<String> bonuses; // 稳定性加分项文案

  const CompatLevel(this.level, this.note, this.issues, this.bonuses);
}

/// 功耗归一化上限（W）：到 1500W 记 0 分
const double kPowerCeiling = 1500;

/// 功耗满分线（W）：功耗 ≤ 此值记满分
const double kPowerFull = 150;

/// 稳定性维度的功耗 0 分线（W）：比性能功耗轴更严格，高功耗更快掉分
const double kStabilityPowerCeiling = 1000;

/// 性价比权重：CPU 单核 20% + 多核 20% + 显卡 60%
const double kCpuSingleWeight = 0.2;
const double kCpuMultiWeight = 0.2;
const double kGpuWeight = 0.6;

/// 性价比参考整机价（元）：总价 = 此值时，综合性能直接作为性价比分
const double kValueRefPrice = 6500;

/// 性能轴放宽指数：得分 = 归一化比例 ^ 此值，小于 1 会让中端硬件得分更高
/// 越小越宽松；满分仍为 100%，超过 100% 的附加分也会被同步压缩
const double kLeniencyExponent = 0.6;

/// 电源余量充足 = 额定功率 ≥ 整机功耗 × 此比例
const double kPsuHeadroomRatio = 1.3;

/// 主板供电充足 = 供电相数 ≥ 此值（如「12+2+1 相」取 12）
const double kMbPhaseThreshold = 10;

/// 显卡 / 多核性能的满分参照：取库内第 N 高值（第 N 名 = 100%）
const int kTopRefRank = 5;

/// 超过 100% 的得分上限（附加分最多显示到 200%）
const double kMaxOverScore = 2.0;

/// 单核多基准权重：降低 CPU-Z 占比（其对 Intel 偏高），以 Geekbench 6 与 Cinebench R23 为主
const List<(String label, double weight)> kSingleBenchWeights = [
  ('Geekbench 6 单核', 0.45),
  ('Cinebench R23 单核', 0.35),
  ('CPU-Z 单核', 0.20),
];

/// 多核多基准权重：以持续渲染负载 Cinebench R23 为主，CPU-Z 辅佐（缺 R23 时自动按可用项重分配权重）
const List<(String label, double weight)> kMultiBenchWeights = [
  ('Cinebench R23 多核', 0.70),
  ('CPU-Z 多核', 0.30),
];

/// 计算一个方案在六维雷达图上的得分（0..1，越大越好）
/// 单核融合 GB6 / R23 / CPU-Z，多核融合 R23 / CPU-Z，消除单一 CPU-Z 对 Intel 的偏科；
/// 单核用最高分、多核/显卡用第 5 名做参照；功耗反向；性价比用加权综合性能；兼容性用 1-5 级
List<RadarAxis> computeRadarScores(BuildPlan plan, List<HardwareSpec> lib) {
  final cpu = plan['cpu'];
  final gpu = plan['gpu'];

  final singleRatio = _cpuSingleRatio(cpu, lib);
  final multiRatio = _cpuMultiRatio(cpu, lib);
  final gpuScore = gpu == null ? null : valueOf(gpu, '3DMark Time Spy', lib);
  final gpuRef = _nthBench(lib, '3DMark Time Spy', kTopRefRank);

  final power = _planPower(plan, lib);
  final compat = computeCompatLevel(plan, lib);
  final total = plan.total;

  // 性能三项先归一化再放宽（幂运算压缩），中端硬件也能拿到较高分，满分仍为 100%
  final s = _soften(singleRatio ?? 0);
  final m = _soften(multiRatio ?? 0);
  final g = _soften(_ratioAbove(gpuScore, gpuRef));

  // 性价比用放宽后的综合性能，让「性价比」轴一并变宽松
  final perf = kCpuSingleWeight * s + kCpuMultiWeight * m + kGpuWeight * g;

  return [
    RadarAxis(
      label: '单核性能',
      score: s,
      rawText: singleRatio == null ? '—' : '多基准 ${(singleRatio * 100).round()}',
      numValue: singleRatio == null ? null : singleRatio * 100,
    ),
    RadarAxis(
      label: '多核性能',
      score: m,
      rawText: multiRatio == null ? '—' : '多基准 ${(multiRatio * 100).round()}',
      numValue: multiRatio == null ? null : multiRatio * 100,
    ),
    RadarAxis(
      label: '显卡性能',
      score: g,
      rawText: gpuScore == null ? '—' : _fmt(gpuScore),
      numValue: gpuScore,
    ),
    RadarAxis(
      label: '功耗',
      score: power == null
          ? 0
          : _clamp((kPowerCeiling - power) / (kPowerCeiling - kPowerFull)),
      rawText: power == null ? '—' : '${_fmt(power)}W',
      numValue: power,
    ),
    RadarAxis(
      label: '性价比',
      score: total <= 0 ? 0 : _clamp(perf * kValueRefPrice / total),
      rawText: '综合 ${(perf * 100).round()}',
      numValue: perf * 100,
    ),
    RadarAxis(
      label: '兼容性',
      score: compat.level / 5,
      rawText: '${compat.level} 级',
    ),
  ];
}

/// 兼容性等级（1-5 级）：
/// - 有 2 个及以上明显兼容问题 → 1 级；1 个 → 2 级
/// - 无明显问题 → 基础 3 级，电源余量充足 / 主板供电充足 各 +1 级，最高 5 级
CompatLevel computeCompatLevel(BuildPlan plan, List<HardwareSpec> lib) {
  final issues = checkCompatibility(plan, lib);
  final msgs = [for (final i in issues) i.message];
  if (issues.length >= 2) {
    return CompatLevel(1, '多项兼容问题', msgs, const []);
  }
  if (issues.length == 1) {
    return CompatLevel(2, '有兼容问题', msgs, const []);
  }
  // 无明显问题：基础 3 级，再看稳定性加分
  final bonuses = <String>[
    if (_psuHeadroomOk(plan, lib)) '电源余量充足',
    if (_mbPowerOk(plan, lib)) '主板供电充足',
  ];
  final note = bonuses.isEmpty ? '无明显问题' : '稳定：${bonuses.join('、')}';
  return CompatLevel(3 + bonuses.length, note, const [], bonuses);
}

/// 能力雷达图：基于 CPU / 显卡 / 内存容量 / CPU 三级缓存，给出六个场景维度（0..1，越大越强）
/// 六维：3A 游戏 / 网游 / 视频创作 / 综合性能 / AI 创作 / 稳定性
/// 游戏与综合类维度用「短板打底、强项加成」，避免顶级显卡配差 CPU 时虚高；
/// 三级缓存（如 3D V-Cache）对游戏帧率影响明显，故游戏与综合维度给其一定权重
List<RadarAxis> computeCapabilityScores(BuildPlan plan, List<HardwareSpec> lib) {
  final cpu = plan['cpu'];
  final gpu = plan['gpu'] == null ? null : valueOf(plan['gpu']!, '3DMark Time Spy', lib);
  final vram = _specNum(plan['gpu'], '显存', lib);
  final ramGb = _specNum(plan['ram'], '容量', lib);
  final l3 = _specNum(cpu, '三级缓存', lib); // CPU 三级缓存容量（MB）

  final gpuRef = _nthBench(lib, '3DMark Time Spy', kTopRefRank);
  final maxVram = _maxSpecNum(lib, '显卡', '显存');
  final maxRam = _maxSpecNum(lib, '内存', '容量');
  final maxL3 = _maxSpecNum(lib, 'CPU', '三级缓存');

  // 各输入项归一化：单核/多核采用多基准融合，消除单一 CPU-Z 偏科；显存/内存/三级缓存用最高分
  final s = _cpuSingleRatio(cpu, lib) ?? 0.0; // 单核（GB6 + R23 + CPU-Z）
  final m = _cpuMultiRatio(cpu, lib) ?? 0.0; // 多核（R23 + CPU-Z）
  final g = _ratioAbove(gpu, gpuRef); // 显卡
  final v = _ratio(vram, maxVram); // 显存
  final r = _ratio(ramGb, maxRam); // 内存容量
  final c = _ratio(l3, maxL3); // CPU 三级缓存容量

  // 稳定性：兼容性等级 + 功耗反向得分（比性能六维更严格，基础合格只给 45 分）
  const stabilityLevels = [0.0, 0.25, 0.45, 0.70, 0.95];
  final compat = stabilityLevels[computeCompatLevel(plan, lib).level - 1];
  final power = _planPower(plan, lib);
  final powerScore = power == null
      ? 0.0
      : _clamp((kStabilityPowerCeiling - power) / (kStabilityPowerCeiling - kPowerFull));

  // 短板打底、强项加成：较弱一方决定基础（70%），较强一方只抬 30%
  // 用于需要 CPU 与显卡协同的场景，避免「顶级显卡配差 CPU」虚高
  double mix(double a, double b) {
    final lo = a < b ? a : b;
    final hi = a > b ? a : b;
    return 0.7 * lo + 0.3 * hi;
  }

  // 综合性能 = 加权平均 50% + 最弱项 50%，突出木桶效应
  final weighted = 0.2 * s + 0.2 * m + 0.1 * c + 0.4 * g + 0.1 * r;
  final weakest = [s, m, g].reduce((a, b) => a < b ? a : b);
  final overall = 0.5 * weighted + 0.5 * weakest;

  // 视频创作 = 加权平均 50% + 最弱项 50%（多核与内存容量取短板），突出木桶效应
  final videoWeighted = 0.55 * m + 0.25 * r + 0.2 * _clamp(g);
  final videoWeakest = m < r ? m : r;
  final videoScore = 0.5 * videoWeighted + 0.5 * videoWeakest;

  RadarAxis cap(String label, double raw) {
    final score = raw.clamp(0.0, kMaxOverScore).toDouble();
    return RadarAxis(
      label: label,
      score: score,
      rawText: '${(score * 100).round()}',
      numValue: score * 100,
    );
  }

  return [
    cap('3A 游戏', mix(0.85 * m + 0.15 * c, g)),
    cap('网游', 0.45 * s + 0.10 * m + 0.35 * c + 0.10 * g),
    cap('视频创作', videoScore),
    cap('综合性能', overall),
    cap('AI 创作', 0.45 * g + 0.35 * v + 0.2 * r),
    cap('稳定性', 0.7 * compat + 0.3 * powerScore),
  ];
}

/// CPU 单核多基准归一化得分（0..1）：融合 Geekbench 6 / Cinebench R23 / CPU-Z；
/// 仅对当前 CPU 具备的跑分项按原权重比例重归一化，兼容只填了单项的自定义 CPU
double? _cpuSingleRatio(PlanComponent? cpu, List<HardwareSpec> lib) {
  if (cpu == null) return null;
  var weightedSum = 0.0;
  var totalWeight = 0.0;
  for (final (label, weight) in kSingleBenchWeights) {
    final val = valueOf(cpu, label, lib);
    final maxVal = _maxBench(lib, label);
    if (val != null && maxVal != null && maxVal > 0) {
      weightedSum += _clamp(val / maxVal) * weight;
      totalWeight += weight;
    }
  }
  if (totalWeight <= 0) return null;
  return _clamp(weightedSum / totalWeight);
}

/// CPU 多核多基准归一化得分（允许超过 1.0，上限 kMaxOverScore）：
/// 融合 Cinebench R23 多核（70%）与 CPU-Z 多核（30%），各按库内第 N 名归一化；
/// 老款或自定义 CPU 缺少 R23 多核时自动按 CPU-Z 多核兜底
double? _cpuMultiRatio(PlanComponent? cpu, List<HardwareSpec> lib) {
  if (cpu == null) return null;
  var weightedSum = 0.0;
  var totalWeight = 0.0;
  for (final (label, weight) in kMultiBenchWeights) {
    final val = valueOf(cpu, label, lib);
    final ref = _nthBench(lib, label, kTopRefRank);
    if (val != null && ref != null && ref > 0) {
      weightedSum += _ratioAbove(val, ref) * weight;
      totalWeight += weight;
    }
  }
  if (totalWeight <= 0) return null;
  return (weightedSum / totalWeight).clamp(0.0, kMaxOverScore).toDouble();
}

/// 读取某配件某规格条目的数值（如「额定功率」「建议电源」「供电」），找不到返回 null
double? _specNum(PlanComponent? comp, String label, List<HardwareSpec> lib) {
  if (comp == null) return null;
  final spec = findSpec(comp.category, comp.model, lib);
  if (spec == null) return null;
  for (final s in spec.specs) {
    if (s.label == label) return parseBench(s.value);
  }
  return null;
}

/// 整机功耗：与 rankPlans 一致，自定义功耗优先，但不低于默认 CPU+显卡 功耗
double? _planPower(BuildPlan plan, List<HardwareSpec> lib) {
  final auto = totalPower(plan, lib);
  if (plan.customPower != null) {
    return auto == null ? plan.customPower : (plan.customPower! < auto ? auto : plan.customPower!);
  }
  return auto;
}

/// 电源余量是否充足：额定功率 ≥ 显卡建议电源，且 ≥ 整机功耗 × kPsuHeadroomRatio
bool _psuHeadroomOk(BuildPlan plan, List<HardwareSpec> lib) {
  final psuW = _specNum(plan['psu'], '额定功率', lib);
  if (psuW == null || psuW <= 0) return false;
  final power = _planPower(plan, lib);
  if (power != null && psuW < power * kPsuHeadroomRatio) return false;
  final gpuSuggest = _specNum(plan['gpu'], '建议电源', lib);
  if (gpuSuggest != null && psuW < gpuSuggest) return false;
  return true;
}

/// 主板供电是否充足：供电相数 ≥ kMbPhaseThreshold
bool _mbPowerOk(BuildPlan plan, List<HardwareSpec> lib) {
  final phases = _specNum(plan['motherboard'], '供电', lib);
  return phases != null && phases >= kMbPhaseThreshold;
}

/// 库内某跑分项的最高分（找不到返回 null）
double? _maxBench(List<HardwareSpec> lib, String label) {
  double? best;
  for (final s in lib) {
    for (final b in s.benchmarks) {
      if (b.label == label) {
        final v = parseBench(b.value);
        if (v != null && (best == null || v > best)) best = v;
      }
    }
  }
  return best;
}

/// 库内某跑分项的第 N 高值（1 起）；不足 N 个时取最高值
double? _nthBench(List<HardwareSpec> lib, String label, int n) {
  final vals = <double>[];
  for (final s in lib) {
    for (final b in s.benchmarks) {
      if (b.label == label) {
        final v = parseBench(b.value);
        if (v != null) vals.add(v);
      }
    }
  }
  if (vals.isEmpty) return null;
  vals.sort((a, b) => b.compareTo(a));
  return vals.length >= n ? vals[n - 1] : vals.last;
}

/// 库内某品类某规格条目的最大值（如显卡显存、内存容量），找不到返回 null
double? _maxSpecNum(List<HardwareSpec> lib, String category, String label) {
  double? best;
  for (final s in lib) {
    if (s.category != category) continue;
    for (final spec in s.specs) {
      if (spec.label == label) {
        final v = parseBench(spec.value);
        if (v != null && (best == null || v > best)) best = v;
      }
    }
  }
  return best;
}

double _ratio(double? v, double? max) {
  if (v == null || max == null || max <= 0) return 0;
  return _clamp(v / max);
}

/// 除以参考值，允许超过 1.0（上限 kMaxOverScore），用于「第 N 名 = 100%」的轴
double _ratioAbove(double? v, double? ref) {
  if (v == null || ref == null || ref <= 0) return 0;
  return (v / ref).clamp(0.0, kMaxOverScore).toDouble();
}

/// 性能轴放宽：把归一化比例做幂运算压缩，中端硬件也能拿到较高分
double _soften(double ratio) {
  if (ratio <= 0) return 0;
  return math.pow(ratio, kLeniencyExponent).toDouble().clamp(0.0, kMaxOverScore);
}

double _clamp(double v) => v.clamp(0.0, 1.0).toDouble();

String _fmt(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
