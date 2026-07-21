part of 'main.dart';

class ReportWorkflowProgress {
  const ReportWorkflowProgress({
    this.title = '正在生成报告',
    this.description = '正在整理你的测评结果，请稍候。',
    this.percent = 0,
  });

  factory ReportWorkflowProgress.fromJson(dynamic value) {
    final json = _reportMap(value);
    final rawPercent = json['percent'];
    final percent = rawPercent is num ? rawPercent.toDouble() : 0.0;
    return ReportWorkflowProgress(
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString()
          : '正在生成报告',
      description: json['description']?.toString().trim().isNotEmpty == true
          ? json['description'].toString()
          : '正在整理你的测评结果，请稍候。',
      percent: percent.clamp(0, 100),
    );
  }

  final String title;
  final String description;
  final double percent;
}

class ReportTaskData {
  const ReportTaskData({
    required this.exists,
    required this.status,
    this.reportId,
    this.queued = false,
    this.errorMessage,
    this.progress = const ReportWorkflowProgress(),
    this.report,
  });

  factory ReportTaskData.fromJson(Map<String, dynamic> json) {
    return ReportTaskData(
      exists:
          json['exists'] != false &&
          (json['reportId']?.toString().isNotEmpty == true ||
              json['status']?.toString().isNotEmpty == true),
      status: json['status']?.toString() ?? 'idle',
      reportId: json['reportId']?.toString(),
      queued: json['queued'] == true,
      errorMessage:
          json['errorMessage']?.toString() ??
          _reportMap(json['error'])['message']?.toString(),
      progress: ReportWorkflowProgress.fromJson(json['workflowProgress']),
      report: json['report'] is Map ? _reportMap(json['report']) : null,
    );
  }

  static const empty = ReportTaskData(exists: false, status: 'idle');

  final bool exists;
  final String status;
  final String? reportId;
  final bool queued;
  final String? errorMessage;
  final ReportWorkflowProgress progress;
  final Map<String, dynamic>? report;

  bool get isRunning => status == 'pending' || status == 'generating';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

extension AuthServiceReportApi on AuthService {
  Future<ReportTaskData> loadLatestReport() async {
    final sessionId = await ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/miniapp/reports/latest?sessionId=${Uri.encodeQueryComponent(sessionId)}&reportType=full_explore',
    );
    return ReportTaskData.fromJson(data);
  }

  Future<ReportTaskData> generateFullReport({bool force = false}) async {
    if (!isLoggedIn) {
      throw const ApiRequestException(
        '请先登录后再生成完整报告',
        statusCode: HttpStatus.unauthorized,
      );
    }
    final sessionId = await bindExploreSessionToCurrentUser();
    final data = await _request(
      'POST',
      '/api/miniapp/reports/generate',
      body: {'sessionId': sessionId, 'force': force},
      timeout: const Duration(minutes: 6),
    );
    return ReportTaskData.fromJson(data);
  }

  Future<ReportTaskData> loadReportStatus(String reportId) async {
    final sessionId = await ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/miniapp/reports/status?sessionId=${Uri.encodeQueryComponent(sessionId)}&reportId=${Uri.encodeQueryComponent(reportId)}',
      timeout: const Duration(seconds: 30),
    );
    return ReportTaskData.fromJson(data);
  }
}

class ReportCenterPage extends StatefulWidget {
  const ReportCenterPage({super.key});

  @override
  State<ReportCenterPage> createState() => _ReportCenterPageState();
}

