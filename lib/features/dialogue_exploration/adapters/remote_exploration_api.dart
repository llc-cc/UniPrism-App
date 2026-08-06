import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'remote_exploration_dto.dart';

/// 远程 1.2 接口边界；Widget 与 Controller 均不直接处理 URL、鉴权头或 JSON。
abstract interface class RemoteExplorationGateway {
  Future<LearningEntrySnapshot> getEntry(String atomId);

  Future<RemoteLearningSessionSnapshot> createSession({
    required String atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
  });

  Future<RemoteLearningSessionSnapshot?> restoreLatest();

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

  Future<String> exportTree(String sessionId);
}

/// 用户可见的稳定远程错误；原始响应和堆栈不直接暴露给学生。
final class RemoteExplorationException implements Exception {
  const RemoteExplorationException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// App 与 Web 共用的 1.2 HTTP 客户端；仅匿名标识和短期会话 ID 保存在本实例。
final class RemoteExplorationApi implements RemoteExplorationGateway {
  RemoteExplorationApi({
    http.Client? client,
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3000',
    ),
    this.timeout = const Duration(seconds: 35),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;
  String? _anonymousId;
  String? _exploreSessionId;
  String? _latestLearningSessionId;

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
    required String atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
  }) async {
    final exploreSessionId = await _ensureExploreSession();
    final data = await _request(
      'POST',
      '/api/learning-sessions',
      body: {
        'exploreSessionId': exploreSessionId,
        'atomId': atomId,
        'scenarioId': scenarioId,
        if ((directionId ?? '').isNotEmpty) 'directionId': directionId,
        if ((question ?? '').trim().isNotEmpty) 'question': question!.trim(),
      },
      idempotencyKey: idempotencyKey,
    );
    final snapshot = RemoteLearningSessionSnapshot.fromJson(data);
    _latestLearningSessionId = snapshot.session.id;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async {
    final learningSessionId = _latestLearningSessionId;
    final exploreSessionId = _exploreSessionId;
    if (learningSessionId == null || exploreSessionId == null) return null;
    final data = await _request(
      'GET',
      '/api/learning-sessions/${Uri.encodeComponent(learningSessionId)}'
          '?exploreSessionId=${Uri.encodeQueryComponent(exploreSessionId)}',
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
    final data = await _request(
      'POST',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/memory-candidates',
      body: {'exploreSessionId': _requiredExploreSessionId(), 'nodeId': nodeId},
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
  Future<String> exportTree(String sessionId) async {
    final data = await _request(
      'GET',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/export'
          '?exploreSessionId=${Uri.encodeQueryComponent(_requiredExploreSessionId())}',
    );
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<RemoteLearningSessionSnapshot> _mutateSnapshot(
    String sessionId,
    String action,
    Map<String, Object?> body,
    String? idempotencyKey,
  ) async {
    final data = await _request(
      'POST',
      '/api/learning-sessions/${Uri.encodeComponent(sessionId)}/$action',
      body: {'exploreSessionId': _requiredExploreSessionId(), ...body},
      idempotencyKey: idempotencyKey,
    );
    return RemoteLearningSessionSnapshot.fromJson(data);
  }

  Future<String> _ensureExploreSession() async {
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

  String _requiredExploreSessionId() {
    return _exploreSessionId ??
        (throw const RemoteExplorationException('学习身份已失效，请重新进入。'));
  }

  Future<Map<String, dynamic>> _request(
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
      return _asMap(rawData);
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

Map<String, dynamic> _asMapOrEmpty(Object? value) {
  if (value == null) return const {};
  return _asMap(value);
}
