import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_mind_map/reactive_mind_map.dart';
import 'package:uniprism_app/main.dart';

const sampleBatchJson = <String, dynamic>{
  'batchId': 'batch-1',
  'conversationId': 'conv-1',
  'messageId': 'msg-1',
  'question': '人工智能专业学什么？',
  'answerExcerpt': '人工智能专业包括机器学习。',
  'suggestedTree': {'mode': 'new', 'treeId': null, 'title': '人工智能'},
  'nodes': [
    {
      'candidateId': 'node-1',
      'parentCandidateId': null,
      'type': 'topic',
      'title': '人工智能',
      'summary': '人工智能专业主题',
      'selected': true,
      'confidence': 0.9,
    },
    {
      'candidateId': 'node-2',
      'parentCandidateId': 'node-1',
      'type': 'concept',
      'title': '机器学习',
      'summary': '从数据中学习规律',
      'selected': true,
      'confidence': 0.8,
    },
  ],
  'relatedEdges': <Map<String, dynamic>>[],
  'traceId': 'trace-1',
  'model': 'deepseek-test',
  'latencyMs': 12,
};

KnowledgeExtractionBatch get sampleBatch =>
    KnowledgeExtractionBatch.fromJson(sampleBatchJson);

class FakeKnowledgeExtractionGateway implements KnowledgeExtractionGateway {
  FakeKnowledgeExtractionGateway.success(this._success) : _failures = const [];

  FakeKnowledgeExtractionGateway.failOnceThenSuccess(
    ApiRequestException failure,
    this._success,
  ) : _failures = [failure];

  final Map<String, dynamic> _success;
  final List<ApiRequestException> _failures;
  int _calls = 0;

  @override
  Future<KnowledgeExtractionBatch> extract({
    required String conversationId,
    required String messageId,
    required String question,
    required String answer,
    required List<KnowledgeTreeSummary> availableTrees,
    required List<KnowledgeSourceRef> sourceRefs,
  }) async {
    if (_calls < _failures.length) throw _failures[_calls++];
    _calls += 1;
    return KnowledgeExtractionBatch.fromJson(
      _success,
    ).copyWith(sourceRefs: sourceRefs);
  }
}