class _ReportCenterPageState extends State<ReportCenterPage> {
  ReportTaskData _task = ReportTaskData.empty;
  bool _loading = false;
  String? _error;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.isLoggedIn) unawaited(_restoreLatest());
  }

  @override
  void dispose() {
    _operation += 1;
    super.dispose();
  }

  Future<void> _restoreLatest() async {
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var task = await AuthService.instance.loadLatestReport();
      if (!mounted || operation != _operation) return;
      if (task.exists &&
          task.reportId != null &&
          (task.isCompleted || task.isRunning)) {
        task = await AuthService.instance.loadReportStatus(task.reportId!);
      }
      if (!mounted || operation != _operation) return;
      setState(() => _task = task);
      if (task.isRunning) unawaited(_poll(task, operation));
    } on ApiRequestException catch (error) {
      if (mounted && operation == _operation)
        setState(() => _error = error.message);
    } finally {
      if (mounted && operation == _operation) setState(() => _loading = false);
    }
  }

  Future<void> _startGeneration({bool force = false}) async {
    if (!await ensureUserLoggedIn(context) || !mounted) return;
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final task = await AuthService.instance.generateFullReport(force: force);
      if (!mounted || operation != _operation) return;
      setState(() => _task = task);
      if (task.isRunning) {
        unawaited(_poll(task, operation));
      }
    } on ApiRequestException catch (error) {
      if (mounted && operation == _operation)
        setState(() => _error = error.message);
    } finally {
      if (mounted && operation == _operation) setState(() => _loading = false);
    }
  }

  Future<void> _poll(ReportTaskData initial, int operation) async {
    var task = initial;
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (mounted && operation == _operation && task.isRunning) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || operation != _operation) return;
      try {
        task = await AuthService.instance.loadReportStatus(task.reportId!);
        if (!mounted || operation != _operation) return;
        setState(() => _task = task);
      } on ApiRequestException catch (error) {
        if (mounted && operation == _operation)
          setState(() => _error = error.message);
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        if (mounted && operation == _operation) {
          setState(() => _error = '报告仍在后台生成，请稍后重新进入查看。');
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.instance.isLoggedIn;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        title: const Text('我的测评报告'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F5FF),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (loggedIn)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _restoreLatest,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: AppConstrainedContent(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppLayout.pagePadding(context),
            18,
            AppLayout.pagePadding(context),
            30,
          ),
          children: [
            if (!loggedIn)
              _ReportEmptyState(
                icon: Icons.lock_outline_rounded,
                title: '登录后查看完整报告',
                description: '登录会关联你已经完成的测评记录，并允许服务端生成完整报告。',
                actionLabel: '登录并继续',
                onPressed: () async {
                  if (await ensureUserLoggedIn(context) && mounted) {
                    await _restoreLatest();
                  }
                },
              )
            else if (_loading && !_task.exists)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_task.isCompleted && _task.report != null)
              GeneratedReportView(
                report: _task.report!,
                reportId: _task.reportId,
              )
            else if (_task.isRunning)
              _ReportGeneratingState(task: _task)
            else if (_task.isFailed)
              _ReportEmptyState(
                icon: Icons.error_outline_rounded,
                title: '报告生成失败',
                description: _task.errorMessage ?? '服务端未能完成本次报告，请重新生成。',
                actionLabel: '重新生成',
                onPressed: _loading
                    ? null
                    : () => _startGeneration(force: true),
              )
            else
              _ReportEmptyState(
                icon: Icons.auto_awesome_outlined,
                title: '生成你的完整测评报告',
                description: '完成全部测评后，服务端会根据你的画像生成个性化分析和专业建议。',
                actionLabel: '生成报告',
                onPressed: _loading ? null : _startGeneration,
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB3261E), height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReportResultPage extends StatefulWidget {
  const ReportResultPage({
    super.key,
    required this.reportId,
    this.initialReport,
  });

  final String reportId;
  final Map<String, dynamic>? initialReport;

  @override
  State<ReportResultPage> createState() => _ReportResultPageState();
}

class _ReportResultPageState extends State<ReportResultPage> {
  ReportTaskData? _task;
  String? _error;

  bool get _isDemo => widget.reportId.startsWith('demo-');

  @override
  void initState() {
    super.initState();
    if (widget.initialReport != null) {
      _task = ReportTaskData(
        exists: true,
        status: 'completed',
        reportId: widget.reportId,
        report: widget.initialReport,
      );
    } else if (!_isDemo) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      var task = await AuthService.instance.loadReportStatus(widget.reportId);
      if (!mounted) return;
      setState(() => _task = task);
      while (mounted && task.isRunning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        task = await AuthService.instance.loadReportStatus(widget.reportId);
        if (mounted) setState(() => _task = task);
      }
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDemo) return _DemoReportPage(reportId: widget.reportId);
    final task = _task;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        title: const Text('专业方向探索报告'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F5FF),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: task?.report != null
            ? ListView(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.pagePadding(context),
                  12,
                  AppLayout.pagePadding(context),
                  30,
                ),
                children: [
                  GeneratedReportView(
                    report: task!.report!,
                    reportId: widget.reportId,
                  ),
                ],
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: _error != null
                      ? _ReportEmptyState(
                          icon: Icons.error_outline,
                          title: '无法读取报告',
                          description: _error!,
                          actionLabel: '重试',
                          onPressed: _load,
                        )
                      : task?.isFailed == true
                      ? _ReportEmptyState(
                          icon: Icons.error_outline,
                          title: '报告生成失败',
                          description: task?.errorMessage ?? '请返回报告中心重新生成。',
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
      ),
    );
  }
}

