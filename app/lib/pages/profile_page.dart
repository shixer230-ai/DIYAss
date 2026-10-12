import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../cloud/auth_service.dart';
import '../cloud/cloud_sync.dart';
import '../models/build_plan.dart';
import '../storage/avatar_image_store.dart';
import '../storage/background_image_store.dart';
import '../storage/build_plan_store.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/category_icons.dart';
import 'account_page.dart';
import 'build_plan_page.dart' show kBuildSlots;

/// 「我的」页：个人信息 + 自定义背景 + 主题色 + 外观（深浅色）+ 关于
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _pickBackground(BuildContext context) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
      maxHeight: 2160,
    );
    if (file == null) return;
    final path = await BackgroundImageStore.saveImage(file);
    if (!context.mounted) return;
    await ThemeController.instance.setBackground(path);
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file == null) return;
    final path = await AvatarImageStore.saveImage(file);
    if (!context.mounted) return;
    await ThemeController.instance.setAvatar(path);
    // 已登录则自动把新头像上传到云（尽力而为，不打断本地流程）
    if (!context.mounted) return;
    if (AuthService.instance.isLoggedIn) _uploadAvatar(context);
  }

  Future<void> _editNickname(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NicknameDialog(initial: ThemeController.instance.nickname),
    );
    if (result == null) return;
    await ThemeController.instance.setNickname(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: ThemeController.instance,
          builder: (context, _) {
            final theme = Theme.of(context);
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: false,
                  floating: false,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  title: const Text('我的'),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    12 + bottomNavClearance(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _accountCard(context, theme),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, '背景'),
                      _backgroundCard(theme, context),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, '主题色'),
                      _seedCard(theme),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, '外观'),
                      _appearanceCard(theme),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, '工具'),
                      _toolsCard(theme, context),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, '关于'),
                      _aboutCard(context, theme),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 顶部卡片：头像 + 昵称 + 账号与云同步（登录/注册、上传头像、退出登录）合并为一块
  Widget _accountCard(BuildContext context, ThemeData theme) {
    final nickname = ThemeController.instance.nickname;
    final avatarPath = ThemeController.instance.avatarPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 头像 + 昵称
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _avatar(theme, context, avatarPath),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _editNickname(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListenableBuilder(
                            listenable: AuthService.instance,
                            builder: (context, _) {
                              final isDonator = AuthService.instance.isDonator;
                              return Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      nickname,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (isDonator) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFF9800),
                                            Color(0xFFE91E63),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'donator',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '点击修改昵称',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 20, color: Colors.grey),
              ],
            ),
          ),
          const Divider(height: 1),
          // 账号与云同步区域
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (context, _) {
              final auth = AuthService.instance;
              if (!auth.isLoggedIn) {
                return ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('登录 / 注册'),
                  subtitle: const Text('登录后把整机方案同步到云端'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountPage()),
                  ),
                );
              }
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: const Text('账号已登录'),
                    subtitle: Text(auth.username ?? ''),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('退出登录'),
                    onTap: () => AuthService.instance.signOut(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 把本地头像图片上传到云存储并存入账号资料
  Future<void> _uploadAvatar(BuildContext context) async {
    final path = ThemeController.instance.avatarPath;
    if (path == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有头像，先点头像从相册选一张')));
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final ext = path.contains('.') ? path.split('.').last : 'jpg';
      await CloudSync.uploadAvatar(bytes, ext);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('头像已上传到云')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// 头像：有自定义图片则显示图片，否则显示默认人形图标；点击更换，右下角相机小标提示
  Widget _avatar(ThemeData theme, BuildContext context, String? path) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _pickAvatar(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: path == null ? null : FileImage(File(path)),
            child: path == null
                ? Icon(
                    LucideIcons.user_round,
                    size: 30,
                    color: theme.colorScheme.onPrimaryContainer,
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backgroundCard(ThemeData theme, BuildContext context) {
    final c = ThemeController.instance;
    final path = c.backgroundPath;
    final hasBg = path != null;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.image),
            title: Text(hasBg ? '更换背景图片' : '上传背景图片'),
            subtitle: Text(hasBg ? '已设置背景，点此更换' : '从手机相册选一张图片'),
            onTap: () => _pickBackground(context),
          ),
          if (hasBg)
            ListTile(
              leading: const Icon(LucideIcons.image_off),
              title: const Text('移除背景'),
              onTap: () => ThemeController.instance.clearBackground(),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on),
            title: const Text('背景模糊'),
            subtitle: const Text('让背景变柔、文字更清晰'),
            value: c.backgroundBlur,
            onChanged: hasBg
                ? (v) => ThemeController.instance.setBackgroundBlur(v)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _seedCard(ThemeData theme) {
    final current = ThemeController.instance.seed.toARGB32();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 12,
              children: [
                for (final option in kSeedOptions)
                  _swatch(theme, option, current == option.color.toARGB32()),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ThemeController.instance.setSeed(kDefaultSeed),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('恢复默认主题色'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(ThemeData theme, SeedOption option, bool selected) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => ThemeController.instance.setSeed(option.color),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(height: 4),
          Text(option.name, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _appearanceCard(ThemeData theme) {
    final mode = ThemeController.instance.mode;
    return Card(
      child: Column(
        children: [
          _modeTile(
            theme,
            mode,
            ThemeMode.system,
            Icons.brightness_auto_outlined,
            '跟随系统',
            '跟随手机系统的深浅色设置',
          ),
          _modeTile(
            theme,
            mode,
            ThemeMode.light,
            Icons.light_mode_outlined,
            '浅色',
            '一直使用浅色外观',
          ),
          _modeTile(
            theme,
            mode,
            ThemeMode.dark,
            Icons.dark_mode_outlined,
            '深色',
            '一直使用深色外观',
          ),
        ],
      ),
    );
  }

  Widget _toolsCard(ThemeData theme, BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('导出配置单'),
            subtitle: const Text('把整机方案生成文本，分享到微信 / 备忘录等'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportConfig(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('导入配置单'),
            subtitle: const Text('粘贴「导出配置单」生成的文本，一键还原成方案'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _importConfig(context),
          ),
        ],
      ),
    );
  }

  /// 一键导出配置单：列出所有整机方案，选一个后用系统分享面板分享
  Future<void> _exportConfig(BuildContext context) async {
    final plans = await BuildPlanStore().loadAll();
    if (!context.mounted) return;
    if (plans.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有整机方案，先去「整机方案」页创建一个')));
      return;
    }
    final plan = await showModalBottomSheet<BuildPlan>(
      context: context,
      builder: (_) => _ExportSheet(plans: plans),
    );
    if (plan == null || !context.mounted) return;
    final name = _planName(plan);
    await SharePlus.instance.share(
      ShareParams(text: configText(plan), subject: '$name 配置单'),
    );
  }

  /// 一键导入配置单：读取剪贴板文本（可手动粘贴修改），解析后还原成新方案
  Future<void> _importConfig(BuildContext context) async {
    String initial = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      initial = data?.text ?? '';
    } catch (_) {
      // 剪贴板读取失败就留空，让用户手动粘贴
    }
    if (!context.mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _ImportDialog(initialText: initial),
    );
    if (text == null || !context.mounted) return;
    final parsed = parseConfig(text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没识别到配置单内容，请粘贴「导出配置单」生成的文本')),
      );
      return;
    }
    final store = BuildPlanStore();
    final plans = await store.loadAll();
    // 与已有方案重名时追加序号，避免列表里混淆
    var name = parsed.name;
    var n = 2;
    while (plans.any((p) => p.name == name)) {
      name = '${parsed.name} $n';
      n++;
    }
    final plan = BuildPlan(name: name, components: parsed.components);
    plans.add(plan);
    await store.saveAll(plans);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已导入「$name」')));
  }

  Widget _aboutCard(BuildContext context, ThemeData theme) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            trailing: Text(kAppVersion),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('版本更新日志'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showVersionLog(context),
          ),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pink),
            title: const Text('支持开发'),
            subtitle: const Text('捐赠后可获得 donator 专属标识，AI 分析次数提高到每天 50 次'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDonate(context),
          ),
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (context, _) {
              final isDonator = AuthService.instance.isDonator;
              return ListTile(
                leading: Icon(
                  isDonator
                      ? Icons.workspace_premium
                      : Icons.workspace_premium_outlined,
                  color: isDonator ? Colors.amber : null,
                ),
                title: Text(isDonator ? 'donator 已开通' : '开通 donator'),
                subtitle: Text(
                  isDonator
                      ? '感谢支持，专属标识与 50 次/天已生效'
                      : '捐赠后填订单号，自动开通专属标识与权益',
                ),
                trailing: isDonator
                    ? const Icon(Icons.check_circle, color: Colors.amber)
                    : const Icon(Icons.chevron_right),
                onTap: isDonator ? null : () => _openDonator(context),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('免责声明'),
            subtitle: const Text('性价比分析、数据准确性、云服务与 AI 功能的说明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDisclaimer(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '© $kCredit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDonate(BuildContext context) async {
    final url = kDonateUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('捐赠链接尚未配置')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 开通 donator：填爱发电订单号，云函数查单后自动开通
  Future<void> _openDonator(BuildContext context) async {
    if (!AuthService.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录，再开通 donator')),
      );
      return;
    }
    final orderNo = await showDialog<String>(
      context: context,
      builder: (_) => const _DonatorDialog(),
    );
    if (orderNo == null || !context.mounted) return;
    try {
      await CloudSync.verifyDonation(orderNo);
      await AuthService.instance.refreshDonator();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开通成功，感谢支持！٩(◕‿◕｡)۶')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showVersionLog(BuildContext context) {
    // 不再用弹窗，直接进入一个整页展示，阅读更舒服
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _VersionLogPage()),
    );
  }

  void _openDisclaimer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _DisclaimerPage()),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _modeTile(
    ThemeData theme,
    ThemeMode current,
    ThemeMode value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = current == value;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: () => ThemeController.instance.setMode(value),
    );
  }
}

/// 免责声明整页：说明性价比分析、数据准确性、云服务与 AI 功能的边界
class _DisclaimerPage extends StatelessWidget {
  const _DisclaimerPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('免责声明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '使用本应用前，请阅读以下说明。',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _section(theme, '一、性价比分析', [
            '本应用的性价比排行、AI 分析、可靠性分析、整机功耗估算等结果，均为基于算法与参考数据的估算，仅供参考，不构成任何购买建议或承诺。',
            '请在购买前自行核实产品信息、价格与兼容性，独立做出判断。',
          ]),
          _section(theme, '二、数据准确性', [
            '应用内的硬件型号、价格、跑分、功耗、规格等数据，来自公开资料整理与用户录入，可能存在误差或滞后。',
            '价格会随市场波动，实际以购买平台展示为准；跑分与功耗为参考约值，随平台、驱动、测试环境不同会有差异。',
            '应用不保证数据绝对准确、完整或实时，因数据偏差造成的任何损失，应用方不承担责任。',
          ]),
          _section(theme, '三、云服务与 AI 功能', [
            '账号云同步、AI 分析、donator 权益等功能，依赖云服务器与第三方服务（如 DeepSeek、爱发电等）。',
            '受项目资金、维护成本、第三方政策等因素影响，上述功能可能随时调整、限流或停用，不构成持续提供的承诺。',
            '若相关功能停用，本地已保存的数据（整机方案、硬件清单等）不会丢失，核心的本地功能仍可正常使用。',
          ]),
          _section(theme, '四、其他', [
            '本应用为独立开发者项目，若因使用本应用产生任何直接或间接损失，应用方不承担法律责任。',
            '最终解释权归开发者所有。',
          ]),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<String> paragraphs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              p,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 版本更新日志整页：按版本分组展示，最新在前
class _VersionLogPage extends StatelessWidget {
  const _VersionLogPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('版本更新日志')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in kVersionLog) ...[
            Text(
              entry.version,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in entry.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· '),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

/// 修改昵称的对话框，返回非空昵称
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改昵称'),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(labelText: '昵称'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 开通 donator 的对话框：填爱发电订单号
class _DonatorDialog extends StatefulWidget {
  const _DonatorDialog();

  @override
  State<_DonatorDialog> createState() => _DonatorDialogState();
}

class _DonatorDialogState extends State<_DonatorDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('开通 donator'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('捐赠后，在爱发电的订单记录里找到订单号，填到下面即可自动开通。'),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '爱发电订单号',
              hintText: '形如 2026xxxxx...',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
          child: const Text('开通'),
        ),
      ],
    );
  }
}

/// 选择要导出的方案
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.plans});

  final List<BuildPlan> plans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '选择要导出的方案',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final plan in plans)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CategoryBadge(category: '整机方案'),
                      title: Text(_planName(plan)),
                      subtitle: Text(
                        '${plan.filledCount} 件 · ¥${_fmt(plan.total)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, plan),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _planName(BuildPlan plan) => plan.name.isEmpty ? '未命名方案' : plan.name;

String _fmt(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

/// 把单个整机方案排版成纯文本配置单
String configText(BuildPlan plan) {
  final buf = StringBuffer();
  buf.writeln('【DIYHelper 配置单】${_planName(plan)}');
  buf.writeln('──────────────');
  for (final slot in kBuildSlots) {
    if (slot.key == 'storage') {
      for (final c in plan.storages) {
        final brand = c.brand.isEmpty ? '' : ' · ${c.brand}';
        buf.writeln('${slot.label}  ${c.model}$brand  ¥${_fmt(c.price)}');
      }
      continue;
    }
    final c = plan[slot.key];
    if (c == null) continue;
    final brand = c.brand.isEmpty ? '' : ' · ${c.brand}';
    buf.writeln('${slot.label}  ${c.model}$brand  ¥${_fmt(c.price)}');
  }
  buf.writeln('──────────────');
  buf.writeln('总价：¥${_fmt(plan.total)}');
  buf.writeln('—— 来自 DIYHelper ——');
  return buf.toString();
}

/// 解析「导出配置单」生成的文本，还原成整机方案；识别不到任何配件时返回 null
/// 格式与 [configText] 一致：方案名从头部读取，配件行按槽位标签+型号+品牌+价格解析
BuildPlan? parseConfig(String text) {
  final lines = text.split('\n').map((e) => e.trim()).toList();

  String name = '';
  const marker = '【DIYHelper 配置单】';
  for (final l in lines) {
    final i = l.indexOf(marker);
    if (i >= 0) {
      name = l.substring(i + marker.length).trim();
      break;
    }
  }
  if (name.isEmpty) name = '导入的方案';

  final components = <String, PlanComponent>{};
  final storages = <PlanComponent>[];
  for (final slot in kBuildSlots) {
    for (final l in lines) {
      final prefix = '${slot.label} ';
      if (!l.startsWith(prefix)) continue;
      final rest = l.substring(prefix.length).trim();
      if (rest.isEmpty) break;

      final yen = rest.lastIndexOf('¥');
      var modelBrand = rest;
      var price = 0.0;
      if (yen >= 0) {
        price = double.tryParse(rest.substring(yen + 1).trim()) ?? 0;
        modelBrand = rest.substring(0, yen).trim();
      }
      final parts = modelBrand.split('·');
      final model = parts.first.trim();
      final brand = parts.length > 1 ? parts[1].trim() : '';
      if (model.isEmpty) break;

      final comp = PlanComponent(
        category: slot.category,
        brand: brand,
        model: model,
        price: price,
        platform: '',
      );
      if (slot.key == 'storage') {
        storages.add(comp);
      } else {
        components[slot.key] = comp;
      }
      break;
    }
  }

  if (components.isEmpty && storages.isEmpty) return null;
  return BuildPlan(name: name, components: components, storages: storages);
}

/// 粘贴配置单文本的对话框；打开时自动填充剪贴板内容
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initialText});

  final String initialText;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入配置单'),
      content: TextField(
        controller: _c,
        minLines: 6,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: '配置单文本',
          hintText: '自动读取剪贴板，也可长按粘贴',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style: capsuleButtonStyle(Theme.of(context), fullWidth: false),
          child: const Text('导入'),
        ),
      ],
    );
  }
}
