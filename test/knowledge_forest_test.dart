import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
}