class GeneratedReportView extends StatelessWidget {
  const GeneratedReportView({super.key, required this.report, this.reportId});

  final Map<String, dynamic> report;
  final String? reportId;

  @override
  Widget build(BuildContext context) {
    final analysis = _reportMap(report['personalityAndCareerAnalysis']);
    final holland = _reportMap(analysis['hollandType']);
    final tendency = _reportMap(analysis['careerTendencyAnalysis']);
    final personality = _reportMap(analysis['personalityTestResult']);
    final persona = _reportMap(analysis['integratedPersona']);
    final majorBlock = _reportMap(report['majorRecommendations']);
    final majors = _reportList(majorBlock['majors']);
    final careerBlock = _reportMap(report['careerRecommendations']);
    final careers = _reportList(careerBlock['careers']);
    final advice = _reportMap(report['comprehensiveAdvice']);
    final heroTitle = _firstReportText([
      holland['title'],
      persona['title'],
      analysis['title'],
      '你的探索画像',
    ]);
    final heroBody = _firstReportText([
      holland['reason'],
      persona['body'],
      tendency['body'],
      '报告已生成，可以查看完整分析。',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B23FF), Color(0xFF9B6AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                holland['code']?.toString().isNotEmpty == true
                    ? '霍兰德类型 · ${holland['code']}'
                    : '报告已生成',
                style: const TextStyle(color: Color(0xFFE8DFFF), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                heroTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                heroBody,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.6,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        if (tendency.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BackendReportSection(
            title: _firstReportText([tendency['title'], '职业倾向分析']),
            child: _ReportParagraph(tendency['body']),
          ),
        ],
        if (personality.isNotEmpty || persona.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BackendReportSection(
            title: _firstReportText([
              personality['title'],
              persona['title'],
              '综合画像',
            ]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (personality['body'] != null)
                  _ReportParagraph(personality['body']),
                if (personality['body'] != null && persona['body'] != null)
                  const SizedBox(height: 12),
                if (persona['body'] != null) _ReportParagraph(persona['body']),
              ],
            ),
          ),
        ],
        if (majors.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BackendReportSection(
            title: _firstReportText([majorBlock['title'], '专业推荐']),
            child: Column(
              children: [
                for (var index = 0; index < majors.length; index++) ...[
                  _MajorRecommendationCard(index: index, major: majors[index]),
                  if (index != majors.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
        if (careers.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BackendReportSection(
            title: _firstReportText([careerBlock['title'], '职业方向建议']),
            child: Column(
              children: [
                for (final career in careers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.work_outline,
                      color: Color(0xFF6B23FF),
                    ),
                    title: Text(
                      _firstReportText([
                        career['name'],
                        career['title'],
                        '职业方向',
                      ]),
                    ),
                    subtitle: career['reason'] == null
                        ? null
                        : Text(
                            '${career['reason']}',
                            style: const TextStyle(height: 1.5),
                          ),
                  ),
              ],
            ),
          ),
        ],
        if (advice.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BackendReportSection(
            title: _firstReportText([advice['title'], '下一步建议']),
            child: _ReportParagraph(advice['developmentAdvice']),
          ),
        ],
        if ((reportId ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '报告编号：$reportId',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF968EA0)),
          ),
        ],
      ],
    );
  }
}

class _ReportGeneratingState extends StatelessWidget {
  const _ReportGeneratingState({required this.task});

  final ReportTaskData task;

  @override
  Widget build(BuildContext context) {
    final value = task.progress.percent > 0
        ? task.progress.percent / 100
        : null;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 48,
            color: Color(0xFF6B23FF),
          ),
          const SizedBox(height: 18),
          Text(
            task.progress.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            task.progress.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6F687A), height: 1.6),
          ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: value,
            minHeight: 7,
            borderRadius: BorderRadius.circular(4),
          ),
          if (value != null) ...[
            const SizedBox(height: 8),
            Text(
              '${task.progress.percent.round()}%',
              style: const TextStyle(color: Color(0xFF6B23FF)),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            '可以返回其他页面，之后从“我的测评报告”继续查看。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8A8392)),
          ),
        ],
      ),
    );
  }
}

