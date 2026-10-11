import 'dart:io';

import 'package:cloudbase_flutter/cloudbase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/avatar_image_store.dart';
import '../theme/theme_controller.dart';
import '../utils/notification_service.dart';
import 'cloud_app.dart';

/// 云端账号状态：登录/注册/登出，以及当前用户信息（单例，变更后通知监听者）
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  User? _user;
  bool _isDonator = false;

  /// 注册第二步的验证回调（第一步发验证码时暂存）
  Future<SignInRes> Function(VerifyOtpParams)? _pendingVerify;

  User? get user => _user;

  bool get isLoggedIn => _user != null;

  /// 是否捐赠用户（拥有 donator 专属标识与权益）
  bool get isDonator => _isDonator;

  /// 用户名（登录标识）
  String? get username => _user?.userMetadata?.username;

  /// 昵称（展示用，注册时先取用户名）
  String? get nickname => _user?.userMetadata?.nickName ?? _user?.userMetadata?.username;

  /// 云端头像（可能是 fileId 或临时链接）
  String? get avatarUrl => _user?.userMetadata?.avatarUrl;

  /// 当前登录用户 uid（云端方案归属 owner 用）
  String? get uid => _user?.id;

  /// 登录/注册/恢复后，本地昵称仍是默认值则同步为云端用户名
  void _adoptNickname() {
    final name = nickname;
    if (name == null || name.isEmpty) return;
    ThemeController.instance.adoptNicknameIfDefault(name);
  }

  /// 登录/注册/恢复后，把云端头像下载到本地（若账号里有头像）
  void _syncAvatar() {
    final fileId = avatarUrl;
    if (fileId == null || !fileId.startsWith('cloud://')) return;
    _doSyncAvatar(fileId);
  }

  Future<void> _doSyncAvatar(String fileId) async {
    try {
      final storage = CloudApp.app.storage.from();
      final res = await storage.getDownloadUrls([fileId], expiresIn: 3600);
      final url = res.data?.first.downloadUrl;
      if (url == null || url.isEmpty) return;
      final bytes = await _downloadBytes(url);
      final path = await AvatarImageStore.saveBytes(bytes, _extOf(fileId));
      await ThemeController.instance.setAvatar(path);
    } catch (_) {
      // 头像同步失败不阻塞登录
    }
  }

  /// 用 dart:io 拉取图片字节（云存储签名链接）
  static Future<List<int>> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('头像下载失败 HTTP ${res.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  /// 从 fileId 取扩展名，取不到默认 jpg
  static String _extOf(String fileId) {
    final name = fileId.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return 'jpg';
  }

  /// 启动时恢复已有会话（token 未过期则自动登录）
  Future<void> restore() async {
    if (!CloudApp.isReady) return;
    try {
      final res = await CloudApp.app.auth.getSession();
      _user = res.data?.user ?? res.data?.session?.user;
      notifyListeners();
      _adoptNickname();
      _syncAvatar();
      await refreshDonator();
    } catch (_) {
      // 未登录/无网络，保持未登录
    }
  }

  /// 登录：自动识别邮箱还是用户名
  Future<void> signIn({required String account, required String password}) async {
    final req = account.contains('@')
        ? SignInWithPasswordReq(email: account, password: password)
        : SignInWithPasswordReq(username: account, password: password);
    final res = await CloudApp.app.auth.signInWithPassword(req);
    if (res.error != null) throw Exception(res.error!.message);
    _user = res.data?.user ?? res.data?.session?.user;
    notifyListeners();
    _adoptNickname();
    _syncAvatar();
    await refreshDonator();
  }

  /// 注册第一步：发验证码到邮箱，验证回调暂存
  Future<void> sendSignUpCode({
    required String email,
    required String password,
    required String username,
  }) async {
    final res = await CloudApp.app.auth.signUp(
      SignUpReq(
        email: email,
        password: password,
        username: username,
        nickname: username,
      ),
    );
    if (res.error != null) throw Exception(res.error!.message);
    _pendingVerify = res.data?.verifyOtp;
    if (_pendingVerify == null) {
      throw Exception('发送验证码失败，请检查邮箱是否正确');
    }
  }

  /// 注册第二步：用验证码完成注册并登录
  Future<void> confirmSignUp(String code) async {
    final verify = _pendingVerify;
    if (verify == null) throw StateError('请先点击「发送验证码」');
    final res = await verify(VerifyOtpParams(token: code));
    if (res.error != null) throw Exception(res.error!.message);
    _pendingVerify = null;
    _user = res.data?.user ?? res.data?.session?.user;
    notifyListeners();
    _adoptNickname();
    _syncAvatar();
    await refreshDonator();
  }

  Future<void> signOut() async {
    await CloudApp.app.auth.signOut();
    _user = null;
    _pendingVerify = null;
    _isDonator = false;
    notifyListeners();
  }

  /// 重新拉取用户资料（头像上传后刷新）
  Future<void> refreshUser() async {
    if (_user == null) return;
    try {
      final res = await CloudApp.app.auth.getUser();
      _user = res.data?.user ?? _user;
      notifyListeners();
    } catch (_) {
      // 拉取失败保持现状
    }
  }

  /// 拉取捐赠状态（donators 集合里是否有自己的记录）；变化时通知，首次识别到发感谢通知
  Future<void> refreshDonator() async {
    final u = uid;
    if (u == null || u.isEmpty) {
      if (_isDonator) {
        _isDonator = false;
        notifyListeners();
      }
      return;
    }
    try {
      final db = CloudApp.app.database();
      final res = await db.collection('donators').where({'uid': u}).get();
      final v = res.isSuccess &&
          res.data.isNotEmpty &&
          res.data.first['enabled'] == true;
      if (v != _isDonator) {
        _isDonator = v;
        notifyListeners();
      }
      if (v) await _maybeThankDonator();
    } catch (_) {
      // 拉取失败保持现状
    }
  }

  /// 首次识别到捐赠时发一条感谢通知（只发一次）；权限没开就不记次数，下次再试
  Future<void> _maybeThankDonator() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('donator_notified') ?? false) return;
    final shown = await NotificationService.instance
        .show('感谢捐赠', '感谢支持 DIYAss！٩(◕‿◕｡)۶');
    if (shown) await prefs.setBool('donator_notified', true);
  }
}
