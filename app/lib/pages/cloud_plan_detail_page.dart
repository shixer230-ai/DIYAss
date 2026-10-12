import 'package:flutter/material.dart';

import '../models/cloud_plan.dart';
import '../utils/category_icons.dart';
import 'build_plan_page.dart' show kBuildSlots;

/// 云方案详情：展示方案名、日期、点赞数与完整配件清单
class CloudPlanDetailPage extends StatelessWidget {
  const CloudPlanDetailPage({super.key, required this.plan});

  final CloudPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(plan.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                plan.date,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const Spacer(),
              const Icon(Icons.favorite, color: Colors.pink, size: 18),
              const SizedBox(width: 4),
              Text('${plan.likeCount}', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('总价', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                '¥${_fmt(plan.total)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(children: _rows(theme)),
          ),
        ],
      ),
    );
  }

  /// 按槽位顺序列出已选配件（跳过空槽位），行间用分割线隔开
  List<Widget> _rows(ThemeData theme) {
    final p = plan.plan;
    final rows = <Widget>[];
    for (final slot in kBuildSlots) {
      if (slot.key == 'storage') {
        for (final c in p.storages) {
          rows.add(_row(theme, '硬盘', c.model, c.brand, c.price));
        }
        continue;
      }
      final c = p[slot.key];
      if (c == null) continue;
      rows.add(_row(theme, slot.category, c.model, c.brand, c.price));
    }
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const Divider(height: 1, indent: 56));
      out.add(rows[i]);
    }
    return out;
  }

  Widget _row(
    ThemeData theme,
    String category,
    String model,
    String brand,
    double price,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CategoryBadge(category: category),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (brand.isNotEmpty)
                  Text(
                    brand,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
              ],
            ),
          ),
          Text(
            '¥${_fmt(price)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
