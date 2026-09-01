import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/practice_assessment/application/speech_formula_controller.dart';
import 'package:uniprism_app/features/practice_assessment/core/spoken_formula.dart';

void main() {
  test('idle 依次进入 requestingPermission 和 listening', () async {
    final recognizer = _FakeRecognizer();
    final controller = _controller(recognizer: recognizer);
    addTearDown(controller.dispose);
    final statuses = <SpeechFormulaStatus>[];
    controller.addListener(() => statuses.add(controller.state.status));

    await controller.startListening();

    expect(statuses, <SpeechFormulaStatus>[
      SpeechFormulaStatus.requestingPermission,
      SpeechFormulaStatus.listening,
    ]);
  });

  test(
    'manual stop 先进入 transcribing，final 后 resolving 且 stop 完成不覆盖 resolved',
    () async {
      final stopGate = Completer<void>();
      final recognizer = _FakeRecognizer(stopGate: stopGate);
      final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_resolved()),
      ]);
      final controller = _controller(
        recognizer: recognizer,
        repository: repository,
      );
      addTearDown(controller.dispose);
      final statuses = <SpeechFormulaStatus>[];
      controller.addListener(() => statuses.add(controller.state.status));
      await controller.startListening();

      final stopping = controller.stopListening();
      expect(controller.state.status, SpeechFormulaStatus.transcribing);
      recognizer.emit('x 的平方', isFinal: true);
      await _flushAsyncWork();
      expect(controller.state.status, SpeechFormulaStatus.resolved);
      stopGate.complete();
      await stopping;

      expect(
        statuses,
        containsAllInOrder(<SpeechFormulaStatus>[
          SpeechFormulaStatus.transcribing,
          SpeechFormulaStatus.resolving,
          SpeechFormulaStatus.resolved,
        ]),
      );
      expect(controller.state.selectedCandidate?.latex, 'x^2');
      expect(controller.state.errorMessage, isNull);
    },
  );

  test('V2 三类 outcome 精确映射且语义结果不占用 errorMessage', () async {
    final fixtures =
        <({SpokenFormulaResolution value, SpeechFormulaStatus want})>[
          (value: _resolved(), want: SpeechFormulaStatus.resolved),
          (value: _candidates(), want: SpeechFormulaStatus.choosingCandidate),
          (value: _clarification(), want: SpeechFormulaStatus.clarifying),
        ];

    for (final fixture in fixtures) {
      final recognizer = _FakeRecognizer();
      final controller = _controller(
        recognizer: recognizer,
        repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
          Future<SpokenFormulaResolution>.value(fixture.value),
        ]),
      );
      await controller.startListening();
      recognizer.emit('测试公式', isFinal: true);
      await _flushAsyncWork();

      expect(controller.state.status, fixture.want);
      expect(controller.state.resolution, same(fixture.value));
      expect(controller.state.errorMessage, isNull);
      controller.dispose();
    }
  });

  test('clarification 续录保留累计文字并用中文逗号合并后重新解析', () async {
    final recognizer = _FakeRecognizer();
    final clarification = _clarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(clarification),
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('二阶行列式', isFinal: true);
    await _flushAsyncWork();

    expect(controller.canContinueRecording, isTrue);
    await controller.continueRecording();

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(controller.state.transcript, '二阶行列式');
    expect(controller.state.accumulatedTranscript, '二阶行列式');
    expect(controller.state.continuationTurn, 0);
    expect(controller.state.resolution, same(clarification));
    recognizer.emit('第一行 x 加一', isFinal: true, listenIndex: 1);
    await _flushAsyncWork();

    expect(repository.texts, <String>['二阶行列式', '二阶行列式，第一行 x 加一']);
    expect(controller.state.transcript, '二阶行列式，第一行 x 加一');
    expect(controller.state.accumulatedTranscript, '二阶行列式，第一行 x 加一');
    expect(controller.state.continuationTurn, 1);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
  });

  test('clarification 未提供 continueRecording 时不可绕过服务端动作续录', () async {
    final recognizer = _FakeRecognizer();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_retryClarification()),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('只允许整段重录', isFinal: true);
    await _flushAsyncWork();

    expect(controller.canContinueRecording, isFalse);
    await controller.continueRecording();
    expect(recognizer.listenCount, 1);
    expect(controller.state.status, SpeechFormulaStatus.clarifying);
  });

  test('deadline 保留 transcript 后可续录并以新 operation 合并重新解析', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit(
      '二阶行列式',
      isFinal: true,
      processingElapsed: const Duration(seconds: 5),
    );
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.canContinueRecording, isTrue);
    await controller.continueRecording();
    recognizer.emit('第一行 x 加一', isFinal: true, listenIndex: 1);
    await _flushAsyncWork();

    expect(repository.texts, <String>['二阶行列式，第一行 x 加一']);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.continuationTurn, 1);
  });

  test('续录隔离上一 operation 的迟到 final 且空补充不发起请求', () async {
    final recognizer = _FakeRecognizer();
    final clarification = _clarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(clarification),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('待澄清公式', isFinal: true, listenIndex: 0);
    await _flushAsyncWork();

    await controller.continueRecording();
    recognizer.emit('旧轮次迟到结果', isFinal: true, listenIndex: 0);
    recognizer.emit('   ', isFinal: true, listenIndex: 1);
    await _flushAsyncWork();

    expect(repository.texts, <String>['待澄清公式']);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, '待澄清公式');
    expect(controller.state.continuationTurn, 0);
    expect(controller.state.resolution, same(clarification));
  });

  test('续录启动失败仍保留累计文字和上一轮安全响应', () async {
    final recognizer = _FakeRecognizer(
      listenErrors: <Object?>[null, StateError('listen failed')],
    );
    final clarification = _clarification();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(clarification),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('待澄清公式', isFinal: true);
    await _flushAsyncWork();

    await controller.continueRecording();

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, '待澄清公式');
    expect(controller.state.accumulatedTranscript, '待澄清公式');
    expect(controller.state.resolution, same(clarification));
    expect(controller.canContinueRecording, isTrue);
  });

  test('续录 ASR 失败后的重试会重新录音而不是重试旧转写解析', () async {
    final recognizer = _FakeRecognizer();
    final clarification = _clarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(clarification),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('二阶行列式', isFinal: true);
    await _flushAsyncWork();
    await controller.continueRecording();
    recognizer.emitError(
      const SpokenFormulaRecognitionException('本机语音识别超时，请重新录音。'),
    );

    await controller.retryResolution();

    expect(recognizer.listenCount, 3);
    expect(repository.callCount, 1);
    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(controller.state.transcript, isEmpty);
    expect(controller.state.accumulatedTranscript, isEmpty);
    expect(controller.state.resolution, isNull);
  });

  test('无 transcript 的权限错误不可续录', () async {
    final controller = _controller(
      recognizer: _FakeRecognizer(
        isAvailable: false,
        initializationError: const SpokenFormulaRecognitionException(
          '麦克风权限不可用',
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.startListening();

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, isEmpty);
    expect(controller.canContinueRecording, isFalse);
  });

  test('最多完成三轮续录，整段重录会清空累计上下文', () async {
    final recognizer = _FakeRecognizer();
    final resolution = _clarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      for (var index = 0; index < 4; index += 1)
        Future<SpokenFormulaResolution>.value(resolution),
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('主体', isFinal: true);
    await _flushAsyncWork();

    for (var turn = 1; turn <= 3; turn += 1) {
      expect(controller.canContinueRecording, isTrue);
      await controller.continueRecording();
      recognizer.emit('补充 $turn', isFinal: true, listenIndex: turn);
      await _flushAsyncWork();
      expect(controller.state.continuationTurn, turn);
    }

    expect(controller.canContinueRecording, isFalse);
    await controller.continueRecording();
    expect(recognizer.listenCount, 4);

    await controller.startListening();
    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(controller.state.transcript, isEmpty);
    expect(controller.state.accumulatedTranscript, isEmpty);
    expect(controller.state.continuationTurn, 0);

    recognizer.emit('全新公式', isFinal: true, listenIndex: 4);
    await _flushAsyncWork();

    expect(repository.texts.last, '全新公式');
    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.continuationTurn, 0);
  });

  test('第三轮续录耗尽 deadline 后不再误提示可以继续补充', () async {
    final recognizer = _FakeRecognizer();
    final clarification = _clarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      for (var index = 0; index < 3; index += 1)
        Future<SpokenFormulaResolution>.value(clarification),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('主体', isFinal: true);
    await _flushAsyncWork();

    for (var turn = 1; turn <= 2; turn += 1) {
      await controller.continueRecording();
      recognizer.emit('补充 $turn', isFinal: true, listenIndex: turn);
      await _flushAsyncWork();
    }
    await controller.continueRecording();
    recognizer.emit(
      '补充 3',
      isFinal: true,
      processingElapsed: const Duration(seconds: 5),
      listenIndex: 3,
    );
    await _flushAsyncWork();

    expect(controller.state.continuationTurn, 3);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.canContinueRecording, isFalse);
    expect(controller.state.errorMessage, isNot(contains('继续补充语音')));
  });

  test('麦克风、ASR、网络与畸形响应统一进入 infrastructureError', () async {
    final cases = <_InfrastructureFailureCase>[
      _InfrastructureFailureCase(
        recognizer: _FakeRecognizer(
          isAvailable: false,
          initializationError: const SpokenFormulaRecognitionException(
            '麦克风权限不可用',
          ),
        ),
        repository: _QueueRepository(const <Future<SpokenFormulaResolution>>[]),
        trigger: (recognizer) async {},
        expectedMessage: '麦克风权限不可用',
      ),
      _InfrastructureFailureCase(
        recognizer: _FakeRecognizer(),
        repository: _QueueRepository(const <Future<SpokenFormulaResolution>>[]),
        trigger: (recognizer) async {
          recognizer.emitError(
            const SpokenFormulaRecognitionException('ASR 暂时不可用'),
          );
        },
        expectedMessage: 'ASR 暂时不可用',
      ),
      _InfrastructureFailureCase(
        recognizer: _FakeRecognizer(),
        repository: _ErrorRepository(StateError('network internals')),
        trigger: (recognizer) async {
          recognizer.emit('网络测试', isFinal: true);
          await _flushAsyncWork();
        },
        expectedMessage: '公式解析暂时不可用，请稍后重试。',
      ),
      _InfrastructureFailureCase(
        recognizer: _FakeRecognizer(),
        repository: _ErrorRepository(
          const SpokenFormulaResolutionException('公式服务返回的数据不完整，请重新说一次。'),
        ),
        trigger: (recognizer) async {
          recognizer.emit('畸形响应测试', isFinal: true);
          await _flushAsyncWork();
        },
        expectedMessage: '公式服务返回的数据不完整，请重新说一次。',
      ),
    ];

    for (final fixture in cases) {
      final controller = _controller(
        recognizer: fixture.recognizer,
        repository: fixture.repository,
      );
      await controller.startListening();
      await fixture.trigger(fixture.recognizer);

      expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
      expect(controller.state.errorMessage, fixture.expectedMessage);
      controller.dispose();
    }
  });

  test('infrastructureError 同帧双击 retryResolution 只发一个新请求', () async {
    final recognizer = _FakeRecognizer();
    final repository = _RetryRepository();
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('需要重试的公式', isFinal: true);
    await _flushAsyncWork();
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(repository.callCount, 1);

    final firstRetry = controller.retryResolution();
    final secondRetry = controller.retryResolution();
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.resolving);
    expect(repository.callCount, 2);
    repository.retryGate.complete(_resolved());
    await Future.wait<void>(<Future<void>>[firstRetry, secondRetry]);

    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(repository.callCount, 2);
  });

  test('5 秒总预算中 ASR 用时 4 秒时 repository 只收到预留后的 0.5 秒', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(seconds: 5),
    );
    addTearDown(controller.dispose);
    await controller.startListening();

    recognizer.emit(
      'x 的平方',
      isFinal: true,
      processingElapsed: const Duration(seconds: 4),
    );
    await _flushAsyncWork();

    expect(repository.timeouts, <Duration>[const Duration(milliseconds: 500)]);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
  });

  test('ASR 超过 4.5 秒时不调用 repository 并保留 final 文本可续录', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(
      const <Future<SpokenFormulaResolution>>[],
    );
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();

    recognizer.emit(
      '从负一到二的定积分',
      isFinal: true,
      processingElapsed: const Duration(milliseconds: 4600),
    );
    await _flushAsyncWork();

    expect(repository.timeouts, isEmpty);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, '从负一到二的定积分');
    expect(controller.canContinueRecording, isTrue);
  });

  test('watchdog 已启动时迟到 Browser final 使用真实剩余预算', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    var fakeNow = Duration.zero;
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(seconds: 1),
      responseDeliveryReserve: const Duration(milliseconds: 500),
      monotonicNow: () => fakeNow,
    );
    addTearDown(controller.dispose);
    final manualTimers = <_ManualTimer>[];

    await runZoned(
      () async {
        await controller.startListening();
        recognizer.emitFinalizationStarted();
        fakeNow += const Duration(milliseconds: 200);

        recognizer.emit('迟到的完整公式', isFinal: true);
        await _flushAsyncWork();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 1)) {
            final timer = _ManualTimer(duration, callback);
            manualTimers.add(timer);
            return timer;
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(manualTimers, hasLength(1));
    expect(repository.timeouts, <Duration>[const Duration(milliseconds: 300)]);
    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.transcript, '迟到的完整公式');
  });

  test(
    'Browser final 无 processingElapsed 时请求预算为 4.5 秒但 watchdog 仍为 5 秒',
    () async {
      final recognizer = _FakeRecognizer();
      final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_resolved()),
      ]);
      final controller = _controller(
        recognizer: recognizer,
        repository: repository,
      );
      addTearDown(controller.dispose);
      final observedTimers = <Duration>[];

      await runZoned(
        () async {
          await controller.startListening();
          recognizer.emit('x 的平方', isFinal: true);
          await _flushAsyncWork();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration > Duration.zero) observedTimers.add(duration);
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );

      expect(repository.timeouts, <Duration>[
        const Duration(milliseconds: 4500),
      ]);
      expect(observedTimers, contains(const Duration(seconds: 5)));
      expect(controller.state.status, SpeechFormulaStatus.resolved);
    },
  );

  test('watchdog 从空文本启动后会绑定同 operation 的迟到 final 文本', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Completer<SpokenFormulaResolution>().future,
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    final manualTimers = <_ManualTimer>[];

    await runZoned(
      () async {
        await controller.startListening();
        recognizer.emitFinalizationStarted();
        recognizer.emit(
          '从负一到二的定积分',
          isFinal: true,
          processingElapsed: const Duration(seconds: 1),
        );
        await _flushAsyncWork();
        manualTimers
            .singleWhere((timer) => timer.delay == const Duration(seconds: 5))
            .fire();
        await _flushAsyncWork();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration >= const Duration(seconds: 1)) {
            final timer = _ManualTimer(duration, callback);
            manualTimers.add(timer);
            return timer;
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(repository.callCount, 1);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, '从负一到二的定积分');
    expect(controller.canContinueRecording, isTrue);
  });

  test('watchdog 启动后 partial 更新也会保留为可恢复文本', () async {
    final recognizer = _FakeRecognizer();
    final controller = _controller(recognizer: recognizer);
    addTearDown(controller.dispose);
    final manualTimers = <_ManualTimer>[];

    await runZoned(
      () async {
        await controller.startListening();
        recognizer.emitFinalizationStarted();
        recognizer.emit('已识别的部分公式', isFinal: false);
        manualTimers
            .singleWhere((timer) => timer.delay == const Duration(seconds: 5))
            .fire();
        await _flushAsyncWork();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 5)) {
            final timer = _ManualTimer(duration, callback);
            manualTimers.add(timer);
            return timer;
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.transcript, '已识别的部分公式');
    expect(controller.canContinueRecording, isTrue);
  });

  test('negative responseDeliveryReserve 在运行时拒绝', () {
    expect(
      () => _controller(
        responseDeliveryReserve: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test('retryResolution 为响应交付预留 0.5 秒', () async {
    final recognizer = _FakeRecognizer();
    final repository = _RetryRepository();
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('需要重试的公式', isFinal: true);
    await _flushAsyncWork();

    final retrying = controller.retryResolution();
    await _flushAsyncWork();

    expect(repository.timeouts.last, const Duration(milliseconds: 4500));
    repository.retryGate.complete(_resolved());
    await retrying;
  });

  test('repository 永不完成时按注入的总 deadline 退出且只调用一次', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Completer<SpokenFormulaResolution>().future,
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(milliseconds: 12),
      responseDeliveryReserve: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('不会结束的解析', isFinal: true);
    expect(controller.state.status, SpeechFormulaStatus.resolving);

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(controller.state.errorMessage, contains('5 秒'));
    expect(controller.state.errorMessage, contains('继续补充语音'));
    expect(controller.canContinueRecording, isTrue);
    expect(repository.callCount, 1);
  });

  test('主动 stop 挂起时 watchdog 按总 deadline 退出并隔离 late final', () async {
    final stopGate = Completer<void>();
    final cancelGate = Completer<void>();
    final recognizer = _FakeRecognizer(
      stopGate: stopGate,
      cancelGates: <Completer<void>>[cancelGate],
    );
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
      totalDeadline: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.startListening();

    final stopping = controller.stopListening();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    final statusAtDeadline = controller.state.status;
    final messageAtDeadline = controller.state.errorMessage;
    final cancelCallsAtDeadline = recognizer.cancelCount;

    recognizer.emit(
      '迟到公式',
      isFinal: true,
      processingElapsed: const Duration(milliseconds: 10),
    );
    stopGate.complete();
    cancelGate.complete();
    await stopping;
    await _flushAsyncWork();

    expect(statusAtDeadline, SpeechFormulaStatus.infrastructureError);
    expect(messageAtDeadline, contains('5 秒'));
    expect(messageAtDeadline, isNot(contains('继续补充语音')));
    expect(controller.canContinueRecording, isFalse);
    expect(cancelCallsAtDeadline, 1);
    expect(repository.callCount, 0);
    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
  });

  test('ASR processingElapsed 已耗尽预算时不调用 repository', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(
      const <Future<SpokenFormulaResolution>>[],
    );
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();

    recognizer.emit(
      '超时文本',
      isFinal: true,
      processingElapsed: const Duration(seconds: 5),
    );
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(repository.callCount, 0);
  });

  test('reset 使迟到 resolution 失效', () async {
    final gate = Completer<SpokenFormulaResolution>();
    final recognizer = _FakeRecognizer();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        gate.future,
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('旧请求', isFinal: true);
    await controller.reset();

    gate.complete(_resolved());
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(controller.state.resolution, isNull);
  });

  test('第二次录音使第一次迟到 resolution 失效', () async {
    final oldGate = Completer<SpokenFormulaResolution>();
    final newGate = Completer<SpokenFormulaResolution>();
    final recognizer = _FakeRecognizer();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        oldGate.future,
        newGate.future,
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('旧请求', isFinal: true, listenIndex: 0);
    await controller.startListening();
    recognizer.emit('新请求', isFinal: true, listenIndex: 1);

    oldGate.complete(_resolved(resolutionId: 'old', latex: 'old'));
    await _flushAsyncWork();
    expect(controller.state.status, SpeechFormulaStatus.resolving);
    newGate.complete(_resolved(resolutionId: 'new', latex: 'new'));
    await _flushAsyncWork();

    expect(controller.state.resolution?.resolutionId, 'new');
    expect(controller.state.selectedCandidate?.latex, 'new');
  });

  test('dispose 使迟到 resolution 无法通知页面且 recognizer 只释放一次', () async {
    final gate = Completer<SpokenFormulaResolution>();
    final recognizer = _FakeRecognizer(
      disposeError: StateError('plugin internals'),
    );
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        gate.future,
      ]),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    await controller.startListening();
    recognizer.emit('待销毁请求', isFinal: true);
    final beforeDispose = notifications;

    controller.dispose();
    controller.dispose();
    gate.complete(_resolved());
    await _flushAsyncWork();

    expect(notifications, beforeDispose);
    expect(recognizer.disposeCount, 1);
  });

  test('用户确认后失效旧回调并返回当前响应唯一公式', () async {
    final recognizer = _FakeRecognizer();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_resolved()),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();

    expect(controller.confirmSelectedCandidate(), 'x^2');
    recognizer.emit('旧 final', isFinal: true);
    await _flushAsyncWork();

    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(controller.state.resolution, isNull);
  });

  test('确认后立即重新录音必须等待旧 cancel 完成', () async {
    final cancelGate = Completer<void>();
    final recognizer = _FakeRecognizer(
      cancelGates: <Completer<void>>[cancelGate],
    );
    final controller = _controller(recognizer: recognizer);
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();

    expect(controller.confirmSelectedCandidate(), 'x^2');
    final restarting = controller.startListening();
    await _flushAsyncWork();
    final statusBeforeCancel = controller.state.status;
    final listensBeforeCancel = recognizer.listenCount;

    cancelGate.complete();
    await restarting;

    expect(statusBeforeCancel, SpeechFormulaStatus.requestingPermission);
    expect(listensBeforeCancel, 1);
    expect(recognizer.cancelCount, 1);
    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(recognizer.listenCount, 2);
  });

  test('迟到 reset finally 不能覆盖更晚的新 listening', () async {
    final oldCancelGate = Completer<void>();
    final newCancelGate = Completer<void>();
    final recognizer = _FakeRecognizer(
      cancelGates: <Completer<void>>[oldCancelGate, newCancelGate],
    );
    final controller = _controller(recognizer: recognizer);
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();

    final resetting = controller.reset();
    await _flushAsyncWork();
    final restarting = controller.startListening();
    await _flushAsyncWork();
    newCancelGate.complete();
    await _flushAsyncWork();
    oldCancelGate.complete();
    await Future.wait<void>(<Future<void>>[resetting, restarting]);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(recognizer.listenCount, 2);
  });

  test('只能按当前 response candidate ID 选择候选', () async {
    final recognizer = _FakeRecognizer();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_candidates()),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('负二的平方', isFinal: true);
    await _flushAsyncWork();

    controller.selectCandidate('candidate-from-old-response');
    expect(controller.state.selectedCandidate, isNull);
    controller.selectCandidate('candidate-b');

    expect(controller.state.selectedCandidate?.id, 'candidate-b');
    expect(controller.state.status, SpeechFormulaStatus.choosingCandidate);
  });

  test('clarification selectCandidate 只选择同响应候选并进入 resolved', () async {
    final recognizer = _FakeRecognizer();
    final resolution = _clarification();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(resolution),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('负二的平方', isFinal: true);
    await _flushAsyncWork();

    await controller.answerClarification(resolution.clarification!.options[0]);

    expect(controller.state.status, SpeechFormulaStatus.resolved);
    expect(controller.state.selectedCandidate?.id, 'candidate-b');
    expect(controller.state.errorMessage, isNull);
  });

  test('clarification continueRecording 保留累计文字并启动独立续录', () async {
    final recognizer = _FakeRecognizer();
    final resolution = _continuationClarification();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Future<SpokenFormulaResolution>.value(resolution),
      Future<SpokenFormulaResolution>.value(_resolved()),
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('二阶行列式', isFinal: true);
    await _flushAsyncWork();

    await controller.answerClarification(resolution.clarification!.options[0]);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(controller.state.transcript, '二阶行列式');
    expect(recognizer.listenCount, 2);
    recognizer.emit('第一行一二第二行三四', isFinal: true, listenIndex: 1);
    await _flushAsyncWork();
    expect(repository.texts, <String>['二阶行列式', '二阶行列式，第一行一二第二行三四']);
  });

  test('clarification retryRecording 开启新录音且隔离旧回调', () async {
    final recognizer = _FakeRecognizer();
    final resolution = _retryClarification();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(resolution),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('待澄清', isFinal: true);
    await _flushAsyncWork();

    await controller.answerClarification(resolution.clarification!.options[0]);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(recognizer.listenCount, 2);
    recognizer.emit('旧 late final', isFinal: true, listenIndex: 0);
    await _flushAsyncWork();
    expect(controller.state.status, SpeechFormulaStatus.listening);
  });

  test('迟到 clarification retry cleanup 不能启动第三轮录音', () async {
    final oldCancelGate = Completer<void>();
    final newCancelGate = Completer<void>();
    final recognizer = _FakeRecognizer(
      cancelGates: <Completer<void>>[oldCancelGate, newCancelGate],
    );
    final resolution = _retryClarification();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(resolution),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('待澄清', isFinal: true);
    await _flushAsyncWork();

    final answering = controller.answerClarification(
      resolution.clarification!.options[0],
    );
    await _flushAsyncWork();
    final restarting = controller.startListening();
    await _flushAsyncWork();
    newCancelGate.complete();
    await _flushAsyncWork();
    oldCancelGate.complete();
    await Future.wait<void>(<Future<void>>[answering, restarting]);

    expect(controller.state.status, SpeechFormulaStatus.listening);
    expect(recognizer.listenCount, 2);
  });

  test('dispose 等待 pending cancel 后再释放 recognizer 且无迟到通知', () async {
    final cancelGate = Completer<void>();
    final events = <String>[];
    final recognizer = _FakeRecognizer(
      cancelGates: <Completer<void>>[cancelGate],
      lifecycleEvents: events,
    );
    final controller = _controller(recognizer: recognizer);
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    await controller.startListening();
    recognizer.emit('x 的平方', isFinal: true);
    await _flushAsyncWork();
    final beforeCleanup = notifications;
    controller.confirmSelectedCandidate();

    controller.dispose();
    await _flushAsyncWork();
    final eventsBeforeCancelCompletes = List<String>.of(events);
    cancelGate.complete();
    await _flushAsyncWork();

    expect(eventsBeforeCancelCompletes, <String>['cancel:start']);
    expect(events, <String>['cancel:start', 'cancel:end', 'dispose']);
    expect(notifications, beforeCleanup + 1);
  });

  test('clarification useKeyboard 回到 idle 且不产生选中答案', () async {
    final recognizer = _FakeRecognizer();
    final resolution = _clarification();
    final controller = _controller(
      recognizer: recognizer,
      repository: _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(resolution),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.startListening();
    recognizer.emit('待澄清', isFinal: true);
    await _flushAsyncWork();

    await controller.answerClarification(resolution.clarification!.options[2]);

    expect(controller.state.status, SpeechFormulaStatus.idle);
    expect(controller.state.selectedCandidate, isNull);
    expect(controller.state.resolution, isNull);
  });
  test('解析内层超时与外层 watchdog 对齐时只落入一个终态', () async {
    final recognizer = _FakeRecognizer();
    final repository = _QueueRepository(<Future<SpokenFormulaResolution>>[
      Completer<SpokenFormulaResolution>().future,
    ]);
    final controller = _controller(
      recognizer: recognizer,
      repository: repository,
    );
    addTearDown(controller.dispose);
    final terminalStatuses = <SpeechFormulaStatus>[];
    controller.addListener(() {
      if (controller.state.status == SpeechFormulaStatus.infrastructureError) {
        terminalStatuses.add(controller.state.status);
      }
    });
    final timers = <_ManualTimer>[];

    await runZoned(
      () async {
        await controller.startListening();
        recognizer.emit(
          '二阶行列式',
          isFinal: true,
          processingElapsed: Duration.zero,
        );
        await _flushAsyncWork();
        timers
            .singleWhere(
              (timer) => timer.delay == const Duration(milliseconds: 4500),
            )
            .fire();
        await _flushAsyncWork();
        timers
            .singleWhere((timer) => timer.delay == const Duration(seconds: 5))
            .fire();
        await _flushAsyncWork();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration >= const Duration(seconds: 1)) {
            final timer = _ManualTimer(duration, callback);
            timers.add(timer);
            return timer;
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );

    expect(controller.state.status, SpeechFormulaStatus.infrastructureError);
    expect(terminalStatuses, <SpeechFormulaStatus>[
      SpeechFormulaStatus.infrastructureError,
    ]);
    expect(repository.callCount, 1);
  });
}

SpeechFormulaController _controller({
  _FakeRecognizer? recognizer,
  SpokenFormulaResolutionRepository? repository,
  Duration totalDeadline = const Duration(seconds: 5),
  Duration responseDeliveryReserve = spokenFormulaResponseDeliveryReserve,
  Duration Function()? monotonicNow,
}) => SpeechFormulaController(
  recognizer: recognizer ?? _FakeRecognizer(),
  repository:
      repository ??
      _QueueRepository(<Future<SpokenFormulaResolution>>[
        Future<SpokenFormulaResolution>.value(_resolved()),
      ]),
  totalDeadline: totalDeadline,
  responseDeliveryReserve: responseDeliveryReserve,
  monotonicNow: monotonicNow,
);

SpokenFormulaResolution _resolved({
  String resolutionId = 'resolution-resolved',
  String latex = 'x^2',
}) => SpokenFormulaResolution(
  resolutionId: resolutionId,
  recognizedText: 'x 的平方',
  normalizedText: 'x 的平方',
  outcome: SpokenFormulaOutcome.resolved,
  candidates: <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-a',
      latex: latex,
      spokenBack: 'x 的平方',
    ),
  ],
  clarification: null,
  warnings: const <String>[],
);

