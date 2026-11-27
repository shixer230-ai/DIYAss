import '../utils/json_safe.dart';

/// 单个配件价格上限（元），超过视为异常输入，提示用户重新输入
const double kMaxPrice = 8388608;

/// 整机方案里的一个配件（含价格）
class PlanComponent {
  final String category;
  final String brand;
  final String model;
  final double price;
  final String platform;

  /// 是否为内置市场参考价（true = 浅色展示并提示可改为实付价；用户手动改价后置为 false）
  final bool isRefPrice;

  const PlanComponent({
    required this.category,
    required this.brand,
    required this.model,
    required this.price,
    required this.platform,
    this.isRefPrice = false,
  });

  factory PlanComponent.fromJson(Map<String, dynamic> json) {
    return PlanComponent(
      category: asString(json['category']),
      brand: asString(json['brand']),
      model: asString(json['model']),
      price: asDouble(json['price']),
      platform: asString(json['platform']),
      isRefPrice: json['isRefPrice'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'brand': brand,
      'model': model,
      'price': price,
      'platform': platform,
      if (isRefPrice) 'isRefPrice': true,
    };
  }
}

/// 整机方案：按槽位（cpu/gpu/主板/内存/电源/机箱）存放已选配件，硬盘支持多块
/// 每个方案有自己的 id 和名称，可保存多个
class BuildPlan {
  final String id;
  final String name;
  final Map<String, PlanComponent> components;

  /// 硬盘可多块，单独用列表存（其余槽位每种一个，放在 components 里）
  final List<PlanComponent> storages;

  /// 用户自定义的整机功耗（W），为空时分析页自动按 CPU+显卡 计算
  final double? customPower;

  BuildPlan({
    String? id,
    this.name = '',
    Map<String, PlanComponent>? components,
    List<PlanComponent>? storages,
    this.customPower,
  })  : id = id ?? newId(),
        components = components ?? {},
        storages = storages ?? [];

  static String newId() => 'plan_${DateTime.now().microsecondsSinceEpoch}';

  PlanComponent? operator [](String key) => components[key];

  void set(String key, PlanComponent? c) {
    if (c == null) {
      components.remove(key);
    } else {
      components[key] = c;
    }
  }

  double get total =>
      components.values.fold(0.0, (s, c) => s + c.price) +
      storages.fold(0.0, (s, c) => s + c.price);

  /// 已选硬件件数（含多块硬盘），用于列表展示「N 件」
  int get filledCount => components.length + storages.length;

  /// 方案里是否包含仍处于「参考价」状态的配件
  bool get hasRefPrices =>
      components.values.any((c) => c.isRefPrice) ||
      storages.any((c) => c.isRefPrice);

  factory BuildPlan.fromJson(Map<String, dynamic> json) {
    final comps = <String, PlanComponent>{};
    asStringMap(json['components']).forEach((k, v) {
      if (v is Map) {
        comps[k] = PlanComponent.fromJson(Map<String, dynamic>.from(v));
      }
    });
    final storages = <PlanComponent>[];
    // 旧版本把硬盘放在 components['storage']，这里迁移到 storages 列表
    final oldStorage = comps.remove('storage');
    if (oldStorage != null) storages.add(oldStorage);
    for (final v in asList(json['storages'])) {
      if (v is Map) {
        storages.add(PlanComponent.fromJson(Map<String, dynamic>.from(v)));
      }
    }
    return BuildPlan(
      id: asNullableString(json['id']),
      name: asString(json['name']),
      components: comps,
      storages: storages,
      customPower: asNullableDouble(json['customPower']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'components': components.map((k, v) => MapEntry(k, v.toJson())),
      'storages': storages.map((e) => e.toJson()).toList(),
      'customPower': customPower,
    };
  }
}
