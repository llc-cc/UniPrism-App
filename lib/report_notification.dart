part of 'main.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ReportTaskSnapshot {
  const ReportTaskSnapshot({
    required this.status,
    this.reportId,
    this.scheduledAt,
    this.triggerAt,
    this.completedAt,
  });

  factory ReportTaskSnapshot.fromMap(Map<Object?, Object?> values) {
    DateTime? readTime(String key) {
      final raw = values[key];
      if (raw is! num || raw <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }

    return ReportTaskSnapshot(
      status: values['status']?.toString() ?? 'idle',
      reportId: values['reportId']?.toString(),
      scheduledAt: readTime('scheduledAt'),
      triggerAt: readTime('triggerAt'),
      completedAt: readTime('completedAt'),
    );
  }

  static const idle = ReportTaskSnapshot(status: 'idle');

  final String status;
  final String? reportId;
  final DateTime? scheduledAt;
  final DateTime? triggerAt;
  final DateTime? completedAt;

  bool get isGenerating => status == 'generating';
  bool get isCompleted => status == 'completed';
}

class ReportNotificationService {
  ReportNotificationService._();

  static final instance = ReportNotificationService._();
  static const _channel = MethodChannel('uniprism/report_notifications');

  Map<String, dynamic>? _pendingPayload;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationTapped') return;
      final payload = _asStringMap(call.arguments);
      if (payload != null) await _handleNotificationPayload(payload);
    });
    try {
      final payload = await _channel.invokeMapMethod<Object?, Object?>(
        'consumeLaunchPayload',
      );
      _pendingPayload = _asStringMap(payload);
    } on MissingPluginException {
      // Widget tests and non-Android platforms do not install this channel.
    } on PlatformException {
      // A failed launch-payload read must never prevent the app from starting.
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<ReportTaskSnapshot> scheduleDemoReport({
    required String reportId,
    int delaySeconds = 20,
  }) async {
    final values = await _channel
        .invokeMapMethod<Object?, Object?>('scheduleReportReady', {
          'reportId': reportId,
          'delaySeconds': delaySeconds,
          'title': '你的测评报告已生成',
          'body': '完整报告和专业推荐已经准备好，点击立即查看',
        });
    return ReportTaskSnapshot.fromMap(values ?? const {});
  }

  Future<ReportTaskSnapshot> readTaskState() async {
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'readTaskState',
      );
      return ReportTaskSnapshot.fromMap(values ?? const {});
    } on MissingPluginException {
      return ReportTaskSnapshot.idle;
    } on PlatformException {
      return ReportTaskSnapshot.idle;
    }
  }

  Future<void> scheduleDemoMessage({required String source}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isPush = source == 'push_demo';
    await _channel
        .invokeMapMethod<Object?, Object?>('scheduleMessageNotification', {
          'messageId': '${isPush ? 'push' : 'local'}-$now',
          'source': source,
          'title': isPush ? '模拟服务器推送' : '本地学习提醒',
          'body': isPush
              ? '这条消息模拟服务器报告或活动通知，点击可进入 App 消息中心。'
              : '记得继续完成你的专业方向探索，点击查看消息详情。',
          'route': '/messages',
          'delaySeconds': 10,
        });
  }

  Future<void> ingestRemotePushPayload(Map<String, dynamic> payload) async {
    // A future Getui/JPush adapter forwards messages received while the app is
    // running here. Persistence remains provider-independent.
    await AppMessageCenter.instance.ingestRemotePayload(payload);
  }

  Future<void> handleRemotePushTap(Map<String, dynamic> payload) async {
    // The adapter forwards notification-click payloads here so every provider
    // shares the same read-state and page-routing behavior.
    await _handleNotificationPayload(payload);
  }

  void handlePendingLaunch() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    if (payload != null) unawaited(_handleNotificationPayload(payload));
  }

  Future<void> _handleNotificationPayload(Map<String, dynamic> payload) async {
    await AppMessageCenter.instance.restore();
    final messageId = payload['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      await AppMessageCenter.instance.markRead(messageId);
    }
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      _pendingPayload = payload;
      return;
    }
    final reportId = payload['reportId']?.toString();
    if (payload['type'] == 'report_ready' &&
        reportId != null &&
        reportId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultPage(reportId: reportId),
          settings: const RouteSettings(name: '/report-result'),
        ),
      );
      return;
    }
    navigator.pushNamed('/messages');
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', item));
  }
}

class ReportGenerationDemoPage extends StatefulWidget {
  const ReportGenerationDemoPage({super.key});

  @override
  State<ReportGenerationDemoPage> createState() =>
      _ReportGenerationDemoPageState();
}

