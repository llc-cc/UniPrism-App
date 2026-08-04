part of 'main.dart';

class AgentContentSource {
  const AgentContentSource({
    required this.id,
    required this.name,
    required this.url,
    this.type = 'unknown',
  });

  factory AgentContentSource.fromJson(dynamic value) {
    final json = AuthService._map(value) ?? const <String, dynamic>{};
    return AgentContentSource(
      id: json['id']?.toString() ?? 'unknown',
      name: json['name']?.toString() ?? '未知来源',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'unknown',
    );
  }

  final String id;
  final String name;
  final String url;
  final String type;
}

class AgentContentCardData {
  const AgentContentCardData({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.source,
    required this.contentType,
    required this.recommendationReason,
    required this.publishedAt,
    required this.aiGenerated,
    this.isDemo = false,
  });

  factory AgentContentCardData.fromJson(dynamic value) {
    final json = AuthService._map(value) ?? const <String, dynamic>{};
    return AgentContentCardData(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名内容',
      excerpt: json['excerpt']?.toString() ?? '',
      source: AgentContentSource.fromJson(json['source']),
      contentType: json['contentType']?.toString() ?? 'knowledge',
      recommendationReason:
          json['recommendationReason']?.toString() ?? '与你当前关注的主题相关',
      publishedAt:
          DateTime.tryParse(json['publishedAt']?.toString() ?? '') ??
          DateTime.now(),
      aiGenerated: json['aiGenerated'] == true,
      isDemo: json['isDemo'] == true,
    );
  }

  final String id;
  final String title;
  final String excerpt;
  final AgentContentSource source;
  final String contentType;
  final String recommendationReason;
  final DateTime publishedAt;
  final bool aiGenerated;
  final bool isDemo;
}

class AgentSubscriptionDraft {
  const AgentSubscriptionDraft({
    required this.previewId,
    required this.name,
    required this.topics,
    required this.sourceScope,
    required this.contentScope,
    required this.frequency,
    required this.pushTime,
    required this.quietHours,
    required this.maxItems,
    this.isDemo = false,
  });

  factory AgentSubscriptionDraft.fromJson(dynamic value) {
    final json = AuthService._map(value) ?? const <String, dynamic>{};
    return AgentSubscriptionDraft(
      previewId: json['previewId']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名订阅',
      topics: _agentStringList(json['topics']),
      sourceScope: _agentStringList(json['sourceScope']),
      contentScope: _agentStringList(json['contentScope']),
      frequency: json['frequency']?.toString() ?? 'daily',
      pushTime: json['pushTime']?.toString() ?? '20:00',
      quietHours: _agentStringList(json['quietHours']),
      maxItems: (json['maxItems'] as num?)?.toInt() ?? 3,
      isDemo: json['isDemo'] == true,
    );
  }

  final String previewId;
  final String name;
  final List<String> topics;
  final List<String> sourceScope;
  final List<String> contentScope;
  final String frequency;
  final String pushTime;
  final List<String> quietHours;
  final int maxItems;
  final bool isDemo;
}

/// Agent 页面使用的统一回复；可携带来源卡片和后台采集任务状态。
class AgentChatReply {
  const AgentChatReply({
    required this.conversationId,
    required this.text,
    this.cards = const [],
    this.subscriptionDraft,
    this.traceId,
    this.acquisition,
  });

  factory AgentChatReply.fromJson(Map<String, dynamic> json) {
    final rawCards = json['cards'];
    final action = AuthService._map(json['pendingAction']);
    final rawSubscription = AuthService._map(action?['subscription']);
    AgentSubscriptionDraft? draft;
    if (action?['type'] == 'create_subscription' && rawSubscription != null) {
      draft = AgentSubscriptionDraft.fromJson({
        ...rawSubscription,
        'previewId': action?['previewId'],
      });
    }
    return AgentChatReply(
      conversationId: json['conversationId']?.toString() ?? '',
      text: json['text']?.toString() ?? '暂时没有找到合适的内容。',
      cards: rawCards is List
          ? rawCards.map(AgentContentCardData.fromJson).toList()
          : const [],
      subscriptionDraft: draft,
      traceId: json['traceId']?.toString(),
      acquisition: ContentAcquisitionInfo.fromDynamic(json['acquisition']),
    );
  }

