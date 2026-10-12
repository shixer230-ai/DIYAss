import '../utils/json_safe.dart';
import 'build_plan.dart';

/// 云端公开方案：用户上传到「硬件库 → 云方案」栏目后的公开条目
/// 含完整方案数据、点赞人列表、上传时间与展示用日期
class CloudPlan {
  final String id;
  final String owner;
  final BuildPlan plan;
  final List<String> likers;
  final DateTime createdAt;
  final String date;

  CloudPlan({
    required this.id,
    required this.owner,
    required this.plan,
    required this.likers,
    required this.createdAt,
    required this.date,
  });

  String get name => plan.name.isEmpty ? '未命名方案' : plan.name;

  double get total => plan.total;

  int get filledCount => plan.filledCount;

  int get likeCount => likers.length;

  bool likedBy(String uid) => likers.contains(uid);

  CloudPlan copyWith({List<String>? likers}) => CloudPlan(
        id: id,
        owner: owner,
        plan: plan,
        likers: likers ?? this.likers,
        createdAt: createdAt,
        date: date,
      );

  factory CloudPlan.fromJson(Map<String, dynamic> json) {
    return CloudPlan(
      id: asString(json['id']),
      owner: asString(json['owner']),
      plan: BuildPlan.fromJson(asStringMap(json['plan'])),
      likers: asList(json['likers']).whereType<String>().toList(),
      createdAt: asDate(json['createdAt']),
      date: asString(json['date']),
    );
  }
}