class _ReportGenerationDemoPageState extends State<ReportGenerationDemoPage>
    with WidgetsBindingObserver {
  ReportTaskSnapshot _snapshot = ReportTaskSnapshot.idle;
  Timer? _poller;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_snapshot.isGenerating) unawaited(_refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = await ReportNotificationService.instance.readTaskState();
    if (next.isCompleted && !_snapshot.isCompleted) {
      await AppMessageCenter.instance.restore();
    }
    if (mounted) setState(() => _snapshot = next);
  }

  Future<void> _startDemo() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final permissionGranted = await ReportNotificationService.instance
          .requestPermission();
      final reportId = 'demo-${DateTime.now().millisecondsSinceEpoch}';
      final next = await ReportNotificationService.instance.scheduleDemoReport(
        reportId: reportId,
      );
      if (!mounted) return;
      setState(() => _snapshot = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            permissionGranted
                ? '模拟任务已提交，约 20 秒后发送系统通知'
                : '任务已提交，但通知权限未开启；返回本页仍可查看结果',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? '无法创建报告通知任务')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        title: const Text('报告生成通知'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F5FF),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: AppConstrainedContent(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppLayout.pagePadding(context),
              12,
              AppLayout.pagePadding(context),
              24,
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: _snapshot.isGenerating
                          ? _GeneratingReportCard(
                              key: const ValueKey('generating'),
                              snapshot: _snapshot,
                            )
                          : _snapshot.isCompleted
                          ? _CompletedReportCard(
                              key: const ValueKey('completed'),
                              snapshot: _snapshot,
                            )
                          : const _ReportNotificationIntro(
                              key: ValueKey('idle'),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_snapshot.isGenerating) ...[
                  _PurpleActionButton(
                    label: '返回主页，等待通知',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '也可以将 App 切到后台；请不要在系统设置中强行停止 App',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF80798D)),
                  ),
                ] else if (_snapshot.isCompleted) ...[
                  _PurpleActionButton(
                    label: '查看模拟报告',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportResultPage(
                          reportId: _snapshot.reportId ?? 'demo-report',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _starting ? null : _startDemo,
                    child: const Text('重新测试通知'),
                  ),
                ] else
                  _PurpleActionButton(
                    label: _starting ? '正在创建任务…' : '开始模拟生成报告',
                    onPressed: _starting ? null : _startDemo,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportNotificationIntro extends StatelessWidget {
  const _ReportNotificationIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: Color(0xFFEBDDFF),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            size: 42,
            color: Color(0xFF6B23FF),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '报告完成后及时告诉你',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          '正式报告可能需要 2–5 分钟。提交后无需停留在当前页面，生成完成时会通过系统通知提醒。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.65,
            color: Color(0xFF6F687A),
          ),
        ),
        const SizedBox(height: 28),
        const _ReportFeatureRow(
          icon: Icons.exit_to_app_rounded,
          title: '可以离开 App',
          subtitle: '报告任务由后台继续处理',
        ),
        const _ReportFeatureRow(
          icon: Icons.notifications_none_rounded,
          title: '完成后发送通知',
          subtitle: '点击通知直接打开报告结果',
        ),
        const _ReportFeatureRow(
          icon: Icons.sync_rounded,
          title: '自动恢复状态',
          subtitle: '重新进入 App 也能看到最新进度',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4D7FF)),
          ),
          child: const Text(
            '当前为本地模拟：20 秒代表正式环境的 2–5 分钟。后续接入服务器后，页面和交互可以直接复用。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF746B80),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportFeatureRow extends StatelessWidget {
  const _ReportFeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF0E8FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF6B23FF), size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF837B8D),
                    ),
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

class _GeneratingReportCard extends StatelessWidget {
  const _GeneratingReportCard({super.key, required this.snapshot});

  final ReportTaskSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final triggerAt = snapshot.triggerAt;
    final seconds = triggerAt == null
        ? 20
        : math.max(0, triggerAt.difference(DateTime.now()).inSeconds);
    return Column(
      children: [
        const SizedBox(height: 42),
        const SizedBox(
          width: 76,
          height: 76,
          child: CircularProgressIndicator(
            strokeWidth: 7,
            color: Color(0xFF6B23FF),
            backgroundColor: Color(0xFFE4D8F8),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          '正在生成你的报告',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          seconds > 0 ? '模拟任务预计约 $seconds 秒后完成' : '报告即将完成，请稍候',
          style: const TextStyle(fontSize: 14, color: Color(0xFF756E80)),
        ),
        const SizedBox(height: 30),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0E8FF), Color(0xFFF9F6FF)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDCAFF)),
          ),
          child: const Column(
            children: [
              Icon(Icons.cloud_done_outlined, color: Color(0xFF6B23FF)),
              SizedBox(height: 9),
              Text(
                '任务已经提交成功',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 7),
              Text(
                '现在可以返回主页或切换到其他 App。报告完成后，系统通知会提醒你。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: Color(0xFF756E80),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletedReportCard extends StatelessWidget {
  const _CompletedReportCard({super.key, required this.snapshot});

  final ReportTaskSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF8E52FF), Color(0xFF5E18EF)],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 52, color: Colors.white),
        ),
        const SizedBox(height: 25),
        const Text(
          '你的报告已经生成',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          '通知任务已完成，可以查看模拟报告。',
          style: TextStyle(fontSize: 14, color: Color(0xFF756E80)),
        ),
        const SizedBox(height: 26),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4D7FF)),
          ),
          child: const Row(
            children: [
              Icon(Icons.description_outlined, color: Color(0xFF6B23FF)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '专业方向探索报告',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '包含综合画像、推荐方向和行动建议',
                      style: TextStyle(fontSize: 12, color: Color(0xFF81798B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PurpleActionButton extends StatelessWidget {
  const _PurpleActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6B23FF),
          disabledBackgroundColor: const Color(0xFFC5A6F5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
