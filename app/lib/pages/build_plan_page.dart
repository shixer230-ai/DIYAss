import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../app_info.dart';
import '../analysis/compat_check.dart';
import '../cloud/auth_service.dart';
import '../cloud/cloud_sync.dart';
import '../analysis/value_index.dart';
import '../data/hardware_library.dart';
import '../models/build_plan.dart';
import '../models/hardware_item.dart';
import '../models/hardware_spec.dart';
import '../storage/build_plan_store.dart';
import '../storage/hardware_store.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import 'component_picker_page.dart';

/// 整机方案的一个槽位
class BuildSlot {
  final String key;
  final String label;
  final String category;
  final bool required;

  const BuildSlot(this.key, this.label, this.category, {this.required = true});
}

const kBuildSlots = [
  BuildSlot('cpu', 'CPU', 'CPU'),
  BuildSlot('gpu', '显卡', '显卡', required: false),
  BuildSlot('motherboard', '主板', '主板'),
  BuildSlot('ram', '内存', '内存'),
  BuildSlot('storage', '硬盘', '硬盘'),
  BuildSlot('psu', '电源', '电源'),
  BuildSlot('case', '机箱', '机箱', required: false),
];

/// 整机方案：支持多个方案（新建/切换/重命名/删除），按槽位选配件自动汇总总金额
class BuildPlanPage extends StatefulWidget {
  const BuildPlanPage({super.key, this.isActive = true});

  /// 当前是否为底部导航选中的标签页；从清单页点方案切过来时用于刷新当前方案
  final bool isActive;

  @override
  State<BuildPlanPage> createState() => _BuildPlanPageState();
}

