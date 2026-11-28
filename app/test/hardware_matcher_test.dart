import 'package:flutter_test/flutter_test.dart';

import 'package:diy_helper/ai/hardware_parser.dart';
import 'package:diy_helper/analysis/value_index.dart';
import 'package:diy_helper/data/hardware_catalog.dart';

void main() {
  group('findSpec 精准与模糊匹配', () {
    test('无前缀与非公长名显卡精准对齐', () {
      expect(
        findSpec('显卡', 'RTX5080', kHardwareCatalog)?.model,
        'GeForce RTX 5080',
      );
      expect(
        findSpec('显卡', '七彩虹 iGame RTX 5080 火神 OC 16G', kHardwareCatalog)?.model,
        'GeForce RTX 5080',
      );
      expect(
        findSpec('显卡', '华硕 TUF RTX 5070 Ti 16GB', kHardwareCatalog)?.model,
        'GeForce RTX 5070 Ti',
      );
      expect(
        findSpec('显卡', '七彩虹 RTX 4070 12G 战斧', kHardwareCatalog)?.model,
        'GeForce RTX 4070',
      );
      expect(
        findSpec('显卡', '微星 RTX 4070 Ti Super 万图师', kHardwareCatalog)?.model,
        'GeForce RTX 4070 Ti Super',
      );
      expect(
        findSpec('显卡', 'RTX 5090 D V2 24G', kHardwareCatalog)?.model,
        'GeForce RTX 5090 D V2',
      );
      expect(
        findSpec('显卡', 'RTX 5090 D 32G', kHardwareCatalog)?.model,
        'GeForce RTX 5090 D',
      );
      expect(
        findSpec('显卡', '华硕 RTX 5060 Ti 8G', kHardwareCatalog)?.model,
        'GeForce RTX 5060 Ti 8GB',
      );
      expect(
        findSpec('显卡', '华硕 RTX 5060 Ti 16G', kHardwareCatalog)?.model,
        'GeForce RTX 5060 Ti',
      );
      expect(
        findSpec('显卡', '蓝宝石 RX 9070 XT 超白金', kHardwareCatalog)?.model,
        'Radeon RX 9070 XT',
      );
      expect(
        findSpec('显卡', '蓝宝石 RX 6500 XT 白金版 OC', kHardwareCatalog)?.model,
        'Radeon RX 6500 XT',
      );
    });

    test('CPU 省略前缀、别名与变体精准区分', () {
      expect(
        findSpec('CPU', 'Ultra 7 270KPlus', kHardwareCatalog)?.model,
        '酷睿 Ultra 7 270K Plus',
      );
      expect(
        findSpec('CPU', 'AMD R7 9850X3D 盒装', kHardwareCatalog)?.model,
        '锐龙 7 9850X3D',
      );
      expect(
        findSpec('CPU', '9950X3D V2', kHardwareCatalog)?.model,
        '锐龙 9 9950X3D2',
      );
      expect(
        findSpec('CPU', '9950X3DV2', kHardwareCatalog)?.model,
        '锐龙 9 9950X3D2',
      );
      expect(
        findSpec('CPU', '9950X3D', kHardwareCatalog)?.model,
        '锐龙 9 9950X3D',
      );
      expect(
        findSpec('CPU', 'Intel i7 14700KF 散片', kHardwareCatalog)?.model,
        '酷睿 i7-14700KF',
      );
      expect(
        findSpec('CPU', 'Intel i7-14700K 盒装', kHardwareCatalog)?.model,
        '酷睿 i7-14700K',
      );
      expect(
        findSpec('CPU', 'AMD R5 5600 散片', kHardwareCatalog)?.model,
        '锐龙 5 5600',
      );
    });

    test('硬盘 1T/500G 简写与主板/电源简写匹配', () {
      expect(
        findSpec('硬盘', '三星 990PRO 1T', kHardwareCatalog)?.model,
        '990 PRO 1TB',
      );
      expect(
        findSpec('硬盘', '西数 SN850X 1T', kHardwareCatalog)?.model,
        '黑盘 SN850X 1TB',
      );
      expect(
        findSpec('硬盘', '致态 Ti600 500G', kHardwareCatalog)?.model,
        'Ti600 500GB',
      );
      expect(
        findSpec('电源', '海韵 FOCUS GX750', kHardwareCatalog)?.model,
        '海韵 FOCUS GX-750 金牌全模组',
      );
    });
  });

  group('parseHardwareFromText 电商截图 OCR 识别', () {
    test('单张 RTX5080 商品截图可识别出 GeForce RTX 5080', () {
      const ocr = '''
      京东自营
      七彩虹 iGame RTX5080 火神 OC 16G 电竞游戏独立显卡
      ¥9999
      ''';
      final res = parseHardwareFromText(ocr, kHardwareCatalog);
      expect(res.items.map((e) => e.model), contains('GeForce RTX 5080'));
      // 不应误匹配其他型号
      expect(res.items.length, 1);
    });

    test('完整购物车截图识别全部核心配件且不误伤相似型号', () {
      const ocr = '''
      购物车(7)
      AMD R7 9850X3D 盒装台式机处理器 ¥3699
      七彩虹 RTX5080 Ultra W OC 16G 显卡 ¥8999
      微星 MAG B850M MORTAR WiFi 迫击炮主板 ¥1399
      金士顿 FURY Beast DDR5-6000 32G (16G*2) ¥899
      三星 990PRO 1T PCIe4.0 固态硬盘 ¥799
      海韵 FOCUS GX-750 金牌全模组电源 ¥799
      联力 LANCOOL 216 黑色机箱 ¥449
      ''';
      final res = parseHardwareFromText(ocr, kHardwareCatalog);
      expect(res.enough, isTrue);
      final byCat = {for (final i in res.items) i.category: i.model};
      expect(byCat['CPU'], '锐龙 7 9850X3D');
      expect(byCat['显卡'], 'GeForce RTX 5080');
      expect(byCat['主板'], 'MAG B850M MORTAR WiFi');
      expect(byCat['内存'], 'FURY Beast DDR5-6000 32GB（16G×2）');
      expect(byCat['硬盘'], '990 PRO 1TB');
      expect(byCat['电源'], '海韵 FOCUS GX-750 金牌全模组');
      expect(byCat['机箱'], '联力 LANCOOL 216');
    });

    test('DDR5-5600 内存文案不会误匹配成 锐龙 5 5600 CPU', () {
      const ocr = '''
      金士顿 FURY Beast DDR5-5600 32G 内存条
      七彩虹 RTX 5070 Ti 16G 战斧
      ''';
      final res = parseHardwareFromText(ocr, kHardwareCatalog);
      final models = res.items.map((e) => e.model).toList();
      expect(models, contains('GeForce RTX 5070 Ti'));
      expect(models, isNot(contains('GeForce RTX 5070')));
      expect(models, isNot(contains('锐龙 5 5600')));
    });

    test('9950X3D V2 与 Ultra 7 270KPlus 均准确识别且不串号', () {
      const ocr1 = 'AMD 锐龙9 9950X3D V2 处理器 + 华硕 ROG STRIX X870E-E GAMING WiFi';
      final r1 = parseHardwareFromText(ocr1, kHardwareCatalog);
      expect(r1.items.map((e) => e.model), contains('锐龙 9 9950X3D2'));
      expect(r1.items.map((e) => e.model), isNot(contains('锐龙 9 9950X3D')));
      expect(r1.items.map((e) => e.model), isNot(contains('锐龙 9 9950X')));

      const ocr2 = '英特尔 Ultra7 270KPlus + 微星 MAG Z890 TOMAHAWK WiFi';
      final r2 = parseHardwareFromText(ocr2, kHardwareCatalog);
      expect(r2.items.map((e) => e.model), contains('酷睿 Ultra 7 270K Plus'));
    });
  });
}
