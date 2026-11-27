import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diy_helper/utils/copy_model.dart';

void main() {
  group('formatCopyModelText', () {
    test('型号不含品牌时自动补上品牌前缀', () {
      expect(
        formatCopyModelText('MAG B760M MORTAR MAX WiFi DDR5', brand: '微星'),
        '微星 MAG B760M MORTAR MAX WiFi DDR5',
      );
      expect(
        formatCopyModelText('酷睿 i7-14700K', brand: 'Intel'),
        'Intel 酷睿 i7-14700K',
      );
    });

    test('型号已含品牌时不重复拼接（忽略大小写）', () {
      expect(
        formatCopyModelText('海韵 FOCUS GX-750 金牌全模组', brand: '海韵'),
        '海韵 FOCUS GX-750 金牌全模组',
      );
      expect(
        formatCopyModelText('intel i5-13400F', brand: 'Intel'),
        'intel i5-13400F',
      );
    });

    test('品牌为空时只返回型号', () {
      expect(formatCopyModelText('原装散热', brand: ''), '原装散热');
    });
  });

  testWidgets('点击 CopyModelButton 复制文本并弹出提示', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CopyModelButton(model: '990 PRO 1TB', brand: '三星'),
          ),
        ),
      );

      await tester.tap(find.byType(CopyModelButton));
      await tester.pump();

      expect(copied, '三星 990 PRO 1TB');
      expect(find.text('已复制：三星 990 PRO 1TB'), findsOneWidget);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });
}