SpokenFormulaResolution _candidates() => SpokenFormulaResolution(
  resolutionId: 'resolution-candidates',
  recognizedText: '负二的平方',
  normalizedText: '负二的平方',
  outcome: SpokenFormulaOutcome.candidates,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-a',
      latex: '(-2)^2',
      spokenBack: '负二整体的平方',
    ),
    SpokenFormulaCandidate(
      id: 'candidate-b',
      latex: '-2^2',
      spokenBack: '二的平方再取负',
    ),
  ],
  clarification: null,
  warnings: const <String>['存在作用域歧义'],
);

SpokenFormulaResolution _clarification() => SpokenFormulaResolution(
  resolutionId: 'resolution-clarification',
  recognizedText: '负二的平方',
  normalizedText: '负二的平方',
  outcome: SpokenFormulaOutcome.clarification,
  candidates: const <SpokenFormulaCandidate>[
    SpokenFormulaCandidate(
      id: 'candidate-b',
      latex: '-2^2',
      spokenBack: '二的平方再取负',
    ),
  ],
  clarification: SpokenFormulaClarification(
    question: '负号是否在平方范围内？',
    focusText: '负二的平方',
    options: const <SpokenFormulaClarificationOption>[
      SpokenFormulaClarificationOption(
        id: 'select-negative-outside',
        label: '平方后再取负',
        action: SpokenFormulaClarificationAction.selectCandidate,
        candidateId: 'candidate-b',
      ),
      SpokenFormulaClarificationOption(
        id: 'continue',
        label: '继续补充语音',
        action: SpokenFormulaClarificationAction.continueRecording,
      ),
      SpokenFormulaClarificationOption(
        id: 'keyboard',
        label: '使用键盘',
        action: SpokenFormulaClarificationAction.useKeyboard,
      ),
    ],
  ),
  warnings: const <String>[],
);