class _BuildPlanPageState extends State<BuildPlanPage>
    with AutomaticKeepAliveClientMixin {
  final _store = BuildPlanStore();
  List<BuildPlan> _plans = [];
  String? _currentId;
  bool _loading = true;

  // 云同步防连点
  bool _syncing = false;

  // 上传到云方案的防连点
  bool _publishing = false;

  // 进入方案编辑时的快照 + 是否有未保存改动（退出时据此询问是否保存）
  BuildPlan? _editSnapshot;
  bool _dirty = false;

  // 离线删除时没删掉的云端方案 id（墓碑），下次登录时补删
  Set<String> _pendingDeletes = {};

  // 硬件库（预置 + 我的添加），用于计算默认的 CPU+显卡 功耗
  List<HardwareSpec> _library = [];

  @override
  bool get wantKeepAlive => true;

  BuildPlan? get _current {
    if (_currentId == null) return null;
    for (final p in _plans) {
      if (p.id == _currentId) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BuildPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从清单页点某个方案跳过来时，重新读取当前方案 id
    if (widget.isActive && !oldWidget.isActive && !_dirty) _load();
  }

  Future<void> _load() async {
    final plans = await _store.loadAll();
    final currentId = await _store.loadCurrentId();
    final pending = await _store.loadPendingDeleteIds();
    final lib = await loadHardwareLibrary();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _currentId = currentId;
      _pendingDeletes = pending;
      _library = lib;
      _loading = false;
    });

    // 已登录时自动从云同步（替代原先手动点「从云恢复」按钮）
    if (AuthService.instance.isLoggedIn) {
      _autoSyncFromCloud();
    }
  }

  Future<void> _createPlan() async {
    if (_plans.length >= CloudSync.kMaxCloudPlans) {
      _snack('方案数量已达上限（${CloudSync.kMaxCloudPlans} 个）');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: '新建方案',
        initial: _nextName(_plans),
        forbidden: _takenNames(null),
      ),
    );
    if (name == null) return;
    final plan = BuildPlan(name: name);
    setState(() {
      _plans.add(plan);
      _currentId = plan.id;
      _editSnapshot = _copyPlan(plan);
      _dirty = false;
    });
    await _store.saveAll(_plans);
    await _store.saveCurrentId(plan.id);
  }

  Future<void> _openPlan(BuildPlan plan) async {
    setState(() {
      _currentId = plan.id;
      _editSnapshot = _copyPlan(plan);
      _dirty = false;
    });
    await _store.saveCurrentId(plan.id);
  }

  Future<void> _backToList() async {
    if (_dirty) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('是否保存修改'),
          content: const Text('有未保存的修改，要保存吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (action == null) return; // 点外部取消，留在编辑页
      final plan = _current;
      if (action == 'save') {
        await _store.saveAll(_plans);
        if (plan != null) await _autoUpload(plan);
      } else {
        // 不保存：还原进入编辑前的快照
        if (plan != null && _editSnapshot != null) {
          setState(() => _replace(plan.id, _editSnapshot!));
        }
      }
    }
    setState(() {
      _currentId = null;
      _dirty = false;
    });
    await _store.saveCurrentId(null);
  }

  /// 现有方案名（trim + 小写归一化）用于查重；重命名时排除自身，允许保留原名
  Set<String> _takenNames(String? excludeId) => {
        for (final p in _plans)
          if (p.id != excludeId) p.name.trim().toLowerCase(),
      };

  Future<void> _rename(BuildPlan plan) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: '重命名',
        initial: plan.name,
        forbidden: _takenNames(plan.id),
      ),
    );
    if (name == null) return;
    final updated = BuildPlan(
      id: plan.id,
      name: name,
      components: plan.components,
      storages: plan.storages,
      customPower: plan.customPower,
    );
    setState(() {
      final i = _plans.indexWhere((p) => p.id == plan.id);
      _plans[i] = updated;
    });
    await _store.saveAll(_plans);
    await _autoUpload(updated);
  }

  Future<void> _delete(BuildPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除方案'),
        content: Text('确定删除「${_planName(plan)}」吗？'),
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
    setState(() {
      _plans.removeWhere((p) => p.id == plan.id);
      if (_currentId == plan.id) _currentId = null;
    });
    await _store.saveAll(_plans);
    await _store.saveCurrentId(_currentId);

    // 无论如何先记墓碑：这个方案「本地已删，云端也不该再回来」
    // 墓碑要等下次恢复时确认云端真的没了才清除，防止云端删除刚提交、
    // 读取还有短暂延迟时又把它拉回来
    _pendingDeletes.add(plan.id);
    await _store.savePendingDeleteIds(_pendingDeletes);

    if (!AuthService.instance.isLoggedIn) {
      _snack('已删除「${_planName(plan)}」');
      return;
    }
    try {
      await CloudSync.deletePlan(plan.id);
      _snack('已删除「${_planName(plan)}」（本地与云端）');
    } catch (_) {
      _snack('本地已删除；云端删除失败，稍后自动重试');
    }
  }

  Future<void> _clearAll() async {
    final plan = _current;
    if (plan == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空方案'),
        content: const Text('确定清空这个方案里的所有配件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _replace(plan.id, BuildPlan(id: plan.id, name: plan.name));
      _dirty = true;
    });
  }

  Future<void> _pick(BuildSlot slot) async {
    final plan = _current;
    if (plan == null) return;
    final result = await Navigator.push<(bool, PlanComponent?)>(
      context,
      MaterialPageRoute(
        builder: (_) => ComponentPickerPage(
          slotLabel: slot.label,
          category: slot.category,
          current: plan[slot.key],
        ),
      ),
    );
    if (result == null) return; // 取消，不改动
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: List.of(plan.storages),
      customPower: plan.customPower,
    );
    updated.set(slot.key, result.$1 ? null : result.$2);
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  /// 移除某个槽位里已选的配件（槽位卡片最右侧的删除按钮）
  Future<void> _clearSlot(BuildSlot slot) async {
    final plan = _current;
    if (plan == null || plan[slot.key] == null) return;
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: List.of(plan.storages),
      customPower: plan.customPower,
    );
    updated.set(slot.key, null);
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  /// 在方案详情页内联改某槽位配件的价格（实时刷新总价）
  Future<void> _setPrice(BuildSlot slot, double price) async {
    final plan = _current;
    if (plan == null) return;
    final comp = plan[slot.key];
    if (comp == null) return;
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: List.of(plan.storages),
      customPower: plan.customPower,
    );
    updated.components[slot.key] = PlanComponent(
      category: comp.category,
      brand: comp.brand,
      model: comp.model,
      price: price,
      platform: comp.platform,
    );
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  Future<void> _pickStorage() async {
    final plan = _current;
    if (plan == null) return;
    final result = await Navigator.push<(bool, PlanComponent?)>(
      context,
      MaterialPageRoute(
        builder: (_) => const ComponentPickerPage(
          slotLabel: '硬盘',
          category: '硬盘',
          current: null,
        ),
      ),
    );
    if (result == null || result.$1 || result.$2 == null) return;
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: [...plan.storages, result.$2!],
      customPower: plan.customPower,
    );
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  Future<void> _clearStorageAt(int index) async {
    final plan = _current;
    if (plan == null || index < 0 || index >= plan.storages.length) return;
    final storages = List.of(plan.storages)..removeAt(index);
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: storages,
      customPower: plan.customPower,
    );
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  Future<void> _setStoragePrice(int index, double price) async {
    final plan = _current;
    if (plan == null || index < 0 || index >= plan.storages.length) return;
    final c = plan.storages[index];
    final storages = List.of(plan.storages);
    storages[index] = PlanComponent(
      category: c.category,
      brand: c.brand,
      model: c.model,
      price: price,
      platform: c.platform,
    );
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: Map.of(plan.components),
      storages: storages,
      customPower: plan.customPower,
    );
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
  }

  Future<void> _saveToItems() async {
    final plan = _current;
    if (plan == null || plan.components.isEmpty) return;
    if (plan.total <= 0) {
      _snack('整机价格不能为 0，请先为配件填写价格');
      return;
    }

    final store = HardwareStore();
    final items = await store.loadAll();
    if (!mounted) return;
    final existingIndex = items.indexWhere((e) => e.planId == plan.id);

    // 首次保存：确认后直接新增
    if (existingIndex < 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('保存到清单'),
          content: Text('把整机方案「${_planName(plan)}」作为一个整体加入「我的硬件清单」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await store.add(_newItem(plan, _planName(plan)));
      _snack('已把「${_planName(plan)}」加入清单');
      return;
    }

    // 已经保存过这个方案：让用户选「覆盖原来的 / 另存为新名称 / 取消」
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清单里已有这个方案'),
        content: Text('清单里已经保存过「${_planName(plan)}」，要覆盖原来的条目，还是另存一份新名称的？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'overwrite'),
            child: const Text('覆盖原来的'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'new'),
            style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
            child: const Text('另存为新名称'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (!mounted) return;

    if (choice == 'overwrite') {
      // 覆盖：保留原条目的 id 和录入时间，刷新价格/摘要/名称
      final old = items[existingIndex];
      items[existingIndex] = HardwareItem(
        id: old.id,
        category: '整机方案',
        brand: '',
        model: _planName(plan),
        price: plan.total,
        platform: '',
        spec: _summary(plan),
        planId: plan.id,
        createdAt: old.createdAt,
      );
      await store.saveAll(items);
      _snack('已更新清单里的「${_planName(plan)}」');
    } else {
      // 另存为新名称：新建一条快照条目，仍关联同一个方案
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(title: '新名称', initial: _planName(plan)),
      );
      if (name == null || name.isEmpty) return;
      await store.add(_newItem(plan, name));
      _snack('已把「$name」加入清单');
    }
  }

  /// 上传方案到公开的「云方案」栏目（登录 + 内容合规由云函数处理）
  Future<void> _publishPlan(BuildPlan plan) async {
    if (!AuthService.instance.isLoggedIn) {
      _snack('请先在「我的」页登录，再上传方案');
      return;
    }
    if (plan.components.isEmpty) {
      _snack('方案还没有配件，无法上传');
      return;
    }
    if (plan.total <= 0) {
      _snack('整机价格不能为 0，请先为配件填写价格');
      return;
    }
    setState(() => _publishing = true);
    try {
      await CloudSync.publishPlan(plan);
      if (!mounted) return;
      _snack('上传成功，已发布到「硬件库 → 云方案」');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// 按槽位顺序列出配件摘要「品类 型号」（硬盘多块逐个列出）
  String _summary(BuildPlan plan) {
    final parts = <String>[];
    for (final s in kBuildSlots) {
      if (s.key == 'storage') {
        for (final c in plan.storages) {
          parts.add('${c.category} ${c.model}');
        }
      } else {
        final c = plan[s.key];
        if (c != null) parts.add('${c.category} ${c.model}');
      }
    }
    return parts.join(' · ');
  }

  HardwareItem _newItem(BuildPlan plan, String model) {
    return HardwareItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      category: '整机方案',
      brand: '',
      model: model,
      price: plan.total,
      platform: '',
      spec: _summary(plan),
      planId: plan.id,
      createdAt: DateTime.now(),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 保存后自动上传到云（尽力而为，失败不打断本地流程）
  Future<void> _autoUpload(BuildPlan plan) async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      await CloudSync.uploadPlan(plan);
    } catch (_) {
      // 自动上传失败静默处理，下次保存会再试
    }
  }

  BuildPlan _copyPlan(BuildPlan plan) => BuildPlan(
        id: plan.id,
        name: plan.name,
        components: Map.of(plan.components),
        storages: List.of(plan.storages),
        customPower: plan.customPower,
      );

  /// 已登录时自动从云拉取方案，按 id 去重并入本地；墓碑里的方案会被过滤
  Future<void> _autoSyncFromCloud() async {
    if (!AuthService.instance.isLoggedIn || _syncing) return;
    setState(() => _syncing = true);
    try {
      // 先把墓碑里的方案尽力从云端删掉（真正删干净）
      for (final id in _pendingDeletes.toList()) {
        try {
          await CloudSync.deletePlan(id);
        } catch (_) {}
      }
      final cloudPlans = await CloudSync.downloadPlans();
      final cloudIds = cloudPlans.map((p) => p.id).toSet();
      // 墓碑里已经不在云端的（删干净了），从墓碑移除
      _pendingDeletes.removeWhere((id) => !cloudIds.contains(id));
      await _store.savePendingDeleteIds(_pendingDeletes);
      // 还在云端的墓碑方案（删除还没生效）过滤掉，避免刚删的又冒出来
      final existing = _plans.map((p) => p.id).toSet();
      final fresh = cloudPlans
          .where((p) =>
              !_pendingDeletes.contains(p.id) && !existing.contains(p.id))
          .toList();
      if (fresh.isNotEmpty) {
        setState(() => _plans.addAll(fresh));
        await _store.saveAll(_plans);
      }
    } catch (_) {
      // 自动同步失败不打断本地使用
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// 自动的 CPU+显卡 功耗（匹配不到返回 null）
  double? _autoPower(BuildPlan plan) => totalPower(plan, _library);

  Widget _powerCard(BuildPlan plan) {
    return _PowerEditor(
      plan: plan,
      autoPower: _autoPower(plan),
      onSave: (v) => _savePower(plan, v),
    );
  }

  Future<void> _savePower(BuildPlan plan, double? value) async {
    final updated = BuildPlan(
      id: plan.id,
      name: plan.name,
      components: plan.components,
      storages: plan.storages,
      customPower: value,
    );
    setState(() {
      _replace(plan.id, updated);
      _dirty = true;
    });
    _snack(value == null ? '已清空自定义功耗' : '已设置整机功耗 ${_fmt(value)} W');
  }

  void _replace(String id, BuildPlan updated) {
    final i = _plans.indexWhere((p) => p.id == id);
    if (i >= 0) _plans[i] = updated;
  }

  String _fmt(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  /// AppBar 标题：方案名（放大）+ 版本标签（Beta 1.0.1）一行显示
  Widget _planTitle(BuildContext context, BuildPlan plan) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _planName(plan),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            kAppVersion,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final plan = _current;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  pinned: false,
                  floating: false,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  // 编辑态显示返回按钮（回到文件夹列表）；列表态不显示
                  leading: plan == null
                      ? null
                      : IconButton(
                          onPressed: _backToList,
                          tooltip: '返回方案列表',
                          icon: const Icon(Icons.arrow_back),
                        ),
                  title: plan == null
                      ? const Text('整机方案')
                      : _planTitle(context, plan),
                  actions: [
                    if (plan == null)
                      IconButton(
                        onPressed: _createPlan,
                        tooltip: '新建方案',
                        icon: const Icon(Icons.add),
                      ),
                    if (plan != null && plan.components.isNotEmpty)
                      IconButton(
                        onPressed: _clearAll,
                        tooltip: '清空方案',
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ],
              body: plan == null ? _folderList(context) : _planBody(plan),
            ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.pc_case, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('还没有整机方案'),
          const SizedBox(height: 4),
          const Text(
            '新建一个方案，选好配件后自动算总价',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _createPlan,
            icon: const Icon(Icons.add),
            label: const Text('新建方案'),
            // 空状态居中展示，按钮按内容自适应宽度（不是满宽长条）
            style: capsuleButtonStyle(theme, fullWidth: false),
          ),
        ],
      ),
    );
  }

  /// 文件夹视图：每个整机方案一行，纵向堆叠展示；点击进入具体配置
  Widget _folderList(BuildContext context) {
    if (_plans.isEmpty) return _emptyState(context);
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
      itemCount: _plans.length,
      itemBuilder: (context, i) => _folderCard(context, _plans[i]),
    );
  }

  Widget _folderCard(BuildContext context, BuildPlan plan) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: () => _openPlan(plan),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  // 文件夹图标改为圆形
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
                      _planName(plan),
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
              // 总金额：放在最右侧（三个点左侧），放大突出
              Text(
                '¥${_fmt(plan.total)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) {
                  if (v == 'rename') _rename(plan);
                  if (v == 'delete') _delete(plan);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planBody(BuildPlan plan) {
    final theme = Theme.of(context);
    final filled = kBuildSlots
        .where((s) =>
            s.key == 'storage' ? plan.storages.isNotEmpty : plan[s.key] != null)
        .length;
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
        _totalLine(theme, filled, plan.total),
        _compatCard(theme, plan),
        const SizedBox(height: 4),
        _slotsCard(plan),
        const SizedBox(height: 12),
        _powerCard(plan),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: plan.components.isEmpty ? null : _saveToItems,
          icon: const Icon(Icons.save_alt),
          label: const Text('保存到我的清单'),
          style: capsuleButtonStyle(theme),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _publishing ? null : () => _publishPlan(plan),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('上传到云方案'),
          style: capsuleOutlinedButtonStyle(theme),
        ),
      ],
    );
  }

  /// 总金额不再用卡片，直接以文字显示在最上方
  Widget _totalLine(ThemeData theme, int filled, double total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '总金额',
            // 与金额同字号（headlineSmall），保持一行观感统一
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              '¥${_fmt(total)}',
              key: ValueKey(total),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '已选 $filled / ${kBuildSlots.length} 项',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// 兼容性提醒：黄色感叹号卡片，有隐患才显示（只提醒、不阻断保存）
  Widget _compatCard(ThemeData theme, BuildPlan plan) {
    final issues = checkCompatibility(plan, _library);
    if (issues.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.amber.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: Colors.amber.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  '兼容性提醒',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.amber)),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 所有槽位合并为一张大圆角卡片，内部每行一个槽位（可内联改价格）
  Widget _slotsCard(BuildPlan plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (var i = 0; i < kBuildSlots.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            if (kBuildSlots[i].key == 'storage')
              _StorageSlot(
                key: ValueKey('${plan.id}-storage'),
                storages: plan.storages,
                onPick: _pickStorage,
                onClearAt: _clearStorageAt,
                onPriceChanged: _setStoragePrice,
              )
            else
              _SlotRow(
                key: ValueKey('${plan.id}-${kBuildSlots[i].key}'),
                slot: kBuildSlots[i],
                comp: plan[kBuildSlots[i].key],
                onPick: () => _pick(kBuildSlots[i]),
                onClear: () => _clearSlot(kBuildSlots[i]),
                onPriceChanged: (price) => _setPrice(kBuildSlots[i], price),
              ),
          ],
        ],
      ),
    );
  }
}

