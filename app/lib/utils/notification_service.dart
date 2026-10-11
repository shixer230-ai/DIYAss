import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地系统通知：感谢捐赠、硬件库更新等消息
/// 走手机本地通知，不依赖服务器，国内手机也能收到
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// 启动时初始化：只建通知渠道，不在这里申请权限（等真要发通知时再申请，时机更友好）
  Future<void> init() async {
    if (_inited) return;
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: init);
    _inited = true;
  }

  /// 确认通知权限已开；没开就申请一次（Android 13+ 需要），返回是否可用
  Future<bool> ensurePermission() async {
    if (!_inited) await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // 非 Android 平台默认放行
    final enabled = await android.areNotificationsEnabled();
    if (enabled ?? false) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 弹一条本地通知（标题 + 正文）；权限没开会先申请，返回是否真的发出去了
  Future<bool> show(String title, String body) async {
    if (!(await ensurePermission())) return false;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'default',
        '通知',
        channelDescription: 'DIYAss 的消息通知',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
    return true;
  }
}