SpokenFormulaResolution _retryClarification() => SpokenFormulaResolution(
  resolutionId: 'resolution-retry-clarification',
  recognizedText: '负二的平方',
  normalizedText: '负二的平方',
  outcome: SpokenFormulaOutcome.clarification,
  candidates: const <SpokenFormulaCandidate>[],
  clarification: SpokenFormulaClarification(
    question: '请重新完整表达公式。',
    focusText: '负二的平方',
    options: const <SpokenFormulaClarificationOption>[
      SpokenFormulaClarificationOption(
        id: 'retry',
        label: '重新说',
        action: SpokenFormulaClarificationAction.retryRecording,
      ),
      SpokenFormulaClarificationOption(
        id: 'keyboard',
        label: '使用键盘',
        action: SpokenFormulaClarificationAction.useKeyboard,
      ),
    ],
  ),
  warnings: const <String>[],
);

SpokenFormulaResolution _continuationClarification() => SpokenFormulaResolution(
  resolutionId: 'resolution-continuation',
  recognizedText: '二阶行列式',
  normalizedText: '二阶行列式',
  outcome: SpokenFormulaOutcome.clarification,
  candidates: const <SpokenFormulaCandidate>[],
  clarification: SpokenFormulaClarification(
    question: '请继续补充每一行的元素。',
    focusText: '二阶行列式',
    options: const <SpokenFormulaClarificationOption>[
      SpokenFormulaClarificationOption(
        id: 'continue',
        label: '继续补充语音',
        action: SpokenFormulaClarificationAction.continueRecording,
      ),
      SpokenFormulaClarificationOption(
        id: 'keyboard',
        label: '使用键盘',
        action: SpokenFormulaClarificationAction.useKeyboard,
      ),
    ],
  ),
  warnings: const <String>[],
);

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 4; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeRecognizer implements SpeechFormulaRecognizer {
  _FakeRecognizer({
    this.isAvailable = true,
    this.initializationError,
    this.stopGate,
    this.disposeError,
    List<Object?>? listenErrors,
    List<Completer<void>>? cancelGates,
    this.lifecycleEvents,
  }) : _listenErrors = listenErrors ?? <Object?>[],
       _cancelGates = cancelGates ?? <Completer<void>>[];

  final bool isAvailable;
  @override
  final SpokenFormulaRecognitionException? initializationError;
  final Completer<void>? stopGate;
  final Object? disposeError;
  final List<Object?> _listenErrors;
  final List<Completer<void>> _cancelGates;
  final List<String>? lifecycleEvents;
  final List<SpeechFormulaResultCallback> _resultCallbacks =
      <SpeechFormulaResultCallback>[];
  final List<SpeechFormulaErrorCallback?> _errorCallbacks =
      <SpeechFormulaErrorCallback?>[];
  final List<SpeechFormulaFinalizationStartedCallback?>
  _finalizationStartedCallbacks = <SpeechFormulaFinalizationStartedCallback?>[];
  int listenCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  @override
  Future<bool> initialize() async => isAvailable;

  @override
  Future<void> listen({
    required SpeechFormulaResultCallback onResult,
    SpeechFormulaErrorCallback? onError,
    SpeechFormulaFinalizationStartedCallback? onFinalizationStarted,
  }) async {
    final index = listenCount;
    listenCount += 1;
    _resultCallbacks.add(onResult);
    _errorCallbacks.add(onError);
    _finalizationStartedCallbacks.add(onFinalizationStarted);
    if (index < _listenErrors.length) {
      final error = _listenErrors[index];
      if (error != null) throw error;
    }
  }

  void emit(
    String words, {
    required bool isFinal,
    Duration? processingElapsed,
    int? listenIndex,
  }) {
    _resultCallbacks[listenIndex ?? _resultCallbacks.length - 1](
      words,
      isFinal: isFinal,
      processingElapsed: processingElapsed,
    );
  }

  void emitError(SpokenFormulaRecognitionException error, {int? listenIndex}) {
    _errorCallbacks[listenIndex ?? _errorCallbacks.length - 1]?.call(error);
  }

  void emitFinalizationStarted({int? listenIndex}) {
    _finalizationStartedCallbacks[listenIndex ??
            _finalizationStartedCallbacks.length - 1]
        ?.call();
  }

  @override
  Future<void> stop() async => stopGate?.future;

  @override
  Future<void> cancel() async {
    final index = cancelCount;
    cancelCount += 1;
    lifecycleEvents?.add('cancel:start');
    if (index < _cancelGates.length) await _cancelGates[index].future;
    lifecycleEvents?.add('cancel:end');
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    lifecycleEvents?.add('dispose');
    if (disposeError case final error?) throw error;
  }
}

