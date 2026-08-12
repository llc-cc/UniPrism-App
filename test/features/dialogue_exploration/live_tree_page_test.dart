import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/guided_teaching_flow_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_api.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';
import 'package:uniprism_app/features/dialogue_exploration/core/remote_exploration_session_controller.dart';
import 'package:uniprism_app/features/dialogue_exploration/presentation/remote_exploration_page.dart';

void main() {
  testWidgets('active history is restored before the chapter catalog loads', (
    tester,
  ) async {
    final api = _UiFakeApi(
      history: const [
        RemoteLearningSessionSummary(
          id: 'learning-active',
          exploreSessionId: 'explore-1',
          topic: '可继续的预习',
          scenarioId: 'prestudy',
          atomId: 'negative-times-negative',
          status: 'ACTIVE',
          nodeCount: 1,
          startedAt: '2026-08-05T01:00:00.000Z',
          expiresAt: '2099-08-05T01:10:00.000Z',
          completedAt: null,
          lastActiveAt: '2026-08-05T01:08:00.000Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ai-exploration-classroom')),
      findsOneWidget,
    );
    expect(api.catalogCalls, 0);
  });

  testWidgets(
    'returning from restored history shows catalog without loading a chapter',
    (tester) async {
      final api = _UiFakeApi(
        history: const [
          RemoteLearningSessionSummary(
            id: 'learning-active',
            exploreSessionId: 'explore-1',
            topic: '可继续的预习',
            scenarioId: 'prestudy',
            atomId: 'negative-times-negative',
            status: 'ACTIVE',
            nodeCount: 1,
            startedAt: '2026-08-05T01:00:00.000Z',
            expiresAt: '2099-08-05T01:10:00.000Z',
            completedAt: null,
            lastActiveAt: '2026-08-05T01:08:00.000Z',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('prestudy-back-to-overview')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('chapter-catalog-picker')),
        findsOneWidget,
      );
      expect(api.catalogCalls, 1);
      expect(api.chapterOverviewIds, isEmpty);
      expect(api.createCalls, 0);
    },
  );

  testWidgets(
    'disposed page does not request catalog after delayed history finishes',
    (tester) async {
      final historyCompleter = Completer<List<RemoteLearningSessionSummary>>();
      final api = _UiFakeApi(historyCompleter: historyCompleter);

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      historyCompleter.complete(const []);
      await tester.pumpAndSettle();

      expect(api.catalogCalls, 0);
    },
  );

  testWidgets(
    'history request keeps catalog empty state hidden while loading',
    (tester) async {
      final historyCompleter = Completer<List<RemoteLearningSessionSummary>>();
      final api = _UiFakeApi(historyCompleter: historyCompleter);

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('当前暂无已审核的预习章节'), findsNothing);
      historyCompleter.complete(const []);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'catalog lists provider chapters and loads only the selected chapter',
    (tester) async {
      final api = _UiFakeApi(
        catalog: const [
          LearningChapterCatalogItem(
            chapterId: 'provider-chapter',
            title: '服务端章节',
            description: '只由 Provider 返回的章节。',
            estimatedMinutes: 20,
            availableNodeCount: 3,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chapter-catalog-picker')),
        findsOneWidget,
      );
      expect(find.text('服务端章节'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('chapter-catalog-provider-chapter')),
      );
      await tester.pumpAndSettle();

      expect(api.chapterOverviewIds, ['provider-chapter']);
      expect(api.createCalls, 0);
      expect(
        find.byKey(const ValueKey('student-mission-hero')),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty catalog does not create a learning session', (
    tester,
  ) async {
    final api = _UiFakeApi(catalog: const []);

    await tester.pumpWidget(
      MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前暂无已审核的预习章节'), findsOneWidget);
    expect(api.createCalls, 0);
    expect(api.chapterOverviewIds, isEmpty);
  });

  testWidgets(
    'catalog failure remains recoverable and retry requests it again',
    (tester) async {
      final api = _UiFakeApi(failCatalog: true);

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pumpAndSettle();

      expect(find.text('操作失败，请重试。'), findsOneWidget);
      api.failCatalog = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(api.catalogCalls, 2);
      expect(
        find.byKey(const ValueKey('chapter-catalog-picker')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'chapter workspace presents one mission and keeps secondary routes collapsed',
    (tester) async {
      final api = _UiFakeApi();
      await _pumpChapterWorkspace(tester, api);

      expect(find.text('负数运算'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('student-mission-hero')),
        findsOneWidget,
      );
      expect(find.text('为什么两个负数相乘会得到正数？'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chapter-learning-journey-strip')),
        findsOneWidget,
      );
      expect(find.text('先发现规律'), findsOneWidget);
      expect(find.text('动手试一试'), findsOneWidget);
      expect(find.text('回看我的发现'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chapter-phase-learning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-phase-practice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-phase-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-question-switcher')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('direct-ai-teacher-entry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-knowledge-tree')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('direct-ai-teacher-question')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chapter-exploration-question-0')),
        findsNothing,
      );
      expect(find.text('从一个问题开始探索'), findsNothing);
      expect(find.text('预计 10 分钟'), findsNothing);
      expect(
        find.byKey(const ValueKey('chapter-enter-selected-node')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chapter-enter-selected-node-with-question')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'chapter workspace provides a visible action to enter the selected node',
    (tester) async {
      final api = _UiFakeApi();
      await _pumpChapterWorkspace(tester, api);

      final enterAction = find.byKey(
        const ValueKey('chapter-enter-selected-node'),
      );
      expect(enterAction, findsOneWidget);

      await tester.ensureVisible(enterAction);
      await tester.tap(enterAction);
      await tester.pumpAndSettle();

      expect(api.createCalls, 1);
      expect(api.lastCreateAtomId, 'negative-times-negative');
    },
  );

  testWidgets('account history opens completed dialogue trees read-only', (
    tester,
  ) async {
    final api = _UiFakeApi(
      history: const [
        RemoteLearningSessionSummary(
          id: 'learning-old',
          exploreSessionId: 'explore-1',
          topic: '负数乘法历史预习',
          scenarioId: 'prestudy',
          atomId: 'negative-times-negative',
          status: 'COMPLETED',
          nodeCount: 4,
          startedAt: '2026-08-05T01:00:00.000Z',
          expiresAt: '2026-08-05T01:10:00.000Z',
          completedAt: '2026-08-05T01:08:00.000Z',
          lastActiveAt: '2026-08-05T01:08:00.000Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prestudy-history-section')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('prestudy-history-learning-old')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prestudy-read-only-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prestudy-question-composer')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('open-concept-map')));
    await tester.pumpAndSettle();
    expect(find.text('从这里继续问'), findsNothing);
    expect(find.text('从这里开分支'), findsNothing);
    await tester.tap(find.byTooltip('关闭探索地图'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prestudy-back-to-overview')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prestudy-history-section')),
      findsOneWidget,
    );
  });

  testWidgets(
    'history restore failure stays visible and retry runs the full initialization',
    (tester) async {
      final api = _UiFakeApi(failHistory: true);

      await tester.pumpWidget(
        MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
      );
      await tester.pumpAndSettle();

      expect(find.text('操作失败，请重试。'), findsOneWidget);
      expect(find.text('负数运算'), findsNothing);

      api.failHistory = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(api.listCalls, 2);
      expect(find.text('负数运算'), findsOneWidget);
    },
  );

  testWidgets(
    'chapter workspace keeps a free AI teacher question in the selected guided node',
    (tester) async {
      final api = _UiFakeApi();
      await _pumpChapterWorkspace(tester, api);

      final directEntry = find.byKey(const ValueKey('direct-ai-teacher-entry'));
      await tester.ensureVisible(directEntry);
      await tester.pumpAndSettle();
      await tester.tap(directEntry);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('direct-ai-teacher-question')),
        '为什么天空是蓝色？',
      );
      final directStart = find.byKey(const ValueKey('direct-ai-teacher-start'));
      await tester.ensureVisible(directStart);
      await tester.pumpAndSettle();
      await tester.tap(directStart);
      await tester.pumpAndSettle();

      expect(api.createCalls, 1);
      expect(api.lastCreateAtomId, 'negative-times-negative');
      expect(api.lastCreateFlowMode, RemoteFlowMode.guidedLesson);
      expect(api.lastCreateQuestion, '为什么天空是蓝色？');
    },
  );

  testWidgets(
    'chapter mission starts exploration with the student own question',
    (tester) async {
      final api = _UiFakeApi();
      await _pumpChapterWorkspace(tester, api);

      expect(
        find.byKey(const ValueKey('chapter-intuition-check')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chapter-free-question')),
        '我想先验证负号是不是代表方向',
      );
      await tester.tap(
        find.byKey(const ValueKey('chapter-enter-selected-node')),
      );
      await tester.pumpAndSettle();

      expect(api.createCalls, 1);
      expect(api.lastCreateAtomId, 'negative-times-negative');
      expect(api.lastCreateQuestion, '我想先验证负号是不是代表方向');
    },
  );

  testWidgets('chapter question switcher keeps a nearby start action', (
    tester,
  ) async {
    final api = _UiFakeApi();
    await _pumpChapterWorkspace(tester, api);

    final questionSwitcher = find.byKey(
      const ValueKey('chapter-question-switcher'),
    );
    await tester.ensureVisible(questionSwitcher);
    await tester.pumpAndSettle();
    await tester.tap(questionSwitcher);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chapter-node-opposite-number')),
    );
    await tester.pumpAndSettle();

    expect(find.text('相反数与方向翻转'), findsWidgets);
    final nearbyStart = find.byKey(
      const ValueKey('chapter-enter-switched-node'),
    );
    await tester.ensureVisible(nearbyStart);
    await tester.pumpAndSettle();
    await tester.tap(nearbyStart);
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastCreateAtomId, 'negative-times-negative');
    expect(api.lastCreateQuestion, '连续两次取相反数会怎样？');
  });

  testWidgets(
    'desktop classroom is full width and opens the concept map only on demand',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exploration-mission-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('exploration-session-timer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai-exploration-classroom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('personal-thinking-tree')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-sidebar-current-path')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('exploration-live-tree')), findsNothing);
      expect(find.byKey(const ValueKey('concept-path-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-concept-map')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('knowledge-overview-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chapter-knowledge-tree')),
        findsNothing,
      );
      expect(find.text('查看完整地图'), findsNothing);
      expect(
        find.byKey(const ValueKey('learning-assets-preview')),
        findsNothing,
      );
      expect(find.text('导出探索地图'), findsOneWidget);
      expect(find.text('学习素材'), findsNothing);
      expect(find.text('知识结构图（章节地图）'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-concept-map')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('concept-map-sheet')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('personal-thinking-tree')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'session follows the dialogue exploration flow instead of a course banner',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(api: _UiFakeApi());
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天，我们一起发现一个秘密'), findsOneWidget);
      expect(find.text('你的问题'), findsWidgets);
      expect(find.text('AI 老师回应'), findsWidgets);
      expect(find.text('下一步'), findsWidgets);
      expect(
        find.byKey(const ValueKey('student-learning-timeline')),
        findsOneWidget,
      );
      expect(find.text('AI 探索课堂'), findsNothing);
      expect(find.text('AI 反问'), findsNothing);
      expect(find.textContaining('正在突破：'), findsNothing);
      expect(find.text('我的探索地图'), findsNothing);
      expect(find.byKey(const ValueKey('concept-path-strip')), findsOneWidget);
      expect(find.textContaining('今日探索'), findsNothing);
      expect(find.textContaining('预计 10 分钟'), findsNothing);
      expect(find.textContaining('探索阶段'), findsNothing);
      expect(find.text('当前探索路径'), findsNothing);
      expect(find.text('5/20 个问题节点'), findsNothing);
      expect(find.text('验证理解'), findsNothing);
      expect(find.text('是什么'), findsNothing);
      expect(find.text('为什么会这样'), findsNothing);
      expect(find.text('如果……会怎样'), findsNothing);
      expect(find.text('这和 X 有什么关系'), findsNothing);
      expect(find.text('这有什么用'), findsNothing);
      expect(
        find.byKey(const ValueKey('remote-question-input')),
        findsOneWidget,
      );
    },
  );

  testWidgets('answer card keeps model-prior provenance out of student view', (
    tester,
  ) async {
    final controller = RemoteExplorationSessionController(
      api: _UiFakeApi(answerSource: 'MODEL_PRIOR'),
    );
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实 AI · 模型知识'), findsNothing);
    expect(find.text('安全兜底'), findsNothing);
  });

  testWidgets(
    'answer card turns a deterministic fallback into a current hint',
    (tester) async {
      final controller = RemoteExplorationSessionController(
        api: _UiFakeApi(answerSource: 'SAFE_FALLBACK'),
      );
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前提示'), findsOneWidget);
      expect(find.text('安全兜底'), findsNothing);
      expect(find.text('真实 AI · 模型知识'), findsNothing);
    },
  );

  testWidgets('answer card keeps knowledge provenance out of student view', (
    tester,
  ) async {
    final controller = RemoteExplorationSessionController(
      api: _UiFakeApi(answerSource: 'KNOWLEDGE_BASE'),
    );
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实 AI · 知识库依据'), findsNothing);
  });

  testWidgets('legacy answer card omits provenance labels', (tester) async {
    final controller = RemoteExplorationSessionController(api: _UiFakeApi());
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实 AI · 模型知识'), findsNothing);
    expect(find.text('真实 AI · 知识库依据'), findsNothing);
    expect(find.text('安全兜底'), findsNothing);
  });

  testWidgets(
    'classroom keeps the active question path visible for further exploration',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(
        api: _UiFakeApi(sessionSnapshot: _longPathSnapshot()),
      );
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 1 个探索问题'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('student-question-node-0')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('student-question-node-11')),
        420,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('exploration-classroom-stage')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('第 12 个探索问题'), findsWidgets);
      expect(
        find.byKey(const ValueKey('student-question-node-11')),
        findsOneWidget,
      );
    },
  );

  testWidgets('concept map opens on demand and keeps a long path scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(sessionSnapshot: _longPathSnapshot());
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('exploration-live-tree')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-concept-map')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('exploration-node-node-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('exploration-node-node-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('exploration-node-node-11')),
      findsOneWidget,
    );
  });

  testWidgets('concept map keeps pre-study focused on the exploration tree', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RemoteExplorationSessionController(
      api: _UiFakeApi(sessionSnapshot: _learningEvidenceSnapshot()),
    );
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-concept-map')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('learning-evidence-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('personal-thinking-tree')),
      findsOneWidget,
    );
  });

  testWidgets(
    'exploration map presents saved concepts as a connected node canvas',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(
        api: _UiFakeApi(sessionSnapshot: _longPathSnapshot()),
      );
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-concept-map')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exploration-node-canvas')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-node-node-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-node-node-5')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('exploration-node-node-11')),
        findsOneWidget,
      );
      expect(find.text('当前探索节点'), findsOneWidget);
    },
  );

  testWidgets(
    'opposite-number material lets the learner inspect a real number change',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RemoteExplorationSessionController(
        api: _UiFakeApi(sessionSnapshot: _signFlipSnapshot()),
      );
      await controller.loadChapter('negative-number-operations');
      await controller.startFromChapterNode('negative-times-negative-concept');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('选一个数，再亲手执行“取相反数”。'), findsOneWidget);
      expect(find.textContaining('当前方向'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('sign-flip-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-flip-apply')));
      await tester.pump();
      expect(find.text('-3  →  3'), findsOneWidget);
    },
  );

  testWidgets('full thinking tree remains readable for a long path on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(sessionSnapshot: _longPathSnapshot());
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadChapter('negative-number-operations');
    await controller.startFromChapterNode('negative-times-negative-concept');

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-concept-map')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('exploration-node-node-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('exploration-node-node-11')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('exploration-node-node-11')))
          .width,
      greaterThanOrEqualTo(180),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop keeps the classroom full width with a lightweight concept path',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('exploration-classroom-stage')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('exploration-live-tree')), findsNothing);
      expect(find.byKey(const ValueKey('concept-path-strip')), findsOneWidget);
      expect(find.text('这一步成立需要什么条件？'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a tree node is read-only and reveals explicit actions',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-concept-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exploration-node-node-1')));
      await tester.pump();

      expect(api.branchCalls, 0);
      expect(api.turnCalls, 0);
      expect(api.backtrackCalls, 0);
      expect(
        find.byKey(const ValueKey('exploration-node-focus-card')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'mobile keeps the exploration map trigger visible and can expand the full map',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi();
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start(directionId: 'graph');
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('concept-path-strip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-concept-map')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('concept-map-sheet')), findsOneWidget);
    },
  );

  testWidgets('guided asset stage keeps the operation with the current step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.asset),
      ),
    );
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('guided-teaching-action-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('student-learning-journey')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('student-verification-message')),
      findsOneWidget,
    );
    expect(find.text('我们验证一下'), findsOneWidget);
    expect(find.text('动手验证'), findsOneWidget);
    expect(find.text('还需要一次验证，确认你的想法'), findsOneWidget);
    expect(find.textContaining('证据 '), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guided-teaching-action-panel')),
        matching: find.text('选一个数，再亲手执行“取相反数”。'),
      ),
      findsOneWidget,
    );

    FilledButton completeButton() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('guided-asset-complete-button')),
    );
    expect(completeButton().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('sign-flip-apply')));
    await tester.pump();
    expect(completeButton().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('sign-flip-apply')));
    await tester.pump();
    expect(find.text('-3  →  3  →  -3'), findsOneWidget);
    expect(completeButton().onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('guided-asset-complete-button')),
    );
    await tester.pumpAndSettle();

    expect(api.materialEventCalls, 1);
    expect(api.lastMaterialEventType, 'SIGN_FLIPPED');
  });

  testWidgets('guided action follows the latest AI response in the timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.asset),
      ),
    );
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('student-learning-timeline')),
        matching: find.byKey(const ValueKey('guided-teaching-action-panel')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guided-teaching-action-panel')),
      findsOneWidget,
    );
  });

  testWidgets(
    'dialogue-first guided flow shows exploration acts before verification',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(
            RemoteTeachingStage.dialogue,
            explorationAct: RemoteGuidedExplorationAct.probeReason,
          ),
        ),
      );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('说说为什么会这样想'), findsOneWidget);
      expect(find.text('明确问题'), findsOneWidget);
      expect(find.text('观察深挖'), findsOneWidget);
      expect(find.text('迁移应用'), findsOneWidget);
      expect(find.text('AI 老师回应'), findsWidgets);
      expect(find.text('一起验证'), findsNothing);
      expect(
        find.byKey(const ValueKey('guided-start-micro-check-button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'technical trace drawer opens read-only without advancing the session',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(RemoteTeachingStage.asset),
        ),
      );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();
      final initialSnapshot = controller.state.snapshot;

      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-technical-trace')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('technical-trace-drawer')),
        findsOneWidget,
      );
      expect(find.text('Mock 演示数据'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close-technical-trace')));
      await tester.pumpAndSettle();
      expect(controller.state.snapshot, same(initialSnapshot));
      expect(api.materialEventCalls, 0);
      expect(api.practiceCalls, 0);
    },
  );

  testWidgets('guided transfer stage opens the server-selected new situation', (
    tester,
  ) async {
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.focus),
      ),
    );
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('换个情况试试'), findsWidgets);

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('remote-send-question')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('remote-question-input')),
          )
          .onSubmitted,
      isNull,
    );

    await _tapVisible(tester, 'guided-start-micro-check-button');
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('guided-practice-submit-button')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('guided-practice-submit-button')),
      findsOneWidget,
    );
    expect(find.text('服务端独立验证题'), findsOneWidget);
    expect(find.text('请说明连续两次方向翻转后的结果。'), findsOneWidget);
    expect(find.text('服务端推理标签'), findsOneWidget);
    expect(find.text('服务端答案标签'), findsOneWidget);
    expect(find.text('提交我的判断'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('guided-practice-submit-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('guided-practice-reasoning-input')),
      '连续翻转两次会回到原方向',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guided-practice-answer-input')),
      '正数',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('guided-practice-submit-button')),
    );
    await tester.pump();

    expect(api.practiceCalls, 1);
    expect(api.lastPracticeId, 'active-negative-sign-prediction');
    expect(
      find.byKey(const ValueKey('guided-practice-submit-button')),
      findsNothing,
    );
  });

  testWidgets(
    'guided practice failure preserves its draft and retries the same request',
    (tester) async {
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(RemoteTeachingStage.focus),
        ),
      )..failNextPractice = true;
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pump();

      await _tapVisible(tester, 'guided-start-micro-check-button');
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('guided-practice-reasoning-input')),
        '草稿推理',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guided-practice-answer-input')),
        '草稿答案',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('guided-practice-submit-button')),
      );
      await tester.pump();

      expect(find.text('服务端独立验证题'), findsOneWidget);
      expect(find.text('草稿推理'), findsOneWidget);
      expect(find.text('草稿答案'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guided-practice-retry-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('guided-practice-retry-button')),
      );
      await tester.pump();
      expect(api.practiceIdempotencyKeys, hasLength(2));
      expect(api.practiceIdempotencyKeys.toSet(), hasLength(1));
    },
  );

  testWidgets('guided practice exposes close only after submission failure', (
    tester,
  ) async {
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.focus),
      ),
    )..failNextPractice = true;
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pump();

    await _tapVisible(tester, 'guided-start-micro-check-button');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('guided-practice-close-button')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('guided-practice-reasoning-input')),
      '草稿推理',
    );
    await tester.enterText(
      find.byKey(const ValueKey('guided-practice-answer-input')),
      '草稿答案',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('guided-practice-submit-button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('guided-practice-close-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('guided-practice-close-button')),
    );
    await tester.pump();

    expect(find.text('服务端独立验证题'), findsNothing);
    expect(
      find.byKey(const ValueKey('prestudy-question-composer')),
      findsOneWidget,
    );
    expect(find.text('练习提交失败'), findsOneWidget);
    expect(controller.state.status, RemoteExplorationStatus.failed);
    expect(api.practiceCalls, 1);
  });

  testWidgets(
    'missing active practice shows recovery instead of an empty form',
    (tester) async {
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(
            RemoteTeachingStage.focus,
            includeActivePractice: false,
          ),
        ),
      );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pump();

      await _tapVisible(tester, 'guided-start-micro-check-button');
      await tester.pump();
      expect(find.text('暂时无法打开新情境'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guided-practice-reasoning-input')),
        findsNothing,
      );
    },
  );

  testWidgets('guided repair shows student feedback without internal codes', (
    tester,
  ) async {
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(
          RemoteTeachingStage.dialogue,
          feedback: '你已经找到了方向变化，再补充为什么会回到原处。',
          repairFocus: '连续两次取相反数会抵消符号变化。',
          supportLevel: 3,
          explorationAct: RemoteGuidedExplorationAct.transferRevisit,
        ),
      ),
    );
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('你已经找到了方向变化，再补充为什么会回到原处。'), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-repair-focus')), findsOneWidget);
    expect(find.text('连续两次取相反数会抵消符号变化。'), findsOneWidget);
    expect(find.text('回到发现，修正薄弱点'), findsOneWidget);
    expect(find.textContaining('先回到探索'), findsOneWidget);
    expect(find.text('我们先完整走一遍例子，再换一道新题由你独立完成。'), findsOneWidget);
    expect(find.textContaining('PARTIAL'), findsNothing);
    expect(find.textContaining('RETRY'), findsNothing);
    expect(find.textContaining('MASTERED'), findsNothing);
  });

  testWidgets(
    'V1 guided flow renders its existing stage action without V2 data',
    (tester) async {
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(RemoteTeachingStage.asset),
        ),
      );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('guided-teaching-action-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('guided-asset-complete-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('next-learning-options')), findsNothing);
    },
  );

  testWidgets(
    'empty next-learning options retain the finish action without creating a session',
    (tester) async {
      final completed = _withTeachingFlow(
        _completedSignFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.reflect),
      );
      final api = _UiFakeApi(
        sessionSnapshot: _withTeachingFlow(
          _signFlipSnapshot(),
          _guidedTeachingFlow(RemoteTeachingStage.reflect),
        ),
        completeSnapshot: completed,
      );
      final controller = RemoteExplorationSessionController(api: api);
      await controller.loadEntry('quadratic-function');
      await controller.start();
      await tester.pumpWidget(
        MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
      );
      await tester.pump();

      await _tapVisible(tester, 'guided-start-reflection-button');
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '我已经完成当前知识点。');
      await tester.tap(find.text('结束预习并生成探索结果'));
      await tester.pump();

      expect(find.text('当前暂无已审核的进阶方向'), findsOneWidget);
      expect(api.createCalls, 1);
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('先结束'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(find.byKey(const ValueKey('next-learning-options')), findsNothing);
      expect(api.createCalls, 1);
    },
  );

  testWidgets('guided reflection exposes choices without auto-starting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completed = _withTeachingFlow(
      _completedSignFlipSnapshot(),
      _guidedTeachingFlow(
        RemoteTeachingStage.reflect,
        nextLearningOptions: const [
          RemoteNextLearningOption(
            atomId: 'integer-division',
            chapterId: 'integer-operations',
            title: '整数除法',
            relation: '把符号规则迁移到除法。',
            difficultyReason: '需要同时判断商的方向。',
            estimatedMinutes: 8,
            hookQuestion: '除法的符号怎样判断？',
            prerequisitesSatisfied: true,
          ),
          RemoteNextLearningOption(
            atomId: 'rational-number',
            chapterId: 'integer-operations',
            title: '有理数运算',
            relation: '先完成整数除法。',
            difficultyReason: '它会组合多条规则。',
            estimatedMinutes: 12,
            hookQuestion: '怎样统一处理有理数？',
            prerequisitesSatisfied: false,
          ),
        ],
      ),
    );
    final api = _UiFakeApi(
      sessionSnapshot: _withTeachingFlow(
        _signFlipSnapshot(),
        _guidedTeachingFlow(RemoteTeachingStage.reflect),
      ),
      completeSnapshot: completed,
    );
    final controller = RemoteExplorationSessionController(api: api);
    await controller.loadEntry('quadratic-function');
    await controller.start();
    api.failNextCreate = true;
    await tester.pumpWidget(
      MaterialApp(home: RemoteLearningSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, 'guided-start-reflection-button');
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '我理解两次翻转会抵消。');
    await tester.tap(find.text('结束预习并生成探索结果'));
    await tester.pump();

    expect(find.byKey(const ValueKey('next-learning-options')), findsOneWidget);
    expect(api.createCalls, 1);
    final locked = tester.widget<FilledButton>(
      find.byKey(const ValueKey('next-learning-rational-number')),
    );
    expect(locked.onPressed, isNull);

    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('next-learning-integer-division')),
        )
        .onPressed!();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('next-learning-retry-button')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('next-learning-integer-division')),
          )
          .onPressed,
      isNull,
    );
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('next-learning-retry-button')),
        )
        .onPressed!();
    await tester.pump();
    expect(api.createCalls, 3);
    expect(api.createIdempotencyKeys.skip(1).toSet(), hasLength(1));
    expect(api.lastCreateAtomId, 'integer-division');
  });
}

