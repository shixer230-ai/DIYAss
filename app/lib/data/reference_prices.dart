// 市场参考价表（由维护者手工查价整理，仅供冷启动与估算参考）
//
// 说明：
// - 价格随渠道、优惠券与行情波动，仅标注查价月份作为参考，不代表实时售价；
// - 键格式统一为「品类|型号」，型号须与 hardware_catalog.dart 一致。

/// 最近一次参考价更新月份（展示给用户，让参考时效透明可见）
const String kRefPriceDate = '2026.11';

/// 品类|型号 -> 市场参考价（元）
const Map<String, double> kReferencePrices = {
  // ===== 方案 1：高端 Intel 游戏主机 =====
  'CPU|酷睿 i7-14700K': 2060,
  '显卡|GeForce RTX 4070 Super': 5899,
  '主板|MAG B760M MORTAR MAX WiFi DDR5': 955,
  '内存|FURY Beast DDR5-6000 32GB（16G×2）': 5249,
  '硬盘|990 PRO 1TB': 955,
  '电源|海韵 FOCUS GX-750 金牌全模组': 799,
  '机箱|联力 LANCOOL 216': 449,

  // ===== 方案 2：高端 AMD 游戏主机 =====
  'CPU|锐龙 7 7800X3D': 1799,
  '显卡|Radeon RX 7800 XT': 4079,
  '主板|MAG B650M MORTAR WiFi': 785,
  '内存|Trident Z5 RGB DDR5-6400 32GB（16G×2）': 3338,
  '硬盘|黑盘 SN850X 1TB': 1498,
  '电源|海盗船 RM850x 850W 金牌': 899,
  '机箱|联力 包豪斯 O11 Dynamic': 549,

  // ===== 方案 3：中端 Intel 主流主机 =====
  'CPU|酷睿 i5-13400F': 856,
  '显卡|GeForce RTX 4060': 2559,
  '主板|TUF GAMING B760M-PLUS WiFi D4': 515,
  '内存|FURY DDR4-3200 16GB（8G×2）': 1130,
  '硬盘|TiPlus7100 1TB': 1199,
  '电源|玄武 650K 金牌': 289,
  '机箱|乔思伯 D31 标准版': 266,

  // ===== 方案 4：中端 AMD 高性价比主机 =====
  'CPU|锐龙 5 5600': 638,
  '显卡|Radeon RX 6650 XT': 1699,
  '主板|TUF GAMING B550M-PLUS WiFi II': 641,
  '内存|银爵 DDR4-3600 32GB（16G×2）': 1415,
  '硬盘|Ti600 1TB': 976,
  '电源|玄武 500K 铜牌': 149,
  '机箱|九州风神 魔方110': 169,

  // ===== 方案 5：入门高性价比主机 =====
  'CPU|酷睿 i3-12100F': 400,
  '显卡|Radeon RX 6600': 1499,
  '主板|PRIME B760M-K DDR4': 452,
  '内存|天策 DDR4-3200 16GB（8G×2）': 580,
  '硬盘|Ti600 500GB': 479,
  '机箱|先马 平头哥M1': 129,

  // ===== 其他已查价型号 =====
  '硬盘|EXCERIA RC20 1TB': 2447,
  '硬盘|980 PRO 500GB': 1050,
  'CPU|锐龙 5 7500F': 566,
  'CPU|酷睿 i5-12400F': 794,
  '显卡|GeForce RTX 4060 Ti': 3099,
};

/// 按品类与型号查市场参考价；未收录返回 null
double? lookupReferencePrice(String category, String model) {
  return kReferencePrices['${category.trim()}|${model.trim()}'];
}
