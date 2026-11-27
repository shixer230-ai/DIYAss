import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 拼出适合直接粘贴去电商搜索的型号文本：
/// 品牌非空且型号里尚未包含该品牌时自动补上品牌前缀（如「微星 MAG B760M...」），
/// 已包含时不再重复拼接（如「海韵 FOCUS GX-750...」）。
String formatCopyModelText(String model, {String brand = ''}) {
  final m = model.trim();
  final b = brand.trim();
  if (m.isEmpty) return b;
  if (b.isEmpty) return m;
  if (m.toLowerCase().contains(b.toLowerCase())) return m;
  return '$b $m';
}

/// 复制硬件型号到剪贴板，并用全站统一的半透明胶囊提示反馈
Future<void> copyHardwareModel(
  BuildContext context,
  String model, {
  String brand = '',
}) async {
  final text = formatCopyModelText(model, brand: brand);
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('已复制：$text')));
}

/// 紧凑型「复制型号」图标按钮：用于槽位行、清单行、云方案行右侧，
/// 视觉尺寸与同行的删除/关闭图标保持一致，避免挤压型号名称空间。
class CopyModelButton extends StatelessWidget {
  const CopyModelButton({
    super.key,
    required this.model,
    this.brand = '',
    this.size = 17,
  });

  final String model;
  final String brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      onPressed: () => copyHardwareModel(context, model, brand: brand),
      tooltip: '复制型号',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(Icons.copy_rounded, size: size, color: color),
    );
  }
}

/// 胶囊风格「复制」轻按钮：用于硬件详情页头部，
/// 采用全站统一的主题色浅底 + 全圆角胶囊样式。
class CopyModelPill extends StatelessWidget {
  const CopyModelPill({
    super.key,
    required this.model,
    this.brand = '',
    this.label = '复制型号',
  });

  final String model;
  final String brand;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => copyHardwareModel(context, model, brand: brand),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
