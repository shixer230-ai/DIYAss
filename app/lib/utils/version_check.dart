import 'dart:convert';
import 'dart:io';

/// 版本更新检测：拉取 GitHub 最新 release 的 tag，与本地版本比较
class VersionCheck {
  VersionCheck._();

  /// GitHub 仓库（发布 release 用）
  static const String kRepo = 'shixer230-ai/DIYAss';

  /// 最新 release 页面地址（有新版时点「去下载」跳转）
  static const String kReleasesUrl = 'https://github.com/$kRepo/releases/latest';

  /// 拉取 GitHub 最新 release 的版本号（去掉 v 前缀）；失败返回 null
  static Future<String?> latestVersion() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'),
      );
      req.headers.set(HttpHeaders.userAgentHeader, 'DIYAss');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return null;
      return tag.startsWith('v') ? tag.substring(1) : tag;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// a 是否比 b 新（按数字逐段比较，忽略 v 前缀）
  static bool isNewer(String a, String b) => compare(a, b) > 0;

  /// 比较两个版本号，正数表示 a 更新
  static int compare(String a, String b) {
    final pa = a.replaceAll(RegExp(r'^v'), '').split('.');
    final pb = b.replaceAll(RegExp(r'^v'), '').split('.');
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
