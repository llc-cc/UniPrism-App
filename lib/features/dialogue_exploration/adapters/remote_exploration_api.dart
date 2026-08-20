import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'guided_teaching_flow_dto.dart';
import 'remote_exploration_dto.dart';
import 'remote_turn_stream.dart';

export 'remote_turn_stream.dart';

/// 远程 1.2 接口边界；Widget 与 Controller 均不直接处理 URL、鉴权头或 JSON。
abstract interface class RemoteExplorationGateway {
  Future<List<LearningChapterCatalogItem>> listChapterCatalog();

  Future<LearningChapterOverviewSnapshot> getChapterOverview(String chapterId);

  Future<LearningEntrySnapshot> getEntry(String atomId);

  Future<RemoteLearningSessionSnapshot> createSession({
    String? atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
    RemoteFlowMode flowMode = RemoteFlowMode.openExploration,
    RemoteSessionEntryMode? entryMode,
  });

  Future<RemoteLearningSessionSnapshot?> restoreLatest();

  Future<List<RemoteLearningSessionSummary>> listSessions();

  Future<RemoteLearningSessionSnapshot> restoreSession(
    RemoteLearningSessionSummary summary,
  );

  Future<RemoteLearningSessionSnapshot> submitTurn({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot> createBranch({
    required String sessionId,
    required String parentNodeId,
    required String question,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot> backtrack({
    required String sessionId,
    required String targetNodeId,
    String? idempotencyKey,
  });

  Future<Map<String, Object?>> createMemoryCandidate({
    required String sessionId,
    required String nodeId,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot> submitPracticeAttempt({
    required String sessionId,
    required String practiceId,
    required String reasoning,
    required String answer,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
    required String sessionId,
    required String materialUsageId,
    required RemoteAssetEvent event,
    String? idempotencyKey,
  });

  /// 拉取当前教学阶段允许的模式菜单；服务端在非 MODE_SELECTION 阶段会返回 options=null。
  Future<RemoteTeachingModeOptionsSnapshot> getTeachingModeOptions({
    required String sessionId,
  });

  /// 提交学生选择的教学模式；skill 必须来自服务端返回的 modeMenuOptions。
  Future<RemoteLearningSessionSnapshot> selectTeachingMode({
    required String sessionId,
    required String skill,
    String? idempotencyKey,
  });

  Future<String> exportTree(String sessionId);
}

/// 可选流式能力独立于原 Gateway，避免要求既有测试替身同时实现新协议。
abstract interface class RemoteStreamingExplorationGateway {
  Stream<RemoteTurnStreamEvent> submitTurnStream({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  });
}

/// 由应用装配层提供的当前学习身份；Feature 不直接依赖 AuthService，避免账号逻辑反向进入 UI 模块。
final class RemoteExplorationIdentity {
  const RemoteExplorationIdentity({
    required this.exploreSessionId,
    this.bearerToken,
    this.anonymousId,
  });

  final String exploreSessionId;
  final String? bearerToken;
  final String? anonymousId;
}

typedef RemoteExplorationIdentityProvider =
    Future<RemoteExplorationIdentity> Function();

/// Web 端由 BrowserClient 自行创建匿名会话，避免调用依赖 dart:io 的应用身份链路。
RemoteExplorationIdentityProvider? remoteIdentityProviderForPlatform({
  required bool isWeb,
  required RemoteExplorationIdentityProvider nativeProvider,
}) => isWeb ? null : nativeProvider;

/// 用户可见的稳定远程错误；原始响应和堆栈不直接暴露给学生。
/// App 与 Web 共用的 1.2 HTTP 客户端；仅匿名标识和短期会话 ID 保存在本实例。
final class RemoteExplorationApi
    implements RemoteExplorationGateway, RemoteStreamingExplorationGateway {
  RemoteExplorationApi({
    http.Client? client,
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3000',
    ),
    this.timeout = const Duration(seconds: 35),
    this.identityProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;
  final RemoteExplorationIdentityProvider? identityProvider;
  String? _anonymousId;
  String? _exploreSessionId;
  String? _bearerToken;

  @override
  Future<List<LearningChapterCatalogItem>> listChapterCatalog() async {
    final items = await _requestList('GET', '/api/learning-chapters');
    // 目录的单条脏数据不应阻断用户恢复既有学习会话。
    return List.unmodifiable(
      items
          .map(LearningChapterCatalogItem.tryFromJson)
          .whereType<LearningChapterCatalogItem>(),
    );
  }

  @override
  Future<LearningChapterOverviewSnapshot> getChapterOverview(
    String chapterId,
  ) async {
    final data = await _request(
      'GET',
      '/api/learning-chapters/${Uri.encodeComponent(chapterId)}',
    );
    return LearningChapterOverviewSnapshot.fromJson(data);
  }

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async {
    final data = await _request(
      'GET',
      '/api/learning-entries?atomId=${Uri.encodeQueryComponent(atomId)}',
    );
    return LearningEntrySnapshot.fromJson(data);
  }

  @override
  Future<RemoteLearningSessionSnapshot> createSession({
    String? atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
    RemoteFlowMode flowMode = RemoteFlowMode.openExploration,
    RemoteSessionEntryMode? entryMode,
  }) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'POST',
      '/api/learning-sessions',
      body: {
        'exploreSessionId': exploreSessionId,
        if ((atomId ?? '').isNotEmpty) 'atomId': atomId,
        'scenarioId': scenarioId,
        'flowMode': flowMode.wireValue,
        if ((directionId ?? '').isNotEmpty) 'directionId': directionId,
        if ((question ?? '').trim().isNotEmpty) 'question': question!.trim(),
        if (entryMode != null) 'entryMode': entryMode.wireValue,
      },
      idempotencyKey: idempotencyKey,
    );
    final snapshot = RemoteLearningSessionSnapshot.fromJson(data);
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async {
    final history = await listSessions();
    RemoteLearningSessionSummary? latest;
    for (final summary in history) {
      if (summary.canContinue) {
        latest = summary;
        break;
      }
    }
    if (latest == null) return null;
    return restoreSession(latest);
  }

  @override
  Future<List<RemoteLearningSessionSummary>> listSessions() async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/learning-sessions'
          '?exploreSessionId=${Uri.encodeQueryComponent(exploreSessionId)}'
          '&scenarioId=prestudy&limit=20',
    );
    final rawItems = data['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .map((item) => RemoteLearningSessionSummary.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  @override
  Future<RemoteLearningSessionSnapshot> restoreSession(
    RemoteLearningSessionSummary summary,
  ) async {
    await _ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/learning-sessions/${Uri.encodeComponent(summary.id)}'
          '?exploreSessionId=${Uri.encodeQueryComponent(summary.exploreSessionId)}',
    );
    return RemoteLearningSessionSnapshot.fromJson(data);
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitTurn({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  }) {
    final body = <String, Object?>{'question': question.trim()};
    if (parentNodeId != null) {
      body['parentNodeId'] = parentNodeId;
    }
    return _mutateSnapshot(sessionId, 'turns', body, idempotencyKey);
  }

  @override
  Stream<RemoteTurnStreamEvent> submitTurnStream({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  }) {
    late final StreamController<RemoteTurnStreamEvent> controller;
    StreamSubscription<RemoteTurnStreamEvent>? subscription;
    var cancelled = false;

    controller = StreamController<RemoteTurnStreamEvent>(
      onListen: () {
        () async {
          try {
            // 身份获取和响应头都受同一超时约束，避免连接态无限等待。
            final exploreSessionId = await _ensureExploreSession().timeout(timeout);
            if (cancelled) return;
            final body = <String, Object?>{
              'exploreSessionId': exploreSessionId,
              'question': question.trim(),
            };
            if (parentNodeId != null) body['parentNodeId'] = parentNodeId;
            final request = _buildRequest(
              'POST',
              '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/turns/stream',
              body: body,
              idempotencyKey: idempotencyKey,
            );
            final streamed = await _client.send(request).timeout(timeout);
            if (cancelled) return;
            if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
              final response = await http.Response.fromStream(streamed).timeout(timeout);
              throw _responseException(response);
            }
            // 每次字节到达都会重置超时，首段答案不必等到流关闭才可见。
            final decoded = decodeRemoteTurnSse(
              streamed.stream.timeout(
                timeout,
                onTimeout: (sink) {
                  sink.addError(const RemoteExplorationException('AI 老师响应超时，请重试。'));
                  sink.close();
                },
              ),
            );
            subscription = decoded.listen(
              controller.add,
              onError: (Object error, StackTrace stackTrace) {
                if (!cancelled) controller.addError(_streamException(error), stackTrace);
                unawaited(subscription?.cancel() ?? Future<void>.value());
                if (!cancelled) unawaited(controller.close());
              },
              onDone: () {
                if (!cancelled) unawaited(controller.close());
              },
            );
          } on TimeoutException {
            if (!cancelled) {
              controller.addError(const RemoteExplorationException('AI 老师响应超时，请重试。'));
              await controller.close();
            }
          } catch (error) {
            if (!cancelled) {
              controller.addError(_streamException(error));
              await controller.close();
            }
          }
        }();
      },
      onCancel: () async {
        // 页面离开时只取消本次订阅，不关闭由应用层复用的 HTTP Client。
        cancelled = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<RemoteLearningSessionSnapshot> createBranch({
    required String sessionId,
    required String parentNodeId,
    required String question,
    String? idempotencyKey,
  }) {
    return _mutateSnapshot(sessionId, 'branches', {
      'parentNodeId': parentNodeId,
      'question': question.trim(),
    }, idempotencyKey);
  }

  @override
  Future<RemoteLearningSessionSnapshot> backtrack({
    required String sessionId,
    required String targetNodeId,
    String? idempotencyKey,
  }) {
    return _mutateSnapshot(sessionId, 'backtracks', {
      'targetNodeId': targetNodeId,
    }, idempotencyKey);
  }

  @override
  Future<Map<String, Object?>> createMemoryCandidate({
    required String sessionId,
    required String nodeId,
    String? idempotencyKey,
  }) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'POST',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/memory-candidates',
      body: {'exploreSessionId': exploreSessionId, 'nodeId': nodeId},
      idempotencyKey: idempotencyKey,
    );
    return data.map((key, value) => MapEntry(key, value as Object?));
  }

  @override
  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  }) {
    return _mutateSnapshot(sessionId, 'complete', {
      'reflection': reflection.trim(),
    }, idempotencyKey);
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitPracticeAttempt({
    required String sessionId,
    required String practiceId,
    required String reasoning,
    required String answer,
    String? idempotencyKey,
  }) {
    return _mutateSnapshot(sessionId, 'practice-attempts', {
      'practiceId': practiceId,
      'reasoning': reasoning.trim(),
      'answer': answer.trim(),
    }, idempotencyKey);
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
    required String sessionId,
    required String materialUsageId,
    required RemoteAssetEvent event,
    String? idempotencyKey,
  }) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'POST',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}'
          '/materials/${Uri.encodeComponent(materialUsageId)}/events',
      body: {'exploreSessionId': exploreSessionId, ...event.toJson()},
      idempotencyKey: idempotencyKey,
    );
    return RemoteLearningSessionSnapshot.fromJson(data);
  }

  @override
  Future<RemoteTeachingModeOptionsSnapshot> getTeachingModeOptions({
    required String sessionId,
  }) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/teaching-mode'
          '?exploreSessionId=${Uri.encodeQueryComponent(exploreSessionId)}',
    );
    return RemoteTeachingModeOptionsSnapshot.fromJson(data);
  }

  @override
  Future<RemoteLearningSessionSnapshot> selectTeachingMode({
    required String sessionId,
    required String skill,
    String? idempotencyKey,
  }) {
    // 客户端不做技能白名单校验，交由服务端拒绝非法值，避免两端规则漂移。
    return _mutateSnapshot(sessionId, 'teaching-mode', {
      'skill': skill,
    }, idempotencyKey);
  }

  @override
  Future<String> exportTree(String sessionId) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'GET',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/export'
          '?exploreSessionId=${Uri.encodeQueryComponent(exploreSessionId)}',
    );
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<RemoteLearningSessionSnapshot> _mutateSnapshot(
    String sessionId,
    String action,
    Map<String, Object?> body,
    String? idempotencyKey,
  ) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'POST',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/$action',
      body: {'exploreSessionId': exploreSessionId, ...body},
      idempotencyKey: idempotencyKey,
    );
    return RemoteLearningSessionSnapshot.fromJson(data);
  }

  Future<String> _ensureExploreSession() async {
    final provider = identityProvider;
    if (provider != null) {
      final identity = await provider();
      _exploreSessionId = identity.exploreSessionId;
      _anonymousId = identity.anonymousId;
      _bearerToken = identity.bearerToken;
      return identity.exploreSessionId;
    }
    final existing = _exploreSessionId;
    if (existing != null) return existing;
    final data = await _request(
      'POST',
      '/api/explore/session',
      body: {if (_anonymousId != null) 'anonymousId': _anonymousId},
    );
    final id = data['sessionId']?.toString();
    if (id == null || id.isEmpty) {
      throw const RemoteExplorationException('无法创建学习身份，请稍后重试。');
    }
    _exploreSessionId = id;
    final anonymousId = data['anonymousId']?.toString();
    if (anonymousId != null && anonymousId.isNotEmpty) {
      _anonymousId = anonymousId;
    }
    return id;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    try {
      return _asMap(
        await _requestData(
          method,
          path,
          body: body,
          idempotencyKey: idempotencyKey,
        ),
      );
    } on FormatException {
      // 成功 envelope 的 data 形状也属于远程契约，不能向 UI 泄漏底层解析异常。
      throw const RemoteExplorationException('服务端返回格式不正确。');
    }
  }

  Future<List<dynamic>> _requestList(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    try {
      return _asList(
        await _requestData(
          method,
          path,
          body: body,
          idempotencyKey: idempotencyKey,
        ),
      );
    } on FormatException {
      // 仅转换已获得的响应，不重发请求，保持原有认证与超时边界。
      throw const RemoteExplorationException('服务端返回格式不正确。');
    }
  }

  /// 统一保留认证、超时和 envelope 错误语义；不同 endpoint 仅在此后选择 map 或 list 数据形状。
  Future<Object?> _requestData(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$_baseUrl$path'));
      final headers = <String, String>{
        'content-type': 'application/json',
        'x-miniapp-client': 'uniprism-weapp',
        if (method != 'GET')
          'idempotency-key': idempotencyKey ?? _traceId('learning'),
      };
      final bearerToken = _bearerToken;
      if (bearerToken != null && bearerToken.isNotEmpty) {
        headers['authorization'] = 'Bearer $bearerToken';
      }
      final anonymousId = _anonymousId;
      if (anonymousId != null) {
        headers['x-anonymous-id'] = anonymousId;
      }
      request.headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      final decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final envelope = _asMap(decoded);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          envelope['ok'] == false) {
        final error = _asMapOrEmpty(envelope['error']);
        throw RemoteExplorationException(
          error['message']?.toString() ??
              envelope['message']?.toString() ??
              '请求失败，请重试。',
          code: error['code']?.toString(),
          statusCode: response.statusCode,
        );
      }
      final rawData = envelope['ok'] == true ? envelope['data'] : envelope;
      return rawData;
    } on RemoteExplorationException {
      rethrow;
    } on TimeoutException {
      throw const RemoteExplorationException('AI 老师响应超时，请重试。');
    } on FormatException {
      throw const RemoteExplorationException('服务端返回格式不正确。');
    } catch (_) {
      throw RemoteExplorationException('无法连接学习服务（$_baseUrl）。');
    }
  }

  http.Request _buildRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    final headers = <String, String>{
      'content-type': 'application/json',
      'x-miniapp-client': 'uniprism-weapp',
      if (method != 'GET')
        'idempotency-key': idempotencyKey ?? _traceId('learning'),
    };
    final bearerToken = _bearerToken;
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $bearerToken';
    }
    final anonymousId = _anonymousId;
    if (anonymousId != null) headers['x-anonymous-id'] = anonymousId;
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return request;
  }

  RemoteExplorationException _responseException(http.Response response) {
    final envelope = _asMap(jsonDecode(response.body));
    final error = _asMapOrEmpty(envelope['error']);
    return RemoteExplorationException(
      error['message']?.toString() ??
          envelope['message']?.toString() ??
          '请求失败，请重试。',
      code: error['code']?.toString(),
      statusCode: response.statusCode,
    );
  }

  RemoteExplorationException _streamException(Object error) {
    if (error is RemoteExplorationException) return error;
    if (error is TimeoutException) {
      return const RemoteExplorationException('AI 老师响应超时，请重试。');
    }
    if (error is FormatException) {
      return const RemoteExplorationException('服务端返回格式不正确。');
    }
    return RemoteExplorationException('无法连接学习服务（$_baseUrl）。');
  }

  static String _traceId(String prefix) {
    final entropy = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$entropy';
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw const FormatException('响应不是 JSON 对象');
}

List<dynamic> _asList(Object? value) {
  if (value is List) return List<dynamic>.from(value, growable: false);
  throw const FormatException('响应不是 JSON 数组');
}

Map<String, dynamic> _asMapOrEmpty(Object? value) {
  if (value == null) return const {};
  return _asMap(value);
}
