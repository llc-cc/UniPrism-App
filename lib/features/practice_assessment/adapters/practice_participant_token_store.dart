import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class PracticeParticipantTokenStore {
  Future<String?> read();
  Future<void> write(String? token);

  Future<void> clear();
}

final class NativePracticeParticipantTokenStore
    implements PracticeParticipantTokenStore {
  static const _channel = MethodChannel('uniprism/auth_storage');
  static const _key = 'uniprism.practiceParticipantToken';

  @override
  Future<String?> read() async {
    // Web 通过 HttpOnly Cookie 恢复身份，禁止把匿名令牌暴露给 JavaScript。
    if (kIsWeb) return null;
    final stored = await _channel.invokeMapMethod<String, Object?>('read');
    final value = stored?[_key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String? token) async {
    if (kIsWeb) return;
    await _channel.invokeMethod<void>('write', <String, String?>{_key: token});
  }

  @override
  Future<void> clear() => write(null);
}

final class MemoryPracticeParticipantTokenStore
    implements PracticeParticipantTokenStore {
  MemoryPracticeParticipantTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String? token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
