part of 'main.dart';

class GitHubContentTestRepository {
  const GitHubContentTestRepository({
    required this.id,
    required this.fullName,
    required this.description,
    required this.url,
    required this.ownerName,
    required this.language,
    required this.stars,
    required this.forks,
    required this.openIssues,
    required this.topics,
    required this.updatedAt,
    required this.archived,
    required this.license,
  });

  final String id;
  final String fullName;
  final String description;
  final String url;
  final String ownerName;
  final String language;
  final int stars;
  final int forks;
  final int openIssues;
  final List<String> topics;
  final DateTime? updatedAt;
  final bool archived;
  final String license;

  factory GitHubContentTestRepository.fromJson(Map<String, dynamic> json) {
    return GitHubContentTestRepository(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      stars: _contentSourceInt(json['stars']),
      forks: _contentSourceInt(json['forks']),
      openIssues: _contentSourceInt(json['openIssues']),
      topics: _contentSourceStringList(json['topics']),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      archived: json['archived'] == true,
      license: json['license']?.toString() ?? '',
    );
  }
}

class GitHubContentTestResult {
  const GitHubContentTestResult({
    required this.searchQuery,
    required this.intentSummary,
    required this.matchedMajors,
    required this.matchedInterests,
    required this.model,
    required this.totalCount,
    required this.authenticated,
    required this.rateLimitRemaining,
    required this.repositories,
  });

  final String searchQuery;
  final String intentSummary;
  final List<String> matchedMajors;
  final List<String> matchedInterests;
  final String model;
  final int totalCount;
  final bool authenticated;
  final int rateLimitRemaining;
  final List<GitHubContentTestRepository> repositories;

  factory GitHubContentTestResult.fromJson(Map<String, dynamic> json) {
    final plan = AuthService._map(json['queryPlan']) ?? const {};
    final rateLimit = AuthService._map(json['rateLimit']) ?? const {};
    final items = json['items'];
    return GitHubContentTestResult(
      searchQuery: json['searchQuery']?.toString() ?? '',
      intentSummary: plan['intentSummary']?.toString() ?? '',
      matchedMajors: _contentSourceStringList(plan['matchedMajors']),
      matchedInterests: _contentSourceStringList(plan['matchedInterests']),
      model: plan['model']?.toString() ?? '',
      totalCount: _contentSourceInt(json['totalCount']),
      authenticated: json['authenticated'] == true,
      rateLimitRemaining: _contentSourceInt(rateLimit['remaining']),
      repositories: items is List
          ? items
                .map(AuthService._map)
                .whereType<Map<String, dynamic>>()
                .map(GitHubContentTestRepository.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

class GitHubContentTestService {
  GitHubContentTestService._();

  static final instance = GitHubContentTestService._();
  final HttpClient _client = HttpClient();

  Future<GitHubContentTestResult> search({
    required String question,
    List<String> recommendedMajors = const [],
    required List<String> interests,
    int count = 5,
  }) async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('该 GitHub 内容源测试只能在开发环境使用');
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
          '$normalizedBaseUrl/api/dev/content-sources/github/search',
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
        // Next.js may spend more than one minute compiling a newly added
        // development route on the first request. Production requests do not
        // have this cold-compile cost, but this test page should not disconnect
        // while that one-time compile is still running.
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
        throw const ApiRequestException('GitHub 内容源返回格式不正确');
      }
      return GitHubContentTestResult.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('GitHub 内容源测试服务连接超时');
    } on ApiRequestException {
      rethrow;
    } on FormatException {
      throw const ApiRequestException('GitHub 内容源返回了无法识别的数据');
    } catch (error, stackTrace) {
      debugPrint(
        '[GitHubContentTest] request failed: '
        '${error.runtimeType}: $error\n$stackTrace',
      );
      throw ApiRequestException(
        AppConfig.developerToolsEnabled
            ? 'GitHub 内容源测试失败：${error.runtimeType}：$error'
            : '无法连接 GitHub 内容源测试服务',
      );
    }
  }
}

class GitHubContentTestPage extends StatefulWidget {
  const GitHubContentTestPage({
    super.key,
    this.recommendedMajors = const [],
  });

