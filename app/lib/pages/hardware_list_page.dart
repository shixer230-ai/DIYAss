import 'package:flutter/material.dart';

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
    final items = await _store.loadAll();
    final plans = await BuildPlanStore().loadAll();
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
    final items = _items.where((e) => e.category == category).toList();
    if (items.isEmpty) return _emptyCategory(category);
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
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _HardwareCard(
          item: item,
          onDelete: () => _confirmDelete(item),
          onTap: null,
        );
      },
    );
  }

  /// 整机方案分类：直接读整机方案（BuildPlanStore）自动出现；
  /// 「保存到清单」产生的快照在方案删除后仍保留，作为孤儿条目列出（可删）
  Widget _planTab() {
    final liveIds = _plans.map((p) => p.id).toSet();
    final orphans = _items
        .where((e) =>
            e.category == '整机方案' &&
            e.planId != null &&
            !liveIds.contains(e.planId))
        .toList();
    if (_plans.isEmpty && orphans.isEmpty) return _emptyCategory('整机方案');

    final entries = <Widget>[
      for (final plan in _plans)
        _HardwareCard(
          item: HardwareItem(
            id: plan.id,
            category: '整机方案',
            brand: '',
            model: plan.name.isEmpty ? '未命名方案' : plan.name,
            price: plan.total,
            platform: '',
            spec: '',
            planId: plan.id,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          onDelete: null,
          onTap: () => _openPlanById(plan.id),
        ),
      for (final snap in orphans)
        _HardwareCard(
          item: snap,
          onDelete: () => _confirmDelete(snap),
          onTap: null,
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
        Text(isPlan ? '还没有整机方案' : '还没有「$category」的记录'),
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
          child: Center(child: content),
        ),
      ),
    );
  }
}

class _HardwareCard extends StatelessWidget {
  const _HardwareCard({required this.item, this.onDelete, this.onTap});

  final HardwareItem item;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  String _formatPrice(double p) {
    return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlan = item.planId != null;
    // 整机方案只展示方案名称，隐藏 CPU/显卡 等配件摘要
    final subtitle = [
      if (item.brand.isNotEmpty) item.brand,
      if (item.platform.isNotEmpty) item.platform,
      if (item.spec.isNotEmpty && !isPlan) item.spec,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CategoryBadge(category: item.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.model,
                      style: TextStyle(
                        // 整机方案：方案名加粗加大；普通硬件保持原样
                        fontWeight: isPlan ? FontWeight.w700 : FontWeight.w600,
                        fontSize: isPlan ? 19 : 16,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      item.category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¥${_formatPrice(item.price)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
