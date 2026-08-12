import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/technical_trace.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/technical_trace_drawer.dart';

void main() {
  group('MockTechnicalTraceProvider', () {
    test('uses real guided facts and marks only MCP details simulated', () {
      final trace = const MockTechnicalTraceProvider().build(
        _snapshot(guided: true),
      );

      expect(trace.isMock, isTrue);
      expect(trace.hasGuidedDecision, isTrue);
      expect(trace.currentNodeId, 'node-1');
      expect(trace.atomId, 'negative-times-negative');
      expect(trace.stageLabel, '动手验证');
      expect(trace.reasonCode, 'GUIDED_OPERATIONAL_EVIDENCE_REQUIRED');
      expect(trace.latestEvidence?.code, 'PRIOR_HYPOTHESIS_RECORDED');
      expect(trace.missingEvidenceCodes, ['NEGATIVE_SIGN_OPERATION_OBSERVED']);
      expect(trace.mcpSelection.isSimulated, isTrue);
      expect(
        trace.mcpSelection.selectedMaterialId,
        'negative-sign-flip-widget',
      );
    });

    test('does not invent guided decisions for open exploration', () {
      final trace = const MockTechnicalTraceProvider().build(
        _snapshot(guided: false),
      );

      expect(trace.hasGuidedDecision, isFalse);
      expect(trace.lessonPlanId, isEmpty);
      expect(trace.reasonCode, isEmpty);
      expect(trace.latestEvidence, isNull);
      expect(trace.mcpSelection.candidateCount, 0);
      expect(trace.mcpSelection.selectedMaterialId, isEmpty);
    });
  });

  group('TechnicalTraceDrawer', () {
    testWidgets('labels mock data and renders the documented trace sections', (
      tester,
    ) async {
      final trace = const MockTechnicalTraceProvider().build(
        _snapshot(guided: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TechnicalTraceDrawer(trace: trace)),
        ),
      );

      expect(find.byKey(const ValueKey('technical-trace-drawer')), findsOne);
      expect(
        find.byKey(const ValueKey('technical-trace-mock-banner')),
        findsOne,
      );
      expect(find.text('Mock 演示数据'), findsOne);
      expect(find.byKey(const ValueKey('technical-trace-context')), findsOne);
      expect(find.byKey(const ValueKey('technical-trace-evidence')), findsOne);

      final listView = find.byType(ListView);
      await tester.drag(listView, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('technical-trace-action')), findsOne);
      expect(find.text('GUIDED_OPERATIONAL_EVIDENCE_REQUIRED'), findsOne);

      await tester.drag(listView, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('technical-trace-mcp')), findsOne);
      expect(find.text('素材选择（模拟）'), findsOne);

      await tester.drag(listView, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('technical-trace-timing')), findsOne);
    });

    testWidgets('shows an honest empty state for open exploration', (
      tester,
    ) async {
      final trace = const MockTechnicalTraceProvider().build(
        _snapshot(guided: false),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TechnicalTraceDrawer(trace: trace)),
        ),
      );

      expect(find.text('当前为开放探索，暂无引导式技术轨迹'), findsOne);
      expect(find.text('GUIDED_OPERATIONAL_EVIDENCE_REQUIRED'), findsNothing);
    });
  });
}

RemoteLearningSessionSnapshot _snapshot({required bool guided}) {
  return RemoteLearningSessionSnapshot.fromJson({
    'session': {
      'id': 'session-trace-1',
      'exploreSessionId': 'explore-trace-1',
      'topic': '为什么负负得正',
      'scenarioId': 'chapter',
      'atomId': 'negative-times-negative',
      'status': 'ACTIVE',
      'revision': 2,
      'nodeCount': 1,
      'startedAt': '2026-08-11T01:00:00.000Z',
      'expiresAt': '2026-08-11T03:00:00.000Z',
    },
    'currentNodeId': 'node-1',
    'activeStrategy': 'SOCRATIC',
    'nodes': [
      {
        'id': 'node-1',
        'status': 'ACTIVE',
        'question': '为什么两个负数相乘会得到正数？',
        'answer': '我们先用连续两次取相反数来观察。',
        'followUpQuestion': '第二次操作后回到了哪里？',
        'depth': 0,
        'isSideBranch': false,
        'createdAt': '2026-08-11T01:00:10.000Z',
      },
    ],
    'conceptNodes': const [],
    'materials': [
      {
        'id': 'material-usage-1',
        'nodeId': 'node-1',
        'materialId': 'negative-sign-flip-widget',
        'type': 'INTERACTIVE',
        'title': '连续取相反数',
        'componentKey': 'sign_flip_widget',
        'payload': const {},
      },
    ],
    if (guided)
      'teachingFlow': {
        'schemaVersion': 1,
        'mode': 'GUIDED_LESSON',
        'stage': 'ASSET',
        'lessonPlanId': 'negative-sign-guided-v1',
        'atomId': 'negative-times-negative',
        'goal': '通过方向翻转解释为什么负负得正。',
        'assetEvidenceCode': 'NEGATIVE_SIGN_OPERATION_OBSERVED',
        'independentEvidenceCode': 'NEGATIVE_SIGN_RULE_EXPLAINED_INDEPENDENTLY',
        'practiceId': 'negative-sign-prediction',
        'currentAction': {
          'schemaVersion': 1,
          'type': 'SHOW_ASSET',
          'prompt': '完成两次取相反数并观察结果。',
          'pedagogicalIntent': 'COLLECT_OPERATIONAL_EVIDENCE',
          'reasonCode': 'GUIDED_OPERATIONAL_EVIDENCE_REQUIRED',
          'materialUsageId': 'material-usage-1',
        },
        'evidence': {
          'schemaVersion': 1,
          'requiredCodes': [
            'PRIOR_HYPOTHESIS_RECORDED',
            'NEGATIVE_SIGN_OPERATION_OBSERVED',
          ],
          'items': [
            {
              'code': 'PRIOR_HYPOTHESIS_RECORDED',
              'strength': 'OBSERVED',
              'sourceType': 'PRACTICE_ATTEMPT',
              'sourceId': 'answer-1',
              'recordedAt': '2026-08-11T01:00:15.000Z',
            },
          ],
          'missingCodes': ['NEGATIVE_SIGN_OPERATION_OBSERVED'],
          'isReadyForMicroCheck': false,
        },
        'hintLevel': 0,
        'updatedAt': '2026-08-11T01:00:20.000Z',
      },
  });
}
