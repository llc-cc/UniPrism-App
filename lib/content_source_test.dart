part of 'main.dart';

class ZhihuContentTestItem {
  const ZhihuContentTestItem({
    required this.id,
    required this.title,
    required this.contentText,
    required this.url,
    required this.contentType,
    required this.authorName,
    required this.authorBadgeText,
    required this.editTime,
    required this.commentCount,
    required this.voteUpCount,
    required this.authorityLevel,
    required this.rankingScore,
  });

  final String id;
  final String title;
  final String contentText;
  final String url;
  final String contentType;
  final String authorName;
  final String authorBadgeText;
  final DateTime? editTime;
  final int commentCount;
  final int voteUpCount;
  final String authorityLevel;
  final double rankingScore;

  factory ZhihuContentTestItem.fromJson(Map<String, dynamic> json) {
    return ZhihuContentTestItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      contentText: json['contentText']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? '',
      authorBadgeText: json['authorBadgeText']?.toString() ?? '',
      editTime: DateTime.tryParse(json['editTime']?.toString() ?? ''),
      commentCount: _contentSourceInt(json['commentCount']),
      voteUpCount: _contentSourceInt(json['voteUpCount']),
      authorityLevel: json['authorityLevel']?.toString() ?? '',
      rankingScore: _contentSourceDouble(json['rankingScore']),
    );
  }
}

class ZhihuContentTestResult {
  const ZhihuContentTestResult({
    required this.provider,
    required this.userQuestion,
    required this.recommendedMajors,
    required this.searchQuery,
    required this.intentSummary,
    required this.matchedMajors,
    required this.matchedInterests,
    required this.model,
    required this.retrievedAt,
    required this.items,
  });

  final String provider;
  final String userQuestion;
  final List<String> recommendedMajors;
  final String searchQuery;
  final String intentSummary;
  final List<String> matchedMajors;
  final List<String> matchedInterests;
  final String model;
  final DateTime? retrievedAt;
  final List<ZhihuContentTestItem> items;

  factory ZhihuContentTestResult.fromJson(Map<String, dynamic> json) {
    final plan = AuthService._map(json['queryPlan']) ?? const {};
    final sourceItems = json['items'];
    return ZhihuContentTestResult(
      provider: json['provider']?.toString() ?? '',
      userQuestion: json['userQuestion']?.toString() ?? '',
      recommendedMajors: _contentSourceStringList(
        json['recommendedMajors'],
      ),
      searchQuery: json['searchQuery']?.toString() ?? '',
      intentSummary: plan['intentSummary']?.toString() ?? '',
      matchedMajors: _contentSourceStringList(plan['matchedMajors']),
      matchedInterests: _contentSourceStringList(plan['matchedInterests']),
      model: plan['model']?.toString() ?? '',
      retrievedAt: DateTime.tryParse(json['retrievedAt']?.toString() ?? ''),
      items: sourceItems is List
          ? sourceItems
                .map(AuthService._map)
                .whereType<Map<String, dynamic>>()
                .map(ZhihuContentTestItem.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

int _contentSourceInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _contentSourceDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _contentSourceStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class ZhihuContentTestService {
  ZhihuContentTestService._();

  static final instance = ZhihuContentTestService._();
  final HttpClient _client = HttpClient();

  Future<ZhihuContentTestResult> search({
    required String question,
    List<String> recommendedMajors = const [],
    required List<String> interests,
    int count = 5,
  }) async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('该内容源测试只能在开发环境使用');
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
        Uri.parse('$normalizedBaseUrl/api/dev/content-sources/zhihu/search'),
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
        const Duration(seconds: 60),
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
        throw const ApiRequestException('内容源测试服务返回格式不正确');
      }
      return ZhihuContentTestResult.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('内容源测试服务连接超时');
    } on ApiRequestException {
      rethrow;
    } on FormatException {
      throw const ApiRequestException('内容源测试服务返回了无法识别的数据');
    } catch (error, stackTrace) {
      debugPrint(
        '[ZhihuContentTest] request failed: '
        '${error.runtimeType}: $error\n$stackTrace',
      );
      throw ApiRequestException(
        AppConfig.developerToolsEnabled
            ? '内容源测试处理失败：${error.runtimeType}：$error'
            : '无法连接内容源测试服务',
      );
    }
  }
}

class ZhihuContentTestPage extends StatefulWidget {
  const ZhihuContentTestPage({
    super.key,
    this.recommendedMajors = const [],
  });

  final List<String> recommendedMajors;

