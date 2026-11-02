import 'package:flutter/material.dart';

import '../models/hardware_item.dart';
import '../models/hardware_spec.dart';
import '../storage/hardware_store.dart';
import '../storage/user_spec_store.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import 'user_spec_form_page.dart';

const _platforms = ['京东', '淘宝', '拼多多', '天猫', '其他'];

/// 硬件型号详情：参数规格 + 跑分，可加入我的清单
class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({super.key, required this.spec});

  final HardwareSpec spec;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  final _store = HardwareStore();
  final _userStore = UserSpecStore();
  late HardwareSpec _spec = widget.spec;
  bool _inMine = false;

  @override
  void initState() {
    super.initState();
    _loadMineState();
  }

  Future<void> _loadMineState() async {
    final inMine = await _userStore.contains(_spec.id);
    if (!mounted) return;
    setState(() => _inMine = inMine);
  }

  Future<void> _toggleMine() async {
    final added = !_inMine;
    if (added) {
      await _userStore.add(_spec);
    } else {
      await _userStore.remove(_spec.id);
    }
    if (!mounted) return;
    setState(() => _inMine = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已加入「我的添加」' : '已从「我的添加」移除')),
    );
  }

  /// 编辑「我的添加」里的型号：复用新增表单，预填并覆盖原条目
  Future<void> _edit() async {
    final updated = await Navigator.push<HardwareSpec>(
      context,
      MaterialPageRoute(builder: (_) => UserSpecFormPage(spec: _spec)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _spec = updated;
      _inMine = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存修改')),
    );
  }

  Future<void> _addToList() async {
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => _AddPriceDialog(spec: _spec),
    );
    if (result == null) return;
    final (price, platform) = result;

    final item = HardwareItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: _spec.category,
      brand: _spec.brand,
      model: _spec.model,
      price: price,
      platform: platform,
      spec: _spec.summary(),
      createdAt: DateTime.now(),
    );
    await _store.add(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入清单：${_spec.model}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = _spec;

    return Scaffold(
      appBar: AppBar(title: Text(spec.model)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CategoryBadge(category: spec.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.model,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${spec.brand} · ${spec.category}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle(theme, '参数规格'),
          ...spec.specs.map((e) => _entryRow(theme, e)),
          if (spec.benchmarks.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle(theme, '跑分'),
            ...spec.benchmarks.map((e) => _entryRow(theme, e, emphasize: true)),
            const SizedBox(height: 12),
            Text(
              '注：跑分为参考值（约），随平台、驱动版本、测试环境不同会有差异',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addToList,
            icon: const Icon(Icons.add),
            label: const Text('加入我的清单'),
            style: capsuleButtonStyle(theme),
          ),
          const SizedBox(height: 12),
          if (_inMine) ...[
            OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑此硬件'),
              style: capsuleOutlinedButtonStyle(theme),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _toggleMine,
            icon: Icon(
              _inMine ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
            ),
            label: Text(_inMine ? '从「我的添加」移除' : '加入「我的添加」'),
            style: capsuleOutlinedButtonStyle(theme),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _entryRow(ThemeData theme, SpecEntry e, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(e.label, style: theme.textTheme.bodyMedium),
          Text(
            e.value,
            style: emphasize
                ? TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// 加入清单时填写价格和平台的对话框
class _AddPriceDialog extends StatefulWidget {
  const _AddPriceDialog({required this.spec});

  final HardwareSpec spec;

  @override
  State<_AddPriceDialog> createState() => _AddPriceDialogState();
}

class _AddPriceDialogState extends State<_AddPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  String _platform = _platforms.first;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.parse(_priceController.text.trim());
    Navigator.pop(context, (price, _platform));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('加入清单：${widget.spec.model}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _priceController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '价格（元）*',
                hintText: '例如：1399',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return '请填写价格';
                final n = double.tryParse(t);
                if (n == null || n <= 0) return '价格格式不对';
                return null;
              },
            ),
            const SizedBox(height: 16),
            GlassDropdown<String>(
              initialValue: _platform,
              decoration: const InputDecoration(labelText: '购买平台'),
              items: _platforms
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _platform = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
          child: const Text('加入'),
        ),
      ],
    );
  }
}
