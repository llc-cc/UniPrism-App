import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'practice_http_client.dart'
    if (dart.library.js_interop) 'practice_http_client_web.dart';
import 'practice_participant_token_store.dart';

final class PracticeApiException implements Exception {
  const PracticeApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.requestId,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() => requestId == null ? message : '$message（请求编号：$requestId）';
}

/// 统一处理练习 API 的超时、身份头和标准响应信封。
final class PracticeApiClient {
  PracticeApiClient({
    required String baseUrl,
    required this.participantTokenStore,
    this.bearerTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? createPracticeHttpClient();

  final String baseUrl;
  final PracticeParticipantTokenStore participantTokenStore;
  final Future<String?> Function()? bearerTokenProvider;
  final http.Client _client;
  final Duration timeout;

  Future<Map<String, Object?>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    final bearer = await bearerTokenProvider?.call();
    final participant = bearer == null ? await participantTokenStore.read() : null;
    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (bearer != null && bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
      if (participant != null) 'authorization': 'PracticeParticipant $participant',
    };
    if (idempotencyKey != null) {
      headers['idempotency-key'] = idempotencyKey;
    }
    final uri = Uri.parse('$baseUrl$path');
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      final decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
        final error = _map(decoded['error']);
        throw PracticeApiException(
          message: error?['message']?.toString() ?? '练习服务请求失败',
          code: error?['code']?.toString(),
          statusCode: response.statusCode,
          requestId: error?['requestId']?.toString() ?? response.headers['x-request-id'],
        );
      }
      final data = _map(decoded['data']);
      if (data == null) {
        throw PracticeApiException(
          message: '练习服务响应格式不完整',
          statusCode: response.statusCode,
          requestId: response.headers['x-request-id'],
        );
      }
      return data;
    } on TimeoutException {
      throw const PracticeApiException(message: '练习服务响应超时，请重试');
    } on PracticeApiException {
      rethrow;
    } catch (error) {
      throw PracticeApiException(message: '无法连接练习服务：$error');
    }
  }

  Map<String, Object?> _decode(String source) {
    try {
      return _map(jsonDecode(source)) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, Object?>? _map(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : null;
}
