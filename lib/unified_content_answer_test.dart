part of 'main.dart';

List<String> _unifiedStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _unifiedInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _unifiedDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// 后端筛选出的单条真实来源，供 Agent 回答和来源卡片展示。
class UnifiedAnswerSource {
  const UnifiedAnswerSource({
    required this.sourceId,
    required this.provider,
    required this.displayName,
    required this.title,
    required this.summary,
    required this.url,
    required this.kind,
    required this.authors,
    required this.publishedAt,
    required this.score,
    required this.scoreReasons,
  });

  final String sourceId;
  final String provider;
  final String displayName;
  final String title;
  final String summary;
  final String url;
  final String kind;
  final List<String> authors;
  final DateTime? publishedAt;
  final double score;
  final List<String> scoreReasons;

  factory UnifiedAnswerSource.fromJson(Map<String, dynamic> json) {
    return UnifiedAnswerSource(
      sourceId: json['sourceId']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      authors: _unifiedStringList(json['authors']),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      score: _unifiedDouble(json['score']),
      scoreReasons: _unifiedStringList(json['scoreReasons']),
    );
  }

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'provider': provider,
    'displayName': displayName,
    'title': title,
    'summary': summary,
    'url': url,
    'kind': kind,
    'authors': authors,
    'publishedAt': publishedAt?.toIso8601String(),
    'score': score,
    'scoreReasons': scoreReasons,
  };
}

/// “先检索内容库”的完整回答数据，包含答案、来源和采集任务状态。
class UnifiedContentAnswerResult {
  const UnifiedContentAnswerResult({
    required this.answer,
    required this.keyPoints,
    required this.confidence,
    required this.caveat,
    required this.model,
    required this.usedFallback,
    required this.successSourceCount,
    required this.failedSourceCount,
    required this.itemCount,
    required this.latencyMs,
    required this.primarySource,
    required this.selectedSources,
    this.acquisition,
  });

  final String answer;
  final List<String> keyPoints;
  final String confidence;
  final String caveat;
  final String model;
  final bool usedFallback;
  final int successSourceCount;
  final int failedSourceCount;
  final int itemCount;
  final int latencyMs;
  final UnifiedAnswerSource? primarySource;
  final List<UnifiedAnswerSource> selectedSources;
  final ContentAcquisitionInfo? acquisition;

  factory UnifiedContentAnswerResult.fromJson(Map<String, dynamic> json) {
    final answerData = AuthService._map(json['answer']) ?? const {};
    final summary = AuthService._map(json['sourceSummary']) ?? const {};
    final primary = AuthService._map(json['primarySource']);
    final rawSelected = json['selectedSources'];
    return UnifiedContentAnswerResult(
      answer: answerData['answer']?.toString() ?? '',
      keyPoints: _unifiedStringList(answerData['keyPoints']),
      confidence: answerData['confidence']?.toString() ?? 'low',
      caveat: answerData['caveat']?.toString() ?? '',
      model: answerData['model']?.toString() ?? '',
      usedFallback: answerData['usedFallback'] == true,
      successSourceCount: _unifiedInt(summary['success']),
      failedSourceCount: _unifiedInt(summary['failed']),
      itemCount: _unifiedInt(summary['itemCount']),
      latencyMs: _unifiedInt(json['latencyMs']),
      primarySource: primary == null
          ? null
          : UnifiedAnswerSource.fromJson(primary),
      selectedSources: rawSelected is List
          ? rawSelected
                .map(AuthService._map)
                .whereType<Map<String, dynamic>>()
                .map(UnifiedAnswerSource.fromJson)
                .toList(growable: false)
          : const [],
      acquisition: ContentAcquisitionInfo.fromDynamic(json['acquisition']),
    );
  }

  Map<String, dynamic> toJson() => {
    'answer': {
      'answer': answer,
      'keyPoints': keyPoints,
      'confidence': confidence,
      'caveat': caveat,
      'model': model,
      'usedFallback': usedFallback,
    },
    'sourceSummary': {
      'success': successSourceCount,
      'failed': failedSourceCount,
      'itemCount': itemCount,
    },
    'latencyMs': latencyMs,
    'primarySource': primarySource?.toJson(),
    'selectedSources': selectedSources
        .map((source) => source.toJson())
        .toList(),
    if (acquisition != null) 'acquisition': acquisition!.toJson(),
  };
}

