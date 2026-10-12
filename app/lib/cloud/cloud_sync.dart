import 'dart:convert';

import 'package:cloudbase_flutter/cloudbase_flutter.dart';

import '../models/build_plan.dart';
import '../models/cloud_plan.dart';
import '../models/custom_item.dart';
import '../models/hardware_spec.dart';
import '../utils/json_safe.dart';
import 'auth_service.dart';
import 'cloud_app.dart';

/// 云端数据读写：方案上传/拉取/删除（按用户隔离），以及头像上传
class CloudSync {
  const CloudSync._();

  /// 每个用户云端方案数量上限（防恶意占用）
  static const int kMaxCloudPlans = 30;

  static const int kMaxPlanNameLen = 50;

  /// 单个方案最大配件数（实际槽位约 7 个）
  static const int kMaxComponentsPerPlan = 16;

  /// 每个用户云端自定义项目数量上限（防恶意占用）
  static const int kMaxCloudCustomItems = 30;

  static const int kMaxCustomNameLen = 50;

  /// 取当前登录用户 uid；未登录抛错
  static String _requireUid() {
    final uid = AuthService.instance.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('请先在「我的」页登录');
    }
    return uid;
  }

  /// 校验方案数据合法，拦异常/超大 payload（防恶意刷数据）
  static void _validatePlan(BuildPlan plan) {
    if (plan.name.length > kMaxPlanNameLen) {
      throw Exception('方案名过长（最多 $kMaxPlanNameLen 字）');
    }
    if (plan.components.length > kMaxComponentsPerPlan) {
      throw Exception('方案配件数量异常');
    }
    for (final c in plan.components.values) {
      if (c.price < 0) throw Exception('配件价格异常');
    }
  }

  /// 上传单个方案：按 id 幂等覆盖，写入 owner 做用户隔离
  static Future<void> uploadPlan(BuildPlan plan) async {
    final uid = _requireUid();
    _validatePlan(plan);
    final db = CloudApp.app.database();
    final data = plan.toJson()..['owner'] = uid;
    final res = await db.collection('plans').doc(plan.id).set(data);
    if (!res.isSuccess) {
      throw Exception('上传失败：${res.message ?? res.code}');
    }
  }

  /// 拉取当前用户自己的方案（按 owner 过滤，避免串号）
  static Future<List<BuildPlan>> downloadPlans() async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res = await db
        .collection('plans')
        .where({'owner': uid})
        .limit(kMaxCloudPlans)
        .get();
    if (!res.isSuccess) {
      throw Exception('拉取失败：${res.message ?? res.code}');
    }
    return res.data.map((e) => BuildPlan.fromJson(e)).toList();
  }

  /// 统计云端方案数（上传前判上限）；失败返回大数让上限检查跳过
  static Future<int> countPlans() async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res = await db.collection('plans').where({'owner': uid}).count();
    if (!res.isSuccess) return kMaxCloudPlans + 1;
    return res.total;
  }

  /// 删除云端方案：只删自己名下的（owner + id 过滤，防删到别人的数据）
  static Future<void> deletePlan(String planId) async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res = await db
        .collection('plans')
        .where({'owner': uid, 'id': planId})
        .remove();
    if (!res.isSuccess) {
      throw Exception('云端删除失败：${res.message ?? res.code}');
    }
  }

  /// 校验自定义项目数据合法
  static void _validateCustomItem(CustomItem item) {
    if (item.name.length > kMaxCustomNameLen) {
      throw Exception('项目名过长（最多 $kMaxCustomNameLen 字）');
    }
    if (item.description.length > 200) {
      throw Exception('画质描述过长');
    }
  }

  /// 上传单个自定义项目（按 id 幂等覆盖，写入 owner）
  static Future<void> uploadCustomItem(CustomItem item) async {
    final uid = _requireUid();
    _validateCustomItem(item);
    final db = CloudApp.app.database();
    final data = item.toJson()..['owner'] = uid;
    final res = await db.collection('custom_items').doc(item.id).set(data);
    if (!res.isSuccess) {
      throw Exception('上传失败：${res.message ?? res.code}');
    }
  }

  /// 拉取当前用户自己的自定义项目
  static Future<List<CustomItem>> downloadCustomItems() async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res = await db
        .collection('custom_items')
        .where({'owner': uid})
        .limit(kMaxCloudCustomItems)
        .get();
    if (!res.isSuccess) {
      throw Exception('拉取失败：${res.message ?? res.code}');
    }
    return res.data.map((e) => CustomItem.fromJson(e)).toList();
  }

  /// 统计云端自定义项目数（上传前判上限）
  static Future<int> countCustomItems() async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res =
        await db.collection('custom_items').where({'owner': uid}).count();
    if (!res.isSuccess) return kMaxCloudCustomItems + 1;
    return res.total;
  }

  /// 删除云端自定义项目：只删自己名下的（owner + id 过滤，防删到别人的数据）
  static Future<void> deleteCustomItem(String itemId) async {
    final uid = _requireUid();
    final db = CloudApp.app.database();
    final res = await db
        .collection('custom_items')
        .where({'owner': uid, 'id': itemId})
        .remove();
    if (!res.isSuccess) {
      throw Exception('云端删除失败：${res.message ?? res.code}');
    }
  }

  /// 拉取云端发行的硬件库（共享集合，无 owner 隔离，读参考硬件）
  static Future<List<HardwareSpec>> downloadHardwareCatalog() async {
    final db = CloudApp.app.database();
    final res = await db.collection('hardware_catalog').limit(5000).get();
    if (!res.isSuccess) {
      throw Exception('拉取硬件库失败：${res.message ?? res.code}');
    }
    return res.data.map((e) => HardwareSpec.fromJson(e)).toList();
  }

  /// 上传头像到云存储，并把 fileId 存进账号资料
  static Future<void> uploadAvatar(List<int> bytes, String ext) async {
    final storage = CloudApp.app.storage.from();
    final name = '${AuthService.instance.username ?? 'user'}'
        '_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final up = await storage.upload(
      'avatars/$name',
      bytes,
      options: StorageUploadOptions(contentType: 'image/$ext', upsert: true),
    );
    final fileId = up.data?.id;
    if (fileId == null || fileId.isEmpty) {
      throw Exception('头像上传失败：${up.error?.message ?? '未知错误'}');
    }
    // 把 fileId 存进账号资料（头像的稳定引用）
    await CloudApp.app.auth.updateUser(UpdateUserReq(avatarUrl: fileId));
    // 上传后刷新本地缓存的用户资料
    await AuthService.instance.refreshUser();
  }

  /// 用账号里的 fileId 换临时下载链接
  static Future<String?> avatarDownloadUrl() async {
    final fileId = AuthService.instance.avatarUrl;
    if (fileId == null || !fileId.startsWith('cloud://')) return null;
    final storage = CloudApp.app.storage.from();
    final res = await storage.getDownloadUrls([fileId], expiresIn: 3600);
    return res.data?.first.downloadUrl;
  }

  /// 用爱发电订单号自助开通 donator（云函数查单并写入 donators）
  static Future<void> verifyDonation(String orderNo) async {
    _requireUid();
    final res = await CloudApp.app.callFunction(
      name: 'verifyDonation',
      data: {'orderNo': orderNo},
    );
    if (!res.isSuccess) {
      throw Exception(res.message ?? '调用失败');
    }
    Map<String, dynamic>? map;
    final result = res.result;
    if (result is Map) {
      map = Map<String, dynamic>.from(result);
    } else if (result is String) {
      try {
        map = jsonDecode(result) as Map<String, dynamic>;
      } catch (_) {
        // 非 JSON 按无结果处理
      }
    }
    final error = map?['error'];
    if (error is String && error.isNotEmpty) {
      throw Exception(error);
    }
    if (map?['ok'] != true) {
      throw Exception('开通失败，请重试');
    }
  }

  /// 把云函数返回结果解析成 Map（result 可能是 Map 或 JSON 字符串）
  static Map<String, dynamic> _parseResult(dynamic result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is String) {
      try {
        final d = jsonDecode(result);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {
        // 非 JSON 按无结果处理
      }
    }
    return const {};
  }

  /// 上传方案到公开的「云方案」栏目（云函数做每日限额 + 关键词内容合规检测）
  static Future<void> publishPlan(BuildPlan plan) async {
    _requireUid();
    final res = await CloudApp.app.callFunction(
      name: 'publishPlan',
      data: {'plan': plan.toJson()},
    );
    if (!res.isSuccess) {
      throw Exception(res.message ?? '上传失败');
    }
    final map = _parseResult(res.result);
    final error = map['error'];
    if (error is String && error.isNotEmpty) throw Exception(error);
    if (map['ok'] != true) throw Exception('上传失败，请重试');
  }

  /// 点赞 / 取消点赞某个云方案，返回最新点赞状态与数量
  static Future<({bool liked, int likeCount})> likePlan(String planId) async {
    _requireUid();
    final res = await CloudApp.app.callFunction(
      name: 'likePlan',
      data: {'planId': planId},
    );
    if (!res.isSuccess) {
      throw Exception(res.message ?? '操作失败');
    }
    final map = _parseResult(res.result);
    final error = map['error'];
    if (error is String && error.isNotEmpty) throw Exception(error);
    if (map['ok'] != true) throw Exception('操作失败，请重试');
    return (liked: map['liked'] == true, likeCount: asInt(map['likeCount']));
  }

  /// 删除自己上传的云方案（云函数校验归属 + 计入每日次数）
  static Future<void> deleteCloudPlan(String planId) async {
    _requireUid();
    final res = await CloudApp.app.callFunction(
      name: 'deleteCloudPlan',
      data: {'planId': planId},
    );
    if (!res.isSuccess) {
      throw Exception(res.message ?? '删除失败');
    }
    final map = _parseResult(res.result);
    final error = map['error'];
    if (error is String && error.isNotEmpty) throw Exception(error);
    if (map['ok'] != true) throw Exception('删除失败，请重试');
  }

  /// 拉取公开的云方案列表，按点赞数降序、同赞按时间倒序
  static Future<List<CloudPlan>> downloadCloudPlans() async {
    final db = CloudApp.app.database();
    final res = await db.collection('cloud_plans').limit(200).get();
    if (!res.isSuccess) {
      throw Exception('拉取云方案失败：${res.message ?? res.code}');
    }
    final list = res.data.map((e) => CloudPlan.fromJson(e)).toList();
    list.sort((a, b) {
      final byLikes = b.likeCount.compareTo(a.likeCount);
      if (byLikes != 0) return byLikes;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }
}
