import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_navbar_plus/liquid_glass_bottom_navbar_plus.dart';

import '../analysis/radar_axis.dart';
import '../models/build_plan.dart';
import '../models/hardware_spec.dart';
import '../theme/app_theme.dart';

/// 六维雷达图页：展示某个方案在六个维度上的得分轮廓
/// 六维：单核 / 多核 / 显卡 / 功耗 / 性价比 / 兼容性，越靠外越好
class RadarChartPage extends StatefulWidget {
  const RadarChartPage({
    super.key,
    required this.plan,
    required this.library,
  });

  final BuildPlan plan;
  final List<HardwareSpec> library;

  @override
  State<RadarChartPage> createState() => _RadarChartPageState();
}

class _RadarChartPageState extends State<RadarChartPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _grow;
  late final List<RadarAxis> _axes;
  late final List<RadarAxis> _capAxes;
  late final CompatLevel _compat;
  int _tab = 0;

  /// 当前板块对应的轴：0 = 性能六维，1 = 场景六维
  List<RadarAxis> get _currentAxes => _tab == 0 ? _axes : _capAxes;

  @override
  void initState() {
    super.initState();
    _axes = computeRadarScores(widget.plan, widget.library);
    _capAxes = computeCapabilityScores(widget.plan, widget.library);
    _compat = computeCompatLevel(widget.plan, widget.library);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _grow = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.plan.name.isEmpty ? '未命名方案' : widget.plan.name;
    return Scaffold(
      appBar: AppBar(title: const Text('雷达图')),
      body: SafeArea(
        // 液态玻璃胶囊放在非滚动区（固定 Column 顶部），避免滚动时 BackdropFilter 闪烁/偏移
        child: Column(
          children: [
            _tabBar(theme),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tab == 0 ? '六维越靠外越强 · 功耗越低越满' : '六项越靠外越适合该场景 · 数值为场景适配度',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _hardwareCard(theme),
                  const SizedBox(height: 8),
                  // 雷达图（动画：从中心向外展开）
                  SizedBox(
                    height: 360,
                    child: AnimatedBuilder(
                      animation: _grow,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _RadarPainter(
                          axes: _currentAxes,
                          progress: _grow.value,
                          scheme: theme.colorScheme,
                        ),
                      ),
                    ),
                  ),
                  if (_tab == 0) ...[
                    const SizedBox(height: 8),
                    _compatCard(theme),
                  ],
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _grow,
                    builder: (context, _) => _legendCard(theme, _grow.value),
                  ),
                  const SizedBox(height: 12),
                  _explainCard(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部液态玻璃胶囊：性能六维 / 场景六维 两个雷达图板块切换
  Widget _tabBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: GlassPressFeedback(
        clipRadius: 24,
        child: LiquidGlassBottomBar(
          items: const [
            LiquidGlassBarItem(label: '性能六维'),
            LiquidGlassBarItem(label: '场景六维'),
          ],
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            _controller.forward(from: 0);
          },
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

  /// 硬件型号卡片：列出方案各槽位的硬件型号，方便对照雷达图查看
  Widget _hardwareCard(ThemeData theme) {
    const order = ['cpu', 'cooler', 'gpu', 'motherboard', 'ram', 'psu', 'case'];
    final parts = <PlanComponent>[
      for (final key in order)
        if (widget.plan[key] != null) widget.plan[key]!,
      ...widget.plan.storages,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '硬件型号',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      c.category,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(c.model, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 图例：每根轴的原始值与得分百分比
  Widget _legendCard(ThemeData theme, double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        children: [
          for (final a in _currentAxes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      a.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    a.animatedRaw(progress),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(a.score * 100 * progress).round()}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 兼容性胶囊：统一胶囊型，等级 + 结论；有问题时在下方小字列出具体提醒
  Widget _compatCard(ThemeData theme) {
    final hasIssue = _compat.issues.isNotEmpty;
    final accent = hasIssue ? Colors.amber : Colors.green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(
                hasIssue ? Icons.warning_amber : Icons.check_circle_outline,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '兼容性 ${_compat.level} 级 · ${_compat.note}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final msg in _compat.issues)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6),
            child: Text(
              '· $msg',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber),
            ),
          ),
      ],
    );
  }

  /// 算法说明卡片：按当前板块展示「性价比排行 + 六维雷达图」或「场景六维雷达图」
  Widget _explainCard(ThemeData theme) {
    final cap = _tab == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '算法说明',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (cap) ...[
            _explainHeader(theme, '场景六维雷达图（本页）'),
            _explainLine(theme, '输入', '基于 CPU 单核/多核、显卡跑分/显存、内存容量'),
            _explainLine(theme, '3A 游戏', '显卡与多核短板打底：较弱一方占 70%、较强一方占 30%，CPU 太弱会拖累显卡'),
            _explainLine(theme, '网游', '75% 单核 + 15% 多核 + 10% 显卡'),
            _explainLine(theme, '视频创作', '加权平均（55% 多核 + 25% 内存 + 20% 显卡）与多核/内存最弱项各占 50%，短板拖累更明显'),
            _explainLine(theme, '综合性能', '加权平均（25% 单核 + 25% 多核 + 40% 显卡 + 10% 内存）与最弱项各占 50%'),
            _explainLine(theme, 'AI 创作', '45% 显卡 + 35% 显存 + 20% 内存容量，主要吃显卡显存，CPU 影响小'),
            _explainLine(theme, '稳定性', '70% 兼容性等级 + 30% 功耗，兼容性按严格档映射（基础合格仅 45 分）、功耗满分 150W / 1000W 记 0 分'),
            _explainLine(theme, '基准', '单核/显存/内存取库内最高分，多核/显卡取第 5 名，超 100% 高亮'),
          ] else ...[
            _explainHeader(theme, '性价比排行（第一栏）'),
            _explainLine(theme, '跑分项目', '指数 = 跑分 ÷ 整机总价 × 1000，越大越划算，从高到低排序'),
            _explainLine(theme, 'CPU-Z 单核', '用指数权重：相邻两款每高 20% 权重翻倍，再除以总价，更强调单核差距'),
            _explainLine(theme, '整机功耗', '累加 CPU + 显卡功耗，越小越省电，从低到高排序'),
            _explainLine(theme, '自定义项目', '你填的分数 ÷ 整机总价 × 1000，从高到低排序'),
            _explainLine(theme, '未上榜', '缺数据、或型号匹配不到硬件库的方案不上榜'),
            const SizedBox(height: 8),
            _explainHeader(theme, '六维雷达图（本页）'),
            _explainLine(theme, '单核', '得分 = 该项跑分 ÷ 硬件库内最高分，满分 = 库里最强'),
            _explainLine(theme, '多核 / 显卡', '得分 = 该项跑分 ÷ 硬件库内第 5 名，第 5 名记 100%，更强的会超过 100% 并高亮'),
            _explainLine(theme, '功耗', '越低越满，${kPowerFull.round()}W 以内记满分，${kPowerCeiling.round()}W 记 0 分'),
            _explainLine(theme, '性价比', '综合性能（20% 单核 + 20% 多核 + 60% 显卡）÷ 相对价格，参考整机价 ${kValueRefPrice.round()} 元'),
            _explainLine(
              theme,
              '兼容性',
              '1~5 级：无兼容问题给 3 级；电源余量充足、主板供电充足各 +1 级，最高 5 级；有明显问题降到 2 级或 1 级',
            ),
          ],
        ],
      ),
    );
  }

  Widget _explainHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _explainLine(ThemeData theme, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: '$title：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: body),
          ],
        ),
      ),
    );
  }
}