/// 内容库未命中后创建或合并的后台采集任务信息。
class ContentAcquisitionInfo {
  const ContentAcquisitionInfo({
    required this.jobId,
    required this.status,
    required this.merged,
    required this.foregroundWaitMs,
    this.notification,
  });

  factory ContentAcquisitionInfo.fromJson(Map<String, dynamic> json) {
    return ContentAcquisitionInfo(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      merged: json['merged'] == true,
      foregroundWaitMs: _unifiedInt(json['foregroundWaitMs']),
      notification: AuthService._map(json['notification']),
    );
  }

  static ContentAcquisitionInfo? fromDynamic(dynamic value) {
    final json = AuthService._map(value);
    if (json == null || (json['jobId']?.toString() ?? '').isEmpty) return null;
    return ContentAcquisitionInfo.fromJson(json);
  }

  final String jobId;
  final String status;
  final bool merged;
  final int foregroundWaitMs;
  final Map<String, dynamic>? notification;

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'status': status,
    'merged': merged,
    'foregroundWaitMs': foregroundWaitMs,
    if (notification != null) 'notification': notification,
  };
}

/// 客户端轮询后台采集任务时使用的轻量状态数据。
class ContentAcquisitionStatusSnapshot {
  const ContentAcquisitionStatusSnapshot({
    required this.jobId,
    required this.status,
    this.notification,
  });

  factory ContentAcquisitionStatusSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    return ContentAcquisitionStatusSnapshot(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'not_found',
      notification: AuthService._map(json['notification']),
    );
  }

  final String jobId;
  final String status;
  final Map<String, dynamic>? notification;

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isTerminal =>
      status == 'completed' || status == 'failed' || status == 'not_found';
}

/// 持久化未完成任务并轮询其状态；完成后转成 App 消息，用户无需停留在聊天页。
class ContentAcquisitionMonitor {
  ContentAcquisitionMonitor._();

  static final instance = ContentAcquisitionMonitor._();
  static const _storageKey = 'uniprism.pendingContentAcquisitions.v1';
  final Set<String> _pendingJobIds = {};
  Timer? _timer;
  bool _polling = false;

  Future<void> initialize() async {
    final stored = await AuthService._readStorage();
    final raw = stored[_storageKey]?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _pendingJobIds.addAll(
            decoded
                .map((value) => value?.toString() ?? '')
                .where((value) => RegExp(r'^acq-[a-f0-9]{32}$').hasMatch(value)),
          );
        }
      } catch (_) {
        // Invalid task state is discarded instead of blocking app startup.
      }
    }
    _ensureTimer();
    if (_pendingJobIds.isNotEmpty) unawaited(_poll());
  }

  Future<void> register(String jobId) async {
    if (!RegExp(r'^acq-[a-f0-9]{32}$').hasMatch(jobId)) return;
    if (_pendingJobIds.add(jobId)) await _persist();
    _ensureTimer();
  }

  Future<void> _persist() {
    return AuthService._writeStorage({
      _storageKey: _pendingJobIds.isEmpty
          ? null
          : jsonEncode(_pendingJobIds.toList(growable: false)),
    });
  }

  void _ensureTimer() {
    if (_pendingJobIds.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    if (_polling || _pendingJobIds.isEmpty) return;
    _polling = true;
    try {
      for (final jobId in _pendingJobIds.toList(growable: false)) {
        try {
          final snapshot = await UnifiedContentAnswerTestService.instance
              .acquisitionStatus(jobId);
          if (snapshot.isCompleted && snapshot.notification != null) {
            await ReportNotificationService.instance.ingestRemotePushPayload(
              snapshot.notification!,
            );
          }
          if (snapshot.isTerminal) _pendingJobIds.remove(jobId);
        } on ApiRequestException {
          // Keep polling after transient network failures.
        }
      }
      await _persist();
    } finally {
      _polling = false;
      _ensureTimer();
    }
  }
}

enum UnifiedAgentChatRole { user, assistant }