String _planName(BuildPlan plan) => plan.name.isEmpty ? '未命名方案' : plan.name;

String _nextName(List<BuildPlan> plans) {
  var n = 1;
  while (plans.any((p) => p.name == '方案 $n')) {
    n++;
  }
  return '方案 $n';
}

String _fmt(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

/// 整机功耗编辑器：显示自动计算的 CPU+显卡 功耗，允许用户自定义（不低于自动值）
class _PowerEditor extends StatefulWidget {
  const _PowerEditor({
    required this.plan,
    required this.autoPower,
    required this.onSave,
  });

  final BuildPlan plan;
  final double? autoPower;
  final Future<void> Function(double? value) onSave;

  @override
  State<_PowerEditor> createState() => _PowerEditorState();
}

class _PowerEditorState extends State<_PowerEditor> {
  late final TextEditingController _c = TextEditingController(
    text: widget.plan.customPower == null ? '' : _fmt(widget.plan.customPower!),
  );

  @override
  void didUpdateWidget(covariant _PowerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.id != widget.plan.id) {
      _c.text = widget.plan.customPower == null
          ? ''
          : _fmt(widget.plan.customPower!);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final t = raw.trim();
    double? value;
    if (t.isEmpty) {
      value = null;
    } else {
      value = double.tryParse(t);
      if (value == null || value <= 0) {
        _toast('功耗格式不对，请输入数字（W）');
        return;
      }
      final auto = widget.autoPower;
      if (auto != null && value < auto) {
        _toast('自定义功耗不能低于 CPU+显卡功耗 ${_fmt(auto)} W');
        return;
      }
    }
    await widget.onSave(value);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
        ),
        onSubmitted: _submit,
        decoration: InputDecoration(
          labelText: '自定义功耗',
          hintText: '选填',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
          isDense: true,
          suffixIcon: IconButton(
            onPressed: () => _submit(_c.text),
            tooltip: '保存功耗',
            icon: const Icon(Icons.check),
          ),
        ),
      ),
    );
  }
}

