import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/platform_speech_formula_recognizer.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('平台工厂构造识别器时不会提前请求麦克风权限', () {
    final recognizer = createPlatformSpeechFormulaRecognizer();

    expect(recognizer, isA<SpeechFormulaRecognizer>());
  });
}
