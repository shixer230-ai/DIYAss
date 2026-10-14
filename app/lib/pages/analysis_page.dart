import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_navbar_plus/liquid_glass_bottom_navbar_plus.dart';

import '../ai/ai_analysis.dart';
import '../analysis/value_index.dart';
import '../cloud/auth_service.dart';
import '../cloud/cloud_sync.dart';
import '../data/hardware_library.dart';
import '../models/build_plan.dart';
import '../models/custom_item.dart';
import '../models/hardware_spec.dart';
import '../storage/build_plan_store.dart';
import '../storage/custom_item_store.dart';
import '../theme/app_theme.dart';
import 'ai_analysis_page.dart';
import 'custom_item_form_page.dart';

/// 分析页：按所选「性价比项目」（内置跑分/功耗 + 自定义项目）给整机方案排行
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key, this.isActive = true});

  /// 当前是否为底部导航选中的标签页；切回来时用于刷新方案数据
  final bool isActive;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage>
    with AutomaticKeepAliveClientMixin {
  final _planStore = BuildPlanStore();
  final _customStore = CustomItemStore();

  List<BuildPlan> _plans = [];
  List<HardwareSpec> _library = [];
  List<CustomItem> _customItems = [];
  ValueItem _builtin = kValueItems.first; // 选中的内置项目
  String? _customId; // 选中的自定义项目 id（null = 没选自定义）
  bool _loading = true;
  bool _syncing = false; // 云同步防连点
  int _mode = 0; // 0=性价比排行，1=AI 分析，2=可靠性分析
  Set<String> _pendingDeletes = {}; // 待补删云端的自定义项目 id
  Set<String> _planPendingDeletes = {}; // 待补删云端的方案 id（与整机方案页共用墓碑）

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从其他标签页切回来时刷新方案/配件数据，避免排行滞后
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  Future<void> _load() async {
    final plans = await _planStore.loadAll();
    final lib = await loadHardwareLibrary();
    final customs = await _customStore.loadAll();
    final pending = await _customStore.loadPendingDeleteIds();
    final planPending = await _planStore.loadPendingDeleteIds();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _library = lib;
      _customItems = customs;
      _pendingDeletes = pending;
      _planPendingDeletes = planPending;
      _loading = false;
    });

    // 已登录时自动从云同步（替代原先手动点「从云恢复」按钮）
    if (AuthService.instance.isLoggedIn) {
      _restoreFromCloud(silent: true);
    }
  }

  Future<void> _reloadCustoms() async {
    final customs = await _customStore.loadAll();
    if (!mounted) return;
    setState(() => _customItems = customs);
  }

  CustomItem? get _custom {
    for (final c in _customItems) {
      if (c.id == _customId) return c;
    }
    return null;
  }

  bool get _isCustom => _custom != null;

  /// 是否为「整机功耗」这类数值越小越好的整机指标
  bool get _isPower => _builtin.category == '整机';

  List<_Choice> get _choices => [
    for (final item in kValueItems) _Choice.builtin(item),
    for (final c in _customItems) _Choice.custom(c),
  ];

  _Choice get _selectedChoice =>
      _isCustom ? _Choice.custom(_custom!) : _Choice.builtin(_builtin);

  void _onChoiceChanged(_Choice? choice) {
    if (choice == null) return;
    setState(() {
      if (choice.isCustom) {
        _customId = choice.custom!.id;
      } else {
        _builtin = choice.builtin!;
        _customId = null;
      }
    });
  }

  Future<void> _addCustom() async {
    final result = await Navigator.push<CustomItem>(
      context,
      MaterialPageRoute(builder: (_) => const CustomItemFormPage()),
    );
    if (result == null) return;
    await _customStore.add(result);
    await _reloadCustoms();
    if (!mounted) return;
    setState(() => _customId = result.id);
    _uploadCustom(result);
  }

  Future<void> _editCustom() async {
    final item = _custom;
    if (item == null) return;
    final result = await Navigator.push<CustomItem>(
      context,
      MaterialPageRoute(builder: (_) => CustomItemFormPage(initial: item)),
    );
    if (result == null) return;
    await _customStore.update(result);
    await _reloadCustoms();
    _uploadCustom(result);
  }

  Future<void> _deleteCustom() async {
    final item = _custom;
    if (item == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义项目'),
        content: Text('确定删除「${item.fullLabel}」吗？已填的分数会一并删除'),
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
    if (ok != true) return;
    await _customStore.remove(item.id);
    if (_customId == item.id) _customId = null;
    await _reloadCustoms();

    // 记墓碑 + 尽力删云端（离线/失败稍后自动补删）
    _pendingDeletes.add(item.id);
    await _customStore.savePendingDeleteIds(_pendingDeletes);
    if (!AuthService.instance.isLoggedIn) return;
    try {
      await CloudSync.deleteCustomItem(item.id);
    } catch (_) {
      // 删不掉就留着墓碑，下次恢复时过滤掉
    }
  }

  /// 新建/编辑后尽力上传到云（不阻断本地流程）
  Future<void> _uploadCustom(CustomItem item) async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      await CloudSync.uploadCustomItem(item);
    } catch (_) {
      _snack('本地已保存；云端同步失败');
    }
  }

  /// 从云拉取数据：先恢复整机方案（分析排行要用），再恢复自定义项目（分数按方案 id 关联）
  /// 两边都按 id 去重并入本地，墓碑里的条目会被过滤
  Future<void> _restoreFromCloud({bool silent = false}) async {
    if (!AuthService.instance.isLoggedIn) {
      if (!silent) _snack('请先在「我的」页登录');
      return;
    }
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      // 1) 恢复整机方案
      for (final id in _planPendingDeletes.toList()) {
        try {
          await CloudSync.deletePlan(id);
        } catch (_) {}
      }
      final cloudPlans = await CloudSync.downloadPlans();
      final cloudPlanIds = cloudPlans.map((p) => p.id).toSet();
      _planPendingDeletes.removeWhere((id) => !cloudPlanIds.contains(id));
      await _planStore.savePendingDeleteIds(_planPendingDeletes);
      final visiblePlans = cloudPlans
          .where((p) => !_planPendingDeletes.contains(p.id))
          .toList();
      final existingPlanIds = _plans.map((p) => p.id).toSet();
      final freshPlans = visiblePlans
          .where((p) => !existingPlanIds.contains(p.id))
          .toList();

      // 2) 恢复自定义项目
      for (final id in _pendingDeletes.toList()) {
        try {
          await CloudSync.deleteCustomItem(id);
        } catch (_) {}
      }
      final cloud = await CloudSync.downloadCustomItems();
      final cloudIds = cloud.map((c) => c.id).toSet();
      _pendingDeletes.removeWhere((id) => !cloudIds.contains(id));
      await _customStore.savePendingDeleteIds(_pendingDeletes);
      final visible = cloud
          .where((c) => !_pendingDeletes.contains(c.id))
          .toList();
      final existing = _customItems.map((c) => c.id).toSet();
      var added = 0;
      for (final c in visible) {
        if (!existing.contains(c.id)) {
          await _customStore.add(c);
          added++;
        }
      }

      // 落盘并刷新界面（_reloadCustoms 的 setState 会一并带上新的 _plans）
      if (freshPlans.isNotEmpty) {
        _plans = [..._plans, ...freshPlans];
        await _planStore.saveAll(_plans);
      }
      await _reloadCustoms();

      if (!silent) {
        final parts = <String>[
          if (freshPlans.isNotEmpty) '${freshPlans.length} 个方案',
          if (added > 0) '$added 个项目',
        ];
        _snack(parts.isEmpty ? '云端数据已在本地' : '已从云恢复 ${parts.join('、')}');
      }
    } catch (e) {
      if (!silent) _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 打开 AI 分析（需登录；分析用户选中的某个方案）
  /// API Key 在云函数里，这里不再解析 key，直接进分析页由云函数代调用
  void _openAiAnalysis(BuildPlan plan, {required String mode}) {
    if (!AuthService.instance.isLoggedIn) {
      _snack('AI 分析需要登录，请先在「我的」页注册/登录');
      return;
    }
    final prompt = mode == 'reliability'
        ? buildReliabilityPrompt(plan)
        : buildPlanPrompt(plan);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiAnalysisPage(
          title: plan.name.isEmpty ? '未命名方案' : plan.name,
          prompt: prompt,
          mode: mode,
        ),
      ),
    );
  }

  Future<void> _saveScore(CustomItem item, String planId, double? value) async {
    item.setScore(planId, value);
    setState(() {});
    await _customStore.saveAll(_customItems);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              bottom: false,
              // 与「清单」页顶部一致的固定布局：液态玻璃分段放在非滚动区域
              // 之前放进 NestedScrollView 里，滑动时 BackdropFilter 采样区域跟着
              // 移动导致渲染出错；改成固定 Column 后分段不再随内容滚动，恢复正常
              child: Column(
                children: [
                  _glassSegmented(theme),
                  if (_mode == 0) ...[
                    _selector(theme),
                    Expanded(child: _body(theme)),
                  ] else if (_mode == 1)
                    Expanded(child: _aiView(theme))
                  else
                    Expanded(child: _reliabilityView(theme)),
                ],
              ),
            ),
    );
  }

  /// 顶部液态玻璃分段（与「清单」顶部分段一致）：性价比排行 / AI 分析 / 可靠性分析
  Widget _glassSegmented(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: GlassPressFeedback(
        clipRadius: 24,
        child: LiquidGlassBottomBar(
          items: const [
            LiquidGlassBarItem(label: '性价比排行'),
            LiquidGlassBarItem(label: 'AI 分析'),
            LiquidGlassBarItem(label: '可靠性分析'),
          ],
          selectedIndex: _mode,
          onDestinationSelected: (i) => setState(() => _mode = i),
          height: 48,
          margin: EdgeInsets.zero,
          applyBottomInset: false,
          theme: LiquidGlassBarTheme(
            iconColor: scheme.onSurfaceVariant,
            selectedIconColor: scheme.primary,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            selectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            pillColor: scheme.primary.withValues(alpha: 0.14),
            showLabels: true,
          ),
        ),
      ),
    );
  }

  /// AI 分析模式：列出所有方案，用户点一个进入常规分析
  Widget _aiView(ThemeData theme) => _planPicker(
        theme,
        mode: 'general',
        icon: Icons.auto_awesome,
        hint: '选择一个方案，AI 会分析它的亮点、侧重、局限与超频稳定性',
      );

  /// 可靠性分析模式：列出所有方案，用户点一个进入可靠性分析
  Widget _reliabilityView(ThemeData theme) => _planPicker(
        theme,
        mode: 'reliability',
        icon: Icons.verified_user_outlined,
        hint: '选择一个方案，AI 会检测功耗稳定性、魔改 CPU / 矿卡等硬件风险',
      );

  /// 方案选择列表（AI 分析 / 可靠性分析共用）：一行一个方案，点按进入对应分析
  Widget _planPicker(
    ThemeData theme, {
    required String mode,
    required IconData icon,
    required String hint,
  }) {
    if (_plans.isEmpty) return _empty(theme);
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
        for (final plan in _plans) _planCard(theme, plan, mode, icon),
      ],
    );
  }

  /// 方案选择卡片：方案名 + 配件数 + 总价，点按进入分析
  Widget _planCard(ThemeData theme, BuildPlan plan, String mode, IconData icon) {
    final name = plan.name.isEmpty ? '未命名方案' : plan.name;
    final count = plan.components.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          onTap: () => _openAiAnalysis(plan, mode: mode),
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$count 个配件 · 整机 ¥${_fmt(plan.total)}'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  Widget _selector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: GlassField(
              child: GlassDropdown<_Choice>(
                initialValue: _selectedChoice,
                decoration: const InputDecoration(
                  labelText: '分析项目',
                  prefixIcon: Icon(Icons.tune),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
                items: [
                  for (final c in _choices)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _onChoiceChanged,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 分析',
            onPressed: () => setState(() => _mode = 1),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建自定义项目',
            onPressed: _addCustom,
          ),
          if (_isCustom)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑此项目',
              onPressed: _editCustom,
            ),
          if (_isCustom)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除此项目',
              onPressed: _deleteCustom,
            ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_isCustom) return _customBody(theme);

    final results = rankPlans(_plans, _builtin, _library);
    final skipped = _plans.length - results.length;
    final topIndex = results.isEmpty ? 0.0 : results.first.index;
    final topPrice = results.isEmpty ? 0.0 : results.first.price;
    // 第一名与后续方案价差 ≥30% 时，只在顶部提示一次
    final showPriceWarn = !_isPower &&
        topPrice > 0 &&
        results.skip(1).any((r) => (r.price - topPrice).abs() >= topPrice * 0.30);
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        if (showPriceWarn) _priceWarnBanner(theme),
        if (results.isEmpty)
          _empty(theme)
        else
          for (final v in results) _capsule(theme, v, topIndex),
        if (results.isNotEmpty && skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _isPower
                  ? '另有 $skipped 个方案未上榜（功耗数据未匹配）'
                  : '另有 $skipped 个方案未上榜（缺少「${_builtin.category}」或型号未匹配）',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _customBody(ThemeData theme) {
    final custom = _custom!;
    if (_plans.isEmpty) return _empty(theme);

    // 性价比指数 = 分数 ÷ 整机总价 × 1000，越大越好；总价为 0 的排在最后
    double indexOf(BuildPlan p) {
      final s = custom.scoreOf(p.id);
      if (s == null || p.total <= 0) return double.negativeInfinity;
      return s / p.total * 1000;
    }

    final scored = _plans.where((p) => custom.scoreOf(p.id) != null).toList()
      ..sort((a, b) => indexOf(b).compareTo(indexOf(a)));
    final unscored = _plans.where((p) => custom.scoreOf(p.id) == null).toList();

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + bottomNavClearance(context),
      ),
      children: [
        Text(
          '填写各方案的「${custom.scoreLabel}」，点 ✓ 保存后按性价比指数从高到低排行',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < scored.length; i++)
          _CustomScoreCard(
            key: ValueKey('${custom.id}-${scored[i].id}'),
            plan: scored[i],
            item: custom,
            rank: i + 1,
            onSave: (v) => _saveScore(custom, scored[i].id, v),
          ),
        for (final plan in unscored)
          _CustomScoreCard(
            key: ValueKey('${custom.id}-${plan.id}'),
            plan: plan,
            item: custom,
            onSave: (v) => _saveScore(custom, plan.id, v),
          ),
      ],
    );
  }

  Widget _empty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.insights, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _plans.isEmpty ? '还没有整机方案' : '没有可评分的方案',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _plans.isEmpty
                ? '先去「整机方案」建一个方案，并选好 CPU / 显卡'
                : _isPower
                ? '所选「整机功耗」下，方案里配件的功耗数据未匹配到硬件库'
                : '所选「${_builtin.label}」下，方案里缺少对应部件或型号未匹配到硬件库',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// 顶部价差提示：第一名与后续方案价差 ≥30% 时显示一次（胶囊样式，与排行胶囊统一）
  Widget _priceWarnBanner(ThemeData theme) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '性价比参考性较低，建议比价近似价格区间的方案',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  /// 性价比胶囊条：整条满宽即底部导航栏的宽度（ListView 内容区 = 屏幕宽 - 24，
  /// 与底部导航的外边距一致），第一名满宽、其余按相对百分比缩短，低于 20% 按 20% 显示
  /// 胶囊内只显示方案名 + 数值（性价比指数 / 整机功耗），不再展示跑分、价格与序号
  Widget _capsule(ThemeData theme, PlanValue v, double topIndex) {
    final ratio = topIndex <= 0
        ? 1.0
        : (_isPower ? topIndex / v.index : v.index / topIndex);
    final clamped = ratio < 0.2 ? 0.2 : ratio;
    final value = _isPower ? '${_fmt(v.index)}W' : v.index.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.38),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    v.planName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择器里的一个选项：内置项目或自定义项目
