import 'package:flutter_test/flutter_test.dart';

import 'package:diy_helper/analysis/radar_axis.dart';
import 'package:diy_helper/data/hardware_catalog.dart';
import 'package:diy_helper/models/build_plan.dart';
import 'package:diy_helper/models/hardware_spec.dart';

void main() {
  BuildPlan planWithCpu(String brand, String model) {
    return BuildPlan(
      name: model,
      components: {
        'cpu': PlanComponent(
          category: 'CPU',
          brand: brand,
          model: model,
          price: 2000,
          platform: '',
        ),
        'gpu': const PlanComponent(
          category: '显卡',
          brand: 'NVIDIA',
          model: 'GeForce RTX 5080',
          price: 8000,
          platform: '',
        ),
      },
    );
  }

  group('六维雷达图 CPU 多基准融合算法', () {
    test('消除单一 CPU-Z 对 Intel 的偏科：9850X3D 单核高于 i5-14600KF，9950X3D 多核高于 i9-14900K', () {
      final r9850 = computeRadarScores(
        planWithCpu('AMD', '锐龙 7 9850X3D'),
        kHardwareCatalog,
      );
      final r14600 = computeRadarScores(
        planWithCpu('Intel', '酷睿 i5-14600KF'),
        kHardwareCatalog,
      );
      final r9950 = computeRadarScores(
        planWithCpu('AMD', '锐龙 9 9950X3D'),
        kHardwareCatalog,
      );
      final r14900 = computeRadarScores(
        planWithCpu('Intel', '酷睿 i9-14900K'),
        kHardwareCatalog,
      );

      // 单核：9850X3D 虽在 CPU-Z 低于 14600KF，但 GB6 显著领先，融合后应高于 14600KF
      expect(r9850[0].score, greaterThan(r14600[0].score));
      expect(r9850[0].rawText, startsWith('多基准 '));

      // 多核：9950X3D 在 Cinebench R23 多核明显领先 14900K，融合后应高于 14900K
      expect(r9950[1].score, greaterThan(r14900[1].score));
      expect(r9950[1].rawText, startsWith('多基准 '));
    });

    test('仅填写 CPU-Z 的自定义 CPU 自动兜底，不掉分为 0', () {
      final customLib = [
        ...kHardwareCatalog,
        const HardwareSpec(
          id: 'custom_cpu_only_cpuz',
          category: 'CPU',
          brand: 'AMD',
          model: '测试自定义CPU',
          specs: [SpecEntry('默认TDP', '65W')],
          benchmarks: [
            SpecEntry('CPU-Z 单核', '约 700'),
            SpecEntry('CPU-Z 多核', '约 8000'),
          ],
        ),
      ];
      final axes = computeRadarScores(
        planWithCpu('AMD', '测试自定义CPU'),
        customLib,
      );
      expect(axes[0].score, greaterThan(0.5));
      expect(axes[1].score, greaterThan(0.4));
    });
  });
}
