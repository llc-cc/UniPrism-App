part of 'main.dart';

/// 开发期查看的一条已清洗数据库内容记录。
class ContentIngestionPreviewItem {
  const ContentIngestionPreviewItem({
    required this.id,
    required this.sourceName,
    required this.sourceCode,
    required this.title,
    required this.normalizedTitle,
    required this.url,
    required this.contentType,
    required this.authors,
    required this.tags,
    required this.cleanerVersion,
    required this.currentVersion,
    required this.rightsStatus,
    required this.reviewStatus,
    required this.lifecycleStatus,
    required this.lastSeenAt,
    required this.hasDocument,
  });

  final String id;
  final String sourceName;
  final String sourceCode;
  final String title;
  final String normalizedTitle;
  final String url;
  final String contentType;
  final List<String> authors;
  final List<String> tags;
  final String cleanerVersion;
  final int currentVersion;
  final String rightsStatus;
  final String reviewStatus;
  final String lifecycleStatus;
  final DateTime? lastSeenAt;
  final bool hasDocument;

  factory ContentIngestionPreviewItem.fromJson(Map<String, dynamic> json) {
    final source = json['source'] is Map<String, dynamic>
        ? json['source'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ContentIngestionPreviewItem(
      id: json['id']?.toString() ?? '',
      sourceName: source['displayName']?.toString() ?? '未知来源',
      sourceCode: source['code']?.toString() ?? '',
      title: json['originalTitle']?.toString() ?? '',
      normalizedTitle: json['normalizedTitle']?.toString() ?? '',
      url: json['canonicalUrl']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? '',
      authors: _ingestionStringList(json['authors']),
      tags: _ingestionStringList(json['tags']),
      cleanerVersion: json['cleanerVersion']?.toString() ?? '',
      currentVersion: _ingestionInt(json['currentVersion']),
      rightsStatus: json['rightsStatus']?.toString() ?? '',
      reviewStatus: json['reviewStatus']?.toString() ?? '',
      lifecycleStatus: json['lifecycleStatus']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
      hasDocument: json['document'] != null,
    );
  }
}

/// 入库统计与最近清洗内容记录组成的预览结果。
class ContentIngestionPreviewResult {
  const ContentIngestionPreviewResult({
    required this.sources,
    required this.batches,
    required this.items,
    required this.documents,
    required this.versions,
    required this.content,
  });

  final int sources;
  final int batches;
  final int items;
  final int documents;
  final int versions;
  final List<ContentIngestionPreviewItem> content;

  factory ContentIngestionPreviewResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawItems = json['items'] is List ? json['items'] as List : const [];
    return ContentIngestionPreviewResult(
      sources: _ingestionInt(summary['sources']),
      batches: _ingestionInt(summary['batches']),
      items: _ingestionInt(summary['items']),
      documents: _ingestionInt(summary['documents']),
      versions: _ingestionInt(summary['versions']),
      content: rawItems
          .whereType<Map<String, dynamic>>()
          .map(ContentIngestionPreviewItem.fromJson)
          .toList(growable: false),
    );
  }
}

List<String> _ingestionStringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _ingestionInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// 开发环境只读查看入库数量与清洗结果的服务，不包含写入操作。
class ContentIngestionPreviewService {
  ContentIngestionPreviewService._();

  static final instance = ContentIngestionPreviewService._();

  Future<ContentIngestionPreviewResult> load() async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('内容入库预览仅在开发环境开放');
    }
    final baseUrl = AppConfig.contentSourceTestApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const ApiRequestException('内容测试后端地址未配置');
    }
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.parse(
          '$normalizedBaseUrl/api/dev/content-ingestion/items?limit=20',
        ),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiRequestException('内容预览接口返回格式不正确');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final message = error is Map<String, dynamic>
            ? error['message']?.toString()
            : null;
        throw ApiRequestException(
          message?.trim().isNotEmpty == true ? message! : '内容预览请求失败',
          statusCode: response.statusCode,
        );
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        throw const ApiRequestException('内容预览数据为空');
      }
      return ContentIngestionPreviewResult.fromJson(data);
    } on TimeoutException {
      throw const ApiRequestException('内容预览服务连接超时');
    } on FormatException {
      throw const ApiRequestException('内容预览接口返回了无法识别的数据');
    } finally {
      client.close(force: true);
    }
  }
}

/// 开发期确认采集结果是否已写入数据库的页面。
class ContentIngestionPreviewPage extends StatefulWidget {
  const ContentIngestionPreviewPage({super.key});

  @override
  State<ContentIngestionPreviewPage> createState() =>
      _ContentIngestionPreviewPageState();
}

/// 负责加载和刷新预览数据，不提供任何写库能力。
class _ContentIngestionPreviewPageState
    extends State<ContentIngestionPreviewPage> {
  ContentIngestionPreviewResult? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ContentIngestionPreviewService.instance.load();
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '内容入库预览加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('内容入库预览'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            const Card(
              color: Color(0xFFF4F0FF),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  '这里展示真实来源经过后端清洗、去重并写入阿里云数据库后的结果。'
                  '当前仅用于开发联调，不代表内容已经审核或允许正式发布。',
                  style: TextStyle(height: 1.5, color: Color(0xFF493777)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '测试后端：${AppConfig.contentSourceTestApiBaseUrl}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            if (_loading && _result == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ContentPreviewError(message: _error!, onRetry: _load)
            else if (_result != null) ...[
              _ContentPreviewSummary(result: _result!),
              const SizedBox(height: 16),
              if (_result!.content.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('数据库中还没有测试内容')),
                  ),
                )
              else
                ..._result!.content.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ContentPreviewCard(item: item),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 汇总展示来源、批次、内容、正文和版本等表级数量。
class _ContentPreviewSummary extends StatelessWidget {
  const _ContentPreviewSummary({required this.result});

  final ContentIngestionPreviewResult result;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(label: '来源', value: result.sources),
        _SummaryChip(label: '批次', value: result.batches),
        _SummaryChip(label: '内容', value: result.items),
        _SummaryChip(label: '正文', value: result.documents),
        _SummaryChip(label: '版本', value: result.versions),
      ],
    );
  }
}

/// 入库汇总区域复用的数量标签。
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}

/// 只读展示一条标准化内容及其权限、审核状态。
class _ContentPreviewCard extends StatelessWidget {
  const _ContentPreviewCard({required this.item});

  final ContentIngestionPreviewItem item;

  String get _timeLabel {
    final value = item.lastSeenAt?.toLocal();
    if (value == null) return '时间未知';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(item.sourceName)),
                Chip(label: Text(item.lifecycleStatus)),
                Chip(label: Text('权利 ${item.rightsStatus}')),
                Chip(label: Text('审核 ${item.reviewStatus}')),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (item.normalizedTitle != item.title.toLowerCase()) ...[
              const SizedBox(height: 6),
              Text(
                '标准化标题：${item.normalizedTitle}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              [
                if (item.authors.isNotEmpty) '作者：${item.authors.join('、')}',
                '类型：${item.contentType}',
                '版本：${item.currentVersion}',
                '正文：${item.hasDocument ? '已保存' : '未保存'}',
                '最后发现：$_timeLabel',
              ].join('\n'),
              style: const TextStyle(height: 1.5),
            ),
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('标签：${item.tags.join('、')}'),
            ],
            const SizedBox(height: 10),
            Text(
              '清洗器：${item.cleanerVersion}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            SelectableText(
              item.url,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5420BF)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('原文链接已复制')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制原文链接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预览接口不可用时显示的错误与重试状态。
class _ContentPreviewError extends StatelessWidget {
  const _ContentPreviewError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF1F1),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