/// 大圆角卡片内的一行槽位：显示品类图标 + 槽位名 + 型号/品牌，
/// 已选时右侧提供内联价格输入（实时改价）与移除按钮
class _SlotRow extends StatefulWidget {
  const _SlotRow({
    super.key,
    required this.slot,
    required this.comp,
    required this.onPick,
    required this.onClear,
    required this.onPriceChanged,
  });

  final BuildSlot slot;
  final PlanComponent? comp;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<double> onPriceChanged;

  @override
  State<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends State<_SlotRow> {
  late final TextEditingController _price = TextEditingController(
    text: _priceText(widget.comp),
  );

  static String _priceText(PlanComponent? comp) =>
      comp == null || comp.price <= 0 ? '' : _fmt(comp.price);

  @override
  void didUpdateWidget(covariant _SlotRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有换型号（重新选择）才重置价格框；用户自己改价时不打断输入
    final modelChanged = oldWidget.comp?.model != widget.comp?.model ||
        (oldWidget.comp == null) != (widget.comp == null);
    if (modelChanged) {
      _price.text = _priceText(widget.comp);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _onPriceChanged(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return; // 空 / 中间态不提交
    final n = double.tryParse(t);
    if (n == null || n <= 0) return;
    if (n > kMaxPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('价格不能超过 8388608，请重新输入')),
      );
      return;
    }
    widget.onPriceChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comp = widget.comp;
    return InkWell(
      onTap: widget.onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CategoryBadge(category: widget.slot.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.slot.required
                        ? widget.slot.label
                        : '${widget.slot.label}（可选）',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comp == null
                        ? '未选择'
                        : comp.brand.isEmpty
                            ? comp.model
                            : '${comp.model} · ${comp.brand}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (comp != null) ...[
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onPriceChanged,
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    hintText: '价格',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClear,
                tooltip: '移除${widget.slot.label}',
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 硬盘槽位（支持多块）：头部带「添加硬盘」，下面逐块列出，可内联改价/移除
class _StorageSlot extends StatelessWidget {
  const _StorageSlot({
    super.key,
    required this.storages,
    required this.onPick,
    required this.onClearAt,
    required this.onPriceChanged,
  });

  final List<PlanComponent> storages;
  final VoidCallback onPick;
  final ValueChanged<int> onClearAt;
  final void Function(int index, double price) onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const CategoryBadge(category: '硬盘'),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '硬盘',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加硬盘'),
              ),
            ],
          ),
        ),
        if (storages.isEmpty)
          InkWell(
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 12),
              child: Row(
                children: [
                  Text(
                    '未选择',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        for (var i = 0; i < storages.length; i++)
          _StorageDriveRow(
            key: ValueKey('${storages[i].model}-$i'),
            comp: storages[i],
            onClear: () => onClearAt(i),
            onPriceChanged: (p) => onPriceChanged(i, p),
          ),
      ],
    );
  }
}

/// 硬盘槽位里的单块硬盘：型号 + 内联价格 + 移除
class _StorageDriveRow extends StatefulWidget {
  const _StorageDriveRow({
    super.key,
    required this.comp,
    required this.onClear,
    required this.onPriceChanged,
  });

