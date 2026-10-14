import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 预设主题色（用户可在「我的」页一键切换）
const Color kDefaultSeed = Color(0xFFEC4899);

/// 卡片圆角半径：各页卡片共用，增大到与底部胶囊导航栏（kNavBarRadius）一致
const double kCardRadius = 34;

/// 底部导航外层胶囊的圆角：NavigationBar 高 68，取半高即胶囊形
const double kNavBarRadius = 34;

/// 底部导航悬浮在内容上方时，内容底部需预留的高度：
/// 导航高 68 + 上边距 8 + 下边距 12 = 88（系统底部安全区另算）
const double kNavOverlaySpace = 88;

/// 底部导航悬浮时，内容底部需预留的总高度（含系统底部安全区）
double bottomNavClearance(BuildContext context) =>
    kNavOverlaySpace + MediaQuery.paddingOf(context).bottom;

/// 主操作按钮统一风格：胶囊圆角 + 半透明底色（透明圆角），
/// 用于「加入我的清单」「保存到我的清单」等主要按钮，保证观感一致
ButtonStyle capsuleButtonStyle(ThemeData theme, {bool fullWidth = true}) {
  final scheme = theme.colorScheme;
  return FilledButton.styleFrom(
    // 列表/底栏里的主按钮默认占满宽度；空状态等居中场景传 fullWidth: false，
    // 让按钮按内容自适应宽度，避免被拉成一条过长的「条」
    minimumSize: fullWidth ? const Size.fromHeight(48) : const Size(0, 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kCardRadius),
    ),
    backgroundColor: scheme.surface.withValues(alpha: 0.5),
    foregroundColor: scheme.primary,
    disabledBackgroundColor: scheme.surface.withValues(alpha: 0.3),
    disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.4),
  );
}

/// 次级操作按钮统一风格：与主按钮同款胶囊圆角 + 半透明底色 + 细描边，
/// 用于「加入我的添加」等次要按钮，观感与主按钮一致（玻璃描边版）
ButtonStyle capsuleOutlinedButtonStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  return OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kCardRadius),
    ),
    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    backgroundColor: scheme.surface.withValues(alpha: 0.3),
    foregroundColor: scheme.primary,
    disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.4),
  );
}

/// 玻璃风格外壳：半透明渐变 + 细描边 + 顶部高光，模拟磨砂玻璃质感
/// 不用 BackdropFilter（实时模糊在滚动时会闪烁），故改为「假玻璃」方案
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.child,
    this.radius = kNavBarRadius,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
              // 半透明玻璃底：从上到下略变淡，模拟玻璃厚度
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface.withValues(alpha: 0.6),
                  scheme.surface.withValues(alpha: 0.42),
                ],
              ),
            ),
            child: child,
          ),
          // 顶部一条细高光，模拟玻璃反光
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: radius / 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.onSurface.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃风下拉框：展开菜单用表面色 + 胶囊圆角，替代原生下拉菜单的方角白底样式
/// 用法与 DropdownButtonFormField 一致，仅多一层统一的菜单外观
class GlassDropdown<T> extends StatelessWidget {
  const GlassDropdown({
    super.key,
    required this.initialValue,
    required this.items,
    this.onChanged,
    this.decoration,
    this.menuMaxHeight = 360,
  });

  final T initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final double menuMaxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      menuMaxHeight: menuMaxHeight,
      dropdownColor: scheme.surface,
      borderRadius: BorderRadius.circular(kCardRadius),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: scheme.onSurfaceVariant,
      ),
      decoration: decoration,
    );
  }
}

/// 液态玻璃栏 / 按钮的点按反馈：按下时整体略微缩小，并在手指处叠一个
/// 跟随手指移动的径向高光（spotlight），松手后淡出。
/// 用 Listener 检测按压与移动（不抢占子组件的点击/滑动手势），高光通过
/// 叠加层 + 圆角裁剪，形状对齐玻璃胶囊本体（透明边距不受影响）
class GlassPressFeedback extends StatefulWidget {
  const GlassPressFeedback({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.spotlightRadius = 90,
    this.clipRadius = kNavBarRadius,
    this.clipInsets = EdgeInsets.zero,
    this.spotlightColor = Colors.white,
    this.spotlightIntensity = 0.5,
  });

  final Widget child;

  /// 按下时的缩放比例（越小收缩越明显）
  final double scale;

  /// 高光半径（逻辑像素，越大光斑越散）
  final double spotlightRadius;

  /// 玻璃胶囊的圆角半径，用于裁剪高光、对齐胶囊形状
  final double clipRadius;

  /// 玻璃胶囊相对外层的边距（底栏自带 margin 时传入，让高光只画在玻璃内）
  final EdgeInsets clipInsets;

  /// 高光颜色（默认白色）
  final Color spotlightColor;

  /// 高光中心的最大强度（0~1，越大越亮）
  final double spotlightIntensity;

  @override
  State<GlassPressFeedback> createState() => _GlassPressFeedbackState();
}

