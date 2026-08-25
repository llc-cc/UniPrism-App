import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/demo_spoken_formula_repository.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_api_client.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/practice_participant_token_store.dart';
import 'package:uniprism_app/features/practice_assessment/adapters/remote_spoken_formula_repository.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('语音公式请求使用 70 秒预算且共享请求仍保留 15 秒默认值', () async {
    final observedTimeouts = <Duration>[];
    final api = PracticeApiClient(
      baseUrl: 'http://localhost:3000',
      participantTokenStore: MemoryPracticeParticipantTokenStore(),
      client: MockClient((request) async {
        final data =
            request.url.path == '/api/practice/formulas/from-spoken-text'
            ? <String, Object?>{
                'recognizedText': 'x',
                'normalizedText': 'x',
                'latex': 'x',
                'alternatives': <String>[],
                'warnings': <String>[],
              }
            : <String, Object?>{'reachable': true};
        return http.Response(
          jsonEncode({'ok': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final repository = RemoteSpokenFormulaRepository(api);

    await runZoned(
      () async {
        await repository.convert(text: 'x');
        await api.request('GET', '/api/practice/ping');
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 15) ||
              duration == const Duration(seconds: 70)) {
            observedTimeouts.add(duration);
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(observedTimeouts, <Duration>[
      const Duration(seconds: 70),
      const Duration(seconds: 15),
    ]);
  });

  test('远程转换只发送最终文字和中文区域', () async {
    final repository = RemoteSpokenFormulaRepository(
      PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: MemoryPracticeParticipantTokenStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/practice/formulas/from-spoken-text');
          expect(jsonDecode(request.body), <String, Object?>{
            'text': 'x 的平方',
            'locale': 'zh-CN',
          });
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'recognizedText': 'x 的平方',
                'normalizedText': 'x 的平方',
                'latex': 'x^2',
                'alternatives': <String>[],
                'warnings': <String>[],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.convert(text: 'x 的平方');

    expect(result.latex, 'x^2');
  });

  test('演示转换兼容浏览器把中文数字转写为阿拉伯数字', () async {
    const repository = DemoSpokenFormulaRepository();

    final conversion = await repository.convert(text: 'x的平方加2x加1');

    expect(conversion.latex, 'x^2+2x+1');
  });

  test('远程响应缺少公式时拒绝进入预览', () async {
    final repository = RemoteSpokenFormulaRepository(
      PracticeApiClient(
        baseUrl: 'http://localhost:3000',
        participantTokenStore: MemoryPracticeParticipantTokenStore(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'recognizedText': 'x',
                'normalizedText': 'x',
                'latex': '',
                'alternatives': <String>[],
                'warnings': <String>[],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.convert(text: 'x'),
      throwsA(isA<SpokenFormulaConversionException>()),
    );
  });

  test('演示转换器保留原表达并为歧义公式提供候选', () async {
    const repository = DemoSpokenFormulaRepository();

    expect((await repository.convert(text: 'x 加 x')).latex, 'x+x');
    final ambiguous = await repository.convert(text: '负二的平方');
    expect(ambiguous.latex, r'(-2)^2');
    expect(ambiguous.alternatives, <String>[r'-2^2']);
    expect(ambiguous.warnings.single, contains('歧义'));
  });
}
