import 'dart:async';
import 'dart:convert';

import 'remote_exploration_dto.dart';

/// 用户可见的稳定远程错误，避免把协议细节或底层异常直接暴露给页面。
final class RemoteExplorationException implements Exception {
  const RemoteExplorationException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 流式教师回合的受限事件基类；UI 只能消费已校验的事件数据。
sealed class RemoteTurnStreamEvent {
  const RemoteTurnStreamEvent();
}

final class RemoteTurnMetadata extends RemoteTurnStreamEvent {
  const RemoteTurnMetadata({required this.traceId, required this.model});

  final String traceId;
  final String model;
}

final class RemoteTurnAnswerDelta extends RemoteTurnStreamEvent {
  const RemoteTurnAnswerDelta(this.text);

  final String text;
}

final class RemoteTurnCommitted extends RemoteTurnStreamEvent {
  const RemoteTurnCommitted(this.snapshot);

  final RemoteLearningSessionSnapshot snapshot;
}

final class RemoteTurnFailed extends RemoteTurnStreamEvent {
  const RemoteTurnFailed({required this.message, required this.canFallback});

  final String message;
  final bool canFallback;
}

final class RemoteTurnDone extends RemoteTurnStreamEvent {
  RemoteTurnDone(Map<String, num> timings) : timings = Map.unmodifiable(timings);

  final Map<String, num> timings;
}

/// 将 HTTP 字节流按 UTF-8 与 SSE 帧边界增量解析为强类型事件。
Stream<RemoteTurnStreamEvent> decodeRemoteTurnSse(Stream<List<int>> bytes) async* {
  var pending = '';
  String? eventName;
  final dataLines = <String>[];

  // UTF-8 解码器跨 chunk 保留半个中文字符，不能分别解码每个网络分片。
  await for (final chunk in bytes.transform(utf8.decoder)) {
    pending += chunk;
    while (true) {
      final newline = pending.indexOf('\n');
      if (newline < 0) break;
      var line = pending.substring(0, newline);
      pending = pending.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

      if (line.isEmpty) {
        final name = eventName;
        if (name != null) {
          final event = _decodeFrame(name, dataLines.join('\n'));
          if (event != null) yield event;
        }
        eventName = null;
        dataLines.clear();
        continue;
      }
      if (line.startsWith(':')) continue;

      final separator = line.indexOf(':');
      final field = separator < 0 ? line : line.substring(0, separator);
      var value = separator < 0 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          eventName = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
      }
    }
  }

  // 没有空行就不能确认一个事件已经完整到达，防止伪造已提交状态。
  if (pending.isNotEmpty || eventName != null || dataLines.isNotEmpty) {
    throw const RemoteExplorationException('服务端流式响应不完整。');
  }
}

RemoteTurnStreamEvent? _decodeFrame(String eventName, String data) {
  switch (eventName) {
    case 'metadata':
      final json = _decodeObject(data);
      return RemoteTurnMetadata(
        traceId: _requiredNonEmptyString(json, 'traceId'),
        model: _requiredNonEmptyString(json, 'model'),
      );
    case 'answer_delta':
      final json = _decodeObject(data);
      return RemoteTurnAnswerDelta(_requiredString(json, 'text'));
    case 'committed':
      final json = _decodeObject(data);
      if (json['ok'] != true) _invalidEvent();
      final snapshotJson = _asObject(json['data']);
      try {
        return RemoteTurnCommitted(
          RemoteLearningSessionSnapshot.fromJson(snapshotJson),
        );
      } on FormatException {
        _invalidEvent();
      }
    case 'error':
      final json = _decodeObject(data);
      final canFallback = json['canFallback'];
      if (canFallback is! bool) _invalidEvent();
      return RemoteTurnFailed(
        message: _requiredNonEmptyString(json, 'message'),
        canFallback: canFallback,
      );
    case 'done':
      return RemoteTurnDone(_decodeMetrics(_decodeObject(data)));
    default:
      // 向前兼容服务端新增的观测或心跳事件，不让其阻塞教师回复。
      return null;
  }
}

Map<String, dynamic> _decodeObject(String data) {
  try {
    return _asObject(jsonDecode(data));
  } on FormatException {
    _invalidEvent();
  }
}

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  _invalidEvent();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  _invalidEvent();
}

String _requiredNonEmptyString(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key).trim();
  if (value.isEmpty) _invalidEvent();
  return value;
}

Map<String, num> _decodeMetrics(Map<String, dynamic> json) {
  final result = <String, num>{};
  final timings = json['timings'];
  final usage = json['usage'];
  if (timings is Map || usage is Map) {
    if (timings is Map) _copyNumericValues(result, timings);
    if (usage is Map) _copyNumericValues(result, usage);
  } else {
    _copyNumericValues(result, json);
  }
  if (result.isEmpty) _invalidEvent();
  return result;
}

void _copyNumericValues(Map<String, num> target, Object? source) {
  if (source is! Map) _invalidEvent();
  for (final entry in source.entries) {
    if (entry.value is! num) _invalidEvent();
    target['${entry.key}'] = entry.value as num;
  }
}

Never _invalidEvent() => throw const RemoteExplorationException('服务端返回格式不正确。');