  final PlanComponent comp;
  final VoidCallback onClear;
  final ValueChanged<double> onPriceChanged;

  @override
  State<_StorageDriveRow> createState() => _StorageDriveRowState();
}

class _StorageDriveRowState extends State<_StorageDriveRow> {
  late final TextEditingController _price = TextEditingController(
    text: widget.comp.price <= 0 ? '' : _fmt(widget.comp.price),
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _onPriceChanged(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    final n = double.tryParse(t);
    if (n == null || n <= 0) return;
    if (n > kMaxPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('价格不能超过 8388608，请重新输入')),
      );
      return;
    }
    widget.onPriceChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comp = widget.comp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              comp.brand.isEmpty ? comp.model : '${comp.model} · ${comp.brand}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: _onPriceChanged,
              decoration: const InputDecoration(
                prefixText: '¥ ',
                hintText: '价格',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onClear,
            tooltip: '移除硬盘',
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入方案名称的对话框，返回名称（非空）；与已有方案重名时不关闭并提示
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    this.initial = '',
    this.forbidden = const {},
  });

  final String title;
  final String initial;

  /// 不允许重名的名称集合（已归一化：trim + 小写）；重命名时不含自身
  final Set<String> forbidden;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: '名称', errorText: _error),
        onSubmitted: (_) => _submit(),
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
