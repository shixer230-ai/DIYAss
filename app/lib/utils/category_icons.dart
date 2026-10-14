import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// 根据品类返回一个扁平图标（Lucide，ISC 开源可商用）
IconData categoryIcon(String category) {
  switch (category) {
    case 'CPU':
      return LucideIcons.cpu;
    case '主板':
      return LucideIcons.circuit_board;
    case '显卡':
      return LucideIcons.gpu;
    case '内存':
      return LucideIcons.memory_stick;
    case '硬盘':
      return LucideIcons.hard_drive;
    case '电源':
      return LucideIcons.power;
    case '机箱':
      return LucideIcons.pc_case;
    case '散热':
      return LucideIcons.fan;
    case '整机方案':
      return LucideIcons.monitor;
    default:
      return LucideIcons.component;
  }
}

/// 根据品类返回一个主题色，让每个品类图标有专属颜色、整体多彩
Color categoryColor(String category) {
  switch (category) {
    case 'CPU':
      return const Color(0xFF1976D2); // 蓝
    case '显卡':
      return const Color(0xFFD32F2F); // 红
    case '主板':
      return const Color(0xFFF57C00); // 橙
    case '内存':
      return const Color(0xFF388E3C); // 绿
    case '硬盘':
      return const Color(0xFF7B1FA2); // 紫
    case '电源':
      return const Color(0xFFF9A825); // 黄
    case '机箱':
      return const Color(0xFF00838F); // 青
    case '散热':
      return const Color(0xFF00ACC1); // 清凉青
    case '整机方案':
      return const Color(0xFF3949AB); // 靛
    default:
      return const Color(0xFF616161); // 灰
  }
}

/// 品类圆形徽章：用品类主题色的淡背景 + 同色图标，替代原来单一主题色的圆形图标
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(categoryIcon(category), color: color),
    );
  }
}
