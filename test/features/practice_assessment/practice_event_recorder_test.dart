import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/practice_assessment.dart';

void main() {
  test('事件最多 50 条一批且失败批次保留原 clientEventId', () async {
    final batches = <List<PracticeEvent>>[];
    var failOnce = true;
    final recorder = PracticeEventRecorder(
      sendBatch: (events) async {
        batches.add(List.of(events));
        if (failOnce) {
          failOnce = false;
          throw StateError('network');
        }
      },
      scheduleFlush: false,
    );
    addTearDown(recorder.dispose);
    for (var index = 0; index < 55; index++) {
      recorder.record(
        questionId: 'q1',
        eventType: PracticeEventType.answerChanged,
        payload: {'lengthBand': '1-20'},
      );
    }
    final originalIds = recorder.pending
        .map((event) => event.clientEventId)
        .toList();

    await expectLater(recorder.flush(), throwsStateError);
    expect(recorder.pending, hasLength(55));
    await recorder.flush();

    expect(batches.map((batch) => batch.length), [50, 50, 5]);
    expect(
      batches[1].map((event) => event.clientEventId),
      originalIds.take(50),
    );
    expect(recorder.pending, isEmpty);
  });

  test('提交方可等待 flush 完成后再发起提交', () async {
    final calls = <String>[];
    final gate = Completer<void>();
    final recorder = PracticeEventRecorder(
      sendBatch: (events) async {
        calls.add('flush');
        await gate.future;
      },
      scheduleFlush: false,
    );
    addTearDown(recorder.dispose);
    recorder.record(
      questionId: 'q1',
      eventType: PracticeEventType.attemptSubmitted,
    );

    final operation = () async {
      await recorder.flush();
      calls.add('submit');
    }();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['flush']);
    gate.complete();
    await operation;
    expect(calls, ['flush', 'submit']);
  });
}
