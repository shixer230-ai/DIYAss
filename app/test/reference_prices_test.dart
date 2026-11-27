import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diy_helper/analysis/value_index.dart';
import 'package:diy_helper/data/default_plans.dart';
import 'package:diy_helper/data/hardware_catalog.dart';
import 'package:diy_helper/data/reference_prices.dart';
import 'package:diy_helper/models/build_plan.dart';
import 'package:diy_helper/storage/build_plan_store.dart';

void main() {
  group('预设方案与参考价完整性检查', () {
    test('5 套预设方案所有配件都在硬件库中且已填参考价', () {
      expect(kDefaultPlans.length, 5);
      final expectedTotals = [16366.0, 12947.0, 6814.0, 5687.0, 3688.0];
      for (var i = 0; i < kDefaultPlans.length; i++) {
        final plan = kDefaultPlans[i];
        expect(plan.total, expectedTotals[i], reason: plan.name);
        expect(plan.hasRefPrices, isTrue, reason: plan.name);
        for (final c in [...plan.components.values, ...plan.storages]) {
          expect(c.price, greaterThan(0), reason: '${plan.name} - ${c.model}');
          expect(c.isRefPrice, isTrue, reason: '${plan.name} - ${c.model}');
          final spec = findSpec(c.category, c.model, kHardwareCatalog);
          expect(spec, isNotNull, reason: '硬件库缺少 ${c.category} · ${c.model}');
          expect(
            lookupReferencePrice(c.category, c.model),
            c.price,
            reason: '参考价表与预设方案不一致：${c.model}',
          );
        }
      }
    });

    test('补充热门型号均存在于硬件库且查得到参考价', () {
      expect(lookupReferencePrice('CPU', '锐龙 5 7500F'), 566);
      expect(lookupReferencePrice('CPU', '酷睿 i5-12400F'), 794);
      expect(lookupReferencePrice('显卡', 'GeForce RTX 4060 Ti'), 3099);
      expect(findSpec('CPU', '锐龙 5 7500F', kHardwareCatalog), isNotNull);
      expect(findSpec('CPU', '酷睿 i5-12400F', kHardwareCatalog), isNotNull);
      expect(
        findSpec('显卡', 'GeForce RTX 4060 Ti', kHardwareCatalog),
        isNotNull,
      );
    });

    test('玄武 500K 已更新为铜牌', () {
      final psu = findSpec('电源', '玄武 500K 铜牌', kHardwareCatalog);
      expect(psu, isNotNull);
      expect(psu!.specs.any((s) => s.value.contains('铜牌')), isTrue);
    });

    test('未改过价格的旧版 0 元预设方案自动升级，用户改过价的保留原样', () async {
      SharedPreferences.setMockInitialValues({});
      final store = BuildPlanStore();
      await store.saveAll([
        BuildPlan(
          id: 'default_1',
          name: '高端 Intel 游戏主机',
          components: {
            'cpu': const PlanComponent(
              category: 'CPU',
              brand: 'Intel',
              model: '酷睿 i7-14700K',
              price: 0,
              platform: '',
            ),
          },
        ),
        BuildPlan(
          id: 'default_5',
          name: '入门高性价比主机',
          components: {
            'cpu': const PlanComponent(
              category: 'CPU',
              brand: 'Intel',
              model: '酷睿 i3-12100F',
              price: 380,
              platform: '',
            ),
          },
        ),
      ]);

      final loaded = await store.loadAll();
      final p1 = loaded.firstWhere((p) => p.id == 'default_1');
      final p5 = loaded.firstWhere((p) => p.id == 'default_5');

      // default_1 原先全 0，自动升级为新版带参考价方案
      expect(p1.total, 16366);
      expect(p1.hasRefPrices, isTrue);

      // default_5 用户自己改过价（380），原样保留不被覆盖
      expect(p5.total, 380);
      expect(p5.hasRefPrices, isFalse);
    });
  });
}
