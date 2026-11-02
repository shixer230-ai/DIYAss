import '../models/build_plan.dart';
import '../models/hardware_spec.dart';

/// 规则解析结果：识别出的硬件条目 + 是否「够用」
class ParseResult {
  final List<PlanComponent> items;
  final bool enough; // 识别出 ≥2 个不同品类就算够用，不再走云端兜底
  const ParseResult(this.items, this.enough);
}

/// 从 OCR 文本里用规则匹配本地硬件库，提取硬件条目
/// 匹配策略：本地库里 model 名（规范化后）完整出现在文本里即命中
/// 价格不在此提取（电商截图价格与商品的对应关系不可靠），统一填 0 让用户在方案里改
ParseResult parseHardwareFromText(String text, List<HardwareSpec> lib) {
  final normText = _norm(text);
  final items = <PlanComponent>[];
  final seenCategories = <String>{};
  final seen = <String>{};

  for (final spec in lib) {
    final normModel = _norm(spec.model);
    // 型号太短不匹配，避免把「i5」「M2」这类短词误判成型号
    if (normModel.length < 3) continue;
    if (!normText.contains(normModel)) continue;
    final key = '${spec.category}|$normModel';
    if (seen.contains(key)) continue;
    seen.add(key);

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

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
