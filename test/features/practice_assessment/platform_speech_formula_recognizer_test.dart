import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/platform_speech_formula_recognizer.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart'
    as web;
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('Web browser 模式构造浏览器识别器且不提前请求麦克风权限', () {
    final recognizer = createPlatformSpeechFormulaRecognizer(
      mode: 'browser',
      senseVoiceBaseUrl: 'http://127.0.0.1:8765',
    );

    expect(recognizer, isA<web.WebSpeechFormulaRecognizer>());
  }, skip: !kIsWeb);

  test('Web sensevoiceLocal 模式使用指定 baseUrl 构造本机识别链路', () async {
    Uri? requestedUri;
    final recognizer = http.runWithClient(
      () => createPlatformSpeechFormulaRecognizer(
        mode: 'sensevoiceLocal',
        senseVoiceBaseUrl: 'http://127.0.0.1:8765/root/',
      ),
      () => MockClient((request) async {
        requestedUri = request.url;
        return http.Response('', 503);
      }),
    );

    expect(recognizer, isA<LocalSenseVoiceSpeechFormulaRecognizer>());
    expect(await recognizer.initialize(), isFalse);
    expect(requestedUri, Uri.parse('http://127.0.0.1:8765/root/health'));
  }, skip: !kIsWeb);

  test('模式值严格区分大小写、空值与未知值', () {
    for (final mode in <String>['', 'Browser', 'sensevoicelocal', 'unknown']) {
      expect(
        () => createPlatformSpeechFormulaRecognizer(
          mode: mode,
          senseVoiceBaseUrl: 'http://127.0.0.1:8765',
        ),
        throwsArgumentError,
        reason: '非法模式 $mode 不得静默回退',
      );
    }
  });

  test('非 Web 的两个合法模式都显式返回安全不可用识别器', () async {
    for (final mode in <String>['browser', 'sensevoiceLocal']) {
      final recognizer = createPlatformSpeechFormulaRecognizer(
        mode: mode,
        senseVoiceBaseUrl: 'http://127.0.0.1:8765',
      );

      expect(recognizer, isA<SpeechFormulaRecognizer>());
      expect(await recognizer.initialize(), isFalse);
    }
  }, skip: kIsWeb);
}