/// 雷达图画笔：网格环 + 轴线 + 数据多边形（随 progress 从中心长出）+ 顶点 + 标签
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.axes,
    required this.progress,
    required this.scheme,
  });

  final List<RadarAxis> axes;
  final double progress;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final n = axes.length;
    if (n == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 44;
    final step = 2 * math.pi / n;

    Offset pointAt(int i, double r) {
      final angle = -math.pi / 2 + i * step;
      return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.onSurface.withValues(alpha: 0.12);
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.onSurface.withValues(alpha: 0.22);

    // 网格环（4 层）与轴线
    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = pointAt(i, r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, pointAt(i, radius), axisPaint);
    }

    // 数据多边形
    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final r = radius * axes[i].score * progress;
      final p = pointAt(i, r);
      i == 0 ? dataPath.moveTo(p.dx, p.dy) : dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(
      dataPath,
      Paint()..color = scheme.primary.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.primary,
    );

    // 顶点圆点：超过 100% 的用金色高亮 + 百分比标签
    final dotPaint = Paint()..color = scheme.primary;
    for (var i = 0; i < n; i++) {
      final r = radius * axes[i].score * progress;
      final p = pointAt(i, r);
      if (axes[i].over) {
        canvas.drawCircle(p, 10, Paint()..color = Colors.amber.withValues(alpha: 0.35));
        canvas.drawCircle(p, 5, Paint()..color = Colors.amber);
        if (progress > 0.6) _drawOverLabel(canvas, p, center, axes[i].score);
      } else {
        canvas.drawCircle(p, 4, dotPaint);
      }
    }

    // 轴标签（在最大环外侧）：轴名 + 原始值
    for (var i = 0; i < n; i++) {
      final p = pointAt(i, radius + 20);
      _drawLabel(canvas, axes[i], p);
    }
  }

  /// 在超 100% 的顶点内侧画百分比标签（金色）
  void _drawOverLabel(Canvas canvas, Offset p, Offset center, double score) {
    final tp = TextPainter(
      text: TextSpan(
        text: '${(score * 100).round()}%',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.amber,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // 往圆心方向偏移 18px，避免贴到顶点或溢出画布
    final dir = center - p;
    final d = dir.distance;
    final pos = d < 1 ? p : p + dir * (18 / d);
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawLabel(Canvas canvas, RadarAxis axis, Offset p) {
    final label = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${axis.label}\n',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          TextSpan(
            text: axis.animatedRaw(progress),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(p.dx - label.width / 2, p.dy - label.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.axes != axes;
}