class _GlassPressFeedbackState extends State<GlassPressFeedback> {
  bool _pressed = false;
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 120);
    return Listener(
      onPointerDown: (e) => setState(() {
        _pressed = true;
        _pos = e.localPosition;
      }),
      onPointerMove: (e) => setState(() => _pos = e.localPosition),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: duration,
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_pos != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: widget.clipInsets,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.clipRadius),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _pressed ? 1.0 : 0.0),
                        duration: duration,
                        curve: Curves.easeOut,
                        builder: (context, t, _) {
                          return CustomPaint(
                            painter: _SpotlightPainter(
                              center: _pos! -
                                  Offset(
                                    widget.clipInsets.left,
                                    widget.clipInsets.top,
                                  ),
                              radius: widget.spotlightRadius,
                              intensity: t,
                              color: widget.spotlightColor,
                              maxIntensity: widget.spotlightIntensity,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 跟随手指的径向高光画笔：以 [center] 为中心、[radius] 为半径的白色渐变，
/// 用加色混合（plus）叠加到玻璃上，产生「被点亮」的效果
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.center,
    required this.radius,
    required this.intensity,
    required this.color,
    required this.maxIntensity,
  });

  final Offset center;
  final double radius;
  final double intensity;
  final Color color;
  final double maxIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final shader = ui.Gradient.radial(
      center,
      radius,
      [
        color.withValues(alpha: maxIntensity * intensity),
        color.withValues(alpha: maxIntensity * 0.4 * intensity),
        color.withValues(alpha: 0),
      ],
      [0.0, 0.45, 1.0],
    );
    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.plus;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.intensity != intensity ||
      old.color != color ||
      old.maxIntensity != maxIntensity;
}

class SeedOption {
  const SeedOption(this.name, this.color);

  final String name;
  final Color color;
}

/// 预设色卡：默认玫瑰粉 + 7 个常用色，贴合国内 app 的柔和配色
const List<SeedOption> kSeedOptions = [
  SeedOption('玫瑰粉', Color(0xFFEC4899)),
  SeedOption('天空蓝', Color(0xFF3B82F6)),
  SeedOption('青绿', Color(0xFF10B981)),
  SeedOption('活力橙', Color(0xFFF97316)),
  SeedOption('优雅紫', Color(0xFF8B5CF6)),
  SeedOption('热情红', Color(0xFFEF4444)),
  SeedOption('湖水青', Color(0xFF06B6D4)),
  SeedOption('深邃靛', Color(0xFF6366F1)),
];

const _cardRadius = BorderRadius.all(Radius.circular(kCardRadius));

/// 输入框圆角：胶囊形（与全站胶囊风格一致，取值足够大保证两端全圆）
const _inputRadius = BorderRadius.all(Radius.circular(999));

/// 淡入淡出转场（非对称）：
/// - 入栈：新页淡入、旧页淡出（旧页连同底部液态玻璃导航一起淡出，不残留）；
/// - 出栈：当前页淡出，下层旧页保持不透明（玻璃不会「淡入消失」）
///
/// 旧页用 secondaryAnimation 淡出，但反向（被重新露出）时用阈值曲线立即回到
/// 不透明，从而兼顾「入栈玻璃一起淡出」和「返回时玻璃不闪现」
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 本页随自身 animation 淡入/淡出（入栈 0→1、出栈 1→0）
    final incoming = FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    );

    // 被新页压住时（secondaryAnimation 0→1）淡出；被重新露出时（1→0）
    // 用 Threshold(1.0) 让中间值直接归 0 → 完全不动，避免玻璃淡入闪现
    final outgoing = FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeInOut,
          reverseCurve: const Threshold(1.0),
        ),
      ),
      child: incoming,
    );

    return outgoing;
  }
}

ThemeData buildLightTheme({
  Color seed = kDefaultSeed,
  bool transparentBackground = false,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  return _base(scheme, transparentBackground).copyWith(
    scaffoldBackgroundColor:
        transparentBackground ? Colors.transparent : const Color(0xFFFDF8FB),
    // 卡片用纯白，和偏暖白的背景拉开层次
    colorScheme: scheme.copyWith(surface: Colors.white),
  );
}

ThemeData buildDarkTheme({
  Color seed = kDefaultSeed,
  bool transparentBackground = false,
}) {
  final scheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  return _base(scheme, transparentBackground).copyWith(
    scaffoldBackgroundColor:
        transparentBackground ? Colors.transparent : const Color(0xFF191216),
  );
}

ThemeData _base(ColorScheme scheme, bool transparentBackground) {
  OutlineInputBorder inputBorder(BorderSide side) => OutlineInputBorder(
        borderRadius: _inputRadius,
        borderSide: side,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: transparentBackground
          ? Colors.transparent
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      // 卡片半透明，和「分析项目」输入框一致（fillColor 0.5 透明度），让背景图透出
      color: scheme.surface.withValues(alpha: 0.5),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      isDense: true,
      border: inputBorder(BorderSide(color: scheme.outlineVariant)),
      enabledBorder: inputBorder(BorderSide(color: scheme.outlineVariant)),
      focusedBorder:
          inputBorder(BorderSide(color: scheme.primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        minimumSize: const Size(64, 48),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer,
      // 选中指示器用圆形（内层小圆块）
      indicatorShape: const CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      // 与卡片 / 主按钮统一：胶囊圆角 + 半透明底色，「保存成功」等提示观感一致
      backgroundColor: scheme.surface.withValues(alpha: 0.6),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kCardRadius)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kCardRadius)),
      ),
    ),
    // 弹出菜单（PopupMenuButton / showMenu）统一胶囊圆角 + 表面色，去掉原生直角菜单
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      elevation: 4,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    // 转场用「纯滑动、无淡入淡出」：既不会因透明底露黑，也不会让页面（含液态玻璃）
    // 在跳转时淡成透明——返回录入页等场景下玻璃不会再短暂消失
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadePageTransitionsBuilder(),
        TargetPlatform.iOS: FadePageTransitionsBuilder(),
        TargetPlatform.macOS: FadePageTransitionsBuilder(),
        TargetPlatform.windows: FadePageTransitionsBuilder(),
        TargetPlatform.linux: FadePageTransitionsBuilder(),
      },
    ),
  );
}