class _ReportEmptyState extends StatelessWidget {
  const _ReportEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, color: const Color(0xFF6B23FF), size: 48),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 9),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6F687A), height: 1.6),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF6B23FF),
              ),
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    ),
  );
}

class _BackendReportSection extends StatelessWidget {
  const _BackendReportSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 13),
        child,
      ],
    ),
  );
}

class _ReportParagraph extends StatelessWidget {
  const _ReportParagraph(this.value);

  final dynamic value;

  @override
  Widget build(BuildContext context) => Text(
    value?.toString() ?? '',
    style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF625A6C)),
  );
}

class _MajorRecommendationCard extends StatelessWidget {
  const _MajorRecommendationCard({required this.index, required this.major});

  final int index;
  final Map<String, dynamic> major;

  @override
  Widget build(BuildContext context) {
    final reason = _firstReportText([
      major['personalizedReason'],
      major['overview'],
      major['preferredMajorDirection'],
    ], fallback: '结合你的测评画像推荐。');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF6B23FF),
            foregroundColor: Colors.white,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _firstReportText([major['name'], '专业方向']),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (major['preferredMajorDirection']?.toString().isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${major['preferredMajorDirection']}',
                    style: const TextStyle(
                      color: Color(0xFF6B23FF),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  reason,
                  style: const TextStyle(
                    color: Color(0xFF625A6C),
                    height: 1.55,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoReportPage extends StatelessWidget {
  const _DemoReportPage({required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F5FF),
    appBar: AppBar(
      title: const Text('专业方向探索报告'),
      centerTitle: true,
      backgroundColor: const Color(0xFFF8F5FF),
      surfaceTintColor: Colors.transparent,
    ),
    body: AppConstrainedContent(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppLayout.pagePadding(context),
          10,
          AppLayout.pagePadding(context),
          30,
        ),
        children: [
          GeneratedReportView(
            reportId: reportId,
            report: const {
              'personalityAndCareerAnalysis': {
                'title': '探索型创造者',
                'careerTendencyAnalysis': {
                  'title': '职业倾向分析',
                  'body': '你善于从兴趣出发发现问题，并通过创造和实践寻找答案。',
                },
              },
              'majorRecommendations': {
                'title': '推荐方向',
                'majors': [
                  {'name': '数字媒体艺术', 'personalizedReason': '适合结合创造力与数字工具持续探索。'},
                  {'name': '视觉传达设计'},
                  {'name': '软件工程'},
                ],
              },
              'comprehensiveAdvice': {
                'title': '下一步建议',
                'developmentAdvice': '结合课程体验、院校信息和真实项目继续验证这些方向。',
              },
            },
          ),
        ],
      ),
    ),
  );
}

Map<String, dynamic> _reportMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _reportList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(_reportMap).toList();
}

String _firstReportText(List<dynamic> values, {String fallback = ''}) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return fallback;
}
