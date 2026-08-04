part of 'main.dart';

abstract interface class KnowledgeExtractionGateway {
  Future<KnowledgeExtractionBatch> extract({
    required String conversationId,
    required String messageId,
    required String question,
    required String answer,
    required List<KnowledgeTreeSummary> availableTrees,
    required List<KnowledgeSourceRef> sourceRefs,
  });
}

/// 开发期知识提炼客户端；DeepSeek 密钥只存在服务端。
class KnowledgeExtractionService implements KnowledgeExtractionGateway {
  KnowledgeExtractionService({
    HttpClient? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient(),
       _baseUrl = baseUrl ?? AppConfig.contentSourceTestApiBaseUrl;

  static final instance = KnowledgeExtractionService();

  final HttpClient _client;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<KnowledgeExtractionBatch> extract({
    required String conversationId,
    required String messageId,
    required String question,
    required String answer,
    required List<KnowledgeTreeSummary> availableTrees,
    required List<KnowledgeSourceRef> sourceRefs,
  }) async {
    if (!AppConfig.developerToolsEnabled) {
      throw const ApiRequestException('知识提炼测试只能在开发环境使用。');
    }
    final normalizedBaseUrl = _normalizeBaseUrl(_baseUrl);
    if (normalizedBaseUrl.isEmpty) {
      throw const ApiRequestException('知识提炼后端地址未配置。');
    }

    try {
      final request = await _client.postUrl(
        Uri.parse('$normalizedBaseUrl/api/dev/knowledge/extract'),
      );
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode({
            'conversationId': conversationId.trim(),
            'messageId': messageId.trim(),
            'question': question.trim(),
            'answer': answer.trim(),
            'availableTrees': availableTrees
                .take(20)
                .map((tree) => tree.toJson())
                .toList(growable: false),
            'clientTraceId': _createTraceId(),
          }),
        ),
      );
      final response = await request.close().timeout(timeout);
      final responseText = await utf8.decodeStream(response).timeout(timeout);
      final decoded = responseText.isEmpty ? null : jsonDecode(responseText);
      final envelope = _knowledgeMap(decoded);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          envelope['ok'] != true) {
        throw ApiRequestException(
          AuthService._errorMessage(envelope),
          statusCode: response.statusCode,
        );
      }
      return _decodeEnvelope(envelope, sourceRefs: sourceRefs);
    } on ApiRequestException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '[KnowledgeExtraction] request failed: '
        '${error.runtimeType}\n$stackTrace',
      );
      _throwDecodedFailure(error, baseUrl: normalizedBaseUrl);
    }
  }

  @visibleForTesting
  static KnowledgeExtractionBatch decodeEnvelopeForTest(
    dynamic envelope, {
    required List<KnowledgeSourceRef> sourceRefs,
  }) {
    return _decodeEnvelope(_knowledgeMap(envelope), sourceRefs: sourceRefs);
  }

  @visibleForTesting
  static Never decodeFailureForTest(Object error) {
    return _throwDecodedFailure(error);
  }

  static KnowledgeExtractionBatch _decodeEnvelope(
    Map<String, dynamic> envelope, {
    required List<KnowledgeSourceRef> sourceRefs,
  }) {
    if (envelope['ok'] != true) {
      throw ApiRequestException(AuthService._errorMessage(envelope));
    }
    final data = AuthService._map(envelope['data']);
    if (data == null) {
      throw const ApiRequestException('知识提炼返回格式不正确。');
    }

    // 来源链接只继承自 App 已验证卡片，不采信模型输出中的 URL。
    return KnowledgeExtractionBatch.fromJson(
      data,
    ).copyWith(sourceRefs: sourceRefs);
  }

  static Never _throwDecodedFailure(Object error, {String? baseUrl}) {
    if (error is TimeoutException) {
      throw const ApiRequestException('知识提炼请求超时，请重试。');
    }
    if (error is SocketException) {
      final suffix = baseUrl == null || baseUrl.isEmpty ? '' : '（$baseUrl）';
      throw ApiRequestException('无法连接知识提炼服务$suffix。');
    }
    if (error is HttpException) {
      throw const ApiRequestException('知识提炼服务连接异常。');
    }
    if (error is FormatException) {
      throw const ApiRequestException('知识提炼返回了无法识别的数据。');
    }
    throw const ApiRequestException('知识提炼失败，请稍后重试。');
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String _createTraceId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final entropy = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return 'knowledge-$micros-$entropy';
  }
}
