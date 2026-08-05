import 'package:flutter/foundation.dart';

import '../mastery/student_mastery.dart';
import '../teaching/teaching_exploration_strategy.dart';
import 'exploration_models.dart';
import 'exploration_outputs.dart';
import 'exploration_ports.dart';
import 'exploration_tree.dart';

/// 教学/public Demo 的异步状态；失败时保留现有树，允许再次提交。
enum TeachingSessionStatus { idle, loading, active, failed, saved }

/// 教学会话的只读页面快照。
final class TeachingSessionState {
  const TeachingSessionState({
    required this.status,
    required this.scenario,
    required this.mastery,
    required this.tree,
    required this.errorMessage,
  });

  const TeachingSessionState.idle()
    : status = TeachingSessionStatus.idle,
      scenario = null,
      mastery = null,
      tree = null,
      errorMessage = null;

  final TeachingSessionStatus status;
  final ExplorationScenario? scenario;
  final StudentMasterySnapshot? mastery;
  final ExplorationTree? tree;
  final String? errorMessage;
}

/// 编排教学对话、分支、保存和记忆候选输出；所有教学决策委托给策略。
final class TeachingSessionController extends ChangeNotifier {
  TeachingSessionController({
    required this.strategy,
    required this.traceRepository,
    required this.memoryCandidateSink,
    required this.nowUtc,
  });

  final TeachingExplorationStrategy strategy;
  final ExplorationTraceRepository traceRepository;
  final MemoryCandidateSink memoryCandidateSink;
  final DateTime Function() nowUtc;

  TeachingSessionState _state = const TeachingSessionState.idle();
  var _idCounter = 0;
  var _isDisposed = false;

  TeachingSessionState get state => _state;

  Future<void> start({
    required ExplorationScenario scenario,
    required StudentMasterySnapshot mastery,
    required String question,
  }) async {
    if (scenario.kind == ExplorationScenarioKind.practice) {
      throw ArgumentError.value(scenario.kind, 'scenario.kind', '练习场景使用练习控制器');
    }
    _idCounter = 0;
    _setState(
      TeachingSessionState(
        status: TeachingSessionStatus.loading,
        scenario: scenario,
        mastery: mastery,
        tree: null,
        errorMessage: null,
      ),
    );
    final response = await strategy.respond(
      scenario: scenario,
      mastery: mastery,
      question: question,
      ancestorTexts: const [],
    );
    final root = _studentNode(
      id: '${scenario.id}-root',
      parentId: null,
      text: question.trim(),
      isSideBranch: false,
    );
    var tree = ExplorationTree.seed(id: scenario.id, root: root);
    tree = tree.append(_tutorNode(parentId: root.id, response: response));
    _setState(
      TeachingSessionState(
        status: TeachingSessionStatus.active,
        scenario: scenario,
        mastery: mastery,
        tree: tree,
        errorMessage: null,
      ),
    );
  }

