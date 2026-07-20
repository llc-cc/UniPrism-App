part of 'main.dart';

class AppMessage {
  const AppMessage({
    required this.id,
    required this.source,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.route,
    this.reportId,
  });

  factory AppMessage.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['createdAt'];
    final createdAt = rawCreatedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(rawCreatedAt.toInt())
        : DateTime.tryParse('${rawCreatedAt ?? ''}') ?? DateTime.now();
    return AppMessage(
      id: '${json['id'] ?? ''}',
      source: '${json['source'] ?? 'system'}',
      title: '${json['title'] ?? '新消息'}',
      body: '${json['body'] ?? ''}',
      createdAt: createdAt,
      isRead: json['isRead'] == true,
      route: '${json['route'] ?? '/messages'}',
      reportId: json['reportId']?.toString(),
    );
  }

  final String id;
  final String source;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String route;
  final String? reportId;

  AppMessage copyWith({bool? isRead}) => AppMessage(
    id: id,
    source: source,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    route: route,
    reportId: reportId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'body': body,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'isRead': isRead,
    'route': route,
    if (reportId != null) 'reportId': reportId,
  };
}

class AppMessageCenter extends ChangeNotifier {
  AppMessageCenter._();

  static final instance = AppMessageCenter._();
  static const _storageKey = 'uniprism.messages';

  List<AppMessage> _messages = const [];

  List<AppMessage> get messages => List.unmodifiable(_messages);
  int get unreadCount => _messages.where((message) => !message.isRead).length;

  Future<void> restore() async {
    final stored = await AuthService._readStorage();
    final raw = stored[_storageKey]?.toString();
    final next = <AppMessage>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          next.addAll(
            decoded
                .whereType<Map>()
                .map(
                  (item) => AppMessage.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .where((message) => message.id.isNotEmpty),
          );
        }
      } catch (_) {
        // Corrupted local messages are ignored instead of blocking app startup.
      }
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _messages = next;
    notifyListeners();
  }

  Future<void> ingestRemotePayload(Map<String, dynamic> payload) async {
    await restore();
    final id = payload['messageId']?.toString();
    if (id == null || id.isEmpty) return;
    final message = AppMessage(
      id: id,
      source: payload['source']?.toString() ?? 'push',
      title: payload['title']?.toString() ?? '新消息',
      body: payload['body']?.toString() ?? '',
      createdAt: DateTime.now(),
      isRead: false,
      route: payload['route']?.toString() ?? '/messages',
      reportId: payload['reportId']?.toString(),
    );
    _messages = [
      message,
      ..._messages.where((item) => item.id != message.id),
    ].take(100).toList();
    await _persist();
  }

  Future<void> markRead(String messageId) async {
    await restore();
    var changed = false;
    _messages = _messages.map((message) {
      if (message.id != messageId || message.isRead) return message;
      changed = true;
      return message.copyWith(isRead: true);
    }).toList();
    if (changed) await _persist();
  }

  Future<void> markAllRead() async {
    await restore();
    if (_messages.every((message) => message.isRead)) return;
    _messages = _messages
        .map((message) => message.copyWith(isRead: true))
        .toList();
    await _persist();
  }

  Future<void> _persist() async {
    await AuthService._writeStorage({
      _storageKey: jsonEncode(
        _messages.map((message) => message.toJson()).toList(),
      ),
    });
    notifyListeners();
  }
}

class _MessageCenterButton extends StatefulWidget {
  const _MessageCenterButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_MessageCenterButton> createState() => _MessageCenterButtonState();
}

