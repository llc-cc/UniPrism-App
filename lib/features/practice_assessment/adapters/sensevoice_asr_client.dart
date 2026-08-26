import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const _maxRequestBytes = 5 * 1024 * 1024;
const _maxResponseBytes = 64 * 1024;
const _maxAudioDurationSeconds = 15;
const _healthTimeout = Duration(seconds: 2);
const _timeoutMessage = '本地语音识别超时，请重新说一次。';
const _unavailableMessage = '本地语音识别暂时不可用，请稍后重试。';

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
    Duration timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client(),
       _timeout = timeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _timeout;

  /// 健康检查仅用于决定是否显示本地服务可用；所有失败统一降级为 false。
  Future<bool> isHealthy() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(_healthTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 上传 Task 3 生成的 canonical PCM16/16k/mono WAV，并返回服务端识别文本。
  Future<String> transcribe(Uint8List wavBytes) async {
    try {
      return await _transcribe(wavBytes).timeout(_timeout);
    } on TimeoutException {
      throw const SenseVoiceAsrException(_timeoutMessage);
    } on SenseVoiceAsrException {
      rethrow;
    } catch (_) {
      // URI、网络与 JSON 实现细节均不应进入 UI 可见的错误文本。
      throw const SenseVoiceAsrException(_unavailableMessage);
    }
  }

  Future<String> _transcribe(Uint8List wavBytes) async {
    _validateCanonicalWav(wavBytes);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/v1/audio/transcriptions'),
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
    // 一个 15 秒时限同时覆盖请求发送与响应读取，避免分段计时放大总等待时间。
    final response = await _client.send(request);
    final responseBody = await _readResponse(response.stream);

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

  Future<String> _readResponse(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      // 达到硬上限后的后续字节无需再读取，避免异常响应占用更多内存。
      if (length > _maxResponseBytes) {
        throw const SenseVoiceAsrException(_unavailableMessage);
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  void _validateCanonicalWav(Uint8List wavBytes) {
    if (wavBytes.length > _maxRequestBytes || wavBytes.length < 44) {
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
