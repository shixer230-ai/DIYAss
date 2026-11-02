import 'dart:convert';

import '../cloud/cloud_app.dart';
import '../models/build_plan.dart';
import '../utils/json_safe.dart';

/// 用户消息最大长度（拦超长输入，避免异常内容发给 AI）
const int kMaxPromptLen = 4000;

/// 把方案拼成发给 AI 的用户消息（常规分析）
/// 分析规则在云函数里，这里只拼用户消息，App 拿不到 Key
String buildPlanPrompt(BuildPlan plan) =>
    '请分析下面这套 DIY 整机配置：\n\n${_planBody(plan)}';

/// 把方案拼成发给 AI 的用户消息（可靠性分析）
/// 规则在云函数里（mode='reliability' 切换提示词）
String buildReliabilityPrompt(BuildPlan plan) =>
    '请对下面这套 DIY 整机配置做可靠性分析：\n\n${_planBody(plan)}';

/// 两种分析共用的方案正文（配件清单 + 总价 + 功耗）
String _planBody(BuildPlan plan) {
  final b = StringBuffer();
  for (final c in plan.components.values) {
    final brand = c.brand.isEmpty ? '' : '（${c.brand}）';
    b.writeln('· ${c.category}：${c.model}$brand　¥${_fmtPrice(c.price)}');
  }
  for (final c in plan.storages) {
    final brand = c.brand.isEmpty ? '' : '（${c.brand}）';
    b.writeln('· ${c.category}：${c.model}$brand　¥${_fmtPrice(c.price)}');
  }
  b.writeln();
  b.writeln('整机总价：¥${_fmtPrice(plan.total)}');
  if (plan.customPower != null) {
    b.writeln('自定义整机功耗：${_fmtPrice(plan.customPower!)} W');
  }
  return b.toString();
}

String _fmtPrice(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

/// 合规检测：为空或过长时拒绝
void validateAiPrompt(String prompt) {
  final t = prompt.trim();
  if (t.isEmpty) throw Exception('方案内容为空，无法分析');
  if (prompt.length > kMaxPromptLen) throw Exception('方案内容过长，无法分析');
}

/// 调云函数做 AI 分析：云函数校验登录 + 限流 + 用云端 Key 调 DeepSeek
/// [mode]：'general'（常规）或 'reliability'（可靠性）
Future<String> analyzeViaCloud(String prompt, {String mode = 'general'}) async {
  validateAiPrompt(prompt);

  final res = await CloudApp.app.callFunction(
    name: 'aiChat',
    data: {'prompt': prompt, 'mode': mode},
  );

  if (!res.isSuccess) {
    throw Exception(res.message ?? '云函数调用失败');
  }

  // 云函数返回 { content } 或 { error }，result 可能是 Map 或 JSON 字符串
  Map<String, dynamic>? map;
  final result = res.result;
  if (result is Map) {
    map = Map<String, dynamic>.from(result);
  } else if (result is String) {
    try {
      map = jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {
      // 非 JSON 字符串按无结果处理
    }
  }

  final error = map?['error'];
  if (error is String && error.isNotEmpty) {
    throw Exception(error);
  }
  final content = map?['content'];
  if (content is String && content.isNotEmpty) {
    return content;
  }
  throw Exception('AI 未返回内容，请重试');
}

/// 调云函数做配置单解析（mode='parse'）：把 OCR 文本发给 DeepSeek，返回硬件条目列表
/// 返回空列表表示云端也没识别出硬件
Future<List<PlanComponent>> parseViaCloud(String text) async {
  var prompt = text.trim();
  // OCR 文本可能很长，截断到云函数上限内（型号/价格通常在标题靠前位置）
  if (prompt.length > kMaxPromptLen) {
    prompt = prompt.substring(0, kMaxPromptLen);
  }

  final res = await CloudApp.app.callFunction(
    name: 'aiChat',
    data: {'prompt': prompt, 'mode': 'parse'},
  );

  if (!res.isSuccess) {
    throw Exception(res.message ?? '云函数调用失败');
  }

  Map<String, dynamic>? map;
  final result = res.result;
  if (result is Map) {
    map = Map<String, dynamic>.from(result);
  } else if (result is String) {
    try {
      map = jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {}
  }

  final error = map?['error'];
  if (error is String && error.isNotEmpty) {
    throw Exception(error);
  }
  final content = map?['content'];
  if (content is String && content.isNotEmpty) {
    return _parseContentItems(content);
  }
  throw Exception('AI 未返回内容，请重试');
}

/// 把 DeepSeek 返回的 JSON 文本解析成硬件条目列表（品类归一化 + 过滤非法项）
List<PlanComponent> _parseContentItems(String content) {
  var s = content.trim();
  // 去掉可能的 markdown 代码块包裹
  final codeBlock = RegExp(r'```[a-zA-Z]*\s*([\s\S]*?)```').firstMatch(s);
  if (codeBlock != null) s = codeBlock.group(1)!.trim();

  dynamic decoded;
  try {
    decoded = jsonDecode(s);
  } catch (_) {
    // 兜底：截取第一个 { 到最后一个 } 之间的内容再试
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        decoded = jsonDecode(s.substring(start, end + 1));
      } catch (_) {}
    }
  }

  final List<dynamic> rawItems;
  if (decoded is Map) {
    rawItems = decoded['items'] is List ? decoded['items'] as List : const [];
  } else if (decoded is List) {
    rawItems = decoded;
  } else {
    return const [];
  }

  const valid = {'CPU', '主板', '显卡', '内存', '硬盘', '电源', '机箱', '散热'};
  final result = <PlanComponent>[];
  for (final it in rawItems) {
    if (it is! Map) continue;
    final category = _normalizeCategory(asString(it['category']));
    if (!valid.contains(category)) continue;
    final model = asString(it['model']).trim();
    if (model.isEmpty) continue;
    result.add(PlanComponent(
      category: category,
      brand: asString(it['brand']).trim(),
      model: model,
      price: _parsePrice(it['price']),
      platform: '',
    ));
  }
  return result;
}

/// 品类归一化：把 DeepSeek 可能返回的「处理器/processor」等映射到标准品类值
String _normalizeCategory(String raw) {
  const alias = {
    'cpu': 'CPU', 'CPU': 'CPU', '处理器': 'CPU', '中央处理器': 'CPU',
    '主板': '主板', 'motherboard': '主板',
    '显卡': '显卡', 'gpu': '显卡', '图形卡': '显卡', '显示卡': '显卡',
    '内存': '内存', 'ram': '内存', '内存条': '内存',
    '硬盘': '硬盘', 'storage': '硬盘', 'ssd': '硬盘', '固态硬盘': '硬盘', '机械硬盘': '硬盘', 'hdd': '硬盘',
    '电源': '电源', 'psu': '电源',
    '机箱': '机箱', 'case': '机箱',
    '散热': '散热', 'cooler': '散热', '散热器': '散热',
  };
  return alias[raw.trim()] ?? raw.trim();
}

/// 价格解析：数字或数字字符串，非法/超上限返回 0
double _parsePrice(dynamic v) {
  double? d;
  if (v is num) {
    d = v.toDouble();
  } else if (v is String) {
    d = double.tryParse(v.trim());
  }
  if (d == null || d < 0 || d > kMaxPrice) return 0;
  return d;
}
