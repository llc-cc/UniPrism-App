import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/adapters/remote_exploration_dto.dart';

void main() {
  test('chapter catalog item parses every directory field and rejects incomplete records', () {
    final item = LearningChapterCatalogItem.tryFromJson({
      'chapterId': 'integer-operations',
      'title': '整数运算',
      'description': '巩固整数运算规则',
      'estimatedMinutes': 20,
      'availableNodeCount': 4,
    });

    expect(item?.chapterId, 'integer-operations');
    expect(item?.title, '整数运算');
    expect(item?.description, '巩固整数运算规则');
    expect(item?.estimatedMinutes, 20);
    expect(item?.availableNodeCount, 4);
    expect(LearningChapterCatalogItem.tryFromJson({'chapterId': ''}), isNull);
    expect(LearningChapterCatalogItem.tryFromJson('malformed'), isNull);
  });

  test(
    'parses optional answer provenance and turn intent without breaking legacy nodes',
    () {
      final current = RemoteLearningNode.fromJson({
        'id': 'node-current',
        'parentId': null,
        'status': 'VALIDATED',
        'question': '海水为什么是蓝色？',
        'answer': '水对不同波长光的吸收程度不同。',
        'followUpQuestion': '水层更深时，颜色会怎样变化？',
        'answerSource': 'MODEL_PRIOR',
        'turnIntent': 'NEW_QUESTION',
        'strategy': 'QUESTION_CHAIN',
        'depth': 0,
        'isSideBranch': false,
        'backtrackTargetId': null,
        'confidence': .82,
        'createdAt': '2026-08-08T12:00:00.000Z',
      });
      final legacy = RemoteLearningNode.fromJson({
        'id': 'node-legacy',
        'status': 'VALIDATED',
        'question': '旧节点',
        'createdAt': '2026-08-08T11:00:00.000Z',
      });

      expect(current.answerSource, 'MODEL_PRIOR');
      expect(current.turnIntent, 'NEW_QUESTION');
      expect(legacy.answerSource, isNull);
      expect(legacy.turnIntent, isNull);
    },
  );

  test('parses evidence-backed diagnostics separately from mastery scores', () {
    final graph = RemoteLearningGraph.fromJson({
      'concept': {'title': '负数乘法'},
      'exploration': {'question': '为什么负负得正？'},
      'practice': const [],
      'solutionPaths': const [],
      'mastery': const [],
      'nextChallenges': const [],
      'diagnostics': [
        {
          'id': 'diagnostic:practice',
          'dimension': 'PRACTICE',
          'status': 'NEEDS_SUPPORT',
          'title': '符号预测',
          'observation': '结论不正确；请重新检查同号相乘的符号。',
          'evidence': ['两个因数都是负数。'],
          'nextAction': '根据反馈补全这一步的依据，再重新提交你的解题思路和答案。',
        },
      ],
    });

    expect(graph.diagnostics, hasLength(1));
    expect(graph.diagnostics.single.status, 'NEEDS_SUPPORT');
    expect(graph.diagnostics.single.evidence, ['两个因数都是负数。']);
  });
}
