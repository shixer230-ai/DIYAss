import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_navbar_plus/liquid_glass_bottom_navbar_plus.dart';

import '../data/hardware_catalog.dart';
import '../data/hardware_library.dart';
import '../models/build_plan.dart';
import '../models/hardware_item.dart';
import '../models/hardware_spec.dart';
import '../storage/hardware_store.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// 为某个槽位选配件：从硬件库、清单，或手动填价格
/// 返回 (是否清空, 配件)；null 表示取消
class ComponentPickerPage extends StatefulWidget {
  const ComponentPickerPage({
    super.key,
    required this.slotLabel,
    required this.category,
    required this.current,
    this.preferredSocket,
  });

  final String slotLabel;
  final String category;
  final PlanComponent? current;

  /// 选主板时传入的 CPU 插槽（如 LGA1700 / AM5），用于把插槽匹配的主板排在前面
  final String? preferredSocket;

  @override
  State<ComponentPickerPage> createState() => _ComponentPickerPageState();
}

class _ComponentPickerPageState extends State<ComponentPickerPage> {
  final _store = HardwareStore();
  final _searchController = TextEditingController();
  List<HardwareItem> _items = [];
  List<HardwareSpec> _library = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (!mounted) return;
    setState(() => _query = _searchController.text);
  }

  bool get _searching => _query.trim().isNotEmpty;

  /// 清单条目关键词匹配（型号/品牌/平台/备注）
  bool _itemMatches(HardwareItem item, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (item.model.toLowerCase().contains(q)) return true;
    if (item.brand.toLowerCase().contains(q)) return true;
    if (item.platform.toLowerCase().contains(q)) return true;
    if (item.spec.toLowerCase().contains(q)) return true;
    return false;
  }

  List<HardwareSpec> get _visibleLibrary {
    final list = (_searching
            ? _library.where((s) => hardwareMatches(s, _query))
            : _library)
        .toList();
    final socket = widget.preferredSocket;
    if (socket != null) {
      // 插槽匹配 CPU 的型号排在前面（搜索结果里同样优先）
      list.sort((a, b) {
        final am = _socketOf(a) == socket ? 0 : 1;
        final bm = _socketOf(b) == socket ? 0 : 1;
        return am.compareTo(bm);
      });
    }
    return list;
  }

  List<HardwareItem> get _visibleItems => _searching
      ? _items.where((i) => _itemMatches(i, _query)).toList()
      : _items;

  /// 读取型号的插槽规格值（如 LGA1700 / AM5）
  String? _socketOf(HardwareSpec spec) {
    for (final e in spec.specs) {
      if (e.label == '插槽') return e.value;
    }
    return null;
  }

  /// 插槽匹配 CPU 的型号（优先展示）
  List<HardwareSpec> get _matchingSpecs => widget.preferredSocket == null
      ? const []
      : _library.where((s) => _socketOf(s) == widget.preferredSocket).toList();

  /// 插槽不匹配的型号（排在匹配组之后）
  List<HardwareSpec> get _otherSpecs => widget.preferredSocket == null
      ? _library
      : _library.where((s) => _socketOf(s) != widget.preferredSocket).toList();

  Future<void> _load() async {
    final allItems = await _store.loadAll();
    final lib = await loadHardwareLibrary();
    if (!mounted) return;
    setState(() {
      _items = allItems.where((e) => e.category == widget.category).toList();
      _library = lib.where((s) => s.category == widget.category).toList();
    });
  }

  void _pickItem(HardwareItem item) {
    Navigator.pop(
      context,
      (
        false,
        PlanComponent(
          category: item.category,
          brand: item.brand,
          model: item.model,
          price: item.price,
          platform: item.platform,
        ),
      ),
    );
  }

  void _pickSpec(HardwareSpec spec) {
    // 价格留空（0），回方案详情页在该行内联填写
    final comp = PlanComponent(
      category: spec.category,
      brand: spec.brand,
      model: spec.model,
      price: 0,
      platform: '',
    );
    Navigator.pop(context, (false, comp));
  }

  void _clear() {
    Navigator.pop(context, (true, null));
  }

  Future<void> _manual() async {
    final result = await showDialog<(double, String, String)>(
      context: context,
      builder: (context) => _ManualEntryDialog(slotLabel: widget.slotLabel),
    );
    if (result == null) return;
    final (price, model, brand) = result;
    if (!mounted) return;
    Navigator.pop(
      context,
      (
        false,
        PlanComponent(
          category: widget.category,
          brand: brand,
          model: model,
          price: price,
          platform: '',
        ),
      ),
    );
  }

  String _fmt(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // 列表内容延伸到按钮下方，按钮悬浮在内容之上（与底部导航一致）
      extendBody: true,
      appBar: AppBar(
        title: Text('选择${widget.slotLabel}'),
        actions: [
          if (widget.current != null)
            TextButton(
              onPressed: _clear,
              child: const Text('清空此项'),
            ),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          Expanded(child: _searching ? _searchList(theme) : _allList(theme)),
        ],
      ),
      bottomNavigationBar: _floatingManualButton(theme),
    );
  }

  /// 底部悬浮的「手动填写」按钮：液态玻璃材质，与底部导航同一套玻璃
  Widget _floatingManualButton(ThemeData theme) {
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: GlassPressFeedback(
          child: FakeGlass(
            borderRadius: BorderRadius.circular(kNavBarRadius),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(kNavBarRadius),
                onTap: _manual,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '手动填写型号和价格',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      // 与硬件库搜索框统一：玻璃半透明底 + 胶囊圆角
      child: GlassField(
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: '清空',
                    onPressed: _searchController.clear,
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _allList(ThemeData theme) {
    final matching = _matchingSpecs;
    final others = _otherSpecs;
    return ListView(
      // 底部留出悬浮按钮高度，避免最后一项被挡住
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomNavClearance(context)),
      children: [
        _sectionTitle(theme, '从硬件库选'),
        if (_library.isEmpty)
          _emptyHint(theme, '硬件库里还没有「${widget.category}」')
        else ...[
          if (matching.isNotEmpty) ...[
            _sectionTitle(theme, '匹配 CPU（插槽 ${widget.preferredSocket}）'),
            _specBrandCard(theme, '推荐', matching),
            if (others.isNotEmpty) _sectionTitle(theme, '其它${widget.category}'),
          ],
          for (final sec in _specBrandSections(others))
            _specBrandCard(theme, sec.brand, sec.specs),
        ],
        const SizedBox(height: 8),
        _sectionTitle(theme, '从我的清单选'),
        if (_items.isEmpty)
          _emptyHint(theme, '清单里还没有「${widget.category}」')
        else
          for (final sec in _itemBrandSections(_items))
            _itemBrandCard(theme, sec.brand, sec.items),
      ],
    );
  }

  /// 硬件库型号按品牌分组（主流品牌在前，其余归「其它」）
  List<({String brand, List<HardwareSpec> specs})> _specBrandSections(
    List<HardwareSpec> specs,
  ) {
    final mains = kBrandGroups[widget.category] ?? const <String>[];
    final sections = <({String brand, List<HardwareSpec> specs})>[];
    for (final brand in [...mains, '其它']) {
      final list =
          specs
              .where((s) => brandGroupOf(widget.category, s.brand) == brand)
              .toList()
            ..sort((a, b) => a.model.compareTo(b.model));
      if (list.isNotEmpty) sections.add((brand: brand, specs: list));
    }
    return sections;
  }

  List<({String brand, List<HardwareItem> items})> _itemBrandSections(
    List<HardwareItem> items,
  ) {
    final mains = kBrandGroups[widget.category] ?? const <String>[];
    final sections = <({String brand, List<HardwareItem> items})>[];
    for (final brand in [...mains, '其它']) {
      final list =
          items
              .where((i) => brandGroupOf(widget.category, i.brand) == brand)
              .toList()
            ..sort((a, b) => a.model.compareTo(b.model));
      if (list.isNotEmpty) sections.add((brand: brand, items: list));
    }
    return sections;
  }

  /// 品牌分组大圆角卡片（硬件库型号）
  Widget _specBrandCard(ThemeData theme, String brand, List<HardwareSpec> specs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              brand,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (var i = 0; i < specs.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            ListTile(
              leading: CategoryBadge(category: specs[i].category),
              title: Text(specs[i].model),
              subtitle: Text(specs[i].brand),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickSpec(specs[i]),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 品牌分组大圆角卡片（我的清单条目）
  Widget _itemBrandCard(ThemeData theme, String brand, List<HardwareItem> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              brand,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            ListTile(
              leading: CategoryBadge(category: items[i].category),
              title: Text(items[i].model),
              subtitle: Text(
                items[i].brand.isEmpty
                    ? items[i].platform
                    : '${items[i].brand} · ${items[i].platform}',
              ),
              trailing: Text(
                '¥${_fmt(items[i].price)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              onTap: () => _pickItem(items[i]),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _searchList(ThemeData theme) {
    final lib = _visibleLibrary;
    final items = _visibleItems;
    if (lib.isEmpty && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('没有找到「${_query.trim()}」相关的配件'),
          ],
        ),
      );
    }
    return ListView(
      // 底部留出悬浮按钮高度，避免最后一项被挡住
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomNavClearance(context)),
      children: [
        if (lib.isNotEmpty) ...[
          _sectionTitle(theme, '硬件库'),
          for (final spec in lib) _specCard(theme, spec),
        ],
        if (items.isNotEmpty) ...[
          _sectionTitle(theme, '我的清单'),
          for (final item in items) _itemCard(theme, item),
        ],
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _emptyHint(ThemeData theme, String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
    );
  }

  Widget _specCard(ThemeData theme, HardwareSpec spec) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CategoryBadge(category: spec.category),
        title: Text(spec.model),
        subtitle: Text(spec.brand),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _pickSpec(spec),
      ),
    );
  }

  Widget _itemCard(ThemeData theme, HardwareItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CategoryBadge(category: item.category),
        title: Text(item.model),
        subtitle: Text(
          item.brand.isEmpty ? item.platform : '${item.brand} · ${item.platform}',
        ),
        trailing: Text(
          '¥${_fmt(item.price)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        onTap: () => _pickItem(item),
      ),
    );
  }
}

/// 弹窗输入框：与全站统一为胶囊圆角 + 半透明底色
InputDecoration _glassFieldDeco(BuildContext context, String label) {
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: scheme.surface.withValues(alpha: 0.4),
    border: border(scheme.outlineVariant.withValues(alpha: 0.5)),
    enabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.5)),
    focusedBorder: border(scheme.primary),
  );
}

/// 手动填写型号 + 品牌 + 价格，返回 (价格, 型号, 品牌)
class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog({required this.slotLabel});

  final String slotLabel;

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _model = TextEditingController();
  final _brand = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    _brand.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.parse(_price.text.trim());
    Navigator.pop(context, (price, _model.text.trim(), _brand.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('手动填写${widget.slotLabel}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _model,
              autofocus: true,
              decoration: _glassFieldDeco(context, '型号 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写型号' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brand,
              decoration: _glassFieldDeco(context, '品牌'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _glassFieldDeco(context, '价格（元）*'),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return '请填写价格';
                final n = double.tryParse(t);
                if (n == null || n <= 0) return '价格格式不对';
                if (n > kMaxPrice) return '价格不能超过 $kMaxPrice';
                return null;
              },
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
          child: const Text('确定'),
        ),
      ],
    );
  }
}
