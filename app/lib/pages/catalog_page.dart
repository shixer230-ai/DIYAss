import 'package:flutter/material.dart';

import '../cloud/auth_service.dart';
import '../cloud/cloud_sync.dart';
import '../data/hardware_catalog.dart';
import '../data/hardware_library.dart';
import '../models/cloud_plan.dart';
import '../models/hardware_spec.dart';
import '../storage/hardware_catalog_store.dart';
import '../storage/user_spec_store.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import 'catalog_detail_page.dart';
import 'cloud_plan_detail_page.dart';
import 'user_spec_form_page.dart';

/// 硬件库：顶部关键词搜索；按品类分 Tab，左右滑动切换；首个 Tab 是「我的添加」
/// 预置型号在各品类内按品牌分组展示（主流品牌 + 其它）
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _userStore = UserSpecStore();
  final _searchController = TextEditingController();
  List<HardwareSpec> _userSpecs = [];
  List<HardwareSpec> _cloudSpecs = [];
  bool _cloudSynced = false;
  String _query = '';

  // 公开的云方案列表（用户上传到「云方案」栏目）
  List<CloudPlan> _cloudPlans = [];
  bool _loadingPlans = false;

  // 预置库的品类顺序（即各 Tab 的顺序）
  static const _categories = ['CPU', '显卡', '主板', '内存', '硬盘', '电源', '机箱'];

  // 搜索结果的品类展示顺序（含用户自定义可能用到的品类）
  static const _searchCategories = [
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length + 2, vsync: this);
    _searchController.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (!mounted) return;
    setState(() => _query = _searchController.text);
  }

  Future<void> _load() async {
    final specs = await _userStore.loadAll();
    final cloud = await HardwareCatalogStore().load();
    if (!mounted) return;
    setState(() {
      _userSpecs = specs;
      _cloudSpecs = cloud;
    });
    _refreshCloud();
    _loadCloudPlans();
  }

  /// 后台拉最新云端硬件并刷新（每次进入硬件库只同步一次）
  Future<void> _refreshCloud() async {
    if (_cloudSynced) return;
    _cloudSynced = true;
    await syncHardwareCatalogFromCloud();
    final cloud = await HardwareCatalogStore().load();
    if (!mounted) return;
    setState(() => _cloudSpecs = cloud);
  }

  Future<void> _openDetail(HardwareSpec spec) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CatalogDetailPage(spec: spec)),
    );
    // 返回后刷新，可能增删了「我的添加」
    _load();
  }

  Future<void> _openCustomForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const UserSpecFormPage()),
    );
    if (saved == true) _load();
  }

  /// 拉取公开的云方案列表；失败保持现状（可能未登录或无网络）
  Future<void> _loadCloudPlans() async {
    if (_loadingPlans) return;
    setState(() => _loadingPlans = true);
    try {
      final plans = await CloudSync.downloadCloudPlans();
      if (!mounted) return;
      setState(() => _cloudPlans = plans);
    } catch (_) {
      // 拉取失败保持现状
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _openCloudPlan(CloudPlan p) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CloudPlanDetailPage(plan: p)),
    );
    if (deleted == true) _loadCloudPlans();
  }

  /// 删除自己上传的云方案（长按卡片触发）
  Future<void> _deleteCloudPlan(CloudPlan p) async {
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「我的」页登录，再删除')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除云方案'),
        content: Text('确定删除「${p.name}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await CloudSync.deleteCloudPlan(p.id);
      if (!mounted) return;
      setState(() => _cloudPlans.removeWhere((x) => x.id == p.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _toggleLike(CloudPlan p) async {
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「我的」页登录，再点赞')),
      );
      return;
    }
    final uid = AuthService.instance.uid!;
    try {
      final r = await CloudSync.likePlan(p.id);
      if (!mounted) return;
      setState(() {
        final newLikers = List<String>.from(p.likers);
        if (r.liked) {
          if (!newLikers.contains(uid)) newLikers.add(uid);
        } else {
          newLikers.remove(uid);
        }
        final i = _cloudPlans.indexWhere((x) => x.id == p.id);
        if (i >= 0) _cloudPlans[i] = p.copyWith(likers: newLikers);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _buildCloudPlansTab() {
    if (_loadingPlans) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cloudPlans.isEmpty) return _emptyCloudPlans();
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
      itemCount: _cloudPlans.length,
      itemBuilder: (context, i) => _cloudPlanCard(_cloudPlans[i]),
    );
  }

  Widget _emptyCloudPlans() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('还没有公开的云方案'),
          const SizedBox(height: 4),
          Text(
            '在「整机方案」里点「上传到云方案」，就能把方案分享到这里',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _cloudPlanCard(CloudPlan p) {
    final theme = Theme.of(context);
    final uid = AuthService.instance.uid;
    final liked = uid != null && p.likedBy(uid);
    final isOwner = uid != null && p.owner == uid;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: () => _openCloudPlan(p),
        onLongPress: isOwner ? () => _deleteCloudPlan(p) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CategoryBadge(category: '整机方案'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.filledCount} 件 · ${p.date}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '¥${_fmtPrice(p.total)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              _likeButton(theme, p, liked),
            ],
          ),
        ),
      ),
    );
  }

  Widget _likeButton(ThemeData theme, CloudPlan p, bool liked) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _toggleLike(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 22,
              color: liked ? Colors.pink : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              '${p.likeCount}',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPrice(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  bool get _searching => _query.trim().isNotEmpty;

  List<HardwareSpec> get _searchResults {
    final all = [...kHardwareCatalog, ..._cloudSpecs, ..._userSpecs];
    return all.where((s) => hardwareMatches(s, _query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: false,
              floating: false,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: const Text('硬件库'),
            ),
          ],
          body: Column(
            children: [
              _searchBar(),
              if (_searching)
                Expanded(child: _buildSearchResults())
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: [
                      const Tab(text: '云方案'),
                      const Tab(text: '我的添加'),
                      for (final c in _categories) Tab(text: c),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCloudPlansTab(),
                      _buildMineTab(),
                      for (final c in _categories) _buildCategoryTab(c),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
            // 去掉 isDense，用显式上下内边距让输入文字在玻璃框内垂直居中
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('没有找到「${_query.trim()}」相关的型号'),
          ],
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        for (final category in _searchCategories)
          ..._searchSection(category, results),
      ],
    );
  }

  List<Widget> _searchSection(String category, List<HardwareSpec> results) {
    final list = results.where((s) => s.category == category).toList();
    if (list.isEmpty) return const [];
    return [
      _sectionHeader(category),
      for (final s in list) _specCard(context, s),
    ];
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildMineTab() {
    final sections = _mineBrandSections();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '我的添加',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _openCustomForm,
              icon: const Icon(Icons.add),
              label: const Text('自定义添加'),
            ),
          ],
        ),
        if (_userSpecs.isEmpty)
          _emptyMine(context)
        else
          for (final sec in sections) _brandGroupCard(sec.brand, sec.specs),
      ],
    );
  }

  /// 「我的添加」按品牌堆叠：主流品牌在前（跨品类去重），其余归「其它」
  List<({String brand, List<HardwareSpec> specs})> _mineBrandSections() {
    final order = <String>[
      for (final mains in kBrandGroups.values) ...mains,
      '其它',
    ];
    final seen = <String>{};
    final unique = order.where((b) => seen.add(b)).toList();
    final sections = <({String brand, List<HardwareSpec> specs})>[];
    for (final brand in unique) {
      final list =
          _userSpecs
              .where((s) => brandGroupOf(s.category, s.brand) == brand)
              .toList()
            ..sort((a, b) => a.model.compareTo(b.model));
      if (list.isNotEmpty) sections.add((brand: brand, specs: list));
    }
    return sections;
  }

  Widget _buildCategoryTab(String category) {
    final specs = [...kHardwareCatalog, ..._cloudSpecs]
        .where((s) => s.category == category)
        .toList();
    final sections = _brandSections(category, specs);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        Text(
          '预置参考型号，跑分为约值，点击查看详情',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (final sec in sections) _brandGroupCard(sec.brand, sec.specs),
      ],
    );
  }

  /// 按品牌把某品类的型号分组：主流品牌在前（按 kBrandGroups 顺序），其余归「其它」
  List<({String brand, List<HardwareSpec> specs})> _brandSections(
    String category,
    List<HardwareSpec> specs,
  ) {
    final mains = kBrandGroups[category] ?? const <String>[];
    final order = [...mains, '其它'];
    final sections = <({String brand, List<HardwareSpec> specs})>[];
    for (final brand in order) {
      final list =
          specs.where((s) => brandGroupOf(category, s.brand) == brand).toList()
            ..sort((a, b) => a.model.compareTo(b.model));
      if (list.isNotEmpty) sections.add((brand: brand, specs: list));
    }
    return sections;
  }

  Widget _emptyMine(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.bookmark_add_outlined,
              size: 36,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            const Text('还没有自定义添加的型号'),
            const SizedBox(height: 4),
            Text(
              '点「自定义添加」录入新硬件，或在预置型号详情里点「加入我的添加」收藏',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个型号行（不含卡片），用于放进品牌分组大卡片内
  Widget _specTile(BuildContext context, HardwareSpec spec) {
    return ListTile(
      leading: CategoryBadge(category: spec.category),
      title: Text(spec.model),
      subtitle: Text(spec.brand),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openDetail(spec),
    );
  }

  /// 搜索结果里的单个型号卡片（保持独立卡片样式）
  Widget _specCard(BuildContext context, HardwareSpec spec) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: _specTile(context, spec),
    );
  }

  Widget _brandGroupCard(String brand, List<HardwareSpec> specs) {
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
          for (var i = 0; i < specs.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16),
            _specTile(context, specs[i]),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
