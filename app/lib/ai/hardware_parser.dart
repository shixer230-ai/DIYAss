import '../analysis/hardware_matcher.dart';
import '../models/build_plan.dart';
import '../models/hardware_spec.dart';

/// 规则解析结果：识别出的硬件条目 + 是否「够用」
class ParseResult {
  final List<PlanComponent> items;
  final bool enough; // 识别出 ≥2 个不同品类就算够用，不再走云端兜底
  const ParseResult(this.items, this.enough);
}

/// 从 OCR 文本里用智能规则匹配本地硬件库，提取硬件条目：
/// - 自动兼容无前缀（RTX5080 / 9850X3D / 14700K）、无空格、非公长名、容量简写（1T/16G）等写法
/// - 价格不在此提取（电商截图价格与商品的对应关系不可靠），统一填 0 让用户在方案里改
ParseResult parseHardwareFromText(String text, List<HardwareSpec> lib) {
  final matched = extractSpecsFromText(text, lib);
  final items = <PlanComponent>[];
  final seenCategories = <String>{};

  for (final spec in matched) {
    items.add(PlanComponent(
      category: spec.category,
      brand: spec.brand,
      model: spec.model,
      price: 0,
      platform: '',
    ));
    seenCategories.add(spec.category);
  }

  return ParseResult(items, seenCategories.length >= 2);
}
