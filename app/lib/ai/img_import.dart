import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../analysis/value_index.dart';
import '../data/hardware_library.dart';
import '../models/build_plan.dart';
import '../models/hardware_spec.dart';
import '../ocr/ocr_text.dart';
import '../storage/build_plan_store.dart';
import '../theme/app_theme.dart';
import 'ai_analysis.dart';
import 'hardware_parser.dart';

/// 品类 → 槽位 key 映射（硬盘进 storages，其余进 components）
const Map<String, String> _categoryToSlot = {
  'CPU': 'cpu',
  '主板': 'motherboard',
  '显卡': 'gpu',
  '内存': 'ram',
  '硬盘': 'storage',
  '电源': 'psu',
  '机箱': 'case',
  '散热': 'cooler',
};

/// 把识别出的型号对齐到硬件库标准型号（品牌/型号用库里的，价格保留识别值）
/// 非公「蓝宝石 RX 6500 XT 白金版 OC」→ 库里「Radeon RX 6500 XT」
PlanComponent _alignToLib(PlanComponent c, List<HardwareSpec> lib) {
  final spec = findSpec(c.category, c.model, lib);
  if (spec == null) return c;
  return PlanComponent(
    category: spec.category,
    brand: spec.brand,
    model: spec.model,
    price: c.price,
    platform: c.platform,
  );
}

/// 把识别结果转成整机方案（硬盘进 storages，其余品类映射到槽位）
BuildPlan buildPlanFromItems(String name, List<PlanComponent> items) {
  final components = <String, PlanComponent>{};
  final storages = <PlanComponent>[];
  for (final c in items) {
    final key = _categoryToSlot[c.category];
    if (key == null) continue;
    if (key == 'storage') {
      storages.add(c);
    } else if (!components.containsKey(key)) {
      components[key] = c;
    }
  }
  return BuildPlan(name: name, components: components, storages: storages);
}

/// 生成默认方案名「截图导入方案 N」，避开已有重名
String _nextImportName(List<BuildPlan> plans) {
  var n = 1;
  while (plans.any((p) => p.name == '截图导入方案 $n')) {
    n++;
  }
  return '截图导入方案 $n';
}

/// 一键图片导入：选图 → OCR → 识别 → 命名 → 保存，返回生成的方案
/// 返回 null 表示取消（选图 / 命名取消）或识别失败（内部已 snackbar 提示）
Future<BuildPlan?> importPlanFromGallery(BuildContext context) async {
  // 1. 选图（image_picker 内部会按需申请相册权限）
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  if (!context.mounted) return null;

  // 2. 识别期间显示 loading（不可点掉）
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  ));

  List<PlanComponent>? items;
  String? errMsg;
  try {
    items = await _recognizePath(file.path);
  } catch (e) {
    errMsg = '识别失败：$e';
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }

  if (!context.mounted) return null;
  if (errMsg != null) {
    _snack(context, errMsg);
    return null;
  }
  if (items == null || items.isEmpty) {
    _snack(context, '没能识别出硬件，换张商品详情截图试试');
    return null;
  }

  // 3. 命名
  final store = BuildPlanStore();
  final plans = await store.loadAll();
  if (!context.mounted) return null;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: '命名方案',
      initial: _nextImportName(plans),
      forbidden: plans.map((p) => p.name.trim().toLowerCase()).toSet(),
    ),
  );
  if (name == null) return null;

  // 4. 生成 + 保存
  final plan = buildPlanFromItems(name, items);
  plans.add(plan);
  await store.saveAll(plans);
  await store.saveCurrentId(plan.id);
  return plan;
}

/// 识别单张图片：OCR → 规则解析 →（不够再）云端兜底 → 型号对齐
Future<List<PlanComponent>> _recognizePath(String path) async {
  final text = (await ocrImagePath(path)).trim();
  if (text.isEmpty) return const [];
  final lib = await loadHardwareLibrary();
  final parsed = parseHardwareFromText(text, lib);
  List<PlanComponent> items;
  if (parsed.enough) {
    items = parsed.items;
  } else {
    items = await parseViaCloud(text);
  }
  return items.map((c) => _alignToLib(c, lib)).toList();
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// 命名方案对话框：胶囊输入框 + 查重（与方案页的命名弹窗一致）
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.forbidden,
  });

  final String title;
  final String initial;

  /// 不允许重名的名称集合（已归一化：trim + 小写）
  final Set<String> forbidden;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    if (widget.forbidden.contains(t.toLowerCase())) {
      setState(() => _error = '已存在同名方案，请换一个');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      title: Text(widget.title),
      content: GlassField(
        child: TextField(
          controller: _c,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '名称',
            errorText: _error,
            prefixIcon: const Icon(Icons.edit_outlined, size: 20),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kCardRadius),
            ),
          ),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: capsuleButtonStyle(theme, fullWidth: false),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
