import 'package:flutter/material.dart';

import '../data/hardware_catalog.dart';
import '../models/build_plan.dart';
import '../models/hardware_item.dart';
import '../storage/build_plan_store.dart';
import '../storage/hardware_store.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import 'hardware_form_page.dart';

/// 硬件清单主页：展示已录入的硬件，可新增、删除，也可进入硬件库选型号
class HardwareListPage extends StatefulWidget {
  const HardwareListPage({super.key, this.onOpenPlan, this.isActive = true});

  /// 点击整机方案条目时回调，用于切换到顶部「整机方案」分段
  final VoidCallback? onOpenPlan;

  /// 当前是否为底部导航选中的标签页；从其他页切回来时用于刷新数据
  final bool isActive;

  @override
  State<HardwareListPage> createState() => _HardwareListPageState();
}

class _HardwareListPageState extends State<HardwareListPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _store = HardwareStore();
  List<HardwareItem> _items = [];
  List<BuildPlan> _plans = [];
  bool _loading = true;

  // 清单分类 Tab 的顺序（可左右滑动切换）
  static const _categories = [
    '整机方案',
    'CPU',
    '显卡',
    '主板',
    '内存',
    '硬盘',
    '电源',
    '机箱',
    '其他',
  ];

  late final TabController _tabController;
  int _currentIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HardwareListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从其他标签页切回来时重新加载，确保能看到在整机方案页里保存的条目
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  void _onTabChanged() {
    if (!mounted || _tabController.index == _currentIndex) return;
    setState(() => _currentIndex = _tabController.index);
  }

  Future<void> _load() async {
    var items = await _store.loadAll();
    final plans = await BuildPlanStore().loadAll();
    // 新版「整机方案」分类直接读方案数据；历史版本遗留的整机方案快照条目一律清理，
    // 避免删除方案后清单里还残留旧版快照
    final stale = items.where((e) => e.category == '整机方案').toList();
    if (stale.isNotEmpty) {
      items = items.where((e) => e.category != '整机方案').toList();
      await _store.saveAll(items);
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _plans = plans;
      _loading = false;
    });
  }

  Future<void> _openForm(String category) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HardwareFormPage(category: category)),
    );
    if (saved == true) _load();
  }

  Future<void> _openPlanById(String id) async {
    await BuildPlanStore().saveCurrentId(id);
    widget.onOpenPlan?.call();
  }

  /// 解构整机方案：把方案里的硬件合并成一张大卡片加入清单，重复硬件跳过
  Future<void> _deconstructPlan(BuildContext context, BuildPlan plan) async {
    final comps = [...plan.components.values, ...plan.storages];
    if (comps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该方案还没有硬件')),
      );
      return;
    }
    // 硬件级去重：清单里已有同品类同型号的硬件则跳过（散热归「其他」）
    String cat(PlanComponent c) => c.category == '散热' ? '其他' : c.category;
    final fresh = <PlanComponent>[
      for (final c in comps)
        if (!_items.any((e) => e.category == cat(c) && e.model == c.model)) c,
    ];
    if (fresh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该方案的硬件都已存在于清单中，无需添加')),
      );
      return;
    }
    final skipped = comps.length - fresh.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解构到硬件清单'),
        content: Text(
          skipped == 0
              ? '将把该方案 ${fresh.length} 件硬件合并成一张卡片加入清单，确定吗？'
              : '将把该方案 ${fresh.length} 件硬件合并加入清单（已跳过 $skipped 件重复），确定吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解构'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 该方案已解构过则先删除旧记录，实现「更新」而非重复新增
    for (final o in _items.where((e) => e.planId == plan.id)) {
      await _store.delete(o.id);
    }

    // 生成一条合并记录，spec 存各硬件明细
    String fmt(double p) =>
        p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
    final lines = <String>[];
    var totalPrice = 0.0;
    for (final c in fresh) {
      lines.add('${cat(c)} · ${c.model} · ¥${fmt(c.price)}');
      totalPrice += c.price;
    }
    final item = HardwareItem(
      id: 'decon_${DateTime.now().microsecondsSinceEpoch}',
      category: '其他',
      brand: '',
      model: plan.name.isEmpty ? '未命名方案' : plan.name,
      price: totalPrice,
      platform: '',
      spec: lines.join('\n'),
      planId: plan.id,
      createdAt: DateTime.now(),
    );
    await _store.add(item);
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0
              ? '已解构 ${fresh.length} 件硬件'
              : '已解构 ${fresh.length} 件硬件（跳过 $skipped 件重复）',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(HardwareItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${item.model}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(item.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final currentCategory = _categories[_currentIndex];
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              // 上滑时标题 + 分类标签随内容一起滚走（淡出），不再悬浮分割观感
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  pinned: false,
                  floating: false,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    _items.isEmpty
                        ? '我的硬件清单'
                        : '我的硬件清单（${_items.length}）',
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(kTextTabBarHeight + 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      // 分类标签：透明底色，仅保留选中胶囊高亮
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        // 选中分类用圆角胶囊高亮，避免默认的直角矩形指示器
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        indicator: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        labelColor: scheme.primary,
                        unselectedLabelColor: scheme.onSurfaceVariant,
                        dividerColor: Colors.transparent,
                        tabs: [for (final c in _categories) Tab(text: c)],
                      ),
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [for (final c in _categories) _categoryTab(c)],
              ),
            ),
      // 「整机方案」由整机方案页生成，不能手动添加，故隐藏右下角 +
      floatingActionButton: currentCategory == '整机方案'
          ? null
          : Padding(
              // 底部导航悬浮在内容上方，FAB 也要上移导航高度，避免被导航遮住
              padding: EdgeInsets.only(bottom: kNavOverlaySpace),
              child: FloatingActionButton(
                shape: const CircleBorder(),
                // 半透明材质，和保存按钮 / 玻璃风格一致
                backgroundColor: scheme.primary.withValues(alpha: 0.16),
                foregroundColor: scheme.primary,
                onPressed: () => _openForm(currentCategory),
                tooltip: '自定义添加',
                child: const Icon(Icons.add),
              ),
            ),
    );
  }

  Widget _categoryTab(String category) {
    if (category == '整机方案') return _planTab();
    final all = _items.where((e) => e.category == category).toList();
    if (all.isEmpty) return _emptyCategory(category);

    // 解构记录（planId 非空）与普通硬件分开
    final decon = all.where((e) => e.planId != null).toList();
    final plain = all.where((e) => e.planId == null).toList();

    // 普通硬件去重：相同型号只保留一条
    final seen = <String>{};
    final unique = [
      for (final e in plain)
        if (seen.add(e.model)) e,
    ];

    // 按品牌分组，每组一张大圆角卡片
    final sections = _brandSections(category, unique);
    final entries = <Widget>[
      for (final sec in sections) _brandGroupCard(sec.brand, sec.items),
      for (final d in decon)
        _DeconstructedCard(item: d, onDelete: () => _confirmDelete(d)),
    ];

    return ListView.builder(
      // 回弹效果：超出可滚动范围时橡皮筋回弹（AlwaysScrollable 保证短列表也能滚）
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index],
    );
  }

  /// 按品牌把某品类的硬件分组：主流品牌在前（按 kBrandGroups 顺序），其余归「其它」
  List<({String brand, List<HardwareItem> items})> _brandSections(
    String category,
    List<HardwareItem> items,
  ) {
    final mains = kBrandGroups[category] ?? const <String>[];
    final sections = <({String brand, List<HardwareItem> items})>[];
    for (final brand in [...mains, '其它']) {
      final list =
          items
              .where((i) => brandGroupOf(category, i.brand) == brand)
              .toList()
            ..sort((a, b) => a.model.compareTo(b.model));
      if (list.isNotEmpty) sections.add((brand: brand, items: list));
    }
    return sections;
  }

  /// 品牌分组大圆角卡片：品牌名 + 该品牌下的硬件行
  Widget _brandGroupCard(String brand, List<HardwareItem> items) {
    final theme = Theme.of(context);
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
            _itemTile(theme, items[i]),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 分组卡片内的一行硬件：品类徽标 + 型号 + 品牌/平台 + 价格 + 删除
  Widget _itemTile(ThemeData theme, HardwareItem item) {
    String fmt(double p) =>
        p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
    return ListTile(
      leading: CategoryBadge(category: item.category),
      title: Text(item.model),
      subtitle: Text(
        item.brand.isEmpty ? item.platform : '${item.brand} · ${item.platform}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '¥${fmt(item.price)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(item),
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }

  /// 整机方案分类：直接读整机方案（BuildPlanStore）自动出现
  Widget _planTab() {
    if (_plans.isEmpty) return _emptyCategory('整机方案');

    final entries = <Widget>[
      // 活方案用「文件夹」风格卡片，与整机方案页的文件夹列表保持一致
      for (final plan in _plans)
        _PlanFolderCard(
          plan: plan,
          onTap: () => _openPlanById(plan.id),
          onDeconstruct: () => _deconstructPlan(context, plan),
        ),
    ];

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index],
    );
  }

  Widget _emptyCategory(String category) {
    final isPlan = category == '整机方案';
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          categoryIcon(category),
          size: 48,
          color: categoryColor(category),
        ),
        const SizedBox(height: 8),
        const Text("啊嘞，这里还没有数据，创建第一个数据吧 (●'◡'●)"),
        const SizedBox(height: 4),
        Text(
          isPlan ? '在顶部「整机方案」里创建后会自动出现在这里' : '可去「硬件库」选型号，或点右下角 + 添加',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
    // 空状态也做成可滚动，让标题栏能随上滑淡出、并带橡皮筋回弹
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// 解构整机方案产生的大圆角矩形卡片：方案名 + 总价 + 各硬件明细
class _DeconstructedCard extends StatelessWidget {
  const _DeconstructedCard({required this.item, required this.onDelete});

  final HardwareItem item;
  final VoidCallback onDelete;

  String _fmt(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines =
        item.spec.split('\n').where((e) => e.trim().isNotEmpty).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.model,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                Text(
                  '¥${_fmt(item.price)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

/// 硬件清单「整机方案」分类里的活方案卡片：圆形文件夹图标 + 方案名 + 件数 + 总价
/// 风格与整机方案页的文件夹列表保持一致（点击进入该方案）
class _PlanFolderCard extends StatelessWidget {
  const _PlanFolderCard({
    required this.plan,
    required this.onTap,
    required this.onDeconstruct,
  });

  final BuildPlan plan;
  final VoidCallback onTap;
  final VoidCallback onDeconstruct;

  String _fmt(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = plan.name.isEmpty ? '未命名方案' : plan.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // 解构按钮放在 InkWell 外面，避免点击时被 onTap（进方案）抢走手势导致无反应
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(kCardRadius),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${plan.filledCount} 件',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '¥${_fmt(plan.total)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDeconstruct,
            tooltip: '解构到清单',
            icon: const Icon(Icons.call_split, size: 20),
          ),
        ],
      ),
    );
  }
}
