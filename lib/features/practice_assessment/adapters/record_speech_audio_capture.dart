import 'dart:typed_data';

import 'package:record/record.dart';

import '../core/speech_audio_capture.dart';

/// 隔离 record 插件的生产边界；替换实现时不会让采集端口或上层业务耦合插件 API。
abstract interface class SpeechRecordDriver {
  Future<bool> hasPermission();

  Future<bool> isEncoderSupported(AudioEncoder encoder);

  /// 插件在硬件或浏览器调整录音参数时报告最终生效的配置。
  Future<void> setOnConfigChanged(void Function(RecordConfig)? callback);

  Future<Stream<Uint8List>> startStream(RecordConfig config);

  Future<void> stop();

  Future<void> cancel();

  Future<void> dispose();
}

enum _CaptureState { idle, starting, recording, stopping }

enum _FinishAction { stop, cancel }

/// 使用 record 插件捕获 SenseVoice 所需的单声道 PCM16 数据流。
final class RecordSpeechAudioCapture implements SpeechAudioCapture {
  RecordSpeechAudioCapture({SpeechRecordDriver? driver})
    : _driver = driver ?? _PluginRecordDriver();

  final SpeechRecordDriver _driver;
  Future<void> _serialOperation = Future<void>.value();
  Future<Stream<Uint8List>>? _startOperation;
  _CaptureState _state = _CaptureState.idle;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Future<bool> requestPermission() {
    if (_disposed) return Future<bool>.error(StateError('录音采集器已释放'));
    return _driver.hasPermission();
  }

  @override
  Future<Stream<Uint8List>> start() {
    if (_disposed) {
      return Future<Stream<Uint8List>>.error(StateError('录音采集器已释放'));
    }
    switch (_state) {
      case _CaptureState.idle:
        final generation = ++_generation;
        _state = _CaptureState.starting;
        final startOperation = _enqueue(() => _startRecording(generation));
        _startOperation = startOperation;
        return startOperation;
      case _CaptureState.starting:
        return _startOperation!;
      case _CaptureState.recording:
      case _CaptureState.stopping:
        return Future<Stream<Uint8List>>.error(StateError('当前录音尚未结束，不能重复启动'));
    }
  }

  @override
  Future<void> stop() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    return _finishRecording(_FinishAction.stop);
  }

  @override
  Future<void> cancel() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    return _finishRecording(_FinishAction.cancel);
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final hasActiveSession =
        _state != _CaptureState.idle || _startOperation != null;
    _disposed = true;
    final canceling = hasActiveSession
        ? _finishRecording(_FinishAction.cancel)
        : Future<void>.value();
    final operation = _disposeAfter(canceling);
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _disposeAfter(Future<void> canceling) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await canceling;
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _driver.dispose();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<Stream<Uint8List>> _startRecording(int generation) async {
    var effectiveConfig = _config;
    try {
      await _driver.setOnConfigChanged((config) {
        effectiveConfig = config;
      });
      final isPcm16Supported = await _driver.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!isPcm16Supported) {
        throw StateError('当前平台不支持 PCM16 音频流录制');
      }
      final stream = await _driver.startStream(_config);
      if (!_isCurrentStart(generation)) {
        throw StateError('录音启动已被停止或取消');
      }
      if (!_isSupportedPcm16Config(effectiveConfig)) {
        await _driver.cancel();
        throw StateError('当前设备返回了不受支持的 PCM16 音频格式');
      }
      _state = _CaptureState.recording;
      if (_isExpectedPcm16Config(effectiveConfig)) return stream;
      // Chrome 通常忽略 16kHz 约束并返回设备原生 48kHz；在适配层统一降采样与混音，
      // 使上层始终只接收 SenseVoice 约定的 16kHz 单声道 PCM16。
      return _normalizePcm16Stream(stream, effectiveConfig);
    } catch (_) {
      if (_isCurrentStart(generation)) {
        _state = _CaptureState.idle;
        _startOperation = null;
      }
      rethrow;
    }
  }

  Future<void> _finishRecording(_FinishAction action) {
    final startOperation = _startOperation;
    final generation = ++_generation;
    _state = _CaptureState.stopping;

    return _enqueue(() async {
      try {
        if (startOperation != null) {
          try {
            await startOperation;
          } catch (_) {
            // 启动失败后仍需执行用户已发出的停止或取消，确保插件会话不会残留。
          }
        }
        if (action == _FinishAction.stop) {
          await _driver.stop();
        } else {
          await _driver.cancel();
        }
      } finally {
        // 即使插件停止失败也要离开 stopping，下一次用户操作才能恢复并决定是否重试。
        if (_generation == generation) {
          _state = _CaptureState.idle;
          _startOperation = null;
        }
      }
    });
  }

  bool _isCurrentStart(int generation) =>
      _generation == generation && _state == _CaptureState.starting;

  bool _isExpectedPcm16Config(RecordConfig config) =>
      config.encoder == AudioEncoder.pcm16bits &&
      config.sampleRate == 16000 &&
      config.numChannels == 1;

  bool _isSupportedPcm16Config(RecordConfig config) =>
      config.encoder == AudioEncoder.pcm16bits &&
      config.sampleRate >= 16000 &&
      config.sampleRate <= 96000 &&
      config.numChannels >= 1 &&
      config.numChannels <= 16;

  Stream<Uint8List> _normalizePcm16Stream(
    Stream<Uint8List> stream,
    RecordConfig config,
  ) async* {
    final normalizer = _Pcm16StreamNormalizer(
      inputSampleRate: config.sampleRate,
      inputChannels: config.numChannels,
    );
    await for (final chunk in stream) {
      final normalized = normalizer.add(chunk);
      if (normalized.isNotEmpty) yield normalized;
    }
    normalizer.close();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _serialOperation.then<T>((_) => operation());
    _serialOperation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );
}

