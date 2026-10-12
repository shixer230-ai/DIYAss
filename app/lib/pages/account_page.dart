import 'package:flutter/material.dart';

import '../cloud/auth_service.dart';
import '../theme/app_theme.dart';

/// 账号页：密码登录 / 邮箱验证码登录 / 注册 三种方式
/// 密码登录：用户名/邮箱 + 密码
/// 验证码登录：邮箱 + 验证码（没注册会自动注册并登录，防恶意刷号）
/// 注册：邮箱 + 用户名 + 密码 + 验证码
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  // 0 密码登录，1 验证码登录，2 注册
  static const _kPassword = 0;
  static const _kCode = 1;
  static const _kRegister = 2;

  final _formKey = GlobalKey<FormState>();
  final _accountCtrl = TextEditingController(); // 密码登录：用户名 / 邮箱
  final _emailCtrl = TextEditingController(); // 验证码登录 / 注册：邮箱
  final _usernameCtrl = TextEditingController(); // 注册：用户名
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController(); // 验证码登录 / 注册：验证码

  int _mode = _kPassword;
  bool _busy = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      switch (_mode) {
        case _kCode:
          if (!_codeSent) {
            // 第一步：发验证码到邮箱
            await AuthService.instance.sendLoginCode(_emailCtrl.text.trim());
            setState(() => _codeSent = true);
            _snack('验证码已发送到邮箱，请查收');
          } else {
            // 第二步：填验证码登录
            await AuthService.instance.confirmLoginCode(_codeCtrl.text.trim());
            if (mounted) Navigator.pop(context);
          }
          break;
        case _kRegister:
          if (!_codeSent) {
            // 第一步：发验证码到邮箱
            await AuthService.instance.sendSignUpCode(
              email: _emailCtrl.text.trim(),
              password: _passwordCtrl.text.trim(),
              username: _usernameCtrl.text.trim(),
            );
            setState(() => _codeSent = true);
            _snack('验证码已发送到邮箱，请查收');
          } else {
            // 第二步：填验证码完成注册
            await AuthService.instance.confirmSignUp(_codeCtrl.text.trim());
            if (mounted) Navigator.pop(context);
          }
          break;
        default:
          await AuthService.instance.signIn(
            account: _accountCtrl.text.trim(),
            password: _passwordCtrl.text.trim(),
          );
          if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode(int mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _codeSent = false;
      _codeCtrl.clear();
    });
  }

  String? _validateEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return '请输入邮箱';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    return ok ? null : '邮箱格式不对';
  }

  String? _validateUsername(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return '请输入用户名';
    // 与云端规则一致：小写字母开头，6~25 位，仅限小写字母/数字/下划线/连字符
    return RegExp(r'^[a-z][0-9a-z_-]{5,24}$').hasMatch(t)
        ? null
        : '小写字母开头，6~25 位，仅限小写字母/数字/下划线/连字符';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _modeSelector(theme),
            const SizedBox(height: 16),
            Text(
              _hint,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_mode == _kRegister) ...[
              _field(_emailCtrl, '邮箱 *', '用于收验证码，例如 you@example.com',
                  validator: _validateEmail),
              const SizedBox(height: 12),
              _field(_usernameCtrl, '用户名 *', '小写字母开头，6~25位，可用字母/数字/_/-',
                  validator: _validateUsername),
            ] else if (_mode == _kCode) ...[
              _field(_emailCtrl, '邮箱 *', '用于收验证码，例如 you@example.com',
                  validator: _validateEmail),
            ] else ...[
              _field(_accountCtrl, '用户名 / 邮箱 *', '',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入用户名或邮箱' : null),
            ],
            if (_mode != _kCode) ...[
              const SizedBox(height: 12),
              _field(_passwordCtrl, '密码 *', '至少 6 位',
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? '密码至少 6 位' : null),
            ],
            if ((_mode == _kRegister || _mode == _kCode) && _codeSent) ...[
              const SizedBox(height: 12),
              _field(_codeCtrl, '邮箱验证码 *', '6 位数字',
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入验证码' : null),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: capsuleButtonStyle(theme),
              child: Text(
                _busy
                    ? '处理中…'
                    : _mode == _kPassword
                        ? '登录'
                        : _codeSent
                            ? (_mode == _kCode ? '登录' : '注册')
                            : '发送验证码',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _hint {
    switch (_mode) {
      case _kCode:
        return '输入邮箱收验证码即可登录，没注册过的邮箱会自动注册';
      case _kRegister:
        return '注册后即可把整机方案同步到云端';
      default:
        return '登录后同步你的方案与账号资料';
    }
  }

  Widget _modeSelector(ThemeData theme) {
    final items = const [
      ('密码登录', _kPassword),
      ('验证码登录', _kCode),
      ('注册', _kRegister),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _modeChip(theme, items[i].$2, items[i].$1),
          ),
        ],
      ],
    );
  }

  Widget _modeChip(ThemeData theme, int mode, String label) {
    final active = _mode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _busy ? null : () => _switchMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validator,
    );
  }
}