Future<void> _pumpChapterWorkspace(WidgetTester tester, _UiFakeApi api) async {
  await tester.pumpWidget(
    MaterialApp(home: RemoteExplorationLabPage(gateway: api)),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('chapter-catalog-negative-number-operations')),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

const _defaultCatalog = <LearningChapterCatalogItem>[
  LearningChapterCatalogItem(
    chapterId: 'negative-number-operations',
    title: '负数运算',
    description: '从负数意义出发理解运算规则。',
    estimatedMinutes: 30,
    availableNodeCount: 2,
  ),
];

final class _UiFakeApi implements RemoteExplorationGateway {
  _UiFakeApi({
    this._sessionSnapshot,
    this.completeSnapshot,
    this.answerSource,
    this.history = const [],
    this.failHistory = false,
    this.catalog = _defaultCatalog,
    this.failCatalog = false,
    this.historyCompleter,
  });

  final RemoteLearningSessionSnapshot? _sessionSnapshot;
  final RemoteLearningSessionSnapshot? completeSnapshot;
  final String? answerSource;
  final List<RemoteLearningSessionSummary> history;
  bool failHistory;
  final List<LearningChapterCatalogItem> catalog;
  bool failCatalog;
  final Completer<List<RemoteLearningSessionSummary>>? historyCompleter;
  int listCalls = 0;
  int catalogCalls = 0;
  int turnCalls = 0;
  int branchCalls = 0;
  int backtrackCalls = 0;
  int createCalls = 0;
  int materialEventCalls = 0;
  int practiceCalls = 0;
  bool failNextPractice = false;
  bool failNextCreate = false;
  String? lastCreateAtomId;
  String? lastCreateQuestion;
  RemoteFlowMode? lastCreateFlowMode;
  String? lastMaterialEventType;
  String? lastPracticeId;
  final List<String?> createIdempotencyKeys = [];
  final List<String?> practiceIdempotencyKeys = [];
  final List<String> chapterOverviewIds = [];

  @override
  Future<List<LearningChapterCatalogItem>> listChapterCatalog() async {
    catalogCalls += 1;
    if (failCatalog) throw StateError('catalog unavailable');
    return catalog;
  }

  final chapter = LearningChapterOverviewSnapshot(
    chapterId: 'negative-number-operations',
    title: '负数运算',
    description: '从负数意义出发理解运算规则。',
    estimatedMinutes: 30,
    progress: .2,
    recommendedNodeId: 'negative-times-negative-concept',
    phases: const [
      LearningChapterPhaseSnapshot(
        kind: 'LEARNING',
        title: '学习',
        summary: '理解概念',
        status: 'IN_PROGRESS',
        progress: .3,
        itemCount: 2,
      ),
      LearningChapterPhaseSnapshot(
        kind: 'PRACTICE',
        title: '练习',
        summary: '验证规则',
        status: 'AVAILABLE',
        progress: 0,
        itemCount: 1,
      ),
      LearningChapterPhaseSnapshot(
        kind: 'REVIEW',
        title: '复习',
        summary: '回顾易错点',
        status: 'LOCKED',
        progress: 0,
        itemCount: 1,
      ),
    ],
    nodes: const [
      LearningChapterNodeSnapshot(
        id: 'opposite-number',
        parentId: null,
        atomId: 'negative-times-negative',
        title: '相反数与方向翻转',
        description: '理解连续两次方向翻转。',
        phase: 'LEARNING',
        hookQuestion: '连续两次取相反数会怎样？',
        recommended: false,
      ),
      LearningChapterNodeSnapshot(
        id: 'negative-times-negative-concept',
        parentId: 'opposite-number',
        atomId: 'negative-times-negative',
        title: '为什么负负得正',
        description: '验证负数乘法规则。',
        phase: 'LEARNING',
        hookQuestion: '为什么两个负数相乘会得到正数？',
        recommended: true,
      ),
    ],
  );

  final entry = LearningEntrySnapshot(
    atomId: 'quadratic-function',
    title: '二次函数探索',
    coreQuestion: '为什么抛物线会出现？',
    estimatedMinutes: 10,
    recommendedDirectionId: 'graph',
    directions: const [
      LearningDirectionSnapshot(
        id: 'basic',
        title: '基础概念',
        description: '先看二次意味着什么',
        hookQuestion: '什么是二次函数？',
      ),
      LearningDirectionSnapshot(
        id: 'graph',
        title: '图像秘密',
        description: '观察顶点和开口方向',
        hookQuestion: '二次函数的顶点为什么在这里？',
      ),
      LearningDirectionSnapshot(
        id: 'application',
        title: '现实应用',
        description: '连接最值问题',
        hookQuestion: '二次函数能解决哪些现实问题？',
      ),
    ],
  );

  RemoteLearningSessionSnapshot get snapshot =>
      _sessionSnapshot ??
      RemoteLearningSessionSnapshot(
        session: const RemoteLearningSessionInfo(
          id: 'learning-1',
          exploreSessionId: 'explore-1',
          topic: '二次函数探索',
          scenarioId: 'teaching',
          atomId: 'quadratic-function',
          status: 'ACTIVE',
          revision: 1,
          nodeCount: 1,
          startedAt: '2026-08-06T01:00:00.000Z',
          expiresAt: '2099-08-06T01:10:00.000Z',
          completedAt: null,
        ),
        currentNodeId: 'node-1',
        activeStrategy: 'QUESTION_CHAIN',
        nodes: [
          RemoteLearningNode(
            id: 'node-1',
            parentId: null,
            status: 'VALIDATED',
            question: '二次函数的顶点为什么在这里？',
            answer: '顶点来自完全平方结构。',
            followUpQuestion: '这一步成立需要什么条件？',
            answerSource: answerSource,
            strategy: 'QUESTION_CHAIN',
            depth: 0,
            isSideBranch: false,
            backtrackTargetId: null,
            confidence: .8,
            createdAt: '2026-08-06T01:00:00.000Z',
          ),
        ],
        materials: const [
          RemoteLearningMaterial(
            id: 'material-1',
            nodeId: 'node-1',
            materialId: 'quadratic-parabola-widget',
            type: 'INTERACTIVE',
            title: '拖动参数观察抛物线',
            componentKey: 'parabola_widget',
            payload: {},
          ),
        ],
        summary: null,
      );

  @override
  Future<LearningChapterOverviewSnapshot> getChapterOverview(
    String chapterId,
  ) async {
    chapterOverviewIds.add(chapterId);
    return chapter;
  }

  @override
  Future<LearningEntrySnapshot> getEntry(String atomId) async => entry;

  @override
  Future<RemoteLearningSessionSnapshot> createSession({
    String? atomId,
    required String scenarioId,
    String? directionId,
    String? question,
    String? idempotencyKey,
    RemoteFlowMode flowMode = RemoteFlowMode.openExploration,
  }) async {
    createCalls += 1;
    createIdempotencyKeys.add(idempotencyKey);
    if (failNextCreate) {
      failNextCreate = false;
      throw const RemoteExplorationException('创建失败');
    }
    lastCreateAtomId = atomId;
    lastCreateQuestion = question;
    lastCreateFlowMode = flowMode;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot?> restoreLatest() async => null;

  @override
  Future<List<RemoteLearningSessionSummary>> listSessions() async {
    listCalls += 1;
    final pendingHistory = historyCompleter;
    if (pendingHistory != null) return pendingHistory.future;
    if (failHistory) throw StateError('history unavailable');
    return history;
  }

  @override
  Future<RemoteLearningSessionSnapshot> restoreSession(
    RemoteLearningSessionSummary summary,
  ) async {
    return RemoteLearningSessionSnapshot(
      session: snapshot.session.copyWith(
        status: summary.status,
        expiresAt: summary.expiresAt,
      ),
      currentNodeId: snapshot.currentNodeId,
      activeStrategy: snapshot.activeStrategy,
      nodes: snapshot.nodes,
      materials: snapshot.materials,
      summary: snapshot.summary,
    );
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitTurn({
    required String sessionId,
    required String question,
    String? parentNodeId,
    String? idempotencyKey,
  }) async {
    turnCalls += 1;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> createBranch({
    required String sessionId,
    required String parentNodeId,
    required String question,
    String? idempotencyKey,
  }) async {
    branchCalls += 1;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> backtrack({
    required String sessionId,
    required String targetNodeId,
    String? idempotencyKey,
  }) async {
    backtrackCalls += 1;
    return snapshot;
  }

  @override
  Future<Map<String, Object?>> createMemoryCandidate({
    required String sessionId,
    required String nodeId,
    String? idempotencyKey,
  }) async => const {'id': 'memory-1', 'status': 'PENDING'};

  @override
  Future<RemoteLearningSessionSnapshot> complete({
    required String sessionId,
    required String reflection,
    String? idempotencyKey,
  }) async => completeSnapshot ?? snapshot;

  @override
  Future<RemoteLearningSessionSnapshot> submitPracticeAttempt({
    required String sessionId,
    required String practiceId,
    required String reasoning,
    required String answer,
    String? idempotencyKey,
  }) async {
    practiceCalls += 1;
    practiceIdempotencyKeys.add(idempotencyKey);
    if (failNextPractice) {
      failNextPractice = false;
      throw const RemoteExplorationException('练习提交失败');
    }
    lastPracticeId = practiceId;
    return snapshot;
  }

  @override
  Future<RemoteLearningSessionSnapshot> submitMaterialEvent({
    required String sessionId,
    required String materialUsageId,
    required RemoteAssetEvent event,
    String? idempotencyKey,
  }) async {
    materialEventCalls += 1;
    lastMaterialEventType = event.eventType;
    return snapshot;
  }

  @override
  Future<String> exportTree(String sessionId) async => '{"schemaVersion":1}';
}

RemoteLearningSessionSnapshot _withTeachingFlow(
  RemoteLearningSessionSnapshot snapshot,
  RemoteTeachingFlow flow,
) {
  return RemoteLearningSessionSnapshot(
    session: snapshot.session,
    currentNodeId: snapshot.currentNodeId,
    activeStrategy: snapshot.activeStrategy,
    nodes: snapshot.nodes,
    conceptNodes: snapshot.conceptNodes,
    materials: snapshot.materials,
    summary: snapshot.summary,
    learningGraph: snapshot.learningGraph,
    teachingFlow: flow,
  );
}

RemoteTeachingFlow _guidedTeachingFlow(
  RemoteTeachingStage stage, {
  String? feedback,
  String? repairFocus,
  int supportLevel = 0,
  bool includeActivePractice = true,
  List<RemoteNextLearningOption> nextLearningOptions = const [],
  RemoteGuidedExplorationAct explorationAct =
      RemoteGuidedExplorationAct.unknown,
}) {
  final isAsset = stage == RemoteTeachingStage.asset;
  final isFocus = stage == RemoteTeachingStage.focus;
  return RemoteTeachingFlow(
    schemaVersion: 1,
    stage: stage,
    lessonPlanId: 'negative-sign-guided-v1',
    atomId: 'negative-times-negative',
    goal: '通过方向翻转解释为什么负负得正',
    practiceId: 'negative-sign-prediction',
    currentAction: RemoteTeacherAction(
      schemaVersion: 1,
      type: isAsset
          ? 'SHOW_ASSET'
          : isFocus
          ? 'REQUEST_MICRO_CHECK'
          : stage == RemoteTeachingStage.reflect
          ? 'REQUEST_REFLECTION'
          : 'ASK_QUESTION',
      prompt: isAsset
          ? '完成两次方向翻转并观察结果'
          : isFocus
          ? '请独立解释两次翻转的结果'
          : stage == RemoteTeachingStage.reflect
          ? '总结你现在的理解'
          : '先说说你的猜想',
      pedagogicalIntent: 'VERIFY_INDEPENDENT_UNDERSTANDING',
      reasonCode: 'GUIDED_MICRO_CHECK_READY',
      materialUsageId: isAsset ? 'sign-material' : null,
      practiceId: isFocus ? 'negative-sign-prediction' : null,
    ),
    evidence: const RemoteEvidenceState(
      schemaVersion: 1,
      requiredCodes: ['operation-observed'],
      items: [],
      missingCodes: ['operation-observed'],
      isReadyForMicroCheck: false,
    ),
    hintLevel: 0,
    updatedAt: '2026-08-10T10:00:00.000Z',
    explorationAct: explorationAct,
    activePractice: isFocus && includeActivePractice
        ? const RemoteGuidedPractice(
            id: 'active-negative-sign-prediction',
            title: '服务端独立验证题',
            prompt: '请说明连续两次方向翻转后的结果。',
            reasoningLabel: '服务端推理标签',
            answerLabel: '服务端答案标签',
          )
        : null,
    feedback: feedback,
    repairFocus: repairFocus,
    supportLevel: supportLevel,
    nextLearningOptions: nextLearningOptions,
  );
}

RemoteLearningSessionSnapshot _longPathSnapshot() {
  final nodes = List.generate(
    12,
    (index) => RemoteLearningNode(
      id: 'node-$index',
      parentId: index == 0 ? null : 'node-${index - 1}',
      status: 'VALIDATED',
      question: '第 ${index + 1} 个探索问题',
      answer: '第 ${index + 1} 个回答',
      followUpQuestion: '下一步可以追问：第 ${index + 2} 个问题是什么？',
      strategy: 'QUESTION_CHAIN',
      depth: index,
      isSideBranch: false,
      backtrackTargetId: null,
      confidence: .8,
      createdAt: '2026-08-06T01:${index.toString().padLeft(2, '0')}:00.000Z',
    ),
  );
  return RemoteLearningSessionSnapshot(
    session: const RemoteLearningSessionInfo(
      id: 'learning-long',
      exploreSessionId: 'explore-1',
      topic: '负数乘法探索',
      scenarioId: 'teaching',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 12,
      nodeCount: 12,
      startedAt: '2026-08-06T01:00:00.000Z',
      expiresAt: '2099-08-06T01:10:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'node-11',
    activeStrategy: 'QUESTION_CHAIN',
    nodes: nodes,
    materials: const [],
    summary: null,
  );
}

RemoteLearningSessionSnapshot _signFlipSnapshot() {
  return RemoteLearningSessionSnapshot(
    session: RemoteLearningSessionInfo(
      id: 'learning-sign-flip',
      exploreSessionId: 'explore-1',
      topic: '负数乘法探索',
      scenarioId: 'teaching',
      atomId: 'negative-times-negative',
      status: 'ACTIVE',
      revision: 1,
      nodeCount: 1,
      startedAt: '2026-08-06T01:00:00.000Z',
      expiresAt: '2099-08-13T01:00:00.000Z',
      completedAt: null,
    ),
    currentNodeId: 'sign-node',
    activeStrategy: 'SOCRATIC',
    nodes: [
      RemoteLearningNode(
        id: 'sign-node',
        parentId: null,
        status: 'VALIDATED',
        question: '为什么乘以 -1 是取相反数？',
        answer: '先从 -3 开始，亲手对它取一次相反数。',
        followUpQuestion: '取完一次后，数值的哪一部分变了，哪一部分没有变？',
        strategy: 'SOCRATIC',
        depth: 0,
        isSideBranch: false,
        backtrackTargetId: null,
        confidence: .8,
        createdAt: '2026-08-06T01:00:00.000Z',
      ),
    ],
    materials: [
      RemoteLearningMaterial(
        id: 'sign-material',
        nodeId: 'sign-node',
        materialId: 'negative-sign-flip-widget',
        type: 'INTERACTIVE',
        title: '动手验证：取相反数',
        componentKey: 'sign_flip_widget',
        payload: {},
      ),
    ],
    summary: null,
  );
}

RemoteLearningSessionSnapshot _completedSignFlipSnapshot() {
  final active = _signFlipSnapshot();
  return RemoteLearningSessionSnapshot(
    session: active.session.copyWith(status: 'COMPLETED'),
    currentNodeId: active.currentNodeId,
    activeStrategy: active.activeStrategy,
    nodes: active.nodes,
    materials: active.materials,
    summary: const RemoteLearningSummary(
      studentRestatement: '两次翻转会抵消。',
      concept: 100,
      application: 100,
      boundary: 100,
      misconceptions: [],
      interestDirections: [],
      recommendedReview: [],
    ),
  );
}

RemoteLearningSessionSnapshot _learningEvidenceSnapshot() {
  return RemoteLearningSessionSnapshot.fromJson({
    'session': {
      'id': 'learning-evidence',
      'exploreSessionId': 'explore-1',
      'topic': '负数乘法探索',
      'scenarioId': 'teaching',
      'atomId': 'negative-times-negative',
      'status': 'ACTIVE',
      'revision': 1,
      'nodeCount': 1,
      'startedAt': '2026-08-06T01:00:00.000Z',
      'expiresAt': '2026-08-13T01:00:00.000Z',
      'completedAt': null,
    },
    'currentNodeId': 'evidence-node',
    'activeStrategy': 'SOCRATIC',
    'nodes': [
      {
        'id': 'evidence-node',
        'parentId': null,
        'status': 'VALIDATED',
        'question': '为什么两个负数相乘会得到正数？',
        'answer': '负号可以理解为取相反数。',
        'followUpQuestion': '连续两次取相反数会发生什么？',
        'mapLabel': '两次取相反数',
        'strategy': 'SOCRATIC',
        'depth': 0,
        'isSideBranch': false,
        'backtrackTargetId': null,
        'confidence': .82,
        'createdAt': '2026-08-06T01:00:00.000Z',
      },
    ],
    'conceptNodes': [],
    'materials': [],
    'summary': null,
    'learningGraph': {
      'version': 1,
      'concept': {
        'id': 'concept:negative-times-negative',
        'kind': 'CONCEPT',
        'atomId': 'negative-times-negative',
        'title': '负数乘法探索',
        'source': 'MOCK_KNOWLEDGE',
      },
      'exploration': {
        'id': 'exploration:learning-evidence',
        'kind': 'EXPLORATION',
        'question': '为什么两个负数相乘会得到正数？',
        'scenarioId': 'teaching',
        'evidenceNodeId': 'evidence-node',
      },
      'thinking': [],
      'practice': [
        {
          'id': 'negative-sign-prediction',
          'kind': 'PRACTICE',
          'title': '符号预测',
          'prompt': '判断 (-7)×(-4) 的符号。',
          'purpose': '验证符号判断',
          'status': 'AVAILABLE',
        },
        {
          'id': 'negative-distribution-proof',
          'kind': 'PRACTICE',
          'title': '分配律验证',
          'prompt': '用分配律验证。',
          'purpose': '验证原理',
          'status': 'AVAILABLE',
        },
        {
          'id': 'negative-application-transfer',
          'kind': 'PRACTICE',
          'title': '情境迁移',
          'prompt': '方向反转两次。',
          'purpose': '验证迁移',
          'status': 'AVAILABLE',
        },
      ],
      'solutionPaths': [],
      'mastery': [
        {
          'id': 'mastery:concept',
          'kind': 'MASTERY',
          'dimension': 'CONCEPT',
          'score': 82,
          'evidence': ['两次取相反数'],
        },
      ],
    },
  });
}