/// 将浏览器原生 PCM16 流按帧混音，再用面积加权降采样到 16kHz。
///
/// 状态保留了跨 chunk 的半帧和未满输出采样，避免插件分包边界导致丢帧或音频时长漂移。
final class _Pcm16StreamNormalizer {
  _Pcm16StreamNormalizer({
    required this.inputSampleRate,
    required this.inputChannels,
  });

  static const int _outputSampleRate = 16000;

  final int inputSampleRate;
  final int inputChannels;
  Uint8List _pendingBytes = Uint8List(0);
  int _outputWeight = 0;
  int _weightedSampleSum = 0;

  Uint8List add(Uint8List chunk) {
    final bytes = _joinPending(chunk);
    final frameBytes = inputChannels * 2;
    final completeLength = bytes.length - (bytes.length % frameBytes);
    _pendingBytes = Uint8List.fromList(bytes.sublist(completeLength));
    if (completeLength == 0) return Uint8List(0);

    final input = ByteData.sublistView(bytes, 0, completeLength);
    final samples = <int>[];
    for (var offset = 0; offset < completeLength; offset += frameBytes) {
      var channelSum = 0;
      for (var channel = 0; channel < inputChannels; channel += 1) {
        channelSum += input.getInt16(offset + channel * 2, Endian.little);
      }
      _appendSample(channelSum ~/ inputChannels, samples);
    }
    return _encodeSamples(samples);
  }

  void close() {
    if (_pendingBytes.isNotEmpty) {
      throw const FormatException('麦克风 PCM16 音频流包含不完整帧');
    }
  }

  Uint8List _joinPending(Uint8List chunk) {
    if (_pendingBytes.isEmpty) return chunk;
    final joined = Uint8List(_pendingBytes.length + chunk.length);
    joined.setRange(0, _pendingBytes.length, _pendingBytes);
    joined.setRange(_pendingBytes.length, joined.length, chunk);
    return joined;
  }

  void _appendSample(int sample, List<int> output) {
    var remainingWeight = _outputSampleRate;
    while (remainingWeight > 0) {
      final availableWeight = inputSampleRate - _outputWeight;
      final consumedWeight = remainingWeight < availableWeight
          ? remainingWeight
          : availableWeight;
      _weightedSampleSum += sample * consumedWeight;
      _outputWeight += consumedWeight;
      remainingWeight -= consumedWeight;
      if (_outputWeight == inputSampleRate) {
        output.add((_weightedSampleSum / inputSampleRate).round());
        _outputWeight = 0;
        _weightedSampleSum = 0;
      }
    }
  }

  Uint8List _encodeSamples(List<int> samples) {
    final bytes = Uint8List(samples.length * 2);
    final output = ByteData.sublistView(bytes);
    for (var index = 0; index < samples.length; index += 1) {
      output.setInt16(index * 2, samples[index], Endian.little);
    }
    return bytes;
  }
}

/// 仅在适配器内部持有插件实例，避免插件异常被包装或吞掉，供上层决定提示与重试策略。
final class _PluginRecordDriver implements SpeechRecordDriver {
  _PluginRecordDriver() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) =>
      _recorder.isEncoderSupported(encoder);

  @override
  Future<void> setOnConfigChanged(void Function(RecordConfig)? callback) =>
      _recorder.setOnConfigChanged(callback);

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
