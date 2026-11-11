import '../models/build_plan.dart';
import '../models/hardware_spec.dart';
import 'value_index.dart';

/// 一条兼容性问题（只提醒，不强制）
class CompatIssue {
  const CompatIssue(this.message);

  final String message;
}

/// 检查兼容性：CPU↔主板插槽、内存类型↔主板、电源功率↔整机功耗、CPU↔显卡发行代差
/// 只做能确定的判断；匹配不到硬件库型号的配件跳过（不误报）
List<CompatIssue> checkCompatibility(BuildPlan plan, List<HardwareSpec> lib) {
  final issues = <CompatIssue>[];

  final cpuSpec = _lookup(plan['cpu'], 'CPU', lib);
  final mbSpec = _lookup(plan['motherboard'], '主板', lib);
  final ramSpec = _lookup(plan['ram'], '内存', lib);
  final gpuSpec = _lookup(plan['gpu'], '显卡', lib);

  // 1) CPU 插槽 vs 主板插槽
  final cpuSocket = _specValue(cpuSpec, '插槽');
  final mbSocket = _specValue(mbSpec, '插槽');
  if (cpuSocket != null && mbSocket != null && cpuSocket != mbSocket) {
    issues.add(CompatIssue('CPU 是 $cpuSocket，主板是 $mbSocket，插槽不兼容'));
  }

  // 2) 内存类型 vs 主板内存支持
  final ramType = _memType(_specValue(ramSpec, '类型'));
  final mbMem = _memType(_specValue(mbSpec, '内存支持'));
  if (ramType != null && mbMem != null && ramType != mbMem) {
    issues.add(CompatIssue('内存是 $ramType，但主板支持 $mbMem，不兼容'));
  }

  // 3) 电源额定功率 vs 整机功耗（只累加 CPU TDP + 显卡功耗，偏保守）
  final psuSpec = _lookup(plan['psu'], '电源', lib);
  final psuPowerRaw = _specValue(psuSpec, '额定功率');
  final psuPower = psuPowerRaw == null ? null : parseBench(psuPowerRaw);
  final sysPower = totalPower(plan, lib);
  if (psuPower != null && sysPower != null && psuPower < sysPower) {
    issues.add(CompatIssue(
        '整机功耗约 ${sysPower.toStringAsFixed(0)}W，但电源额定功率仅 ${psuPower.toStringAsFixed(0)}W，可能不够'));
  }

  // 4) CPU 与显卡发行年份差距：超过 10 年提示代差过大，兼容性下降
  final cpuYear = _year(_specValue(cpuSpec, '发行日期'));
  final gpuYear = _year(_specValue(gpuSpec, '发行日期'));
  if (cpuYear != null && gpuYear != null) {
    final gap = (cpuYear - gpuYear).abs();
    if (gap > 10) {
      issues.add(CompatIssue(
          'CPU（$cpuYear 年）与显卡（$gpuYear 年）发行相差 $gap 年，代差过大，兼容性下降'));
    }
  }

  return issues;
}

HardwareSpec? _lookup(PlanComponent? comp, String category, List<HardwareSpec> lib) {
  if (comp == null) return null;
  return findSpec(category, comp.model, lib);
}

/// 取某规格条目（如「插槽」「内存支持」「类型」）的值；找不到返回 null
String? _specValue(HardwareSpec? spec, String label) {
  if (spec == null) return null;
  for (final s in spec.specs) {
    if (s.label == label) return s.value;
  }
  return null;
}

/// 从「DDR5-5600」这类字符串里提取内存代别（DDR4 / DDR5）
String? _memType(String? value) {
  if (value == null) return null;
  return RegExp(r'DDR\d').firstMatch(value)?.group(0);
}

/// 从「2022」「2022-10」这类发行日期字符串里提取年份；失败返回 null
int? _year(String? value) {
  if (value == null) return null;
  final m = RegExp(r'\d{4}').firstMatch(value);
  return m == null ? null : int.tryParse(m.group(0)!);
}
