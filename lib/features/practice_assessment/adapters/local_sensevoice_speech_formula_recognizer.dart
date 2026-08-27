import 'dart:async';
import 'dart:typed_data';

import '../core/speech_audio_capture.dart';
import '../core/spoken_formula.dart';
import 'pcm_wav_encoder.dart';
import 'sensevoice_asr_client.dart';

typedef SpeechFormulaTimerFactory =
    Timer Function(Duration duration, void Function() callback);
typedef SpeechFormulaProcessingClock = Duration Function();

final Stopwatch _processingStopwatch = Stopwatch()..start();
const Duration _senseVoiceRequestCap = Duration(milliseconds: 3800);

Duration _readProcessingClock() => _processingStopwatch.elapsed;

enum _LocalRecognitionState { idle, starting, listening, stopping }

/// 将一轮 PCM 采集封装为一次 SenseVoice 请求，并用 generation 隔离迟到异步结果。
final class LocalSenseVoiceSpeechFormulaRecognizer
    implements SpeechFormulaRecognizer {
  LocalSenseVoiceSpeechFormulaRecognizer(
    this._capture,
    this._client, {
    this.maxDuration = const Duration(seconds: 15),
    this.finalizationDeadline = spokenFormulaTotalDeadline,
    this.timerFactory = Timer.new,
    this.processingClock = _readProcessingClock,
  });

  final SpeechAudioCapture _capture;
  final SenseVoiceAsrApi _client;
  final SpeechFormulaTimerFactory timerFactory;
  final SpeechFormulaProcessingClock processingClock;
  final Duration maxDuration;
  final Duration finalizationDeadline;

  int _generation = 0;
  _LocalRecognitionState _state = _LocalRecognitionState.idle;
  List<Uint8List> _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  SpeechFormulaResultCallback? _onResult;
  SpeechFormulaErrorCallback? _onError;
  SpeechFormulaFinalizationStartedCallback? _onFinalizationStarted;
  Future<void>? _listenFuture;
  Future<void>? _stopFuture;
  Future<void>? _cancelFuture;
  Future<void>? _captureCancelFuture;
  bool _hasTerminalCallback = false;
  SpokenFormulaRecognitionException? _initializationError;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  SpokenFormulaRecognitionException? get initializationError =>
      _initializationError;

  @override
  Future<bool> initialize() async {
    _ensureNotDisposed();
    _initializationError = null;
    var isHealthy = false;
    try {
      isHealthy = await _client.isHealthy();
    } catch (_) {
      // 健康检查的网络与传输异常等价于本机服务不可用，UI 只给出可恢复操作。
    }
    if (!isHealthy) {
      _initializationError = const SpokenFormulaRecognitionException(
        '请先启动本机 SenseVoice 服务后重试。',
      );
      return false;
    }
    try {
      if (await _capture.requestPermission()) return true;
    } catch (_) {
      // 插件权限异常与用户拒绝权限使用同一安全恢复提示，不暴露实现细节。
    }
    _initializationError = const SpokenFormulaRecognitionException(
      '无法使用麦克风，请检查麦克风权限后重试。',
    );
    return false;
  }

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) {
    _ensureNotDisposed();
    if (_state != _LocalRecognitionState.idle) {
      return Future<void>.error(StateError('上一轮语音识别尚未结束，不能重复启动'));
    }
    final generation = ++_generation;
    _state = _LocalRecognitionState.starting;
    _chunks = <Uint8List>[];
    _subscription = null;
    _timer = null;
    _onResult = onResult;
    _onError = onError;
    _onFinalizationStarted = onFinalizationStarted;
    _stopFuture = null;
    _hasTerminalCallback = false;
    final operation = _startCaptureAfterCleanup(generation, _cancelFuture);
    _listenFuture = operation;
    return operation;
  }

  Future<void> _startCaptureAfterCleanup(
    int generation,
    Future<void>? pendingCleanup,
  ) async {
    // 旧 capture.cancel 完成前不能启动新 capture，否则迟到释放会终止新录音。
    await pendingCleanup;
    if (!_isCurrent(generation) || _state != _LocalRecognitionState.starting) {
      return;
    }
    await _startCapture(generation);
  }

  Future<void> _startCapture(int generation) async {
    try {
      final stream = await _capture.start();
      if (!_isCurrent(generation) ||
          _state != _LocalRecognitionState.starting) {
        return;
      }
      _state = _LocalRecognitionState.listening;
      final subscription = stream.listen(
        (chunk) {
          if (_isCurrent(generation) &&
              !_hasTerminalCallback &&
              (_state == _LocalRecognitionState.listening ||
                  _state == _LocalRecognitionState.stopping)) {
            // 插件可能复用底层缓冲；进入会话缓冲前必须复制，避免随后写入篡改已录数据。
            _chunks.add(Uint8List.fromList(chunk));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleStreamError(generation, error);
        },
        cancelOnError: false,
      );
      if (!_isCurrent(generation) ||
          _state != _LocalRecognitionState.listening) {
        await subscription.cancel();
        return;
      }
      _subscription = subscription;
      _timer = timerFactory(maxDuration, () {
        // Timer 回调不能遗留未观察的 Future；stop 内外两层都将异常收敛为安全错误。
        unawaited(
          stop().catchError((Object error, StackTrace stackTrace) {
            _emitSafeError(generation, error);
          }),
        );
      });
    } catch (_) {
      if (_isCurrent(generation)) {
        _state = _LocalRecognitionState.idle;
        _clearCallbacksAndBuffer();
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    final existing = _stopFuture;
    if (existing != null) return existing;
    if (_state == _LocalRecognitionState.idle) return Future<void>.value();

    final operation = _stopInternal(_generation);
    _stopFuture = operation;
    return operation;
  }

  Future<void> _stopInternal(int generation) async {
    // 从 stop/finalization 发起就计时，pending start、capture.stop、WAV 和 ASR 都不能漏算。
    final processingStartedAt = processingClock();
    _emitFinalizationStarted(generation);
    final pendingStart = _listenFuture;
    if (_state == _LocalRecognitionState.starting && pendingStart != null) {
      try {
        await pendingStart;
      } catch (error) {
        _emitSafeError(generation, error);
        return;
      }
    }
    if (!_isCurrent(generation) || _state == _LocalRecognitionState.idle) {
      return;
    }

    _state = _LocalRecognitionState.stopping;
    _timer?.cancel();
    _timer = null;
    try {
      await _capture.stop();
      await _cancelSubscription();
      if (!_isCurrent(generation)) return;
      if (_hasTerminalCallback) return;

      final pcm = _joinChunks();
      if (pcm.isEmpty) {
        throw const SpokenFormulaRecognitionException('没有录到有效语音，请重新说一次。');
      }
      final wav = encodePcm16MonoWav(pcm);
      final elapsedBeforeAsr = processingClock() - processingStartedAt;
      final remaining = finalizationDeadline - elapsedBeforeAsr;
      if (remaining <= Duration.zero) {
        throw const SpokenFormulaRecognitionException('本机语音识别超时，请重新说一次。');
      }
      final asrTimeout = remaining < _senseVoiceRequestCap
          ? remaining
          : _senseVoiceRequestCap;
      final transcript = (await _client.transcribe(
        wav,
        timeout: asrTimeout,
      )).trim();
      if (!_isCurrent(generation)) return;
      if (transcript.isEmpty) {
        throw const SpokenFormulaRecognitionException('本地语音识别暂时不可用，请稍后重试。');
      }
      final processingElapsed = processingClock() - processingStartedAt;
      _emitFinal(generation, transcript, processingElapsed);
    } catch (error) {
      _emitSafeError(generation, error);
    } finally {
      await _cancelSubscription();
      if (_isCurrent(generation)) {
        _state = _LocalRecognitionState.idle;
        _clearCallbacksAndBuffer();
      }
    }
  }

  @override
  Future<void> cancel() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    // 先推进 generation，再触碰插件或订阅，确保其间完成的 HTTP Future 已无回调资格。
    final previousState = _state;
    final pendingStart = _listenFuture;
    final pendingStop = _stopFuture;
    ++_generation;
    _state = _LocalRecognitionState.idle;
    final subscription = _subscription;
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _clearCallbacksAndBuffer();
    _stopFuture = null;
    final existing = _cancelFuture;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation =
        _cancelSessionResources(
          subscription: subscription,
          pendingStart: previousState == _LocalRecognitionState.starting
              ? pendingStart
              : null,
          pendingStop: previousState == _LocalRecognitionState.stopping
              ? pendingStop
              : null,
        ).whenComplete(() {
          if (identical(_cancelFuture, operation)) _cancelFuture = null;
        });
    _cancelFuture = operation;
    return operation;
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final previousState = _state;
    final pendingStart = _listenFuture;
    final pendingStop = _stopFuture;
    final pendingCancel = _cancelFuture;
    _disposed = true;
    ++_generation;
    _state = _LocalRecognitionState.idle;
    final subscription = _subscription;
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _clearCallbacksAndBuffer();
    _stopFuture = null;
    final operation = _disposeResources(
      subscription: subscription,
      pendingCancel: pendingCancel,
      pendingStart: previousState == _LocalRecognitionState.starting
          ? pendingStart
          : null,
      pendingStop: previousState == _LocalRecognitionState.stopping
          ? pendingStop
          : null,
    );
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _disposeResources({
    required StreamSubscription<Uint8List>? subscription,
    required Future<void>? pendingCancel,
    required Future<void>? pendingStart,
    required Future<void>? pendingStop,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> release(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (pendingCancel != null) {
      await release(() => pendingCancel);
    } else {
      await release(() async => subscription?.cancel());
      if (pendingStart != null) await release(() => pendingStart);
      await release(_cancelCaptureSerialized);
      if (pendingStop != null) await release(() => pendingStop);
    }
    await release(_capture.dispose);
    await release(_client.dispose);
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> _cancelResources(
    StreamSubscription<Uint8List>? subscription,
  ) async {
    try {
      await subscription?.cancel();
    } catch (_) {
      // 用户取消不应产生第二条 UI 错误；capture.cancel 仍需执行以释放麦克风。
    }
    try {
      await _cancelCaptureSerialized();
    } catch (_) {
      // generation 已失效，取消失败也不能恢复或污染旧会话。
    }
  }

  Future<void> _cancelSessionResources({
    required StreamSubscription<Uint8List>? subscription,
    required Future<void>? pendingStart,
    required Future<void>? pendingStop,
  }) async {
    try {
      await subscription?.cancel();
    } catch (_) {
      // 用户取消不应产生第二条 UI 错误；capture 清理仍必须继续。
    }
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        // start 失败已由原调用方观察；取消路径只负责确保它不再晚于 capture.cancel。
      }
    }
    try {
      await _cancelCaptureSerialized();
    } catch (_) {
      // generation 已失效，取消失败也不能恢复或污染旧会话。
    }
    if (pendingStop != null) {
      try {
        await pendingStop;
      } catch (_) {
        // stop 的安全错误由原终止 Future 收敛；新会话只等待资源顺序完成。
      }
    }
  }

  Future<void> _cancelCaptureSerialized() {
    final existing = _captureCancelFuture;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = Future<void>.sync(_capture.cancel).whenComplete(() {
      if (identical(_captureCancelFuture, operation)) {
        _captureCancelFuture = null;
      }
    });
    _captureCancelFuture = operation;
    return operation;
  }

  void _handleStreamError(int generation, Object error) {
    if (!_isCurrent(generation) || _hasTerminalCallback) return;
    _state = _LocalRecognitionState.stopping;
    _timer?.cancel();
    _timer = null;
    // stream error 与 manual/auto stop 共用本轮唯一终止屏障，不能替换已在执行的 stop。
    _stopFuture ??= _finishStreamError(generation);
    _emitSafeError(generation, error);
  }

  Future<void> _finishStreamError(int generation) async {
    try {
      final subscription = _subscription;
      _subscription = null;
      await _cancelResources(subscription);
    } finally {
      if (_isCurrent(generation)) {
        _state = _LocalRecognitionState.idle;
        _clearCallbacksAndBuffer();
      }
    }
  }

  Uint8List _joinChunks() {
    final builder = BytesBuilder(copy: false);
    for (final chunk in _chunks) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // stop 的主错误优先；订阅清理失败不得覆盖或重复 onError。
    }
  }

  void _emitFinal(
    int generation,
    String transcript,
    Duration processingElapsed,
  ) {
    if (!_isCurrent(generation) || _hasTerminalCallback) return;
    _hasTerminalCallback = true;
    try {
      _onResult?.call(
        transcript,
        isFinal: true,
        processingElapsed: processingElapsed,
      );
    } catch (_) {
      // 消费方回调失败不能改变 terminal 次数，也不能跳过 finally 中的资源释放。
    }
  }

  void _emitFinalizationStarted(int generation) {
    if (!_isCurrent(generation) || _hasTerminalCallback) return;
    try {
      _onFinalizationStarted?.call();
    } catch (_) {
      // 生命周期信号只负责启动 watchdog；消费方异常不能阻断录音收尾。
    }
  }

  void _emitSafeError(int generation, Object error) {
    if (!_isCurrent(generation) || _hasTerminalCallback) return;
    _hasTerminalCallback = true;
    try {
      _onError?.call(_safeException(error));
    } catch (_) {
      // typed error 已是本轮唯一终态；消费方异常不得再次回调或逃逸为未处理 Future。
    }
  }

  SpokenFormulaRecognitionException _safeException(Object error) {
    if (error is SpokenFormulaRecognitionException) return error;
    if (error is SenseVoiceAsrException) {
      return SpokenFormulaRecognitionException(error.message);
    }
    return const SpokenFormulaRecognitionException('语音识别暂时不可用，请重新说一次。');
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('本机语音识别器已释放');
  }

  void _clearCallbacksAndBuffer() {
    _chunks = <Uint8List>[];
    _onResult = null;
    _onError = null;
    _onFinalizationStarted = null;
    _listenFuture = null;
  }
}
