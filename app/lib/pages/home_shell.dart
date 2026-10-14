import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:liquid_glass_bottom_navbar_plus/liquid_glass_bottom_navbar_plus.dart';

import '../theme/app_theme.dart';
import 'analysis_page.dart';
import 'catalog_page.dart';
import 'list_plan_page.dart';
import 'profile_page.dart';

/// 底部导航壳：清单 / 硬件库 / 分析 / 我的
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 切换标签页：直接切换之前用淡入过渡会让 body 短暂变透明，导致底部导航
  /// 玻璃背后的内容「闪现」成非玻璃的空白背景，故改为无过渡的即时切换
  void _switchTo(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 底栏胶囊自带 margin（含底部安全区），高光需按同样的边距裁剪到玻璃内
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final pages = [
      ListPlanPage(isActive: _index == 0),
      AnalysisPage(isActive: _index == 1),
      const CatalogPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      // 让页面内容延伸到导航栏下方，导航栏悬浮在内容之上
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      // 底部导航：iOS 26 液态玻璃材质（真实折射 + 跟手滑动），对齐酷安的实现方式
      bottomNavigationBar: GlassPressFeedback(
        clipInsets: EdgeInsets.fromLTRB(12, 8, 12, 12 + safeBottom),
        child: LiquidGlassBottomBar(
          items: _kNavItems,
          selectedIndex: _index,
          onDestinationSelected: _switchTo,
          height: 68,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          theme: LiquidGlassBarTheme(
            iconColor: scheme.onSurfaceVariant,
            selectedIconColor: scheme.primary,
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            pillColor: scheme.primary.withValues(alpha: 0.14),
            showLabels: true,
          ),
        ),
      ),
    );
  }
}

/// 底部导航项：图标 + 文案（Lucide 线性图标）
const _kNavItems = <LiquidGlassBarItem>[
  LiquidGlassBarItem(icon: Icon(LucideIcons.clipboard_list), label: '清单'),
  LiquidGlassBarItem(icon: Icon(LucideIcons.chart_bar), label: '分析'),
  LiquidGlassBarItem(icon: Icon(LucideIcons.library), label: '硬件库'),
  LiquidGlassBarItem(icon: Icon(LucideIcons.user), label: '我的'),
];
