import 'package:flutter/material.dart';

import '../analysis/value_index.dart';
import '../data/hardware_catalog.dart';
import '../models/hardware_spec.dart';
import '../storage/user_spec_store.dart';
import '../theme/app_theme.dart';

const _categories = ['CPU', '主板', '显卡', '内存', '硬盘', '电源', '机箱', '其他'];

/// 自定义添加硬件型号到「我的添加」：填品类、型号、品牌、参数规格和性价比跑分
/// 全部字段合并为一张大圆角卡片，字段间用横线分割，不再用胶囊输入框
/// 传入 [spec] 时进入编辑模式（预填已有内容，保存时覆盖原条目）
class UserSpecFormPage extends StatefulWidget {
  const UserSpecFormPage({super.key, this.spec});

  /// 要编辑的已有型号；null 表示新增
  final HardwareSpec? spec;

  @override
  State<UserSpecFormPage> createState() => _UserSpecFormPageState();
}

class _UserSpecFormPageState extends State<UserSpecFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _modelController = TextEditingController();
  final _store = UserSpecStore();

  String _category = _categories.first;
  String _brand = '其它';
  bool _saving = false;

  /// 当前品类可选的品牌：主流品牌 + 「其它」
  List<String> get _brandOptions =>
      [...(kBrandGroups[_category] ?? const <String>[]), '其它'];

  final List<_EntryPair> _specPairs = [];
  final Map<String, TextEditingController> _valueControllers = {};
  final _powerController = TextEditingController();

  /// 当前品类参与「分析」排行的性价比项目
  List<ValueItem> get _valueItems =>
      kValueItems.where((e) => e.category == _category).toList();

  @override
  void initState() {
    super.initState();
    for (final item in kValueItems) {
      _valueControllers[item.label] = TextEditingController();
    }
    final src = widget.spec;
    if (src == null) {
      // 新增：给一行空输入，方便直接填写
      _specPairs.add(_EntryPair());
      _brand = _brandOptions.first;
    } else {
      // 编辑：预填已有内容
      _category = _categories.contains(src.category) ? src.category : '其它';
      _brand = _brandOptions.contains(src.brand) ? src.brand : '其它';
      _modelController.text = src.model;
      _prefillSpecs(src);
      _prefillBenches(src);
    }
  }

  /// 编辑态：把已有规格拆成「功耗条目 + 参数规格」，功耗单独进功耗输入框
  void _prefillSpecs(HardwareSpec src) {
    final powerLabel = _powerLabel;
    final specs = <SpecEntry>[];
    for (final e in src.specs) {
      if (powerLabel != null && e.label == powerLabel) {
        _powerController.text = e.value;
      } else {
        specs.add(e);
      }
    }
    _specPairs.clear();
    if (specs.isEmpty) {
      _specPairs.add(_EntryPair());
    } else {
      for (final e in specs) {
        final p = _EntryPair();
        p.label.text = e.label;
        p.value.text = e.value;
        _specPairs.add(p);
      }
    }
  }

  /// 编辑态：把已有跑分按分析约定的条目名回填到对应输入框
  void _prefillBenches(HardwareSpec src) {
    for (final item in _valueItems) {
      for (final b in src.benchmarks) {
        if (b.label == item.benchLabel) {
          _valueControllers[item.label]?.text = b.value;
        }
      }
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    _powerController.dispose();
    for (final p in _specPairs) {
      p.dispose();
    }
    for (final c in _valueControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<SpecEntry> _collect(List<_EntryPair> pairs) {
    return pairs
        .map((p) => SpecEntry(p.label.text.trim(), p.value.text.trim()))
        .where((e) => e.label.isNotEmpty || e.value.isNotEmpty)
        .toList();
  }

  /// 收集「性价比跑分」：只取当前品类对应项目里填了数值的，label 用分析约定的精确名
  List<SpecEntry> _collectValueBenches() {
    final result = <SpecEntry>[];
    for (final item in _valueItems) {
      final text = _valueControllers[item.label]?.text.trim() ?? '';
      if (text.isNotEmpty) result.add(SpecEntry(item.benchLabel, text));
    }
    return result;
  }

  /// 功耗写入规格里的条目名：CPU 用「默认TDP」、显卡用「功耗」，其它品类无
  String? get _powerLabel {
    if (_category == 'CPU') return '默认TDP';
    if (_category == '显卡') return '功耗';
    return null;
  }

  /// 收集功耗：填了才写入，label 用分析约定的精确名
  List<SpecEntry> _collectPower() {
    final label = _powerLabel;
    final text = _powerController.text.trim();
    if (label == null || text.isEmpty) return [];
    return [SpecEntry(label, text)];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final editing = widget.spec != null;
    final spec = HardwareSpec(
      // 编辑复用原 id（store.add 内部 removeWhere+add，实现覆盖）
      id: editing
          ? widget.spec!.id
          : 'user_${DateTime.now().microsecondsSinceEpoch}',
      category: _category,
      brand: _brand,
      model: _modelController.text.trim(),
      specs: [..._collect(_specPairs), ..._collectPower()],
      benchmarks: _collectValueBenches(),
    );
    setState(() => _saving = true);
    await _store.add(spec);
    if (!mounted) return;
    Navigator.pop(context, spec);
  }

  /// 统一的无边框、无填充输入样式：把胶囊输入框换成大卡片内的纯行
  InputDecoration _plain(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.spec == null ? '自定义添加硬件' : '编辑自定义硬件'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      decoration: _plain('品类'),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _category = v!;
                        // 换品类后，品牌重置为该品类的首个主流品牌
                        _brand = _brandOptions.first;
                      }),
                    ),
                    const Divider(height: 1),
                    TextFormField(
                      controller: _modelController,
                      decoration: _plain('型号 *', hint: '例如：i5-13600KF / RTX 3060'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请填写型号' : null,
                    ),
                    const Divider(height: 1),
                    DropdownButtonFormField<String>(
                      // 品类变化时用 key 重建，让品牌回退到该品类首个主流品牌
                      key: ValueKey(_category),
                      initialValue: _brand,
                      isExpanded: true,
                      dropdownColor: scheme.surface,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      decoration: _plain('品牌'),
                      items: _brandOptions
                          .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (v) => setState(() => _brand = v!),
                    ),
                    const Divider(height: 1),
                    _entryEditor(
                      title: '参数规格',
                      hint: '例如：核心/线程 → 8核16线程',
                      pairs: _specPairs,
                    ),
                    if (_valueItems.isNotEmpty) ...[
                      const Divider(height: 1),
                      _valueBenchEditor(),
                    ],
                    if (_powerLabel != null) ...[
                      const Divider(height: 1),
                      _powerEditor(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              // 胶囊 + 半透明材质，和清单页「保存」等主按钮保持一致
              style: capsuleButtonStyle(Theme.of(context)),
              child: Text(widget.spec == null ? '保存到「我的添加」' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryEditor({
    required String title,
    required String hint,
    required List<_EntryPair> pairs,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => pairs.add(_EntryPair())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加一项'),
            ),
          ],
        ),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (final p in pairs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: p.label,
                    decoration: _plain('名称', hint: '如：核心/线程'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: p.value,
                    decoration: _plain('数值', hint: '如：8核16线程'),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    pairs.remove(p);
                    p.dispose();
                    setState(() {});
                  },
                  tooltip: '删除这项',
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 性价比跑分：按当前品类列出「分析」用的跑分项，label 固定，只填数值（可跳过）
  Widget _valueBenchEditor() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '性价比跑分（用于「分析」排行）',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          '填了这几项，这个型号就能参与「分析」页的性价比排行；不填可跳过',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (final item in _valueItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _valueControllers[item.label],
              decoration: _plain(item.label, hint: '如：约 10500'),
            ),
          ),
      ],
    );
  }

  /// 功耗：CPU/显卡 填了才能参与「分析」的整机功耗排行（可跳过）
  Widget _powerEditor() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '功耗（用于「分析」整机功耗排行）',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          '填了功耗，这个型号就能参与「分析」页的整机功耗排行；不填可跳过',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _powerController,
          decoration: _plain('功耗', hint: '如：65W / 450W'),
        ),
      ],
    );
  }
}

/// 一组「名称 + 数值」输入框，持有各自的控制器
class _EntryPair {
  final TextEditingController label = TextEditingController();
  final TextEditingController value = TextEditingController();

  void dispose() {
    label.dispose();
    value.dispose();
  }
}