  @override
  State<ZhihuContentTestPage> createState() => _ZhihuContentTestPageState();
}

class _ZhihuContentTestPageState extends State<ZhihuContentTestPage> {
  final _questionController = TextEditingController(text: '人工智能专业就业前景');
  final _interestController = TextEditingController(text: '人工智能、专业选择、就业');
  late final List<String> _recommendedMajors;
  ZhihuContentTestResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _recommendedMajors = widget.recommendedMajors
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(5)
        .toList(growable: false);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_loading) return;
    final interests = _interestController.text
        .split(RegExp(r'[,，、\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList(growable: false);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ZhihuContentTestService.instance.search(
        question: _questionController.text,
        recommendedMajors: _recommendedMajors,
        interests: interests,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '测试失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知乎内容真实性测试')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5D8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '开发测试功能：DeepSeek 只把阶段推荐专业、你的问题和补充兴趣整理成搜索词；'
                '下方内容直接来自知乎官方开放平台，并保留作者与原文链接。',
                style: TextStyle(height: 1.5, color: Color(0xFF6D5012)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前测试后端：${AppConfig.contentSourceTestApiBaseUrl}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF756F7B)),
            ),
            const SizedBox(height: 18),
            Text(
              '当前阶段推荐专业',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_recommendedMajors.isEmpty)
              Container(
                key: const ValueKey('zhihu-recommended-majors-empty'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '暂未读取到阶段推荐专业。你仍可测试当前问题，完成一个测评阶段后从首页进入即可自动带入专业。',
                  style: TextStyle(height: 1.45, color: Color(0xFF625B69)),
                ),
              )
            else
              Wrap(
                key: const ValueKey('zhihu-recommended-majors'),
                spacing: 8,
                runSpacing: 8,
                children: _recommendedMajors
                    .map(
                      (major) => Chip(
                        avatar: const Icon(
                          Icons.school_outlined,
                          size: 17,
                        ),
                        label: Text(major),
                      ),
                    )
                    .toList(growable: false),
              ),
            const SizedBox(height: 18),
            TextField(
              controller: _questionController,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '你想了解什么',
                hintText: '例如：人工智能专业未来有哪些就业方向？',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _interestController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '补充兴趣标签（用逗号分隔）',
                hintText: '人工智能、升学规划、编程',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _loading ? null : _search,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(_loading ? '正在规划搜索并获取知乎内容…' : '获取真实知乎内容'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB3261E)),
                ),
              ),
            ],
            if (_result case final result?) ...[
              const SizedBox(height: 20),
              _ZhihuTestSummary(result: result),
              const SizedBox(height: 12),
              ...result.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ZhihuTestResultCard(item: item),
                ),
              ),
              if (result.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('知乎没有返回匹配内容，请换一种说法')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZhihuTestSummary extends StatelessWidget {
  const _ZhihuTestSummary({required this.result});

  final ZhihuContentTestResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本次检索说明',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('AI 生成搜索词：${result.searchQuery}'),
          if (result.intentSummary.isNotEmpty)
            Text('理解的需求：${result.intentSummary}'),
          if (result.matchedMajors.isNotEmpty)
            Text('结合的推荐专业：${result.matchedMajors.join('、')}'),
          if (result.matchedInterests.isNotEmpty)
            Text('采用的补充兴趣：${result.matchedInterests.join('、')}'),
          if (result.model.isNotEmpty) Text('搜索规划模型：${result.model}'),
          Text('真实来源结果：${result.items.length} 条'),
        ],
      ),
    );
  }
}

class _ZhihuTestResultCard extends StatelessWidget {
  const _ZhihuTestResultCard({required this.item});

  final ZhihuContentTestItem item;

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(item.editTime);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                const Chip(label: Text('知乎官方接口')),
                if (item.contentType.isNotEmpty)
                  Chip(label: Text(item.contentType)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title.isEmpty ? '知乎内容' : item.title,
              style: const TextStyle(
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (item.contentText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                item.contentText,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.55, color: Color(0xFF4D4855)),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              [
                if (item.authorName.isNotEmpty) '作者：${item.authorName}',
                if (item.authorBadgeText.isNotEmpty) item.authorBadgeText,
                if (date.isNotEmpty) date,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF756F7B)),
            ),
            const SizedBox(height: 4),
            Text(
              '赞同 ${item.voteUpCount} · 评论 ${item.commentCount}'
              ' · 排序分 ${item.rankingScore.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF756F7B)),
            ),
            if (item.url.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: item.url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('知乎原文链接已复制')));
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('复制原文链接'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
