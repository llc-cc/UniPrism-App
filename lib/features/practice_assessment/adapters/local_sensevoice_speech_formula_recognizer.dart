import 'dart:async';
import 'dart:typed_data';

import '../core/speech_audio_capture.dart';
import '../core/spoken_formula.dart';
import 'pcm_wav_encoder.dart';
import 'sensevoice_asr_client.dart';

typedef SpeechFormulaTimerFactory =
    Timer Function(Duration duration, void Function() callback);

enum _LocalRecognitionState { idle, starting, listening, stopping }

/// 将一轮 PCM 采集封装为一次 SenseVoice 请求，并用 generation 隔离迟到异步结果。
final class LocalSenseVoiceSpeechFormulaRecognizer
    implements SpeechFormulaRecognizer {
  LocalSenseVoiceSpeechFormulaRecognizer(
    this._capture,
    this._client, {
    this.maxDuration = const Duration(seconds: 15),
    this.timerFactory = Timer.new,
  });

  final SpeechAudioCapture _capture;
  final SenseVoiceAsrApi _client;
  final SpeechFormulaTimerFactory timerFactory;
  final Duration maxDuration;

  int _generation = 0;
  _LocalRecognitionState _state = _LocalRecognitionState.idle;
  List<Uint8List> _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  SpeechFormulaResultCallback? _onResult;
  SpeechFormulaErrorCallback? _onError;
  Future<void>? _listenFuture;
  Future<void>? _stopFuture;
  bool _hasTerminalCallback = false;

  @override
  Future<bool> initialize() async {
    if (!await _client.isHealthy()) return false;
    return _capture.requestPermission();
  }

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
  }) {
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
    _stopFuture = null;
    _hasTerminalCallback = false;
    final operation = _startCapture(generation);
    _listenFuture = operation;
    return operation;
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
    final existing = _stopFuture;
    if (existing != null) return existing;
    if (_state == _LocalRecognitionState.idle) return Future<void>.value();

    final operation = _stopInternal(_generation);
    _stopFuture = operation;
    return operation;
  }

  Future<void> _stopInternal(int generation) async {
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
      final transcript = (await _client.transcribe(wav)).trim();
      if (!_isCurrent(generation)) return;
      if (transcript.isEmpty) {
        throw const SpokenFormulaRecognitionException('本地语音识别暂时不可用，请稍后重试。');
      }
      _emitFinal(generation, transcript);
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
    // 先推进 generation，再触碰插件或订阅，确保其间完成的 HTTP Future 已无回调资格。
    ++_generation;
    _state = _LocalRecognitionState.idle;
    final subscription = _subscription;
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _clearCallbacksAndBuffer();
    _stopFuture = null;
    return _cancelResources(subscription);
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
      await _capture.cancel();
    } catch (_) {
      // generation 已失效，取消失败也不能恢复或污染旧会话。
    }
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

  void _emitFinal(int generation, String transcript) {
    if (!_isCurrent(generation) || _hasTerminalCallback) return;
    _hasTerminalCallback = true;
    try {
      _onResult?.call(transcript, isFinal: true);
    } catch (_) {
      // 消费方回调失败不能改变 terminal 次数，也不能跳过 finally 中的资源释放。
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

  bool _isCurrent(int generation) => generation == _generation;

  void _clearCallbacksAndBuffer() {
    _chunks = <Uint8List>[];
    _onResult = null;
    _onError = null;
    _listenFuture = null;
  }
}