  Future<void> submitQuestion(
    String question, {
    String? branchFromNodeId,
  }) async {
    final current = _requiredState();
    final tree = current.tree!;
    _setState(
      TeachingSessionState(
        status: TeachingSessionStatus.loading,
        scenario: current.scenario,
        mastery: current.mastery,
        tree: tree,
        errorMessage: null,
      ),
    );
    try {
      final response = await strategy.respond(
        scenario: current.scenario!,
        mastery: current.mastery!,
        question: question,
        ancestorTexts: _ancestorTexts(tree, branchFromNodeId ?? tree.activeLeafId),
      );
      final parentId = branchFromNodeId ?? tree.activeLeafId;
      final student = _studentNode(
        id: _nextId('question'),
        parentId: parentId,
        text: question.trim(),
        isSideBranch: branchFromNodeId != null,
      );
      var updated = branchFromNodeId == null
          ? tree.append(student)
          : tree.branchFrom(parentNodeId: parentId, node: student);
      updated = updated.append(
        _tutorNode(parentId: student.id, response: response),
      );
      _setState(
        TeachingSessionState(
          status: TeachingSessionStatus.active,
          scenario: current.scenario,
          mastery: current.mastery,
          tree: updated,
          errorMessage: null,
        ),
      );
    } on ExplorationInputRejectedException {
      // 安全拒绝发生在写树之前，保证不适宜内容不会留下半个节点。
      _setState(current);
      rethrow;
    } catch (error) {
      _setState(
        TeachingSessionState(
          status: TeachingSessionStatus.failed,
          scenario: current.scenario,
          mastery: current.mastery,
          tree: tree,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<String> convertNodeToMemory(String nodeId) async {
    final current = _requiredState();
    final node = current.tree!.nodeById(nodeId);
    if (node == null || node.kind != ExplorationNodeKind.tutorResponse) {
      throw ArgumentError.value(nodeId, 'nodeId', '只能把导师解释节点转为记忆候选');
    }
    final candidate = ExplorationMemoryCandidate(
      id: 'memory-${current.tree!.id}-${node.id}',
      scenarioId: current.scenario!.id,
      nodeId: node.id,
      text: node.text,
      createdAt: nowUtc(),
    );
    return memoryCandidateSink.upsert(candidate);
  }

  Future<ExplorationTraceRecord> saveTrace({required String reflection}) async {
    final normalized = reflection.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(reflection, 'reflection', '复述不能为空');
    }
    final current = _requiredState();
    final record = ExplorationTraceRecord(
      id: 'trace-${current.tree!.id}',
      scenarioId: current.scenario!.id,
      tree: current.tree!,
      reflection: normalized,
      savedAt: nowUtc(),
    );
    await traceRepository.save(record);
    _setState(
      TeachingSessionState(
        status: TeachingSessionStatus.saved,
        scenario: current.scenario,
        mastery: current.mastery,
        tree: current.tree,
        errorMessage: null,
      ),
    );
    return record;
  }

  TeachingSessionState _requiredState() {
    if (_state.tree == null || _state.scenario == null || _state.mastery == null) {
      throw StateError('教学探索尚未开始');
    }
    return _state;
  }

  ExplorationNode _studentNode({
    required String id,
    required String? parentId,
    required String text,
    required bool isSideBranch,
  }) {
    return ExplorationNode(
      id: id,
      parentId: parentId,
      kind: ExplorationNodeKind.studentQuestion,
      status: ExplorationNodeStatus.validated,
      text: text,
      materialIds: const [],
      isSideBranch: isSideBranch,
      backtrackTargetNodeId: null,
      createdAt: nowUtc(),
      strategyVersion: MockExplorationGatewayVersion.value,
    );
  }

  ExplorationNode _tutorNode({
    required String parentId,
    required ExplorationTurnResponse response,
  }) {
    return ExplorationNode(
      id: _nextId('tutor'),
      parentId: parentId,
      kind: ExplorationNodeKind.tutorResponse,
      status: ExplorationNodeStatus.validated,
      text: '${response.answer}\n\n反问：${response.followUpQuestion}',
      materialIds: response.materialIds.toList(growable: false),
      isSideBranch: false,
      backtrackTargetNodeId: null,
      createdAt: nowUtc(),
      strategyVersion: response.strategyVersion,
    );
  }

  List<String> _ancestorTexts(ExplorationTree tree, String nodeId) {
    final reversed = <String>[];
    var current = tree.nodeById(nodeId);
    while (current != null) {
      reversed.add(current.text);
      current = current.parentId == null ? null : tree.nodeById(current.parentId!);
    }
    return reversed.reversed.toList(growable: false);
  }

  String _nextId(String prefix) => '$prefix-${++_idCounter}';

  void _setState(TeachingSessionState value) {
    _state = value;
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

/// 根节点在 Gateway 回答前创建，因此使用与 Mock Gateway 一致的版本标签。
abstract final class MockExplorationGatewayVersion {
  static const value = 'mock-exploration-v1';
}
