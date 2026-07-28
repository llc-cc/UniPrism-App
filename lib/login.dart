part of 'main.dart';

enum _AppLoginMethod { sms, password }

Future<bool> openAppLogin(BuildContext context) async {
  final result = await Navigator.of(context).pushNamed('/login');
  return result == true;
}

/// Returns true when the current operation may continue with an authenticated
/// user. Callers keep their own route and state instead of being redirected to
/// a new home page after login.
Future<bool> ensureUserLoggedIn(BuildContext context) async {
  if (AuthService.instance.isLoggedIn) return true;
  return openAppLogin(context);
}

class AppLoginPage extends StatefulWidget {
  const AppLoginPage({super.key});

  @override
  State<AppLoginPage> createState() => _AppLoginPageState();
}

class _AppLoginPageState extends State<AppLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  _AppLoginMethod _method = _AppLoginMethod.sms;
  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _agreed = false;
  bool _sendingCode = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String _error = '';
  String _devCodeHint = '';

  String get _phone => _phoneController.text.trim();
  String get _code => _codeController.text.trim();
  String get _account => _accountController.text.trim();
  String get _password => _passwordController.text;
  bool get _validPhone => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone);
  bool get _validCode => RegExp(r'^\d{6}$').hasMatch(_code);
  bool get _canSubmit => switch (_method) {
    _AppLoginMethod.sms => _validPhone && _validCode,
    _AppLoginMethod.password => _account.length >= 3 && _password.length >= 6,
  };

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _phoneController,
      _codeController,
      _accountController,
      _passwordController,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final controller in [
      _phoneController,
      _codeController,
      _accountController,
      _passwordController,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _selectMethod(_AppLoginMethod method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _error = '';
      if (method == _AppLoginMethod.password && _account.isEmpty) {
        _accountController.text = _phone;
      }
    });
  }

  bool _ensureAgreement() {
    if (_agreed) return true;
    setState(() => _error = '请先阅读并同意用户服务条款和隐私政策');
    return false;
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_ensureAgreement()) return;
    if (!_validPhone) {
      setState(() => _error = '请输入有效的中国大陆手机号');
      return;
    }
    if (_sendingCode || _cooldown > 0) return;
    setState(() {
      _sendingCode = true;
      _error = '';
      _devCodeHint = '';
    });
    try {
      String? devCode;
      if (AppConfig.showDevelopmentSmsCode) {
        devCode = await AuthService.instance.sendSmsCodeWithDevCode(_phone);
      } else {
        await AuthService.instance.sendSmsCode(_phone);
      }
      if (!mounted) return;
      if ((devCode ?? '').isNotEmpty) {
        _codeController.text = devCode!;
        _devCodeHint = '开发验证码：$devCode';
      }
      _startCooldown();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送')));
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_ensureAgreement() || !_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      switch (_method) {
        case _AppLoginMethod.sms:
          await AuthService.instance.loginWithPhone(_phone, _code);
        case _AppLoginMethod.password:
          await AuthService.instance.loginWithPassword(_account, _password);
      }
      if (mounted) _finishLogin();
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _finishLogin() {
    TextInput.finishAutofillContext();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    } else {
      navigator.pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  Future<void> _showSmsHelp() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '收不到验证码？',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const Text(
                '1. 检查手机号、网络和短信拦截记录。\n'
                '2. 等待倒计时结束后重新发送。\n'
                '3. 频繁请求可能触发安全限制，请稍后再试。\n'
                '4. 手机号已停用时，需要通过账号找回流程更换手机号。',
                style: TextStyle(fontSize: 14, height: 1.75),
              ),
              const SizedBox(height: 18),
              if (AppConfig.passwordLoginEnabled)
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _selectMethod(_AppLoginMethod.password);
                  },
                  child: const Text('使用账号密码登录'),
                ),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountRecoveryHelpPage(),
                    ),
                  );
                },
                child: const Text('手机号已停用或需要找回账号'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = AppLayout.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FB),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(false),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AppConstrainedContent(
          maxWidth: AppLayout.dialogContentMaxWidth,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppLayout.isShortHeight(context) ? 8 : 20,
                horizontal,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 44),
                ),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          Icons.change_history_rounded,
                          size: 48,
                          color: Color(0xFF6B23FF),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _method == _AppLoginMethod.sms ? '手机号登录' : '账号密码登录',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '登录后同步测评进度与报告',
                        style: TextStyle(
                          color: Color(0xFF77717D),
                          fontSize: 14,
                        ),
                      ),
                      if (AppConfig.passwordLoginEnabled) ...[
                        const SizedBox(height: 24),
                        SegmentedButton<_AppLoginMethod>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: _AppLoginMethod.sms,
                              label: Text('验证码登录'),
                            ),
                            ButtonSegment(
                              value: _AppLoginMethod.password,
                              label: Text('密码登录'),
                            ),
                          ],
                          selected: {_method},
                          onSelectionChanged: (values) =>
                              _selectMethod(values.first),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_method == _AppLoginMethod.sms)
                        _buildSmsFields()
                      else
                        _buildPasswordFields(),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error,
                          style: const TextStyle(
                            color: Color(0xFFC62828),
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _canSubmit && !_submitting
                              ? _submit
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6B23FF),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD8CCF7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(_submitting ? '登录中...' : '登录并继续'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildAgreement(),
                      const SizedBox(height: 18),
                      if (!AppConfig.passwordLoginEnabled &&
                          AppConfig.developerToolsEnabled)
                        const Text(
                          '密码登录客户端已准备，等待服务端接口后再对用户开放。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8A8490),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmsFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.telephoneNumber],
        maxLength: 11,
        decoration: _inputDecoration('请输入手机号').copyWith(prefixText: '+86  '),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        onSubmitted: (_) => _submit(),
        decoration: _inputDecoration('6 位验证码').copyWith(
          suffixIcon: TextButton(
            onPressed: _sendingCode || _cooldown > 0 || !_validPhone
                ? null
                : _sendCode,
            child: Text(
              _cooldown > 0
                  ? '${_cooldown}s'
                  : (_sendingCode ? '发送中' : '获取验证码'),
            ),
          ),
        ),
      ),
      if (_devCodeHint.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _devCodeHint,
          style: const TextStyle(color: Color(0xFF6B23FF), fontSize: 12),
        ),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _showSmsHelp,
          child: const Text('收不到验证码？'),
        ),
      ),
    ],
  );

  Widget _buildPasswordFields() => Column(
    children: [
      TextField(
        controller: _accountController,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
        decoration: _inputDecoration('手机号或账号'),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _submit(),
        decoration: _inputDecoration('密码').copyWith(
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AccountRecoveryHelpPage(),
            ),
          ),
          child: const Text('忘记密码或手机号已停用？'),
        ),
      ),
    ],
  );

  Widget _buildAgreement() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: _agreed,
          activeColor: const Color(0xFF6B23FF),
          onChanged: (value) => setState(() {
            _agreed = value ?? false;
            if (_agreed) _error = '';
          }),
        ),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '我已阅读并同意',
              style: TextStyle(color: Color(0xFF77717D), fontSize: 12),
            ),
            _legalLink('《用户服务条款》', '/terms'),
            const Text(
              '和',
              style: TextStyle(color: Color(0xFF77717D), fontSize: 12),
            ),
            _legalLink('《隐私政策》', '/privacy'),
          ],
        ),
      ),
    ],
  );

  Widget _legalLink(String label, String route) => InkWell(
    onTap: () => Navigator.of(context).pushNamed(route),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF6B23FF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    counterText: '',
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE4E0E8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE4E0E8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF6B23FF), width: 1.5),
    ),
  );
}

class AccountRecoveryHelpPage extends StatelessWidget {
  const AccountRecoveryHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = AppConfig.displayOrPending(AppConfig.supportPhone);
    final email = AppConfig.displayOrPending(AppConfig.supportEmail);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: const Text('账号找回'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F7FB),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppLayout.pagePadding(context),
            16,
            AppLayout.pagePadding(context),
            28,
          ),
          children: [
            const Text(
              '以下情况需要账号找回',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            const Text(
              '• 原手机号已经停用或无法补办\n'
              '• 忘记密码且无法接收短信\n'
              '• 微信账号与原手机号绑定关系异常',
              style: TextStyle(fontSize: 14, height: 1.8),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '为了避免他人冒领账号，更换手机号不能仅凭新手机号验证码完成。正式流程需要后端生成工单，并由客服按照主体确认的身份核验规则处理。',
                style: TextStyle(
                  color: Color(0xFF5E5863),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('客服电话'),
              subtitle: Text(phone),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('客服邮箱'),
              subtitle: Text(email),
            ),
          ],
        ),
      ),
    );
  }
}
