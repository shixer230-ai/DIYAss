import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diy_helper/main.dart';

void main() {
  testWidgets('清单页空状态冒烟测试', (WidgetTester tester) async {
    // 用内存 mock 替代真实的本地存储，避免测试环境缺插件报错。
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DiyAssApp());
    await tester.pumpAndSettle();

    // 清单页现在按品类分 Tab，空态时首个 Tab（整机方案）显示空提示。
    expect(find.text('还没有整机方案'), findsOneWidget);
  });
}