class UnifiedAgentChatMessage {
  const UnifiedAgentChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.result,
    this.isError = false,
  });

  final String id;
  final UnifiedAgentChatRole role;
  final String text;
  final DateTime createdAt;
  final UnifiedContentAnswerResult? result;
  final bool isError;

  factory UnifiedAgentChatMessage.fromJson(Map<String, dynamic> json) {
    final result = AuthService._map(json['result']);
    return UnifiedAgentChatMessage(
      id: json['id']?.toString() ?? '',
      role: json['role'] == 'user'
          ? UnifiedAgentChatRole.user
          : UnifiedAgentChatRole.assistant,
      text: json['text']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      result: result == null
          ? null
          : UnifiedContentAnswerResult.fromJson(result),
      isError: json['isError'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role == UnifiedAgentChatRole.user ? 'user' : 'assistant',
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    if (result != null) 'result': result!.toJson(),
    if (isError) 'isError': true,
  };
}

class _UnifiedAgentChatStore {
  static const _storageKey = 'uniprism.agentChatSessions.v1';
  static const _retention = Duration(days: 7);
  static const _maxMessages = 40;

  static String get _scope => AuthService.instance.agentChatStorageScope;

  static List<UnifiedAgentChatMessage> _decodeMessages(dynamic value) {
    if (value is! List) return const [];
    final cutoff = DateTime.now().subtract(_retention);
    final messages = value
        .whereType<Map>()
        .map(
          (item) => UnifiedAgentChatMessage.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .where(
          (message) =>
              message.id.isNotEmpty &&
              message.text.isNotEmpty &&
              message.createdAt.isAfter(cutoff),
        )
        .toList(growable: false);
    return messages.length <= _maxMessages
        ? messages
        : messages.sublist(messages.length - _maxMessages);
  }

  static Future<Map<String, List<UnifiedAgentChatMessage>>>
  _readSessions() async {
    final stored = await AuthService._readStorage();
    final raw = stored[_storageKey]?.toString();
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final sessions = <String, List<UnifiedAgentChatMessage>>{};
      for (final entry in decoded.entries) {
        final messages = _decodeMessages(entry.value);
        if (messages.isNotEmpty) sessions['${entry.key}'] = messages;
      }
      return sessions;
    } catch (_) {
      return {};
    }
  }

  static Future<List<UnifiedAgentChatMessage>> restore() async {
    final sessions = await _readSessions();
    await _writeSessions(sessions);
    return sessions[_scope] ?? const [];
  }

  static Future<void> _writeSessions(
    Map<String, List<UnifiedAgentChatMessage>> sessions,
  ) {
    return AuthService._writeStorage({
      _storageKey: sessions.isEmpty
          ? null
          : jsonEncode(
              sessions.map(
                (scope, scopedMessages) => MapEntry(
                  scope,
                  scopedMessages.map((message) => message.toJson()).toList(),
                ),
              ),
            ),
    });
  }

  static Future<void> persist(List<UnifiedAgentChatMessage> messages) async {
    final sessions = await _readSessions();
    final retained = messages.length <= _maxMessages
        ? messages
        : messages.sublist(messages.length - _maxMessages);
    sessions[_scope] = retained;
    await _writeSessions(sessions);
  }

  static Future<void> clear() async {
    final sessions = await _readSessions();
    sessions.remove(_scope);
    await _writeSessions(sessions);
  }
}

/// 开发环境下连接“内容库优先回答接口”和“采集状态接口”的服务层。
class UnifiedContentAnswerTestService {
  UnifiedContentAnswerTestService._();

  static final instance = UnifiedContentAnswerTestService._();
  final HttpClient _client = HttpClient();

  Future<UnifiedContentAnswerResult> answer({
    required String question,
    required List<String> recommendedMajors,
    required List<String> interests,
    required List<String> historySignals,
    required List<Map<String, String>> conversation,
    String? acquisitionJobId,
  }) async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('统一内容回答测试只能在开发环境使用');
    }
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.length < 2) {
      throw const ApiRequestException('请至少输入 2 个字的问题');
    }
    final baseUrl = AppConfig.contentSourceTestApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const ApiRequestException('内容来源测试后端地址未配置');
    }
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    try {
      final request = await _client.postUrl(
        Uri.parse('$normalizedBaseUrl/api/dev/content-library/answer'),
      );
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode({
            'question': normalizedQuestion,
            'recommendedMajors': recommendedMajors,
            'interests': interests,
            'historySignals': historySignals,
            'conversation': conversation,
            if (acquisitionJobId?.isNotEmpty == true)
              'acquisitionJobId': acquisitionJobId,
            'count': 3,
          }),
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 180),
      );
      final responseText = await utf8.decodeStream(response);
      final decoded = responseText.isEmpty ? null : jsonDecode(responseText);
      final envelope = AuthService._map(decoded) ?? const {};
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          envelope['ok'] != true) {
        throw ApiRequestException(
          AuthService._errorMessage(envelope),
          statusCode: response.statusCode,
        );
      }
      final data = AuthService._map(envelope['data']);
      if (data == null) {
        throw const ApiRequestException('统一回答返回格式不正确');
      }
      return UnifiedContentAnswerResult.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('统一内容回答连接超时');
    } on ApiRequestException {
      rethrow;
    } on SocketException catch (error, stackTrace) {
      // 展示目标地址，避免 App 只显示 SocketException 而无法定位配置问题。
      debugPrint(
        '[UnifiedContentAnswerTest] socket request failed: ' +
            normalizedBaseUrl + '; ' + error.message + '\n' + stackTrace.toString(),
      );
      throw ApiRequestException(
        '无法连接内容服务（' + normalizedBaseUrl +
            '）。请确认后端 npm run dev 正在运行。',
      );
    } on HttpException catch (error, stackTrace) {
      debugPrint(
        '[UnifiedContentAnswerTest] HTTP request failed: ' +
            normalizedBaseUrl + '; ' + error.message + '\n' + stackTrace.toString(),
      );
      throw ApiRequestException(
        '内容服务连接异常（' + normalizedBaseUrl + '）：' + error.message,
      );
    } on FormatException {
      throw const ApiRequestException('统一内容回答返回了无法识别的数据');
    } catch (error, stackTrace) {
      debugPrint(
        '[UnifiedContentAnswerTest] request failed: '
        '${error.runtimeType}: $error\n$stackTrace',
      );
      throw ApiRequestException('统一内容回答失败：${error.runtimeType}');
    }
  }

  Future<ContentAcquisitionStatusSnapshot> acquisitionStatus(
    String jobId,
  ) async {
    final baseUrl = AppConfig.contentSourceTestApiBaseUrl.trim();
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    try {
      final uri = Uri.parse(
        '$normalizedBaseUrl/api/dev/content-acquisition/status',
      ).replace(queryParameters: {'jobId': jobId});
      final request = await _client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final responseText = await utf8.decodeStream(response);
      final envelope =
          AuthService._map(jsonDecode(responseText)) ?? const {};
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          envelope['ok'] != true) {
        throw ApiRequestException(
          AuthService._errorMessage(envelope),
          statusCode: response.statusCode,
        );
      }
      final data = AuthService._map(envelope['data']);
      if (data == null) {
        throw const ApiRequestException('内容采集任务状态格式不正确');
      }
      return ContentAcquisitionStatusSnapshot.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('内容采集任务状态查询超时');
    } on ApiRequestException {
      rethrow;
    } catch (_) {
      throw const ApiRequestException('暂时无法查询内容采集任务状态');
    }
  }
}