class _Choice {
  final ValueItem? builtin;
  final CustomItem? custom;

  const _Choice.builtin(ValueItem v) : builtin = v, custom = null;
  const _Choice.custom(CustomItem c) : builtin = null, custom = c;

  bool get isCustom => custom != null;
  String get label => isCustom ? custom!.fullLabel : builtin!.label;

  @override
  bool operator ==(Object other) =>
      other is _Choice &&
      identical(builtin, other.builtin) &&
      custom?.id == other.custom?.id;

  @override
  int get hashCode => isCustom ? custom!.id.hashCode : builtin.hashCode;
}

/// 自定义项目下：一个方案一行，附分数输入框；有分数的按排名显示序号
class _CustomScoreCard extends StatefulWidget {
  const _CustomScoreCard({
    super.key,
    required this.plan,
    required this.item,
    this.rank,
    required this.onSave,
  });

  final BuildPlan plan;
  final CustomItem item;
  final int? rank;
  final ValueChanged<double?> onSave;

  @override
  State<_CustomScoreCard> createState() => _CustomScoreCardState();
}

class _CustomScoreCardState extends State<_CustomScoreCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final v = widget.item.scoreOf(widget.plan.id);
    _controller = TextEditingController(text: v == null ? '' : _fmt(v));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final t = _controller.text.trim();
    if (t.isEmpty) {
      widget.onSave(null);
      return;
    }
    final n = double.tryParse(t);
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入大于 0 的数字')));
      return;
    }
    widget.onSave(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = widget.item.scoreOf(widget.plan.id);
    final index = (score != null && widget.plan.total > 0)
        ? score / widget.plan.total * 1000
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.38),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.plan.name.isEmpty ? '未命名方案' : widget.plan.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (score != null)
                    Text(
                      '整机 ¥${_fmt(widget.plan.total)} · ${widget.item.scoreLabel} ${_fmt(score)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: widget.item.scoreLabel,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    tooltip: '保存',
                    onPressed: _save,
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    index == null ? '—' : index.toStringAsFixed(1),
                    key: ValueKey(index),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  '性价比指数',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