void main() {
  test('knowledge extraction batch parses candidates and tree suggestion', () {
    final batch = sampleBatch;

    expect(batch.nodes.last.title, '机器学习');
    expect(batch.suggestedTree.title, '人工智能');
    expect(batch.relatedEdges, isEmpty);
  });

  test('confirmBatch promotes selected children whose parent was removed', () {
    final store = KnowledgeForestStore();
    final batch = KnowledgeExtractionBatch.fromJson({
      ...sampleBatchJson,
      'batchId': 'batch-parent-test',
      'nodes': [
        {
          'candidateId': 'parent',
          'parentCandidateId': null,
          'type': 'topic',
          'title': '未选择父节点',
          'summary': '父节点摘要',
          'selected': false,
          'confidence': 0.7,
        },
        {
          'candidateId': 'child',
          'parentCandidateId': 'parent',
          'type': 'concept',
          'title': '保留的子节点',
          'summary': '子节点摘要',
          'selected': true,
          'confidence': 0.8,
        },
      ],
    });

    final tree = store.confirmBatch(batch, targetTreeTitle: '人工智能');

    expect(tree.nodes.single.parentNodeId, isNull);
    expect(tree.nodes.single.sourceConversationId, 'conv-1');
    expect(tree.nodes.single.sourceMessageId, 'msg-1');
  });

  test('confirmBatch is idempotent for the same extraction batch', () {
    final store = KnowledgeForestStore();

    final first = store.confirmBatch(sampleBatch, targetTreeTitle: '人工智能');
    final second = store.confirmBatch(sampleBatch, targetTreeTitle: '忽略的新标题');

    expect(identical(first, second), isTrue);
    expect(store.trees, hasLength(1));
    expect(second.nodes, hasLength(2));
  });

  test('confirmBatch can merge a later batch into an existing target tree', () {
    final store = KnowledgeForestStore();
    final first = store.confirmBatch(sampleBatch, targetTreeTitle: '人工智能');
    final laterBatch = KnowledgeExtractionBatch.fromJson({
      ...sampleBatchJson,
      'batchId': 'batch-2',
      'messageId': 'msg-2',
      'nodes': [
        {
          'candidateId': 'robotics',
          'parentCandidateId': null,
          'type': 'concept',
          'title': '机器人学',
          'summary': '感知、决策与控制',
          'selected': true,
          'confidence': 0.82,
        },
      ],
    });

    final merged = store.confirmBatch(
      laterBatch,
      targetTreeId: first.id,
      targetTreeTitle: first.title,
    );

    expect(store.trees, hasLength(1));
    expect(merged.nodes, hasLength(3));
    expect(merged.nodes.last.id, 'node-batch-2-robotics');
  });

  test(
    'knowledge extraction service parses envelope and attaches trusted refs',
    () {
      const sourceRefs = [
        KnowledgeSourceRef(
          id: 'source-1',
          title: '教育部专业介绍',
          url: 'https://example.edu/ai',
          sourceName: '教育部',
        ),
      ];

      final batch = KnowledgeExtractionService.decodeEnvelopeForTest({
        'ok': true,
        'data': sampleBatchJson,
      }, sourceRefs: sourceRefs);

      expect(batch.nodes, isNotEmpty);
      expect(batch.sourceRefs.single.url, 'https://example.edu/ai');
    },
  );

  test('knowledge extraction service exposes timeout as user-facing error', () {
    expect(
      () => KnowledgeExtractionService.decodeFailureForTest(
        TimeoutException('network timeout'),
      ),
      throwsA(
        isA<ApiRequestException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
  });

  testWidgets('candidate preview edits and selectively confirms nodes', (
    tester,
  ) async {
    final store = KnowledgeForestStore();
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeExtractionPreviewPage(batch: sampleBatch, store: store),
      ),
    );

    final secondCandidate = find.byKey(
      const ValueKey('knowledge-candidate-node-2'),
    );
    final reviewList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      secondCandidate,
      300,
      scrollable: reviewList,
    );
    await tester.tap(secondCandidate);
    final firstTitle = find.byKey(
      const ValueKey('knowledge-candidate-title-node-1'),
    );
    await tester.scrollUntilVisible(firstTitle, -300, scrollable: reviewList);
    await tester.enterText(firstTitle, '人工智能基础');
    await tester.tap(find.byKey(const ValueKey('confirm-knowledge-batch')));
    await tester.pumpAndSettle();

    expect(store.trees.single.nodes, hasLength(1));
    expect(store.trees.single.nodes.single.title, '人工智能基础');
  });

  testWidgets('cancelling candidate preview leaves the forest unchanged', (
    tester,
  ) async {
    final store = KnowledgeForestStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => KnowledgeExtractionPreviewPage(
                  batch: sampleBatch,
                  store: store,
                ),
              ),
            ),
            child: const Text('打开审核'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开审核'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();

    expect(store.trees, isEmpty);
  });

  testWidgets('candidate preview can target an existing tree', (tester) async {
    final store = KnowledgeForestStore();
    final existing = store.confirmBatch(sampleBatch, targetTreeTitle: '人工智能');
    final laterBatch = KnowledgeExtractionBatch.fromJson({
      ...sampleBatchJson,
      'batchId': 'batch-preview-existing',
      'nodes': [
        {
          'candidateId': 'robotics',
          'parentCandidateId': null,
          'type': 'concept',
          'title': '机器人学',
          'summary': '感知、决策与控制',
          'selected': true,
          'confidence': 0.82,
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeExtractionPreviewPage(batch: laterBatch, store: store),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('knowledge-target-tree-choice')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(existing.title).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-knowledge-batch')));
    await tester.pumpAndSettle();

    expect(store.trees, hasLength(1));
    expect(store.trees.single.nodes, hasLength(3));
  });

  test('mind map adapter renders primary parent-child edges', () {
    final store = KnowledgeForestStore();
    final tree = store.confirmBatch(sampleBatch, targetTreeTitle: '人工智能');

    final data = KnowledgeMindMapAdapter.toMindMapData(tree);

    expect(data.id, 'node-batch-1-node-1');
    expect(data.children.single.id, 'node-batch-1-node-2');
  });

  testWidgets('knowledge forest opens one tree as a mind map', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final store = KnowledgeForestStore()
      ..confirmBatch(sampleBatch, targetTreeTitle: '人工智能');
    await tester.pumpWidget(
      MaterialApp(home: KnowledgeForestPage(store: store)),
    );

    await tester.tap(find.text('人工智能').last);
    await tester.pumpAndSettle();

    expect(find.byType(MindMapWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent answer can be extracted and confirmed into the forest', (
    tester,
  ) async {
    final gateway = FakeKnowledgeExtractionGateway.success(sampleBatchJson);
    final store = KnowledgeForestStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AgentExperiencePage(
          knowledgeGateway: gateway,
          knowledgeStore: store,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      '人工智能专业主要学习什么？',
    );
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final extractButton = find.byKey(
      const ValueKey('knowledge-extract-button'),
    );
    final conversationScroll = find.descendant(
      of: find.byKey(const ValueKey('agent-conversation-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      extractButton,
      260,
      scrollable: conversationScroll,
    );
    await tester.tap(extractButton);
    await tester.pumpAndSettle();

    expect(find.text('确认知识节点'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-knowledge-batch')));
    await tester.pumpAndSettle();

    expect(store.trees.single.title, '人工智能');
  });

  testWidgets('failed agent extraction keeps the answer and allows retry', (
    tester,
  ) async {
    final gateway = FakeKnowledgeExtractionGateway.failOnceThenSuccess(
      const ApiRequestException('知识提炼暂时不可用'),
      sampleBatchJson,
    );
    await tester.pumpWidget(
      MaterialApp(home: AgentExperiencePage(knowledgeGateway: gateway)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      '数学专业需要哪些能力？',
    );
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final extractButton = find.byKey(
      const ValueKey('knowledge-extract-button'),
    );
    final conversationScroll = find.descendant(
      of: find.byKey(const ValueKey('agent-conversation-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      extractButton,
      260,
      scrollable: conversationScroll,
    );
    await tester.tap(extractButton);
    await tester.pump();

    expect(find.textContaining('暂时不可用'), findsOneWidget);
    final originalQuestion = find.textContaining('数学专业');
    await tester.scrollUntilVisible(
      originalQuestion,
      -180,
      scrollable: conversationScroll,
    );
    expect(originalQuestion, findsWidgets);
    await tester.drag(
      find.byKey(const ValueKey('agent-conversation-list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.tap(extractButton);
    await tester.pumpAndSettle();

    expect(find.text('确认知识节点'), findsOneWidget);
  });
}
