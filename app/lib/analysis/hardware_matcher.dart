import '../models/hardware_spec.dart';

/// 硬件名称智能匹配引擎：
/// - 供 `findSpec`（兼容性、性价比、雷达图、云端识别结果对齐）使用
/// - 供 `parseHardwareFromText`（截图 OCR 本地识别）使用
///
/// 设计目标：
/// 1. 高召回：电商标题常见的省略前缀（无 GeForce/Radeon/酷睿/锐龙）、无空格（RTX5080）、
///    非公长名（七彩虹 iGame RTX 5080 火神 OC 16G）、容量简写（1T/16G）、别名（9950X3D V2）均可识别；
/// 2. 高精确：按匹配特异性打分 + 变体后缀边界保护，杜绝把 RTX 5070 Ti 错配成 RTX 5070、
///    把 RTX 4070 错配成 RTX 4070 Ti Super、把 9950X3D2 错配成 9950X、把 DDR5-5600 错配成 锐龙 5 5600。

/// 规范化用于匹配：小写 + 统一容量简写（1T→1TB、16G→16GB）+ 统一常见前缀简写（R7/U7）
/// + 去空白与标点，保留纯字母数字与中文。
String normalizeHardwareText(String raw) {
  var s = raw.toLowerCase();
  // 统一全角括号/符号与常见分隔符为空格，方便先做词级单位归一化
  s = s.replaceAll(RegExp(r'[\u3000\s\-_/·—–()（）\[\]【】,，.。:+*×]+'), ' ');
  // 电商常见容量简写：1t -> 1tb、16g -> 16gb（避免误伤 ghz / gtx / gre）
  s = s.replaceAllMapped(
    RegExp(r'(\d+)\s*t(?![a-z0-9])'),
    (m) => '${m.group(1)}tb',
  );
  s = s.replaceAllMapped(
    RegExp(r'(\d+)\s*g(?!(?:b|hz|tx|ts|t|re|ddr))'),
    (m) => '${m.group(1)}gb',
  );
  // 去除所有空格，得到紧凑串
  return s.replaceAll(' ', '');
}

/// 单个候选签名（从 HardwareSpec 派生）
class _Signature {
  final String key; // 已规范化的紧凑签名
  final int priority; // 越高越优先（完整型号 > 去前缀核心名 > 精简别名）

  const _Signature(this.key, {required this.priority});
}

/// 常见营销前缀（电商标题通常会省略）
final RegExp _gpuPrefix = RegExp(
  r'^(?:nvidia\s*|amd\s*|intel\s*)?(?:geforce\s+|radeon\s+)+',
  caseSensitive: false,
);
final RegExp _cpuPrefix = RegExp(
  r'^(?:intel\s*|amd\s*)?(?:酷睿|锐龙|至强|core|ryzen|xeon)\s*',
  caseSensitive: false,
);
final RegExp _ssdNickname = RegExp(r'^(?:黑盘|蓝盘|红盘|绿盘)\s*');
final RegExp _parenSuffix = RegExp(r'[（(][^）)]*[）)]');
final RegExp _psuMarketing = RegExp(
  r'(?:钛金|铂金|金牌|银牌|铜牌|白牌|全模组|半模组|直出|电源)+',
);

/// 显卡档位修饰词（跟在芯片数字后面，用于区分不同型号而非非公系列名如 Ultra W / OC）
const List<String> _gpuTierSuffixes = [
  'tisuper',
  'super',
  'xtx',
  'gre',
  'xt',
  'ti',
  'se',
  'xl',
  'v2',
  'le',
];

/// CPU 档位修饰词（区分 K / KF / KS / X / X3D / X3D2 / Plus 等不同型号）
const List<String> _cpuTierSuffixes = [
  'x3d2',
  'x3dv2',
  'x3d',
  'kfplus',
  'kplus',
  'plus',
  'kf',
  'ks',
  'xt',
  'ge',
  'gt',
  'v4',
  'v3',
  'v2',
  'k',
  'f',
  'x',
  'g',
  't',
  's',
];

/// 通用容量/频率/功率词（绝不能单独拿来做型号兜底匹配，否则会把任意 16GB/32GB/6000 乱配）
final RegExp _genericSpecToken = RegExp(
  r'^(?:\d+(?:gb|tb|mb|w|mhz|hz)|ddr[345]\d*|pcie\d*|gen\d*|20\d{2}|1080p|1440p|2160p)$',
);

