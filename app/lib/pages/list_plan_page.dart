import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_navbar_plus/liquid_glass_bottom_navbar_plus.dart';

import '../theme/app_theme.dart';
import 'build_plan_page.dart';
import 'hardware_list_page.dart';

/// 「清单 / 整机方案」合并页：顶部用胶囊分段控件切换两个视图
/// 原底部导航的「清单」和「整机方案」两个入口合并到这里
class ListPlanPage extends StatefulWidget {
  const ListPlanPage({super.key, this.isActive = true});

  /// 当前是否为底部导航选中的标签页；切回来时用于刷新对应分段的数据
  final bool isActive;

  @override
  State<ListPlanPage> createState() => _ListPlanPageState();
}

class _ListPlanPageState extends State<ListPlanPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted || _tab.index == _index) return;
    setState(() => _index = _tab.index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部胶囊分段：硬件清单 / 整机方案（与底部导航同款液态玻璃）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: GlassPressFeedback(
                clipRadius: 24,
                child: LiquidGlassBottomBar(
                  items: const [
                    LiquidGlassBarItem(label: '硬件清单'),
                    LiquidGlassBarItem(label: '整机方案'),
                  ],
                  selectedIndex: _index,
                  onDestinationSelected: (i) => _tab.animateTo(i),
                  height: 48,
                  margin: EdgeInsets.zero,
                  applyBottomInset: false,
                  theme: LiquidGlassBarTheme(
                    iconColor: scheme.onSurfaceVariant,
                    selectedIconColor: scheme.primary,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    selectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    pillColor: scheme.primary.withValues(alpha: 0.14),
                    showLabels: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  HardwareListPage(
                    onOpenPlan: () => _tab.animateTo(1),
                    isActive: widget.isActive && _index == 0,
                  ),
                  BuildPlanPage(isActive: widget.isActive && _index == 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