  final List<String> recommendedMajors;

  @override
  State<GitHubContentTestPage> createState() =>
      _GitHubContentTestPageState();
}

class _GitHubContentTestPageState extends State<GitHubContentTestPage> {
  final _questionController = TextEditingController(
    text: '我想体验人工智能专业相关的开源项目',
  );
  final _interestController = TextEditingController(
    text: '人工智能、编程、项目实践',
  );
  late final List<String> _recommendedMajors;
  GitHubContentTestResult? _result;
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
      final result = await GitHubContentTestService.instance.search(
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
      setState(() => _error = 'GitHub 测试失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub 内容真实性测试')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '开发测试功能：DeepSeek 只生成公开仓库检索词；'
                '仓库名称、描述、Star、语言、许可证和链接直接来自 GitHub 官方 REST API。',
                style: TextStyle(height: 1.5, color: Color(0xFF23466F)),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '暂未读取到阶段推荐专业，仍可先用当前问题和补充兴趣测试公开仓库搜索。',
                  style: TextStyle(height: 1.45, color: Color(0xFF625B69)),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recommendedMajors
                    .map(
                      (major) => Chip(
                        avatar: const Icon(Icons.school_outlined, size: 17),
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
                labelText: '你想寻找什么项目',
                hintText: '例如：人工智能专业有哪些适合学生体验的开源项目？',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _interestController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '补充兴趣标签（用逗号分隔）',
                hintText: '人工智能、编程、项目实践',
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
                  : const Icon(Icons.code_rounded),
              label: Text(
                _loading ? '正在规划并搜索 GitHub…' : '获取真实 GitHub 仓库',
              ),
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
              _GitHubTestSummary(result: result),
              const SizedBox(height: 12),
              ...result.repositories.map(
                (repository) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GitHubRepositoryCard(repository: repository),
                ),
              ),
              if (result.repositories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('GitHub 没有返回匹配仓库，请换一种说法')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GitHubTestSummary extends StatelessWidget {
  const _GitHubTestSummary({required this.result});

  final GitHubContentTestResult result;

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
          Text('GitHub 匹配总数：${result.totalCount}'),
          Text(
            result.authenticated
                ? 'GitHub 调用：已使用后端 Token'
                : 'GitHub 调用：公开匿名额度',
          ),
          if (result.rateLimitRemaining > 0)
            Text('当前剩余额度：${result.rateLimitRemaining}'),
          Text('本次展示：${result.repositories.length} 个公开仓库'),
        ],
      ),
    );
  }
}

class _GitHubRepositoryCard extends StatelessWidget {
  const _GitHubRepositoryCard({required this.repository});

  final GitHubContentTestRepository repository;

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final updatedAt = _formatDate(repository.updatedAt);
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
                const Chip(label: Text('GitHub 官方接口')),
                if (repository.language.isNotEmpty)
                  Chip(label: Text(repository.language)),
                if (repository.license.isNotEmpty)
                  Chip(label: Text(repository.license)),
                if (repository.archived)
                  const Chip(label: Text('已归档')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              repository.fullName.isEmpty ? 'GitHub 仓库' : repository.fullName,
              style: const TextStyle(
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (repository.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                repository.description,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.55, color: Color(0xFF4D4855)),
              ),
            ],
            if (repository.topics.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                repository.topics.take(6).map((topic) => '#$topic').join('  '),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5A3FA0),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              [
                if (repository.ownerName.isNotEmpty)
                  '作者：${repository.ownerName}',
                if (updatedAt.isNotEmpty) '更新：$updatedAt',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF756F7B)),
            ),
            const SizedBox(height: 4),
            Text(
              'Star ${repository.stars} · Fork ${repository.forks}'
              ' · Issues ${repository.openIssues}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF756F7B)),
            ),
            if (repository.url.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: repository.url),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('GitHub 仓库链接已复制')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('复制仓库链接'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
