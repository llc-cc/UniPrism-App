part of 'main.dart';

class MultiContentItem {
  const MultiContentItem({
    required this.title,
    required this.summary,
    required this.url,
    required this.kind,
    required this.authors,
    required this.tags,
    required this.publishedAt,
    required this.metrics,
  });

  final String title;
  final String summary;
  final String url;
  final String kind;
  final List<String> authors;
  final List<String> tags;
  final DateTime? publishedAt;
  final Map<String, dynamic> metrics;

  factory MultiContentItem.fromJson(Map<String, dynamic> json) {
    return MultiContentItem(
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      authors: _contentSourceStringList(json['authors']),
      tags: _contentSourceStringList(json['tags']),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      metrics: AuthService._map(json['metrics']) ?? const {},
    );
  }
}

class MultiContentSource {
  const MultiContentSource({
    required this.provider,
    required this.displayName,
    required this.status,
    required this.authMode,
    required this.query,
    required this.total,
    required this.latencyMs,
    required this.message,
    required this.items,
  });

  final String provider;
  final String displayName;
  final String status;
  final String authMode;
  final String query;
  final int total;
  final int latencyMs;
  final String message;
  final List<MultiContentItem> items;

  factory MultiContentSource.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return MultiContentSource(
      provider: json['provider']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      status: json['status']?.toString() ?? 'failed',
      authMode: json['authMode']?.toString() ?? '',
      query: json['query']?.toString() ?? '',
      total: _contentSourceInt(json['total']),
      latencyMs: _contentSourceInt(json['latencyMs']),
      message: json['message']?.toString() ?? '',
      items: rawItems is List
          ? rawItems
                .map(AuthService._map)
                .whereType<Map<String, dynamic>>()
                .map(MultiContentItem.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

class MultiContentSourceResult {
  const MultiContentSourceResult({
    required this.intentSummary,
    required this.model,
    required this.usedFallback,
    required this.queries,
    required this.successCount,
    required this.configurationRequiredCount,
    required this.failedCount,
    required this.itemCount,
    required this.latencyMs,
    required this.sources,
  });

  final String intentSummary;
  final String model;
  final bool usedFallback;
  final Map<String, dynamic> queries;
  final int successCount;
  final int configurationRequiredCount;
  final int failedCount;
  final int itemCount;
  final int latencyMs;
  final List<MultiContentSource> sources;

  factory MultiContentSourceResult.fromJson(Map<String, dynamic> json) {
    final plan = AuthService._map(json['queryPlan']) ?? const {};
    final summary = AuthService._map(json['sourceSummary']) ?? const {};
    final rawSources = json['sources'];
    return MultiContentSourceResult(
      intentSummary: plan['intentSummary']?.toString() ?? '',
      model: plan['model']?.toString() ?? '',
      usedFallback: plan['usedFallback'] == true,
      queries: AuthService._map(plan['queries']) ?? const {},
      successCount: _contentSourceInt(summary['success']),
      configurationRequiredCount:
          _contentSourceInt(summary['configurationRequired']),
      failedCount: _contentSourceInt(summary['failed']),
      itemCount: _contentSourceInt(summary['itemCount']),
      latencyMs: _contentSourceInt(json['latencyMs']),
      sources: rawSources is List
          ? rawSources
                .map(AuthService._map)
                .whereType<Map<String, dynamic>>()
                .map(MultiContentSource.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

class MultiContentSourceTestService {
  MultiContentSourceTestService._();

  static final instance = MultiContentSourceTestService._();
  final HttpClient _client = HttpClient();

  Future<MultiContentSourceResult> search({
    required String question,
    List<String> recommendedMajors = const [],
    required List<String> interests,
    int count = 3,
  }) async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('多来源内容测试只能在开发环境使用');
    }
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.length < 2) {
      throw const ApiRequestException('请至少输入 2 个字的问题');
    }
    final baseUrl = AppConfig.contentSourceTestApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const ApiRequestException('内容源测试后端地址未配置');
    }
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    try {
      final request = await _client.postUrl(
        Uri.parse(
          '$normalizedBaseUrl/api/dev/content-sources/multi/search',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode({
            'question': normalizedQuestion,
            'recommendedMajors': recommendedMajors,
            'interests': interests,
            'count': count,
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
        throw const ApiRequestException('多来源内容返回格式不正确');
      }
      return MultiContentSourceResult.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('多来源内容测试连接超时');
    } on ApiRequestException {
      rethrow;
    } on FormatException {
      throw const ApiRequestException('多来源内容返回了无法识别的数据');
    } catch (error, stackTrace) {
      debugPrint(
        '[MultiContentSourceTest] request failed: '
        '${error.runtimeType}: $error\n$stackTrace',
      );
      throw ApiRequestException(
        '多来源内容测试失败：${error.runtimeType}：$error',
      );
    }
  }
}

class MultiContentSourceTestPage extends StatefulWidget {
  const MultiContentSourceTestPage({
    super.key,
    this.recommendedMajors = const [],
  });

  final List<String> recommendedMajors;

  @override
  State<MultiContentSourceTestPage> createState() =>
      _MultiContentSourceTestPageState();
}

class _MultiContentSourceTestPageState
    extends State<MultiContentSourceTestPage> {
  final _questionController = TextEditingController(
    text: '我想了解人工智能专业的研究、技能、职业和近期科技热点',
  );
  final _interestController = TextEditingController(
    text: '机器学习，编程，项目实践',
  );
  late final List<String> _recommendedMajors;
  MultiContentSourceResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _recommendedMajors = widget.recommendedMajors;
  }

  @override
  void dispose() {
    _questionController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  List<String> _interests() => _interestController.text
      .split(RegExp(r'[,，、;\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(10)
      .toList(growable: false);

  Future<void> _search() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await MultiContentSourceTestService.instance.search(
        question: _questionController.text,
        recommendedMajors: _recommendedMajors,
        interests: _interests(),
      );
      if (mounted) setState(() => _result = result);
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('棱镜 Agent 多来源测试'),
        backgroundColor: const Color(0xFFFAF7FF),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '一次调用 Crossref、ESCO、O*NET、Hacker News。'
              '每个平台独立返回；未配置 O*NET Key 不会影响其他来源。',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '当前测试后端：${AppConfig.contentSourceTestApiBaseUrl}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          const Text(
            '当前阶段推荐专业',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _recommendedMajors.isEmpty
                ? '暂未获取推荐专业，本次仅使用问题和兴趣标签'
                : _recommendedMajors.join('、'),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _questionController,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '你想了解什么',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _interestController,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: '补充兴趣标签（用逗号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _search,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.hub_outlined),
            label: Text(_loading ? '正在并行查询…' : '查询四个真实来源'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xFF6A52A3),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _MultiSourceNotice(
              color: const Color(0xFFFFE8E8),
              text: _error!,
            ),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 16),
            _MultiSourceSummary(result: result),
            const SizedBox(height: 12),
            ...result.sources.map(
              (source) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MultiSourceSection(source: source),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MultiSourceNotice extends StatelessWidget {
  const _MultiSourceNotice({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}

class _MultiSourceSummary extends StatelessWidget {
  const _MultiSourceSummary({required this.result});

  final MultiContentSourceResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本次聚合说明',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(result.intentSummary),
          Text('规划模型：${result.model}${result.usedFallback ? '（本地规则兜底）' : ''}'),
          Text(
            '成功 ${result.successCount} · 待配置 '
            '${result.configurationRequiredCount} · 失败 '
            '${result.failedCount} · 内容 ${result.itemCount} 条',
          ),
          Text('总耗时：${result.latencyMs}ms'),
        ],
      ),
    );
  }
}

class _MultiSourceSection extends StatelessWidget {
  const _MultiSourceSection({required this.source});

  final MultiContentSource source;

  Color get _statusColor => switch (source.status) {
        'success' => const Color(0xFFE9F8EE),
        'configuration_required' => const Color(0xFFFFF2D4),
        _ => const Color(0xFFFFE8E8),
      };

  String get _statusText => switch (source.status) {
        'success' => '成功',
        'configuration_required' => '待配置',
        _ => '失败',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4DDF2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusText),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '检索词：${source.query}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Text(
            '鉴权：${source.authMode} · 总量：${source.total} · '
            '${source.latencyMs}ms',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (source.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MultiSourceNotice(color: _statusColor, text: source.message),
          ],
          ...source.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _MultiSourceItemCard(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiSourceItemCard extends StatelessWidget {
  const _MultiSourceItemCard({required this.item});

  final MultiContentItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (item.summary.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              item.summary,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black87),
            ),
          ],
          if (item.authors.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              item.authors.join('、'),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                item.kind,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: item.url.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: item.url),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('原始来源链接已复制')),
                        );
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制来源'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
