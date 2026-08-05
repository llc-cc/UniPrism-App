import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/features/dialogue_exploration/dialogue_exploration.dart';

void main() {
  group('ExplorationTree', () {
    test('ordinary append follows the active leaf without creating a branch', () {
      final tree = _seededTree().append(
        _node(
          id: 'tutor-1',
          parentId: 'root',
          kind: ExplorationNodeKind.tutorResponse,
          text: '先检查这个结论成立的条件。',
        ),
      );

      expect(tree.activeLeafId, 'tutor-1');
      expect(tree.nodeById('tutor-1')!.parentId, 'root');
      expect(tree.nodeById('tutor-1')!.isSideBranch, isFalse);
      expect(tree.sideBranchCount, 0);
    });

    test('explicit branching can restart from a historical node', () {
      final linear = _seededTree().append(
        _node(
          id: 'tutor-1',
          parentId: 'root',
          kind: ExplorationNodeKind.tutorResponse,
          text: '先检查定义。',
        ),
      );

      final branched = linear.branchFrom(
        parentNodeId: 'root',
        node: _node(
          id: 'question-branch',
          parentId: 'root',
          kind: ExplorationNodeKind.studentQuestion,
          text: '如果换一种方法呢？',
        ),
      );

      expect(branched.activeLeafId, 'question-branch');
      expect(branched.nodeById('question-branch')!.isSideBranch, isTrue);
      expect(branched.sideBranchCount, 1);
      expect(linear.sideBranchCount, 0);
    });

    test('keeps the contradicted path and records an explicit backtrack', () {
      final attempted = _seededTree()
          .append(
            _node(
              id: 'try-cauchy',
              parentId: 'root',
              kind: ExplorationNodeKind.studentHypothesis,
              text: '直接使用柯西不等式。',
            ),
          )
          .append(
            _node(
              id: 'condition-fails',
              parentId: 'try-cauchy',
              kind: ExplorationNodeKind.reasoningStep,
              text: '当前写法无法满足所需条件。',
            ),
          )
          .updateStatus(
            'condition-fails',
            ExplorationNodeStatus.contradicted,
          );

      final recovered = attempted.backtrack(
        fromNodeId: 'condition-fails',
        targetNodeId: 'root',
        backtrackNodeId: 'backtrack-1',
        reason: '回到题目，重新选择不等式工具。',
        createdAt: DateTime.utc(2026, 8, 5, 9),
      );

      expect(
        recovered.nodeById('condition-fails')!.status,
        ExplorationNodeStatus.contradicted,
      );
      expect(recovered.nodes.map((node) => node.id), contains('try-cauchy'));
      expect(recovered.activeLeaf!.kind, ExplorationNodeKind.backtrack);
      expect(recovered.activeLeaf!.status, ExplorationNodeStatus.backtracked);
      expect(recovered.activeLeaf!.backtrackTargetNodeId, 'root');
    });

    test('folding is immutable and can be toggled', () {
      final original = _seededTree();

      final folded = original.toggleCollapsed('root');
      final reopened = folded.toggleCollapsed('root');

      expect(original.collapsedNodeIds, isEmpty);
      expect(folded.collapsedNodeIds, {'root'});
      expect(reopened.collapsedNodeIds, isEmpty);
    });

    test('rejects a 41st node and leaves the source tree unchanged', () {
      var tree = _seededTree();
      for (var index = 1; index < ExplorationTree.maxNodes; index++) {
        tree = tree.append(
          _node(
            id: 'node-$index',
            parentId: tree.activeLeafId,
            kind: ExplorationNodeKind.tutorResponse,
            text: '节点 $index',
          ),
          enforceDepthLimit: false,
        );
      }

      expect(tree.nodes, hasLength(ExplorationTree.maxNodes));
      expect(
        () => tree.append(
          _node(
            id: 'node-overflow',
            parentId: tree.activeLeafId,
            kind: ExplorationNodeKind.tutorResponse,
            text: '不应加入',
          ),
          enforceDepthLimit: false,
        ),
        throwsA(
          isA<ExplorationLimitException>().having(
            (error) => error.kind,
            'kind',
            ExplorationLimitKind.nodeCount,
          ),
        ),
      );
      expect(tree.nodes, hasLength(ExplorationTree.maxNodes));
    });

    test('rejects depth beyond six nodes on one path', () {
      var tree = _seededTree();
      for (var depth = 2; depth <= ExplorationTree.maxDepth; depth++) {
        tree = tree.append(
          _node(
            id: 'depth-$depth',
            parentId: tree.activeLeafId,
            kind: ExplorationNodeKind.tutorResponse,
            text: '第 $depth 层',
          ),
        );
      }

      expect(tree.maxPathDepth, ExplorationTree.maxDepth);
      expect(
        () => tree.append(
          _node(
            id: 'depth-overflow',
            parentId: tree.activeLeafId,
            kind: ExplorationNodeKind.tutorResponse,
            text: '第 7 层',
          ),
        ),
        throwsA(
          isA<ExplorationLimitException>().having(
            (error) => error.kind,
            'kind',
            ExplorationLimitKind.pathDepth,
          ),
        ),
      );
    });

    test('rejects a ninth direct branch from the same node', () {
      var tree = _seededTree();
      for (var index = 1; index <= ExplorationTree.maxDirectBranches; index++) {
        tree = tree.branchFrom(
          parentNodeId: 'root',
          node: _node(
            id: 'branch-$index',
            parentId: 'root',
            kind: ExplorationNodeKind.studentQuestion,
            text: '分支 $index',
          ),
        );
      }

      expect(tree.childrenOf('root'), hasLength(8));
      expect(
        () => tree.branchFrom(
          parentNodeId: 'root',
          node: _node(
            id: 'branch-overflow',
            parentId: 'root',
            kind: ExplorationNodeKind.studentQuestion,
            text: '第九个分支',
          ),
        ),
        throwsA(
          isA<ExplorationLimitException>().having(
            (error) => error.kind,
            'kind',
            ExplorationLimitKind.directBranches,
          ),
        ),
      );
    });
  });
}

ExplorationTree _seededTree() {
  return ExplorationTree.seed(
    id: 'session-1',
    root: _node(
      id: 'root',
      parentId: null,
      kind: ExplorationNodeKind.studentQuestion,
      status: ExplorationNodeStatus.validated,
      text: '证明：当 x > 0 时，x + 1/x ≥ 2。',
    ),
  );
}

ExplorationNode _node({
  required String id,
  required String? parentId,
  required ExplorationNodeKind kind,
  required String text,
  ExplorationNodeStatus status = ExplorationNodeStatus.exploring,
}) {
  return ExplorationNode(
    id: id,
    parentId: parentId,
    kind: kind,
    status: status,
    text: text,
    materialIds: const [],
    isSideBranch: false,
    backtrackTargetNodeId: null,
    createdAt: DateTime.utc(2026, 8, 5, 8),
    strategyVersion: 'mock-exploration-v1',
  );
}