final class _QueueRepository implements SpokenFormulaResolutionRepository {
  _QueueRepository(this._responses);

  final List<Future<SpokenFormulaResolution>> _responses;
  final List<Duration> timeouts = <Duration>[];
  final List<String> texts = <String>[];
  int callCount = 0;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) {
    texts.add(text);
    timeouts.add(timeout);
    final response = _responses[callCount];
    callCount += 1;
    return response;
  }
}

final class _ErrorRepository implements SpokenFormulaResolutionRepository {
  const _ErrorRepository(this.error);

  final Object error;

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    await Future<void>.delayed(Duration.zero);
    throw error;
  }
}

final class _RetryRepository implements SpokenFormulaResolutionRepository {
  final Completer<SpokenFormulaResolution> retryGate =
      Completer<SpokenFormulaResolution>();
  int callCount = 0;
  final List<Duration> timeouts = <Duration>[];

  @override
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  }) async {
    callCount += 1;
    timeouts.add(timeout);
    if (callCount == 1) {
      throw const SpokenFormulaResolutionException('首次请求失败');
    }
    return retryGate.future;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  var _isActive = true;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _callback();
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;

  @override
  void cancel() {
    _isActive = false;
  }
}

final class _InfrastructureFailureCase {
  const _InfrastructureFailureCase({
    required this.recognizer,
    required this.repository,
    required this.trigger,
    required this.expectedMessage,
  });

  final _FakeRecognizer recognizer;
  final SpokenFormulaResolutionRepository repository;
  final Future<void> Function(_FakeRecognizer recognizer) trigger;
  final String expectedMessage;
}