class _MessageCenterButtonState extends State<_MessageCenterButton>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AppMessageCenter.instance.restore());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(AppMessageCenter.instance.restore()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppMessageCenter.instance.restore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppMessageCenter.instance,
      builder: (context, _) {
        final unread = AppMessageCenter.instance.unreadCount;
        return IconButton(
          tooltip: '消息通知',
          onPressed:
              widget.onPressed ??
              () => Navigator.of(context).pushNamed('/messages'),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (unread > 0)
                Positioned(
                  right: -7,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF426F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MessageCenterPage extends StatefulWidget {
  const MessageCenterPage({super.key});

  @override
  State<MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<MessageCenterPage> {
  Timer? _refreshTimer;
  bool _scheduling = false;

  @override
  void initState() {
    super.initState();
    unawaited(AppMessageCenter.instance.restore());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(AppMessageCenter.instance.restore()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _scheduleTest(String source) async {
    if (_scheduling) return;
    setState(() => _scheduling = true);
    try {
      final granted = await ReportNotificationService.instance
          .requestPermission();
      await ReportNotificationService.instance.scheduleDemoMessage(
        source: source,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '测试消息已创建，约 10 秒后送达' : '消息已创建，但需要先允许系统通知权限'),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? '创建测试消息失败')));
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  Future<void> _openMessage(AppMessage message) async {
    await AppMessageCenter.instance.markRead(message.id);
    if (!mounted) return;
    if (message.route == '/report-result' &&
        (message.reportId ?? '').isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultPage(reportId: message.reportId!),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageDetailPage(message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: AppBar(
        title: const Text('消息通知'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F6FC),
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: () => AppMessageCenter.instance.markAllRead(),
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: AppConstrainedContent(
        child: AnimatedBuilder(
          animation: AppMessageCenter.instance,
          builder: (context, _) {
            final messages = AppMessageCenter.instance.messages;
            return RefreshIndicator(
              onRefresh: AppMessageCenter.instance.restore,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                children: [
                  if (AppConfig.developerToolsEnabled) ...[
                    _NotificationTestPanel(
                      scheduling: _scheduling,
                      onLocal: () => _scheduleTest('local'),
                      onPush: () => _scheduleTest('push_demo'),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      const Text(
                        '全部消息',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${messages.length} 条',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8B8493),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (messages.isEmpty)
                    const _EmptyMessageState()
                  else
                    ...messages.map(
                      (message) => _MessageTile(
                        message: message,
                        onTap: () => _openMessage(message),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTestPanel extends StatelessWidget {
  const _NotificationTestPanel({
    required this.scheduling,
    required this.onLocal,
    required this.onPush,
  });

  final bool scheduling;
  final VoidCallback onLocal;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6B23FF), Color(0xFF9864FF)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, color: Colors.white),
              SizedBox(width: 9),
              Text(
                '通知功能测试',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '测试消息约 10 秒后进入系统通知栏，同时保存到 App 消息中心。',
            style: TextStyle(
              color: Color(0xFFE9DFFF),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: scheduling ? null : onLocal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: const Text('本地通知'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: scheduling ? null : onPush,
                  style: FilledButton.styleFrom(
                    foregroundColor: const Color(0xFF6420E5),
                    backgroundColor: Colors.white,
                  ),
                  child: const Text('模拟推送'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '真实推送通道：待后续接入个推与服务器',
            style: TextStyle(color: Color(0xFFDCCBFF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessageState extends StatelessWidget {
  const _EmptyMessageState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 54),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 42,
            color: Color(0xFFC6BECE),
          ),
          SizedBox(height: 12),
          Text(
            '暂时没有消息',
            style: TextStyle(color: Color(0xFF81798B), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.onTap});

  final AppMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = _messageVisual(message.source);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: message.isRead ? Colors.white : const Color(0xFFF3ECFF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: config.$2,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(config.$1, color: config.$3, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: message.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!message.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF426F),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        message.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: Color(0xFF716A7A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatMessageTime(message.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9B94A3),
                        ),
                      ),
                    ],
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

class MessageDetailPage extends StatelessWidget {
  const MessageDetailPage({super.key, required this.message});

  final AppMessage message;

  @override
  Widget build(BuildContext context) {
    final config = _messageVisual(message.source);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: AppBar(
        title: const Text('消息详情'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F6FC),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppLayout.pagePadding(context)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: config.$2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(config.$1, color: config.$3),
                ),
                const SizedBox(height: 18),
                Text(
                  message.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  _formatMessageTime(message.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF978F9F),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  message.body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.75,
                    color: Color(0xFF5F5868),
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

(IconData, Color, Color) _messageVisual(String source) => switch (source) {
  'report' => (
    Icons.description_outlined,
    const Color(0xFFEADDFF),
    const Color(0xFF6B23FF),
  ),
  'push_demo' || 'push' => (
    Icons.cloud_outlined,
    const Color(0xFFDFF4FF),
    const Color(0xFF2584C7),
  ),
  _ => (
    Icons.notifications_none_rounded,
    const Color(0xFFFFEDDA),
    const Color(0xFFD97918),
  ),
};

String _formatMessageTime(DateTime value) {
  final now = DateTime.now();
  final difference = now.difference(value);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
}