  final String conversationId;
  final String text;
  final List<AgentContentCardData> cards;
  final AgentSubscriptionDraft? subscriptionDraft;
  final String? traceId;
  final ContentAcquisitionInfo? acquisition;
}

class AgentSubscription {
  const AgentSubscription({
    required this.id,
    required this.name,
    required this.topics,
    required this.frequency,
    required this.pushTime,
    required this.status,
    this.nextRunAt,
    this.isDemo = false,
  });

  factory AgentSubscription.fromJson(dynamic value) {
    final json = AuthService._map(value) ?? const <String, dynamic>{};
    return AgentSubscription(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名订阅',
      topics: _agentStringList(json['topics']),
      frequency: json['frequency']?.toString() ?? 'daily',
      pushTime: json['pushTime']?.toString() ?? '20:00',
      status: json['status']?.toString() ?? 'active',
      nextRunAt: DateTime.tryParse(json['nextRunAt']?.toString() ?? ''),
      isDemo: json['isDemo'] == true,
    );
  }

  final String id;
  final String name;
  final List<String> topics;
  final String frequency;
  final String pushTime;
  final String status;
  final DateTime? nextRunAt;
  final bool isDemo;

  bool get isActive => status == 'active';

  AgentSubscription copyWith({String? status}) => AgentSubscription(
    id: id,
    name: name,
    topics: topics,
    frequency: frequency,
    pushTime: pushTime,
    status: status ?? this.status,
    nextRunAt: nextRunAt,
    isDemo: isDemo,
  );
}

List<String> _agentStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

/// 保持来源卡片易扫读；完整内容仍可通过原始来源链接查看。
String _agentCompactExcerpt(String value, {int maxLength = 180}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return normalized.substring(0, maxLength) + '…';
}

/// 只有完全相同的问题才允许复用已完成的采集任务。
String _agentQuestionKey(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s，。！？、,.!?]'), '').trim();
}

/// 根据环境调用正式 Agent 接口或开发期内容库接口，页面无需关心差异。
class AgentExperienceService {
  AgentExperienceService._();

  static final instance = AgentExperienceService._();