/// 开发环境手动验证内容库问答流程的页面。
class UnifiedContentAnswerTestPage extends StatefulWidget {
  const UnifiedContentAnswerTestPage({
    super.key,
    this.recommendedMajors = const [],
    this.interests = const [],
  });

  final List<String> recommendedMajors;
  final List<String> interests;

  @override
  State<UnifiedContentAnswerTestPage> createState() =>
      _UnifiedContentAnswerTestPageState();
}

/// 保存测试聊天记录，并在页面恢复后继续关联未完成的采集任务。
class _UnifiedContentAnswerTestPageState
    extends State<UnifiedContentAnswerTestPage> {
  static const _statusMessages = [
    '正在为你理解问题…',
    '正在为你查找相关信息…',
    '正在为你整理可靠内容…',
    '正在为你生成回答…',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<UnifiedAgentChatMessage> _messages = const [];
  Timer? _statusTimer;
  bool _loading = false;
  bool _restoring = true;
  int _statusIndex = 0;
  String? _acquisitionJobId;
  String? _acquisitionQuestion;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreConversation());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  UnifiedAgentChatMessage _welcomeMessage() {
    final majors = widget.recommendedMajors.isEmpty
        ? ''
        : '我会参考你当前推荐的专业：${widget.recommendedMajors.join('、')}。';
    final interests = widget.interests.isEmpty
        ? ''
        : '也会结合你在意的方向：${widget.interests.take(5).join('、')}。';
    return UnifiedAgentChatMessage(
      id: 'welcome',
      role: UnifiedAgentChatRole.assistant,
      text:
          '你好，我可以陪你把专业、学习和未来方向一步步想清楚。'
          '$majors$interests你现在最想聊哪一件事？',
      createdAt: DateTime.now(),
    );
  }

  Future<void> _restoreConversation() async {
    final restored = await _UnifiedAgentChatStore.restore();
    if (!mounted) return;
    setState(() {
      _messages = restored.isEmpty ? [_welcomeMessage()] : restored;
      for (final message in _messages.reversed) {
        final acquisition = message.result?.acquisition;
        if (acquisition?.isPending == true) {
          _acquisitionJobId = acquisition!.jobId;
          break;
        }
      }
      _restoring = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusIndex = 0;
    _statusTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted || !_loading) return;
      setState(() {
        _statusIndex = (_statusIndex + 1) % _statusMessages.length;
      });
    });
  }

  List<Map<String, String>> _recentConversation(
    UnifiedAgentChatMessage current,
  ) {
    final available = _messages
        .where(
          (message) =>
              message.id != current.id &&
              message.id != 'welcome' &&
              !message.isError,
        )
        .toList();
    final recent = available.length <= 8
        ? available
        : available.sublist(available.length - 8);
    return recent
        .map(
          (message) => {
            'role': message.role == UnifiedAgentChatRole.user
                ? 'user'
                : 'assistant',
            'content': message.text.length <= 1500
                ? message.text
                : message.text.substring(0, 1500),
          },
        )
        .toList(growable: false);
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (_loading || text.length < 2) return;
    FocusScope.of(context).unfocus();
    final userMessage = UnifiedAgentChatMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: UnifiedAgentChatRole.user,
      text: text,
      createdAt: DateTime.now(),
    );
    _inputController.clear();
    setState(() {
      _messages = [..._messages, userMessage];
      _loading = true;
      _statusIndex = 0;
    });
    _startStatusTimer();
    _scrollToBottom();
    unawaited(_UnifiedAgentChatStore.persist(_messages));

    try {
      final canReuseTask = _acquisitionJobId != null
          && _acquisitionQuestion != null
          && _agentQuestionKey(userMessage.text)
              == _agentQuestionKey(_acquisitionQuestion!);
      if (!canReuseTask) {
        _acquisitionJobId = null;
        _acquisitionQuestion = null;
      }
      final result = await UnifiedContentAnswerTestService.instance.answer(
        question: text,
        recommendedMajors: widget.recommendedMajors,
        interests: widget.interests,
        // 历史消息仅用于对话语气；独立问题不能把上一题关键词带入检索。
        historySignals: const [],
        conversation: _recentConversation(userMessage),
        acquisitionJobId: canReuseTask ? _acquisitionJobId : null,
      );
      final acquisition = result.acquisition;
      if (acquisition?.isPending == true) {
        _acquisitionJobId = acquisition!.jobId;
        _acquisitionQuestion = userMessage.text;
        await ContentAcquisitionMonitor.instance.register(acquisition.jobId);
      } else if (acquisition?.isCompleted == true) {
        _acquisitionJobId = null;
        _acquisitionQuestion = null;
        if (acquisition?.notification != null) {
          await ReportNotificationService.instance.ingestRemotePushPayload(
            acquisition!.notification!,
          );
        }
      } else {
        // 历史任务仍由通知监听器追踪，但不再作为下一条独立问题的上下文。
        _acquisitionJobId = null;
        _acquisitionQuestion = null;
      }
      final assistantMessage = UnifiedAgentChatMessage(
        id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
        role: UnifiedAgentChatRole.assistant,
        text: result.answer,
        createdAt: DateTime.now(),
        result: result,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, assistantMessage];
      });
      await _UnifiedAgentChatStore.persist(_messages);
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      final errorMessage = UnifiedAgentChatMessage(
        id: 'error-${DateTime.now().microsecondsSinceEpoch}',
        role: UnifiedAgentChatRole.assistant,
        text: '这次没能顺利给出合适的建议。你可以换一种说法，或补充你最在意的是学习、就业还是未来方向，我会继续帮你分析。',
        createdAt: DateTime.now(),
        isError: true,
      );
      setState(() {
        _messages = [..._messages, errorMessage];
      });
      await _UnifiedAgentChatStore.persist(_messages);
    } finally {
      _statusTimer?.cancel();
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _clearConversation() async {
    if (_loading) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清空当前对话？'),
            content: const Text('本机保存的最近对话和引用来源会被清除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _UnifiedAgentChatStore.clear();
    if (!mounted) return;
    setState(() => _messages = [_welcomeMessage()]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: AppBar(
        title: const Text('棱镜 Agent'),
        backgroundColor: const Color(0xFFFAF7FF),
        actions: [
          IconButton(
            onPressed: _loading ? null : _clearConversation,
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _UnifiedAgentContextBar(
              recommendedMajors: widget.recommendedMajors,
              interests: widget.interests,
            ),
            Expanded(
              child: _restoring
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return _UnifiedAgentStatusBubble(
                            text: _statusMessages[_statusIndex],
                          );
                        }
                        return _UnifiedAgentMessageBubble(
                          message: _messages[index],
                        );
                      },
                    ),
            ),
            _UnifiedAgentComposer(
              controller: _inputController,
              loading: _loading,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedAgentContextBar extends StatelessWidget {
  const _UnifiedAgentContextBar({
    required this.recommendedMajors,
    required this.interests,
  });

  final List<String> recommendedMajors;
  final List<String> interests;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: const Color(0xFFFFF3D6),
      child: Text(
        [
          if (recommendedMajors.isNotEmpty)
            '推荐专业：${recommendedMajors.join('、')}',
          if (interests.isNotEmpty) '兴趣线索：${interests.take(4).join('、')}',
          if (recommendedMajors.isEmpty && interests.isEmpty)
            '尚未读取到推荐专业和兴趣线索，将先根据对话内容检索',
        ].join('  ·  '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFF765A16)),
      ),
    );
  }
}

class _UnifiedAgentComposer extends StatelessWidget {
  const _UnifiedAgentComposer({
    required this.controller,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE9E4F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !loading,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.none,
              autocorrect: true,
              enableSuggestions: true,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: loading ? '正在为你回答…' : '继续问专业、就业、技能或项目…',
                filled: true,
                fillColor: const Color(0xFFF5F2F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: loading ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF6A52A3),
              foregroundColor: Colors.white,
            ),
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _UnifiedAgentStatusBubble extends StatelessWidget {
  const _UnifiedAgentStatusBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                text,
                key: ValueKey(text),
                style: const TextStyle(color: Color(0xFF5D4B86)),
              ),
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 3,
              color: Color(0xFF7A5BB5),
              backgroundColor: Color(0xFFEAE3F7),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedAgentMessageBubble extends StatelessWidget {
  const _UnifiedAgentMessageBubble({required this.message});

  final UnifiedAgentChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == UnifiedAgentChatRole.user;
    final result = message.result;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF6B23FF)
              : message.isError
              ? const Color(0xFFFFE8E8)
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: TextStyle(
                height: 1.5,
                color: isUser ? Colors.white : const Color(0xFF2F2938),
              ),
            ),
            if (result != null) ...[
              if (result.keyPoints.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...result.keyPoints.map(
                  (point) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $point'),
                  ),
                ),
              ],
              if (result.selectedSources.isNotEmpty)
                _UnifiedSourcesExpansion(result: result),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnifiedSourcesExpansion extends StatelessWidget {
  const _UnifiedSourcesExpansion({required this.result});

  final UnifiedContentAnswerResult result;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          '查看来源（${result.selectedSources.length}）',
          style: const TextStyle(
            color: Color(0xFF6A52A3),
            fontWeight: FontWeight.w700,
          ),
        ),
        children: result.selectedSources
            .map(
              (source) => _UnifiedSourceCard(
                source: source,
                primary: result.primarySource?.sourceId == source.sourceId,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _UnifiedSourceCard extends StatelessWidget {
  const _UnifiedSourceCard({required this.source, required this.primary});

  final UnifiedAnswerSource source;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FC),
        border: Border.all(
          color: primary ? const Color(0xFF8B67DE) : const Color(0xFFE4DDF2),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${source.sourceId} · ${source.displayName}'
            '${primary ? ' · 核心来源' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A52A3),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            source.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (source.summary.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              source.summary,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
          Row(
            children: [
              Text(
                '综合分 ${source.score.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: source.url.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: source.url),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('原始来源链接已复制')),
                        );
                      },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('复制链接'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
