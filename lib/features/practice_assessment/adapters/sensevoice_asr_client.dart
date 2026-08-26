import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const _maxRequestBytes = 5 * 1024 * 1024;
const _maxResponseBytes = 64 * 1024;
const _maxAudioDurationSeconds = 15;
const _healthTimeout = Duration(seconds: 2);
const _timeoutMessage = '本机语音识别超时，请重新说一次。';
const _unavailableMessage = '本地语音识别暂时不可用，请稍后重试。';
const _tooLargeMessage = '录音文件过大，请重新录制。';

/// 为请求 deadline 提供可替换调度器；默认实现使用系统 Timer。
abstract interface class SenseVoiceDeadlineScheduler {
  Timer schedule(Duration delay, void Function() callback);
}

final class _TimerDeadlineScheduler implements SenseVoiceDeadlineScheduler {
  @override
  Timer schedule(Duration delay, void Function() callback) => Timer(delay, callback);
}

/// 为页面提供可安全展示的语音识别失败原因，不携带服务端或网络内部信息。
final class SenseVoiceAsrException implements Exception {
  const SenseVoiceAsrException(this.message);

  final String message;
}

/// 本地 SenseVoice HTTP 适配器，负责协议封装及上传、响应的资源边界校验。
final class SenseVoiceAsrClient {
  SenseVoiceAsrClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    SenseVoiceDeadlineScheduler? deadlineScheduler,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client(),
       _deadlineScheduler = deadlineScheduler ?? _TimerDeadlineScheduler();

  final String _baseUrl;
  final http.Client _client;
  final SenseVoiceDeadlineScheduler _deadlineScheduler;
  /// 单次转写操作的总时限；计时同时覆盖上传、等待响应头和读取响应体。
  final Duration timeout;

  /// 健康检查仅用于决定是否显示本地服务可用；所有失败统一降级为 false。
  Future<bool> isHealthy() async {
    final deadline = Completer<void>();
    final timer = _deadlineScheduler.schedule(_healthTimeout, deadline.complete);
    try {
      final response = await Future.any<http.Response>([
        _client.get(Uri.parse('$_baseUrl/health')),
        deadline.future.then<http.Response>(
          (_) => throw TimeoutException('SenseVoice health deadline exceeded'),
        ),
      ]);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      timer.cancel();
    }
  }

  /// 上传 Task 3 生成的 canonical PCM16/16k/mono WAV，并返回服务端识别文本。
  Future<String> transcribe(Uint8List wavBytes) async {
    final abortCompleter = Completer<void>();
    final deadline = _deadlineScheduler.schedule(timeout, () {
      if (!abortCompleter.isCompleted) {
        abortCompleter.complete();
      }
    });
    try {
      return await Future.any<String>([
        _transcribe(wavBytes, abortCompleter),
        abortCompleter.future.then<String>(
          (_) => throw TimeoutException('SenseVoice request deadline exceeded'),
        ),
      ]);
    } on TimeoutException {
      throw const SenseVoiceAsrException(_timeoutMessage);
    } on http.RequestAbortedException {
      throw const SenseVoiceAsrException(_timeoutMessage);
    } on SenseVoiceAsrException {
      rethrow;
    } catch (_) {
      // URI、网络与 JSON 实现细节均不应进入 UI 可见的错误文本。
      throw const SenseVoiceAsrException(_unavailableMessage);
    } finally {
      deadline.cancel();
    }
  }

  Future<String> _transcribe(
    Uint8List wavBytes,
    Completer<void> abortCompleter,
  ) async {
    _validateCanonicalWav(wavBytes);

    final request = http.AbortableMultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/v1/audio/transcriptions'),
      abortTrigger: abortCompleter.future,
    )
      ..fields['model'] = 'sensevoice'
      ..fields['response_format'] = 'json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'formula.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );
    final response = await _client.send(request);
    final responseBody = await _readResponse(response.stream, abortCompleter);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SenseVoiceAsrException(_unavailableMessage);
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const SenseVoiceAsrException(_unavailableMessage);
    }
    final text = decoded['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const SenseVoiceAsrException(_unavailableMessage);
    }
    return text.trim();
  }

  Future<String> _readResponse(
    Stream<List<int>> stream,
    Completer<void> abortCompleter,
  ) {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    var isFinished = false;
    final result = Completer<String>();
    late final StreamSubscription<List<int>> subscription;

    void finishError(Object error, [StackTrace? stackTrace]) {
      if (isFinished) {
        return;
      }
      isFinished = true;
      // 达到上限或 deadline 时主动取消订阅，不能只让外部 Future 脱离等待。
      result.completeError(error, stackTrace);
      unawaited(subscription.cancel().catchError((Object _) {}));
    }

    subscription = stream.listen(
      (chunk) {
        if (isFinished) {
          return;
        }
        length += chunk.length;
        if (length > _maxResponseBytes) {
          finishError(const SenseVoiceAsrException(_unavailableMessage));
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) =>
          finishError(error, stackTrace),
      onDone: () {
        if (isFinished) {
          return;
        }
        isFinished = true;
        try {
          result.complete(utf8.decode(bytes.takeBytes()));
        } catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
      },
      cancelOnError: false,
    );
    abortCompleter.future.then((_) {
      finishError(TimeoutException('SenseVoice request deadline exceeded'));
    });
    return result.future;
  }

  void _validateCanonicalWav(Uint8List wavBytes) {
    if (wavBytes.length > _maxRequestBytes) {
      throw const SenseVoiceAsrException(_tooLargeMessage);
    }
    if (wavBytes.length < 44) {
      throw const SenseVoiceAsrException(_unavailableMessage);
    }

    final data = ByteData.sublistView(wavBytes);
    final dataLength = data.getUint32(40, Endian.little);
    final byteRate = data.getUint32(28, Endian.little);
    final isCanonical =
        _hasAscii(wavBytes, 0, 'RIFF') &&
        data.getUint32(4, Endian.little) == wavBytes.length - 8 &&
        _hasAscii(wavBytes, 8, 'WAVE') &&
        _hasAscii(wavBytes, 12, 'fmt ') &&
        data.getUint32(16, Endian.little) == 16 &&
        data.getUint16(20, Endian.little) == 1 &&
        data.getUint16(22, Endian.little) == 1 &&
        data.getUint32(24, Endian.little) == 16000 &&
        byteRate == 32000 &&
        data.getUint16(32, Endian.little) == 2 &&
        data.getUint16(34, Endian.little) == 16 &&
        _hasAscii(wavBytes, 36, 'data') &&
        dataLength == wavBytes.length - 44 &&
        dataLength.isEven;
    // 以可信 header 的 byteRate 计算时长，避免仅按总文件大小误判或放行伪造数据。
    final isWithinDuration = dataLength <= byteRate * _maxAudioDurationSeconds;
    if (!isCanonical || !isWithinDuration) {
      throw const SenseVoiceAsrException(_unavailableMessage);
    }
  }

  bool _hasAscii(Uint8List bytes, int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      if (bytes[offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }
}
