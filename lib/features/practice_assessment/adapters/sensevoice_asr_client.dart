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
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

/// 为页面提供可安全展示的语音识别失败原因，不携带服务端或网络内部信息。
final class SenseVoiceAsrException implements Exception {
  const SenseVoiceAsrException(this.message);

  final String message;
}

/// SenseVoice 识别边界，便于本地录音状态机与具体 HTTP 生命周期解耦。
abstract interface class SenseVoiceAsrApi {
  Future<bool> isHealthy();

  Future<String> transcribe(Uint8List wavBytes, {Duration? timeout});

  /// 触发全部活动请求的 abort，并仅释放 API 自己创建的传输资源；实现必须幂等。
  /// 外部注入 transport 的物理连接生命周期仍属于调用方。
  Future<void> dispose();
}

/// 本地 SenseVoice HTTP 适配器，负责协议封装及上传、响应的资源边界校验。
final class SenseVoiceAsrClient implements SenseVoiceAsrApi {
  SenseVoiceAsrClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    SenseVoiceDeadlineScheduler? deadlineScheduler,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _deadlineScheduler = deadlineScheduler ?? _TimerDeadlineScheduler();

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final SenseVoiceDeadlineScheduler _deadlineScheduler;
  final Set<_SenseVoiceOperation> _activeOperations = <_SenseVoiceOperation>{};
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// 单次转写操作的总时限；计时同时覆盖上传、等待响应头和读取响应体。
  final Duration timeout;

  /// 健康检查仅用于决定是否显示本地服务可用；所有失败统一降级为 false。
  @override
  Future<bool> isHealthy() async {
    final operation = _beginOperation();
    final timer = _deadlineScheduler.schedule(_healthTimeout, operation.cancel);
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse('$_baseUrl/health'),
        abortTrigger: operation.cancelSignal,
      );
      final response = await Future.any<http.StreamedResponse>([
        _client.send(request),
        operation.cancelSignal.then<http.StreamedResponse>(
          (_) => throw TimeoutException('SenseVoice health deadline exceeded'),
        ),
      ]);
      // 健康检查只消费状态码，主动取消响应体以归还连接且避免无界 body 占用资源。
      operation.cancelResponseStream(response.stream);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      timer.cancel();
      _finishOperation(operation);
    }
  }

  /// 上传 Task 3 生成的 canonical PCM16/16k/mono WAV，并返回服务端识别文本。
  @override
  Future<String> transcribe(Uint8List wavBytes, {Duration? timeout}) async {
    final operation = _beginOperation();
    // Local 录音链路传入当前剩余时间；独立调用方仍沿用构造器默认值。
    final requestTimeout = timeout ?? this.timeout;
    final deadline = _deadlineScheduler.schedule(requestTimeout, () {
      operation.cancel();
    });
    try {
      return await Future.any<String>([
        _transcribe(wavBytes, operation),
        operation.cancelSignal.then<String>(
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
      _finishOperation(operation);
    }
  }

  Future<String> _transcribe(
    Uint8List wavBytes,
    _SenseVoiceOperation operation,
  ) async {
    _validateCanonicalWav(wavBytes);

    final request =
        http.AbortableMultipartRequest(
            'POST',
            Uri.parse('$_baseUrl/v1/audio/transcriptions'),
            abortTrigger: operation.cancelSignal,
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
    final responseBody = await _readResponse(response.stream, operation);

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
    _SenseVoiceOperation operation,
  ) {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    var isFinished = false;
    final result = Completer<String>();
    late final StreamSubscription<List<int>> subscription;

    void finishError(
      Object error, [
      StackTrace? stackTrace,
      bool cancelSubscription = true,
    ]) {
      if (isFinished) {
        return;
      }
      isFinished = true;
      // 达到上限或 deadline 时主动取消订阅，不能只让外部 Future 脱离等待。
      result.completeError(error, stackTrace);
      operation.detachResponseSubscription(subscription);
      if (cancelSubscription) {
        unawaited(subscription.cancel().catchError((Object _) {}));
      }
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
        operation.detachResponseSubscription(subscription);
        try {
          result.complete(utf8.decode(bytes.takeBytes()));
        } catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
      },
      cancelOnError: false,
    );
    operation.attachResponseSubscription(subscription);
    operation.cancelSignal.then((_) {
      finishError(
        TimeoutException('SenseVoice request deadline exceeded'),
        null,
        false,
      );
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

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    try {
      // 遍历快照，operation 的 finally 可同时从原集合移除，不能直接遍历活动集合。
      for (final operation in List<_SenseVoiceOperation>.of(
        _activeOperations,
      )) {
        operation.cancel();
      }
      if (_ownsClient) _client.close();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('SenseVoiceAsrClient 已释放');
  }

  _SenseVoiceOperation _beginOperation() {
    _ensureNotDisposed();
    final operation = _SenseVoiceOperation();
    _activeOperations.add(operation);
    return operation;
  }

  void _finishOperation(_SenseVoiceOperation operation) {
    _activeOperations.remove(operation);
  }
}

/// 单次 HTTP 操作的取消上下文；传输 abort 与响应订阅共用同一幂等信号。
final class _SenseVoiceOperation {
  final Completer<void> _cancelSignal = Completer<void>();
  StreamSubscription<List<int>>? _responseSubscription;

  Future<void> get cancelSignal => _cancelSignal.future;

  void attachResponseSubscription(StreamSubscription<List<int>> subscription) {
    _responseSubscription = subscription;
    if (_cancelSignal.isCompleted) {
      _cancelResponseSubscription(subscription);
    }
  }

  void detachResponseSubscription(StreamSubscription<List<int>> subscription) {
    if (identical(_responseSubscription, subscription)) {
      _responseSubscription = null;
    }
  }

  void cancelResponseStream(Stream<List<int>> stream) {
    final subscription = stream.listen(null);
    _responseSubscription = subscription;
    _cancelResponseSubscription(subscription);
  }

  void cancel() {
    if (!_cancelSignal.isCompleted) {
      _cancelSignal.complete();
    }
    final subscription = _responseSubscription;
    if (subscription != null) {
      _cancelResponseSubscription(subscription);
    }
  }

  void _cancelResponseSubscription(StreamSubscription<List<int>> subscription) {
    detachResponseSubscription(subscription);
    try {
      unawaited(subscription.cancel().catchError((Object _) {}));
    } catch (_) {
      // 第三方 stream 可能同步抛错；abort 信号已完成，不能让其阻断其它 operation 的释放。
    }
  }
}