/// 为硬件库的一条型号生成匹配签名列表
List<_Signature> _signaturesFor(HardwareSpec spec, {Set<String>? sharedBaseGpu}) {
  final sigs = <_Signature>[];
  final seen = <String>{};

  void add(String raw, int priority) {
    final k = normalizeHardwareText(raw);
    if (k.length < 3) return;
    if (_genericSpecToken.hasMatch(k)) return;
    if (seen.add(k)) {
      sigs.add(_Signature(k, priority: priority));
    }
  }

  final model = spec.model.trim();
  final brand = spec.brand.trim();

  // 1) 完整型号（最高优先级）
  add(model, 100);
  if (brand.isNotEmpty && !model.toLowerCase().contains(brand.toLowerCase())) {
    add('$brand $model', 105);
  }

  // 2) specs 里的「别名」字段（如 9950X3D V2）
  for (final e in spec.specs) {
    if (e.label == '别名') {
      for (final part in e.value.split(RegExp(r'[/、,，]'))) {
        add(part, 92);
      }
    }
  }

  // 3) 按品类派生核心签名
  switch (spec.category) {
    case '显卡':
      final core = model.replaceFirst(_gpuPrefix, '').trim();
      if (core.isNotEmpty && core != model) {
        add(core, 90);
      }
      // 显存区分（如 RTX 5060 Ti 16GB vs RTX 5060 Ti 8GB）
      final vram = _vramCapacity(spec);
      if (vram != null && core.isNotEmpty) {
        final normCore = normalizeHardwareText(core);
        if (!normCore.endsWith(vram)) {
          add('$core $vram', 96);
        }
        // 若同名卡存在不同显存版本，不带显存的基础签名降一点优先级，让显存精确命中胜出
        if (sharedBaseGpu != null && sharedBaseGpu.contains(normCore)) {
          add(core, 85);
        }
      }
      break;

    case 'CPU':
      final noPrefix = model.replaceFirst(_cpuPrefix, '').trim();
      if (noPrefix.isNotEmpty && noPrefix != model) {
        add(noPrefix, 92);
      }
      // 锐龙 N xxxx -> rN xxxx / ryzen N xxxx；Ultra N xxxx -> uN xxxx
      final ryzenMatch = RegExp(r'^锐龙\s*([3579])\s+(.+)$').firstMatch(model);
      if (ryzenMatch != null) {
        final tier = ryzenMatch.group(1)!;
        final code = ryzenMatch.group(2)!.trim();
        add('r$tier $code', 90);
        add('ryzen $tier $code', 90);
        if (_isDistinctiveCpuCode(code)) {
          add(code, 82);
        }
      }
      final ultraMatch =
          RegExp(r'ultra\s*([579])\s+(.+)$', caseSensitive: false)
              .firstMatch(model);
      if (ultraMatch != null) {
        final tier = ultraMatch.group(1)!;
        final code = ultraMatch.group(2)!.trim();
        add('ultra $tier $code', 92);
        add('u$tier $code', 88);
        if (_isDistinctiveCpuCode(code)) {
          add(code, 82);
        }
      }
      final coreIMatch =
          RegExp(r'(i[3579])[-\s]+(.+)$', caseSensitive: false).firstMatch(model);
      if (coreIMatch != null) {
        final tier = coreIMatch.group(1)!;
        final code = coreIMatch.group(2)!.trim();
        add('$tier $code', 92);
        if (_isDistinctiveCpuCode(code)) {
          add(code, 82);
        }
      }
      final xeonMatch =
          RegExp(r'(e[35])[-\s]+(.+)$', caseSensitive: false).firstMatch(model);
      if (xeonMatch != null) {
        final series = xeonMatch.group(1)!;
        final code = xeonMatch.group(2)!.trim();
        add('$series $code', 92);
        if (_isDistinctiveCpuCode(code)) {
          add(code, 80);
        }
      }
      break;

    case '主板':
      // 去掉 WiFi/DDR4/DDR5/GAMING 等可选后缀，作为次级签名
      final stripped = model
          .replaceAll(RegExp(r'\b(?:wifi\s*6e?|wifi\s*7|wifi|ax|ddr[45]|d[45]|gaming|mag|mpg|rog|strix|tuf|prime|pro)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      // 同时保留「系列+芯片组+型号」的常见缩写（如 TUF B760M-PLUS、B760M MORTAR）
      final noWifi = model
          .replaceAll(RegExp(r'\b(?:wifi\s*6e?|wifi\s*7|wifi|ax|ddr[45]|d[45])\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (noWifi.length >= 6) add(noWifi, 86);
      if (stripped.length >= 6) add(stripped, 78);
      break;

    case '内存':
      final noParen = model.replaceAll(_parenSuffix, '').trim();
      if (noParen.isNotEmpty && noParen != model) {
        add(noParen, 90);
      }
      break;

    case '硬盘':
      final noNick = model.replaceFirst(_ssdNickname, '').trim();
      if (noNick.isNotEmpty && noNick != model) {
        add(noNick, 88);
      }
      break;

    case '电源':
      final noBrand = _stripBrand(model, brand);
      final clean = noBrand.replaceAll(_psuMarketing, '').trim();
      if (noBrand.length >= 4) add(noBrand, 88);
      if (clean.length >= 4) add(clean, 82);
      if (brand.isNotEmpty && clean.length >= 3) {
        add('$brand $clean', 86);
      }
      break;

    case '机箱':
      final noBrand = _stripBrand(model, brand);
      final noStd = noBrand.replaceAll(RegExp(r'标准版|标准|黑色|白色'), '').trim();
      if (noBrand.length >= 3) add(noBrand, 86);
      if (noStd.length >= 3) add(noStd, 82);
      break;
  }

  return sigs;
}

String _stripBrand(String model, String brand) {
  if (brand.isEmpty) return model;
  if (model.toLowerCase().startsWith(brand.toLowerCase())) {
    return model.substring(brand.length).trim();
  }
  return model;
}

/// CPU 独立型号码是否足够独特、适合脱离前缀单独匹配
/// 例如 14700K / 7800X3D / 9850X3D / 9950X3D2 / 270K Plus / 7500F / 12100F -> true
/// 例如 5600 / 7700 / 265 / 235 / 9600（纯数字，容易和内存频率 DDR5-5600 或价格撞车）-> false
bool _isDistinctiveCpuCode(String code) {
  final norm = normalizeHardwareText(code);
  if (norm.length < 4) return false;
  // 纯数字绝不裸匹配
  if (RegExp(r'^\d+$').hasMatch(norm)) return false;
  // 必须包含数字且带有明确的 CPU 后缀字母（且不能像容量/功耗）
  if (_genericSpecToken.hasMatch(norm)) return false;
  return RegExp(
    r'^\d{3,5}(?:k|kf|ks|f|x|xt|x3d|x3d2|x3dv2|g|ge|t|kplus|kfplus|v[234])$',
  ).hasMatch(norm);
}

String? _vramCapacity(HardwareSpec spec) {
  for (final s in spec.specs) {
    if (s.label == '显存') {
      final m = RegExp(r'(\d+)\s*gb', caseSensitive: false).firstMatch(s.value);
      if (m != null) return '${m.group(1)}gb';
    }
  }
  return null;
}

/// CPU 系列前缀 + 档位数字（如 锐龙9 / R7 / i7 / Ultra7 / U5），紧接在型号数字前时属于合法边界
final RegExp _cpuTierPrefixBeforeDigit = RegExp(
  r'(?:锐龙|ryzen|ultra|[iru])[3579]$',
);

/// 检查签名 [sig] 在 [normText] 的 [start..end) 处是否满足边界条件，
/// 防止短型号误吃掉长变体（如 rtx5070 误命中 rtx5070ti，9950x 误命中 9950x3d）。
bool _isValidBoundary(String normText, int start, int end, String category, String sig) {
  // 1) 前边界：若签名以数字开头，前面不能紧贴另一个数字（防止 114700k 命中 14700k，或 16gb 命中 6gb）；
  //    但 CPU 系列档位（如「锐龙9」「R7」「i7」「Ultra7」去空格后紧贴 9950X3D / 14700K）属于合法边界
  if (start > 0 && _isDigit(sig.codeUnitAt(0)) && _isDigit(normText.codeUnitAt(start - 1))) {
    final before = normText.substring(0, start);
    if (!(category == 'CPU' && _cpuTierPrefixBeforeDigit.hasMatch(before))) {
      return false;
    }
  }

  // 2) 后边界
  if (end >= normText.length) return true;
  final tail = normText.substring(end);
  final nextChar = tail.codeUnitAt(0);

  // 若签名以数字结尾，后面不能紧贴另一个数字（防止 508 命中 5080）
  if (_isDigit(sig.codeUnitAt(sig.length - 1)) && _isDigit(nextChar)) {
    return false;
  }

  if (category == '显卡') {
    // 后面紧跟显卡档位词（ti / super / xt / xtx / gre / se / v2 / pro / ultra / le），
    // 说明原文指的是更高/不同档位的卡，不能匹配基础型号
    for (final mod in _gpuTierSuffixes) {
      if (tail.startsWith(mod)) return false;
    }
    // 特殊处理 RTX 5090 D / 4090 D：后面紧跟 d 且不是 ddr/display 等词
    if (tail.startsWith('d') && !tail.startsWith('ddr')) {
      // 仅当 d 后面不是普通英文词（即后面是结尾、数字、中文、v2、oc、16gb 等）
      if (tail.length == 1 ||
          !_isAsciiLetter(tail.codeUnitAt(1)) ||
          tail.startsWith('dv2') ||
          tail.startsWith('doc')) {
        return false;
      }
    }
    return true;
  }

  if (category == 'CPU') {
    // 若签名结尾已含字母或数字，检查后面是否紧跟 CPU 变体后缀（防止 14700k 命中 14700kf、
    // 9950x 命中 9950x3d、9950x3d 命中 9950x3d2 / 9950x3dv2、270k 命中 270kplus）
    if (sig.endsWith('x') && tail.startsWith('3d')) return false;
    if (tail.startsWith('2') && sig.endsWith('x3d')) return false;
    if (tail.startsWith('v2') || tail.startsWith('v3') || tail.startsWith('v4')) {
      return false;
    }
    for (final mod in _cpuTierSuffixes) {
      if (tail.startsWith(mod)) {
        // 避免把后面的正常英文词（如 "fan" / "gaming" / "ghz"）当成单字母后缀 f/g
        if (mod.length == 1 && tail.length > 1 && _isAsciiLetter(tail.codeUnitAt(1))) {
          // 除非是已知双字母 CPU 后缀（如 kf / ks / xt / x3d）
          continue;
        }
        return false;
      }
    }
    return true;
  }

  return true;
}

bool _isDigit(int c) => c >= 48 && c <= 57;
bool _isAsciiLetter(int c) => (c >= 97 && c <= 122) || (c >= 65 && c <= 90);

/// 在 [normText] 里寻找 [sig] 的第一个合法边界匹配位置；找不到返回 -1
int _findBoundaryMatch(String normText, String sig, String category) {
  var from = 0;
  while (from <= normText.length - sig.length) {
    final idx = normText.indexOf(sig, from);
    if (idx < 0) return -1;
    if (_isValidBoundary(normText, idx, idx + sig.length, category, sig)) {
      return idx;
    }
    from = idx + 1;
  }
  return -1;
}

/// 找出同品类下存在多个显存版本的显卡基础名（如 RTX 5060 Ti 16GB / 8GB）
Set<String> _sharedBaseGpuNames(List<HardwareSpec> lib) {
  final counts = <String, int>{};
  for (final s in lib) {
    if (s.category != '显卡') continue;
    final core = normalizeHardwareText(
      s.model.replaceFirst(_gpuPrefix, '').replaceAll(RegExp(r'\d+\s*gb$', caseSensitive: false), ''),
    );
    if (core.isNotEmpty) counts[core] = (counts[core] ?? 0) + 1;
  }
  return {
    for (final e in counts.entries)
      if (e.value > 1) e.key,
  };
}

/// 按「品类 + 型号名」匹配硬件库中最契合的规格：
/// 1. 完整规范化精确匹配
/// 2. 签名精确匹配（如「RTX5080」直中「GeForce RTX 5080」）
/// 3. 边界安全的最佳签名命中（按 优先级 + 签名长度 打分，不会把 RTX 4070 错配成 RTX 4070 Ti Super）
/// 4. 型号反包含（用户输入短于库里全称，如「B760M MORTAR」）
HardwareSpec? matchSpecByName(
  String category,
  String model,
  List<HardwareSpec> lib,
) {
  final normInput = normalizeHardwareText(model);
  if (normInput.isEmpty) return null;

  final sharedGpus = category == '显卡' ? _sharedBaseGpuNames(lib) : null;

  HardwareSpec? best;
  var bestScore = -1;

  for (final spec in lib) {
    if (spec.category != category) continue;
    final normSpec = normalizeHardwareText(spec.model);

    // 1) 完整型号完全一致
    if (normSpec == normInput) return spec;

    final sigs = _signaturesFor(spec, sharedBaseGpu: sharedGpus);
    for (final sig in sigs) {
      // 2) 签名完全一致（例如输入「RTX5080」正好等于核心签名「rtx5080」）
      if (sig.key == normInput) {
        final score = 10000 + sig.priority * 10 + sig.key.length;
        if (score > bestScore) {
          bestScore = score;
          best = spec;
        }
        continue;
      }

      // 3) 输入包含签名（例如「七彩虹 iGame RTX 5080 火神 OC 16G」包含「rtx5080」）
      if (_findBoundaryMatch(normInput, sig.key, category) >= 0) {
        final score = 5000 + sig.key.length * 40 + sig.priority * 5;
        if (score > bestScore) {
          bestScore = score;
          best = spec;
        }
        continue;
      }

      // 4) 签名反包含输入（例如用户输入简写「B760M MORTAR」被完整主板名包含）
      if (normInput.length >= 5 &&
          !_genericSpecToken.hasMatch(normInput) &&
          _findBoundaryMatch(sig.key, normInput, category) >= 0) {
        // 偏向越接近输入长度的候选（避免「RTX 4070」反包含命中更长的「RTX 4070 Ti Super」）
        final lenDiff = (sig.key.length - normInput.length).abs();
        final score = 2000 + normInput.length * 20 - lenDiff * 15 + sig.priority;
        if (score > bestScore) {
          bestScore = score;
          best = spec;
        }
      }
    }
  }

  return best;
}

/// 一条从长文本（OCR 截图文字）里提取出的命中记录
class _TextHit {
  final HardwareSpec spec;
  final int start;
  final int end;
  final int score;

  const _TextHit({
    required this.spec,
    required this.start,
    required this.end,
    required this.score,
  });
}

/// 从整段 OCR 文本里提取所有匹配到的硬件库型号：
/// - 支持无前缀、无空格、非公长名、容量简写（1T/16G）、别名
/// - 按匹配特异性从高到低挑选，并标记已占用的文本区间，避免同一处文本同时命中父/子型号
List<HardwareSpec> extractSpecsFromText(String text, List<HardwareSpec> lib) {
  final normText = normalizeHardwareText(text);
  if (normText.isEmpty) return const [];

  final sharedGpus = _sharedBaseGpuNames(lib);
  final hits = <_TextHit>[];

  for (final spec in lib) {
    final sigs = _signaturesFor(spec, sharedBaseGpu: sharedGpus);
    _TextHit? bestForSpec;
    for (final sig in sigs) {
      // 在整段长文本中扫描时，至少 4 字符才匹配，避免短词误触发
      if (sig.key.length < 4) continue;
      final idx = _findBoundaryMatch(normText, sig.key, spec.category);
      if (idx < 0) continue;
      final score = sig.key.length * 50 + sig.priority * 5;
      if (bestForSpec == null || score > bestForSpec.score) {
        bestForSpec = _TextHit(
          spec: spec,
          start: idx,
          end: idx + sig.key.length,
          score: score,
        );
      }
    }
    if (bestForSpec != null) hits.add(bestForSpec);
  }

  // 特异性高的排前面（如 RTX 5070 Ti 排在 RTX 5070 前，9950X3D2 排在 9950X3D 前）
  hits.sort((a, b) {
    final cmp = b.score.compareTo(a.score);
    if (cmp != 0) return cmp;
    return a.start.compareTo(b.start);
  });

  final occupied = <(int, int)>[];
  final chosen = <_TextHit>[];
  final seenIds = <String>{};

  bool overlaps(int s, int e) {
    for (final span in occupied) {
      if (s < span.$2 && e > span.$1) return true;
    }
    return false;
  }

  for (final hit in hits) {
    if (!seenIds.add(hit.spec.id)) continue;
    if (overlaps(hit.start, hit.end)) continue;
    occupied.add((hit.start, hit.end));
    chosen.add(hit);
  }

  // 最终按在截图原文中出现的先后顺序输出
  chosen.sort((a, b) => a.start.compareTo(b.start));
  return chosen.map((h) => h.spec).toList();
}
