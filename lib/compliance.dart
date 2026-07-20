part of 'main.dart';

enum LegalDocumentType { terms, privacy }

class ComplianceService {
  ComplianceService._();

  static final instance = ComplianceService._();
  static const _acceptedVersionKey = 'uniprism.privacyAcceptedVersion';

  String? _acceptedVersion;

  bool get hasAcceptedCurrentVersion =>
      _acceptedVersion == AppConfig.privacyVersion;

  Future<void> restore() async {
    final stored = await AuthService._readStorage();
    _acceptedVersion = stored[_acceptedVersionKey]?.toString();
  }

  Future<void> acceptCurrentVersion() async {
    _acceptedVersion = AppConfig.privacyVersion;
    await AuthService._writeStorage({
      _acceptedVersionKey: AppConfig.privacyVersion,
    });
  }
}

class ComplianceGate extends StatefulWidget {
  const ComplianceGate({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<ComplianceGate> createState() => _ComplianceGateState();
}

class _ComplianceGateState extends State<ComplianceGate> {
  bool _accepted = ComplianceService.instance.hasAcceptedCurrentVersion;

  Future<void> _accept() async {
    await ComplianceService.instance.acceptCurrentVersion();
    if (mounted) setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) return MainShell(initialIndex: widget.initialIndex);
    return PrivacyConsentPage(onAccept: _accept);
  }
}

class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key, required this.onAccept});

  final Future<void> Function() onAccept;

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool _accepting = false;
  bool _declined = false;

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _declined = false;
    });
    await widget.onAccept();
    if (mounted) setState(() => _accepting = false);
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = AppLayout.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FC),
      body: SafeArea(
        child: AppConstrainedContent(
          maxWidth: AppLayout.dialogContentMaxWidth,
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Color(0xFFECE2FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.privacy_tip_rounded,
                    size: 36,
                    color: Color(0xFF6B23FF),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '隐私保护说明',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                const Text(
                  '在使用万有棱镜前，请阅读并了解用户服务条款和隐私政策。我们会按照页面说明处理登录信息、测评答案和报告数据，并在需要系统权限时单独向你说明。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF66616D),
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/terms'),
                      child: const Text('《用户服务条款》'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/privacy'),
                      child: const Text('《隐私政策》'),
                    ),
                  ],
                ),
                if (_declined)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '不同意将无法进入 App，你仍可继续查看条款和隐私政策。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFC62828), fontSize: 13),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _accepting ? null : _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6B23FF),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_accepting ? '正在保存...' : '同意并继续'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton(
                    onPressed: () => setState(() => _declined = true),
                    child: const Text('暂不同意'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final privacy = type == LegalDocumentType.privacy;
    final sections = privacy ? _privacySections : _termsSections;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FA),
      appBar: AppBar(
        title: Text(privacy ? '隐私政策' : '用户服务条款'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F7FA),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppLayout.pagePadding(context),
            12,
            AppLayout.pagePadding(context),
            32,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '当前为开发接入稿。正式上线前必须由运营主体或法务补齐主体名称、联系方式、数据保存期限和第三方 SDK 信息，并发布同内容的 HTTPS 页面。',
                style: TextStyle(
                  color: Color(0xFF7A5713),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '生效日期：${AppConfig.privacyVersion}\n运营主体：${AppConfig.displayOrPending(AppConfig.companyName)}',
              style: const TextStyle(
                color: Color(0xFF77727D),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            for (final section in sections) ...[
              const SizedBox(height: 22),
              Text(
                section.$1,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section.$2,
                style: const TextStyle(
                  color: Color(0xFF514D56),
                  fontSize: 14,
                  height: 1.75,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _privacySections = <(String, String)>[
  (
    '1. 我们收集的信息',
    '登录时可能处理手机号和验证码；使用专业探索功能时会处理用户主动提交的基础资料、测评答案、探索进度和报告结果。最终数据字段以正式个人信息清单为准。',
  ),
  ('2. 系统权限', '网络权限用于访问服务端；通知权限仅在需要接收报告或活动提醒时申请。拒绝非必要权限不应影响基础浏览和测评功能。'),
  ('3. 信息的使用和保存', '信息仅用于登录、保存探索进度、生成报告、保障安全和提供客服。保存地点、期限和删除规则须在上线前由运营主体确认。'),
  ('4. 第三方 SDK', '正式版使用的统计、推送、支付或其他第三方 SDK，必须在上线前逐项列明名称、提供方、用途、收集信息和隐私政策链接。'),
  ('5. 用户权利', '用户可以查询、更正、删除个人信息，撤回非必要授权或申请注销账号。具体处理时限和联系渠道以上线后的正式政策为准。'),
  ('6. 未成年人保护', '如产品面向未成年人，应补充监护人同意、信息最小化、付费限制和投诉处理规则，并在正式上线前完成专项评估。'),
  ('7. 联系我们', '客服电话、邮箱和联系地址请在“帮助与反馈”页面查看；当前信息尚待运营主体确认。'),
];

const _termsSections = <(String, String)>[
  ('1. 服务说明', '万有棱镜提供专业方向探索、测评进度和报告展示等功能。测评结果仅作为个人探索参考，不构成录取、就业、医疗或心理诊断承诺。'),
  ('2. 账号使用', '用户应使用本人合法持有的手机号注册和登录，并妥善保管验证码及账号信息，不得利用账号从事违法或侵害他人权益的活动。'),
  ('3. 用户内容和行为', '用户提交的内容应真实、合法，不得上传违法、有害或侵犯第三方权利的信息。平台可依法处理违规内容和异常账号。'),
  ('4. 付费服务', '如后续提供付费报告、会员或课程，应在购买前明确价格、内容、有效期、退款和发票规则。当前具体收费规则待产品确认。'),
  ('5. 服务变更与责任', '平台可能因维护、升级或不可抗力调整服务，并将尽力提前通知。正式责任范围和争议解决条款须由运营主体或法务确认。'),
  ('6. 联系方式', '运营主体、客服联系方式、注册地址和争议解决方式将在正式上线版本中补齐。'),
];

class HelpAndFeedbackPage extends StatelessWidget {
  const HelpAndFeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final contacts = [
      ('客服电话', AppConfig.displayOrPending(AppConfig.supportPhone)),
      ('客服邮箱', AppConfig.displayOrPending(AppConfig.supportEmail)),
      ('联系地址', AppConfig.displayOrPending(AppConfig.supportAddress)),
    ];
    return _SettingsPage(
      title: '帮助与反馈',
      children: [
        const _SettingsNotice(text: '正式上线前请配置真实可用的客服电话、邮箱和联系地址。'),
        for (final contact in contacts)
          ListTile(
            title: Text(contact.$1),
            subtitle: Text(contact.$2),
            trailing: contact.$2 == '待主体确认'
                ? null
                : IconButton(
                    tooltip: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: contact.$2));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已复制${contact.$1}')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
          ),
      ],
    );
  }
}

class AboutAndFilingPage extends StatelessWidget {
  const AboutAndFilingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _SettingsPage(
      title: '关于万有棱镜',
      children: [
        const SizedBox(height: 8),
        const Icon(
          Icons.change_history_rounded,
          color: Color(0xFF6B23FF),
          size: 58,
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            '万有棱镜',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 22),
        ListTile(title: const Text('版本'), trailing: Text(AppConfig.appVersion)),
        ListTile(
          title: const Text('运营主体'),
          subtitle: Text(AppConfig.displayOrPending(AppConfig.companyName)),
        ),
        ListTile(
          title: const Text('APP 备案号'),
          subtitle: Text(AppConfig.displayOrPending(AppConfig.appFilingNumber)),
        ),
      ],
    );
  }
}

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _showDeletionStatus() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销账号'),
        content: const Text(
          '客户端入口已经预留，但服务端注销、身份校验和数据删除接口尚未接入。正式上线前必须完成真实注销流程，当前不会执行假注销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.instance.isLoggedIn;
    return _SettingsPage(
      title: '账号与安全',
      children: [
        ListTile(
          title: const Text('登录状态'),
          trailing: Text(loggedIn ? '已登录' : '未登录'),
        ),
        ListTile(
          enabled: loggedIn,
          title: const Text('退出登录'),
          onTap: loggedIn ? _logout : null,
        ),
        ListTile(
          enabled: loggedIn,
          title: const Text('注销账号', style: TextStyle(color: Color(0xFFC62828))),
          subtitle: const Text('永久删除账号前需要再次验证身份'),
          onTap: loggedIn ? _showDeletionStatus : null,
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F6FA),
    appBar: AppBar(
      title: Text(title),
      centerTitle: true,
      backgroundColor: const Color(0xFFF7F6FA),
      surfaceTintColor: Colors.transparent,
    ),
    body: AppConstrainedContent(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppLayout.pagePadding(context),
          12,
          AppLayout.pagePadding(context),
          30,
        ),
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    ),
  );
}

class _SettingsNotice extends StatelessWidget {
  const _SettingsNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF7A5713),
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );
}