  Future<AgentChatReply> sendMessage({
    required String message,
    String? conversationId,
    bool useProfile = true,
    List<String> recommendedMajors = const [],
    List<String> interests = const [],
    List<Map<String, String>> conversation = const [],
    String? acquisitionJobId,
  }) async {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      throw const ApiRequestException('请输入想了解的内容');
    }
    if (AppConfig.agentMockEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return _mockReply(normalized, conversationId: conversationId);
    }
    if (!AppConfig.agentEnabled) {
      throw const ApiRequestException('Agent 服务尚未在当前环境启用');
    }
    if (AppConfig.developerToolsEnabled) {
      return _sendDevelopmentMessage(
        message: normalized,
        conversationId: conversationId,
        recommendedMajors: recommendedMajors,
        interests: interests,
        conversation: conversation,
        acquisitionJobId: acquisitionJobId,
      );
    }
    final data = await AuthService.instance._request(
      'POST',
      '/api/app/agent/chat',
      body: {
        if (conversationId?.isNotEmpty == true)
          'conversationId': conversationId,
        'message': normalized,
        'useProfile': useProfile,
        'clientContext': {'timezone': 'Asia/Shanghai', 'locale': 'zh-CN'},
      },
      timeout: const Duration(seconds: 45),
    );
    return AgentChatReply.fromJson(data);
  }

  Future<AgentChatReply> _sendDevelopmentMessage({
    required String message,
    String? conversationId,
    required List<String> recommendedMajors,
    required List<String> interests,
    required List<Map<String, String>> conversation,
    String? acquisitionJobId,
  }) async {
    final result = await UnifiedContentAnswerTestService.instance.answer(
      question: message,
      recommendedMajors: recommendedMajors,
      interests: interests,
      historySignals: const [],
      conversation: conversation,
      acquisitionJobId: acquisitionJobId,
    );
    final now = DateTime.now();
    return AgentChatReply(
      conversationId:
          conversationId ??
          'unified-conversation-${now.millisecondsSinceEpoch}',
      // 来源卡片已单独呈现，不把检索计数等内部信息塞进用户回答。
      text: result.answer,
      cards: result.selectedSources
          .map(
            (source) => AgentContentCardData(
              id: source.sourceId.isNotEmpty ? source.sourceId : source.url,
              title: source.title.isNotEmpty ? source.title : '相关内容',
              excerpt: _agentCompactExcerpt(source.summary),
              source: AgentContentSource(
                id: source.provider,
                name: source.displayName,
                url: source.url,
                type: source.provider,
              ),
              contentType: source.kind.isEmpty ? 'knowledge' : source.kind,
              recommendationReason: source.scoreReasons.isEmpty
                  ? '来自真实平台检索结果，与你当前的问题相关'
                  : source.scoreReasons.take(2).join('；'),
              publishedAt: source.publishedAt ?? now,
              aiGenerated: false,
            ),
          )
          .toList(growable: false),
      traceId: 'unified-${now.millisecondsSinceEpoch}',
      acquisition: result.acquisition,
    );
  }

  AgentChatReply _mockReply(String message, {String? conversationId}) {
    final now = DateTime.now();
    final wantsSubscription = RegExp(r'每天|每日|定时|订阅|推送|晚上|早上').hasMatch(message);
    final topics = <String>[
      if (message.contains('人工智能') || message.toLowerCase().contains('ai'))
        '人工智能',
      if (message.contains('计算机')) '计算机专业',
      if (message.contains('机器人')) '机器人竞赛',
      if (message.contains('数学')) '数学',
    ];
    if (topics.isEmpty) topics.add('专业探索');
    final previewId = 'demo-preview-${now.millisecondsSinceEpoch}';
    return AgentChatReply(
      conversationId:
          conversationId ?? 'demo-conversation-${now.millisecondsSinceEpoch}',
      text: wantsSubscription
          ? '我根据你的兴趣整理了一个订阅预览。当前是内部演示数据，正式版本只会搜索已授权来源；确认后仅在本机演示订阅状态，不会发送真实通知。'
          : '我先为你整理了几条内部演示内容。正式接入后，这里会调用已授权搜索接口，并为每条结果展示真实来源。',
      cards: [
        AgentContentCardData(
          id: 'demo-content-1',
          title: '演示：从兴趣出发了解人工智能专业',
          excerpt: '这是一条自有模拟内容，用于验证来源卡片、推荐理由和订阅流程，不代表已接入任何外部平台。',
          source: const AgentContentSource(
            id: 'uniprism-demo',
            name: '万有棱镜内部演示',
            url: 'https://uniprism.cn',
            type: 'own_content',
          ),
          contentType: 'major_experience',
          recommendationReason: '与你关注的 ${topics.join('、')} 相关',
          publishedAt: now,
          aiGenerated: false,
          isDemo: true,
        ),
        AgentContentCardData(
          id: 'demo-content-2',
          title: '演示：如何设计一条可执行的专业探索计划',
          excerpt: '通过课程体验、项目实践和从业者访谈验证兴趣，避免只根据热门程度选择专业。',
          source: const AgentContentSource(
            id: 'uniprism-demo',
            name: '万有棱镜内部演示',
            url: 'https://uniprism.cn',
            type: 'own_content',
          ),
          contentType: 'learning_guide',
          recommendationReason: '适合作为专业探索的下一步行动',
          publishedAt: now.subtract(const Duration(hours: 2)),
          aiGenerated: true,
          isDemo: true,
        ),
      ],
      subscriptionDraft: wantsSubscription
          ? AgentSubscriptionDraft(
              previewId: previewId,
              name: '${topics.join('与')}探索',
              topics: topics,
              sourceScope: const ['own_content', 'authorized_sources'],
              contentScope: const ['major_experience', 'learning_guide'],
              frequency: 'daily',
              pushTime: message.contains('早上') ? '08:00' : '20:00',
              quietHours: const ['22:00', '07:30'],
              maxItems: 3,
              isDemo: true,
            )
          : null,
      traceId: 'demo-trace-${now.millisecondsSinceEpoch}',
    );
  }

  Future<AgentSubscription> confirmSubscription(
    AgentSubscriptionDraft draft,
  ) async {
    if (AppConfig.agentMockEnabled || draft.isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return AgentSubscription(
        id: 'demo-sub-${DateTime.now().millisecondsSinceEpoch}',
        name: draft.name,
        topics: draft.topics,
        frequency: draft.frequency,
        pushTime: draft.pushTime,
        status: 'active',
        nextRunAt: DateTime.now().add(const Duration(days: 1)),
        isDemo: true,
      );
    }
    final data = await AuthService.instance._request(
      'POST',
      '/api/app/content/subscriptions',
      body: {
        'previewId': draft.previewId,
        'confirmed': true,
        'consentVersion': 'agent-subscription-v1',
        'idempotencyKey':
            'app-${draft.previewId}-${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    return AgentSubscription.fromJson(data['subscription']);
  }

  Future<List<AgentSubscription>> loadSubscriptions() async {
    if (AppConfig.agentMockEnabled) return const [];
    if (!AppConfig.agentEnabled) return const [];
    final data = await AuthService.instance._request(
      'GET',
      '/api/app/content/subscriptions',
    );
    final rawItems = data['subscriptions'] ?? data['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .map(AgentSubscription.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<AgentSubscription> setSubscriptionActive(
    AgentSubscription subscription,
    bool active,
  ) async {
    if (AppConfig.agentMockEnabled || subscription.isDemo) {
      return subscription.copyWith(status: active ? 'active' : 'paused');
    }
    final action = active ? 'resume' : 'pause';
    final data = await AuthService.instance._request(
      'POST',
      '/api/app/content/subscriptions/${Uri.encodeComponent(subscription.id)}/$action',
    );
    return AgentSubscription.fromJson(data['subscription']);
  }

  Future<void> deleteSubscription(AgentSubscription subscription) async {
    if (AppConfig.agentMockEnabled || subscription.isDemo) return;
    await AuthService.instance._request(
      'DELETE',
      '/api/app/content/subscriptions/${Uri.encodeComponent(subscription.id)}',
    );
  }
}

class AgentSubscriptionCenter extends ChangeNotifier {
  AgentSubscriptionCenter._();

  static final instance = AgentSubscriptionCenter._();
  final List<AgentSubscription> _subscriptions = [];
  bool _loading = false;

  List<AgentSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);
  bool get loading => _loading;

  Future<void> refresh() async {
    if (AppConfig.agentMockEnabled || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final subscriptions = await AgentExperienceService.instance
          .loadSubscriptions();
      _subscriptions
        ..clear()
        ..addAll(subscriptions);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AgentSubscription> confirm(AgentSubscriptionDraft draft) async {
    final subscription = await AgentExperienceService.instance
        .confirmSubscription(draft);
    _subscriptions.removeWhere((item) => item.id == subscription.id);
    _subscriptions.insert(0, subscription);
    notifyListeners();
    return subscription;
  }

  Future<void> toggle(String id) async {
    final index = _subscriptions.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = _subscriptions[index];
    final updated = await AgentExperienceService.instance.setSubscriptionActive(
      current,
      !current.isActive,
    );
    final currentIndex = _subscriptions.indexWhere((item) => item.id == id);
    if (currentIndex < 0) return;
    _subscriptions[currentIndex] = updated;
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final index = _subscriptions.indexWhere((item) => item.id == id);
    if (index < 0) return;
    await AgentExperienceService.instance.deleteSubscription(
      _subscriptions[index],
    );
    _subscriptions.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}

/// Agent 会话页：传递用户画像用于个性化表达，但不把画像当作检索关键词。
class AgentExperiencePage extends StatefulWidget {
  const AgentExperiencePage({
    super.key,
    this.recommendedMajors = const [],
    this.interests = const [],
    this.knowledgeGateway,
    this.knowledgeStore,
  });

  final List<String> recommendedMajors;
  final List<String> interests;
  final KnowledgeExtractionGateway? knowledgeGateway;
  final KnowledgeForestStore? knowledgeStore;

  @override
  State<AgentExperiencePage> createState() => _AgentExperiencePageState();
}

/// 管理本地聊天记录及当前已合并的后台采集任务编号。
class _AgentExperiencePageState extends State<AgentExperiencePage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AgentConversationEntry> _entries = [
    const _AgentConversationEntry(
      fromUser: false,
      messageId: 'agent-welcome',
      text: '你好，我可以根据你的兴趣查找专业体验、学习方法和成长内容。长期推送会先给你预览，并在你确认后创建订阅。',
    ),
  ];
  final Set<String> _confirmedPreviewIds = {};
  final Set<String> _extractingKnowledgeMessageIds = {};
  final Map<String, String> _knowledgeExtractionErrors = {};
  late final KnowledgeExtractionGateway _knowledgeGateway;
  late final KnowledgeForestStore _knowledgeStore;
  Timer? _scrollCorrectionTimer;
  String? _conversationId;
  String? _acquisitionJobId;
  String? _acquisitionQuestion;
  int _localMessageSequence = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _knowledgeGateway =
        widget.knowledgeGateway ?? KnowledgeExtractionService.instance;
    _knowledgeStore = widget.knowledgeStore ?? KnowledgeForestStore.instance;
  }

  @override
  void dispose() {
    _scrollCorrectionTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 先渲染用户消息；若后端转入后台采集，则保存任务编号并等待 App 通知。
  Future<void> _send([String? suggested]) async {
    final message = (suggested ?? _controller.text).trim();
    if (message.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    final conversation = _entries
        .where((entry) => !entry.isError)
        .toList(growable: false)
        .reversed
        .take(8)
        .toList(growable: false)
        .reversed
        .map(
          (entry) => {
            'role': entry.fromUser ? 'user' : 'assistant',
            'content': entry.text,
          },
        )
        .toList(growable: false);
    _controller.clear();
    setState(() {
      _entries.add(
        _AgentConversationEntry(
          fromUser: true,
          messageId: _nextLocalMessageId('user'),
          text: message,
          question: message,
        ),
      );
      _sending = true;
    });
    _scrollToEnd();
    final canReuseTask =
        _acquisitionJobId != null &&
        _acquisitionQuestion != null &&
        _agentQuestionKey(message) == _agentQuestionKey(_acquisitionQuestion!);
    if (!canReuseTask) {
      // 旧任务仍由通知中心追踪，但新问题绝不能携带旧任务编号请求回答。
      _acquisitionJobId = null;
      _acquisitionQuestion = null;
    }
    try {
      final reply = await AgentExperienceService.instance.sendMessage(
        message: message,
        conversationId: _conversationId,
        recommendedMajors: widget.recommendedMajors,
        interests: widget.interests,
        conversation: conversation,
        acquisitionJobId: canReuseTask ? _acquisitionJobId : null,
      );
      if (!mounted) return;
      _conversationId = reply.conversationId;
      final acquisition = reply.acquisition;
      if (acquisition?.isPending == true) {
        _acquisitionJobId = acquisition!.jobId;
        _acquisitionQuestion = message;
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
        // 旧任务仍由通知监听器追踪，但不能再作为下一条独立问题的上下文。
        _acquisitionJobId = null;
        _acquisitionQuestion = null;
      }
      setState(() {
        final traceId = (reply.traceId ?? '').trim();
        _entries.add(
          _AgentConversationEntry(
            fromUser: false,
            messageId: traceId.isEmpty
                ? _nextLocalMessageId('answer')
                : traceId,
            text: reply.text,
            question: message,
            cards: reply.cards,
            subscriptionDraft: reply.subscriptionDraft,
          ),
        );
      });
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() {
        _entries.add(
          _AgentConversationEntry(
            fromUser: false,
            messageId: _nextLocalMessageId('error'),
            text: '暂时无法完成这次请求：${error.message}',
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  Future<void> _confirmSubscription(AgentSubscriptionDraft draft) async {
    if (_confirmedPreviewIds.contains(draft.previewId)) return;
    try {
      final subscription = await AgentSubscriptionCenter.instance.confirm(
        draft,
      );
      if (!mounted) return;
      setState(() {
        _confirmedPreviewIds.add(draft.previewId);
        _entries.add(
          _AgentConversationEntry(
            fromUser: false,
            messageId: _nextLocalMessageId('subscription'),
            text: subscription.isDemo
                ? '内部演示订阅已创建：${subscription.name}。它不会触发真实远程推送，离开进程后可能清空。'
                : '订阅已创建：${subscription.name}，你可以在“我的订阅”中随时暂停或删除。',
          ),
        );
      });
      _scrollToEnd();
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _nextLocalMessageId(String kind) {
    _localMessageSequence += 1;
    return 'agent-$kind-$_localMessageSequence';
  }

  /// 页面只编排提炼状态；网络、审核和存储分别交给既有边界。
  Future<void> _extractKnowledge(_AgentConversationEntry entry) async {
    if (_extractingKnowledgeMessageIds.contains(entry.messageId)) return;
    setState(() {
      _extractingKnowledgeMessageIds.add(entry.messageId);
      _knowledgeExtractionErrors.remove(entry.messageId);
    });

    try {
      final batch = await _knowledgeGateway.extract(
        conversationId: _conversationId ?? 'local-agent-conversation',
        messageId: entry.messageId,
        question: entry.question,
        answer: entry.text,
        availableTrees: _knowledgeStore.trees
            .map((tree) => KnowledgeTreeSummary(id: tree.id, title: tree.title))
            .toList(growable: false),
        sourceRefs: entry.cards
            .where((card) => card.source.url.trim().isNotEmpty)
            .map(
              (card) => KnowledgeSourceRef(
                id: card.id,
                title: card.title,
                url: card.source.url,
                sourceName: card.source.name,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _extractingKnowledgeMessageIds.remove(entry.messageId));
      await Navigator.of(context).push<KnowledgeTreeSnapshot>(
        MaterialPageRoute<KnowledgeTreeSnapshot>(
          builder: (_) => KnowledgeExtractionPreviewPage(
            batch: batch,
            store: _knowledgeStore,
          ),
        ),
      );
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() {
        _extractingKnowledgeMessageIds.remove(entry.messageId);
        _knowledgeExtractionErrors[entry.messageId] = error.message;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extractingKnowledgeMessageIds.remove(entry.messageId);
        _knowledgeExtractionErrors[entry.messageId] = '知识提炼失败，请稍后重试。';
      });
      _scrollToEnd();
    }
  }

  /// 来源卡片会在首帧后撑高列表，因此二次滚动以保证最新回答可见。
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
      // Long answers and source cards can increase the list extent after the
      // first frame. A second pass keeps the newest reply above the composer.
      _scrollCorrectionTimer?.cancel();
      _scrollCorrectionTimer = Timer(const Duration(milliseconds: 320), () {
        if (!mounted || !_scrollController.hasClients) return;
        unawaited(
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: const Text('棱镜 Agent'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '我的知识森林',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => KnowledgeForestPage(store: _knowledgeStore),
              ),
            ),
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: '我的订阅',
            onPressed: () =>
                Navigator.of(context).pushNamed('/agent-subscriptions'),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (AppConfig.agentMockEnabled) const _AgentMockBanner(),
          if (AppConfig.agentEnabled && AppConfig.developerToolsEnabled)
            const _AgentLiveTestBanner(),
          Expanded(
            child: AppConstrainedContent(
              maxWidth: AppLayout.phoneContentMaxWidth,
              child: ListView.builder(
                key: const ValueKey('agent-conversation-list'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                itemCount: _entries.length + (_sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _entries.length) {
                    return const _AgentTypingIndicator();
                  }
                  final entry = _entries[index];
                  return _AgentEntryView(
                    entry: entry,
                    knowledgeExtracting: _extractingKnowledgeMessageIds
                        .contains(entry.messageId),
                    knowledgeError: _knowledgeExtractionErrors[entry.messageId],
                    onExtractKnowledge:
                        entry.knowledgeEligible && entry.question.isNotEmpty
                        ? () => _extractKnowledge(entry)
                        : null,
                    subscriptionConfirmed:
                        entry.subscriptionDraft != null &&
                        _confirmedPreviewIds.contains(
                          entry.subscriptionDraft!.previewId,
                        ),
                    onConfirmSubscription: entry.subscriptionDraft == null
                        ? null
                        : () => _confirmSubscription(entry.subscriptionDraft!),
                  );
                },
              ),
            ),
          ),
          if (_entries.length == 1)
            _AgentSuggestions(onSelected: (value) => _send(value)),
          _AgentComposer(
            controller: _controller,
            enabled: !_sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _AgentConversationEntry {
  const _AgentConversationEntry({
    required this.fromUser,
    required this.messageId,
    required this.text,
    this.question = '',
    this.cards = const [],
    this.subscriptionDraft,
    this.isError = false,
  });

  final bool fromUser;
  final String messageId;
  final String text;
  final String question;
  final List<AgentContentCardData> cards;
  final AgentSubscriptionDraft? subscriptionDraft;
  final bool isError;

  bool get knowledgeEligible =>
      !fromUser && !isError && text.trim().length >= 40;
}

class _AgentHomeEntry extends StatelessWidget {
  const _AgentHomeEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2EDFF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const ValueKey('agent-home-entry'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B23FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '和棱镜 Agent 聊聊',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '按兴趣发现知识，确认后创建定时订阅',
                      style: TextStyle(color: Color(0xFF6D6875), height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF6B23FF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentMockBanner extends StatelessWidget {
  const _AgentMockBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4D9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: const SafeArea(
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science_outlined, size: 17, color: Color(0xFF8A5A00)),
            SizedBox(width: 7),
            Flexible(
              child: Text(
                '内部演示模式 · 未连接知乎、小红书或真实推送',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF704A00),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentLiveTestBanner extends StatelessWidget {
  const _AgentLiveTestBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFEAF7EF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: const SafeArea(
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_outlined, size: 17, color: Color(0xFF187A46)),
            SizedBox(width: 7),
            Flexible(
              child: Text(
                '真实内容联调 · 定期采集内容库 + DeepSeek',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF136239),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentEntryView extends StatelessWidget {
  const _AgentEntryView({
    required this.entry,
    required this.knowledgeExtracting,
    required this.subscriptionConfirmed,
    this.knowledgeError,
    this.onExtractKnowledge,
    this.onConfirmSubscription,
  });

  final _AgentConversationEntry entry;
  final bool knowledgeExtracting;
  final bool subscriptionConfirmed;
  final String? knowledgeError;
  final VoidCallback? onExtractKnowledge;
  final VoidCallback? onConfirmSubscription;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = entry.fromUser
        ? const Color(0xFF6B23FF)
        : entry.isError
        ? const Color(0xFFFFECEC)
        : Colors.white;
    final textColor = entry.fromUser
        ? Colors.white
        : entry.isError
        ? const Color(0xFF9E2929)
        : const Color(0xFF27242D);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: entry.fromUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: entry.fromUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: entry.fromUser
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
              ),
              child: Text(
                entry.text,
                style: TextStyle(color: textColor, height: 1.45),
              ),
            ),
          ),
          if (entry.cards.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...entry.cards.map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AgentContentCard(card: card),
              ),
            ),
          ],
          if (onExtractKnowledge != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('knowledge-extract-button'),
                onPressed: knowledgeExtracting ? null : onExtractKnowledge,
                icon: knowledgeExtracting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(knowledgeExtracting ? '正在提炼…' : '可提炼为知识（内部测试）'),
              ),
            ),
          ],
          if (knowledgeError != null) ...[
            const SizedBox(height: 6),
            Text(
              '$knowledgeError 可重试。',
              style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
            ),
          ],
          if (entry.subscriptionDraft != null) ...[
            const SizedBox(height: 2),
            _AgentSubscriptionPreviewCard(
              draft: entry.subscriptionDraft!,
              confirmed: subscriptionConfirmed,
              onConfirm: onConfirmSubscription,
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentContentCard extends StatelessWidget {
  const _AgentContentCard({required this.card});

  final AgentContentCardData card;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE9E5F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _AgentPill(label: card.source.name),
                if (card.isDemo) const _AgentPill(label: '演示数据', accent: true),
                if (card.aiGenerated) const _AgentPill(label: 'AI 辅助'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              card.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (card.excerpt.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                card.excerpt,
                style: const TextStyle(color: Color(0xFF68636E), height: 1.45),
              ),
            ],
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: Color(0xFF6B23FF),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card.recommendationReason,
                    style: const TextStyle(
                      color: Color(0xFF5E35B1),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showAgentSource(context, card),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('查看来源'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentPill extends StatelessWidget {
  const _AgentPill({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFFFFF0C2) : const Color(0xFFF1EEF5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent ? const Color(0xFF7B5200) : const Color(0xFF625C69),
        ),
      ),
    );
  }
}

Future<void> _showAgentSource(
  BuildContext context,
  AgentContentCardData card,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.source.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              card.source.url.isEmpty ? '暂无原文地址' : card.source.url,
              style: const TextStyle(color: Color(0xFF66616D)),
            ),
            if (card.isDemo) ...[
              const SizedBox(height: 10),
              const Text(
                '该卡片为内部演示，不代表已经取得外部平台数据或内容授权。',
                style: TextStyle(color: Color(0xFF8A5A00)),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: card.source.url.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: card.source.url),
                        );
                        if (context.mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制原文地址'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AgentSubscriptionPreviewCard extends StatelessWidget {
  const _AgentSubscriptionPreviewCard({
    required this.draft,
    required this.confirmed,
    this.onConfirm,
  });

  final AgentSubscriptionDraft draft;
  final bool confirmed;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: const Color(0xFFEEE8FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: Color(0xFF5E20D3),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    draft.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('主题：${draft.topics.join('、')}'),
            const SizedBox(height: 4),
            Text('频率：每天 ${draft.pushTime}，最多 ${draft.maxItems} 条'),
            const SizedBox(height: 4),
            const Text('默认排除未经核验的新闻和高风险内容'),
            if (draft.isDemo) ...[
              const SizedBox(height: 6),
              const Text(
                '内部演示订阅，不会发送真实通知',
                style: TextStyle(color: Color(0xFF8A5A00), fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey('confirm-agent-subscription-${draft.previewId}'),
                onPressed: confirmed ? null : onConfirm,
                child: Text(confirmed ? '已确认' : '确认创建订阅'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentSuggestions extends StatelessWidget {
  const _AgentSuggestions({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const suggestions = ['我想了解人工智能专业', '推荐一些专业探索方法', '每天晚上八点推送计算机专业内容'];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          label: Text(suggestions[index]),
          onPressed: () => onSelected(suggestions[index]),
        ),
      ),
    );
  }
}

class _AgentComposer extends StatelessWidget {
  const _AgentComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x22000000),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('agent-message-input'),
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: '说说你想了解的专业或话题…',
                    filled: true,
                    fillColor: const Color(0xFFF4F2F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('agent-send-button'),
                tooltip: '发送',
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentTypingIndicator extends StatelessWidget {
  const _AgentTypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class AgentSubscriptionsPage extends StatefulWidget {
  const AgentSubscriptionsPage({super.key});

  @override
  State<AgentSubscriptionsPage> createState() => _AgentSubscriptionsPageState();
}

class _AgentSubscriptionsPageState extends State<AgentSubscriptionsPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await AgentSubscriptionCenter.instance.refresh();
      if (mounted) setState(() => _error = null);
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订阅'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF8F7FB),
      body: AnimatedBuilder(
        animation: AgentSubscriptionCenter.instance,
        builder: (context, _) {
          final items = AgentSubscriptionCenter.instance.subscriptions;
          if (AgentSubscriptionCenter.instance.loading && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null && items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 52,
                      color: Color(0xFFA7A1AD),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '还没有内容订阅',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '在 Agent 对话中预览并确认后，订阅会显示在这里。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF77717D)),
                    ),
                  ],
                ),
              ),
            );
          }
          return AppConstrainedContent(
            maxWidth: AppLayout.phoneContentMaxWidth,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return _AgentSubscriptionTile(subscription: item);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AgentSubscriptionTile extends StatelessWidget {
  const _AgentSubscriptionTile({required this.subscription});

  final AgentSubscription subscription;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subscription.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  value: subscription.isActive,
                  onChanged: (_) async {
                    try {
                      await AgentSubscriptionCenter.instance.toggle(
                        subscription.id,
                      );
                    } on ApiRequestException catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  },
                ),
              ],
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: subscription.topics
                  .map((topic) => _AgentPill(label: topic))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Text(
              '每天 ${subscription.pushTime} · 最多推送 3 条${subscription.isDemo ? ' · 内部演示' : ''}',
              style: const TextStyle(color: Color(0xFF6E6875)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    _confirmDeleteAgentSubscription(context, subscription),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除订阅'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteAgentSubscription(
  BuildContext context,
  AgentSubscription subscription,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除订阅'),
      content: Text('确定删除“${subscription.name}”吗？删除后将停止对应内容提醒。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    try {
      await AgentSubscriptionCenter.instance.remove(subscription.id);
    } on ApiRequestException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
