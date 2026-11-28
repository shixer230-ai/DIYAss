import 'package:flutter_test/flutter_test.dart';

import 'package:diy_helper/data/hardware_catalog.dart';

void main() {
  group('硬件库完整性与搜索检查', () {
    test('无重复 id 与重复（品类+型号）', () {
      final ids = <String>{};
      final pairs = <String>{};
      for (final s in kHardwareCatalog) {
        expect(ids.add(s.id), isTrue, reason: '重复 id: ${s.id}');
        final pair = '${s.category}|${s.model}';
        expect(pairs.add(pair), isTrue, reason: '重复型号: $pair');
      }
    });

    test('2025-2026 新品可无空格模糊搜索命中', () {
      bool found(String q) =>
          kHardwareCatalog.any((s) => hardwareMatches(s, q));

      expect(found('ultra 7 270kplus'), isTrue);
      expect(found('270K Plus'), isTrue);
      expect(found('250kplus'), isTrue);
      expect(found('225f'), isTrue);
      expect(found('9850x3d'), isTrue);
      expect(found('9950x3dv2'), isTrue);
      expect(found('9950x3d2'), isTrue);
      expect(found('9900x3d'), isTrue);
      expect(found('9500f'), isTrue);
      expect(found('7400f'), isTrue);
      expect(found('5090d'), isTrue);
      expect(found('5050'), isTrue);
      expect(found('9070gre'), isTrue);
      expect(found('b850m'), isTrue);
      expect(found('x870'), isTrue);
    });
  });
}
