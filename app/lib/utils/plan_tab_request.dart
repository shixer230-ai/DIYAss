import 'package:flutter/foundation.dart';

/// 跨页导航信号：从「我的」导入图片成功后，请求切到「清单 → 整机方案」分段
class PlanTabRequest {
  PlanTabRequest._();

  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  static ValueListenable<int> get listenable => _notifier;

  /// 触发一次「跳到整机方案」请求（监听方据此切换到整机方案分段）
  static void request() => _notifier.value++;
}
