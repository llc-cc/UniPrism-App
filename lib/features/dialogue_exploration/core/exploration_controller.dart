import 'package:flutter/foundation.dart';

import '../mastery/student_mastery.dart';
import '../practice/practice_diagnosis.dart';
import '../practice/practice_exploration_strategy.dart';
import 'exploration_models.dart';
import 'exploration_ports.dart';
import 'exploration_tree.dart';

/// 练习闭环的页面状态；pendingDiagnosis 存在时必须先确认或修改才能继续。
enum ExplorationControllerStatus { idle, active, awaitingDiagnosis, completed }

/// 控制器对外暴露的不可变快照。
final class ExplorationControllerState {
  const ExplorationControllerState({
    required this.status,
    required this.scenario,
    required this.mastery,
    required this.tree,
    required this.pendingDiagnosis,
  });

  const ExplorationControllerState.idle()
    : status = ExplorationControllerStatus.idle,
      scenario = null,
      mastery = null,
      tree = null,
      pendingDiagnosis = null;

  final ExplorationControllerStatus status;
  final ExplorationScenario? scenario;
  final StudentMasterySnapshot? mastery;
  final ExplorationTree? tree;
  final PracticeDiagnosisSuggestion? pendingDiagnosis;
}

/// 编排练习思维树、诊断确认和证据输出；Widget 不直接修改树。
final class ExplorationController extends ChangeNotifier {
  ExplorationController({
    required this.practiceStrategy,
    required this.masteryEvidenceSink,
    required this.nowUtc,
  });

  final PracticeExplorationStrategy practiceStrategy;
  final MasteryEvidenceSink masteryEvidenceSink;
  final DateTime Function() nowUtc;

  ExplorationControllerState _state = const ExplorationControllerState.idle();
  String? _nextBranchParentId;
  var _idCounter = 0;
  var _isDisposed = false;

  ExplorationControllerState get state => _state;

  void startPractice({
    required ExplorationScenario scenario,
    required StudentMasterySnapshot mastery,
  }) {
    if (scenario.kind != ExplorationScenarioKind.practice) {
      throw ArgumentError.value(scenario.kind, 'scenario.kind', '只能启动练习场景');
    }
    final root = ExplorationNode(
      id: '${scenario.id}-root',
      parentId: null,
      kind: ExplorationNodeKind.studentQuestion,
      status: ExplorationNodeStatus.validated,
      text: scenario.openingPrompt,
      materialIds: const [],
      isSideBranch: false,
      backtrackTargetNodeId: null,
      createdAt: nowUtc(),
      strategyVersion: MockStrategyVersions.practice,
    );
    _nextBranchParentId = null;
    _state = ExplorationControllerState(
      status: ExplorationControllerStatus.active,
      scenario: scenario,
      mastery: mastery,
      tree: ExplorationTree.seed(id: scenario.id, root: root),
      pendingDiagnosis: null,
    );
    _notifySafely();
  }

  void submitHypothesis(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(text, 'text', '解题思路不能为空');
    }
    if (_state.pendingDiagnosis != null) {
      throw StateError('请先确认或修改当前卡点诊断');
    }
    final tree = _requiredTree();
    final branchParentId = _nextBranchParentId;
    final parentId = branchParentId ?? tree.activeLeafId;
    final node = _node(
      parentId: parentId,
      kind: ExplorationNodeKind.studentHypothesis,
      status: ExplorationNodeStatus.exploring,
      text: normalized,
      prefix: 'hypothesis',
    );
    final updated = branchParentId == null
        ? tree.append(node)
        : tree.branchFrom(parentNodeId: branchParentId, node: node);
    _nextBranchParentId = null;
    _replace(tree: updated, status: ExplorationControllerStatus.active);
  }

  Future<void> validateActiveStep() async {
    final tree = _requiredTree();
    final hypothesis = tree.activeLeaf;
    if (hypothesis == null || hypothesis.kind != ExplorationNodeKind.studentHypothesis) {
      throw StateError('当前节点不是可验证的学生思路');
    }
    final result = practiceStrategy.validateHypothesis(hypothesis.text);
    final reasoningNode = _node(
      parentId: hypothesis.id,
      kind: ExplorationNodeKind.reasoningStep,
      status: result.isValid
          ? ExplorationNodeStatus.validated
          : ExplorationNodeStatus.contradicted,
      text: result.explanation,
      prefix: 'reasoning',
    );
    final updated = tree.append(reasoningNode);
    if (result.isValid) {
      await masteryEvidenceSink.write(
        MasteryEvidence(
          id: 'evidence-${reasoningNode.id}',
          atomId: _requiredScenario().atomId,
          nodeId: reasoningNode.id,
          diagnosisKind: null,
          source: MasteryEvidenceSource.verifiedByStep,
          summary: result.explanation,
          occurredAt: nowUtc(),
        ),
      );
      _replace(tree: updated, status: ExplorationControllerStatus.active);
      return;
    }
    _replace(
      tree: updated,
      status: ExplorationControllerStatus.awaitingDiagnosis,
      pendingDiagnosis: result.diagnosis,
    );
  }

  Future<void> confirmDiagnosis(DifficultyDiagnosisKind selectedKind) async {
    final pending = _state.pendingDiagnosis;
    if (pending == null) throw StateError('当前没有待确认的诊断');
    final tree = _requiredTree();
    final node = _node(
      parentId: tree.activeLeafId,
      kind: ExplorationNodeKind.diagnosis,
      status: ExplorationNodeStatus.validated,
      text: '学生确认卡点：${_diagnosisLabel(selectedKind)}。${pending.rationale}',
      prefix: 'diagnosis',
    );
    final updated = tree.append(node);
    await masteryEvidenceSink.write(
      MasteryEvidence(
        id: 'evidence-${node.id}',
        atomId: _requiredScenario().atomId,
        nodeId: node.id,
        diagnosisKind: selectedKind,
        source: MasteryEvidenceSource.confirmedByStudent,
        summary: node.text,
        occurredAt: nowUtc(),
      ),
    );
    _replace(
      tree: updated,
      status: ExplorationControllerStatus.active,
      clearPendingDiagnosis: true,
    );
  }

  void backtrack({required String targetNodeId}) {
    final tree = _requiredTree();
    final updated = tree.backtrack(
      fromNodeId: tree.activeLeafId,
      targetNodeId: targetNodeId,
      backtrackNodeId: _nextId('backtrack'),
      reason: '回到上一个有效节点，重新选择解题方法。',
      createdAt: nowUtc(),
    );
    _nextBranchParentId = targetNodeId;
    _replace(tree: updated, status: ExplorationControllerStatus.active);
  }

  void saveReflection(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(text, 'text', '复述不能为空');
    }
    final tree = _requiredTree();
    final node = _node(
      parentId: tree.activeLeafId,
      kind: ExplorationNodeKind.reflection,
      status: ExplorationNodeStatus.completed,
      text: normalized,
      prefix: 'reflection',
    );
    _replace(
      tree: tree.append(node),
      status: ExplorationControllerStatus.completed,
    );
  }

  ExplorationNode _node({
    required String parentId,
    required ExplorationNodeKind kind,
    required ExplorationNodeStatus status,
    required String text,
    required String prefix,
  }) {
    return ExplorationNode(
      id: _nextId(prefix),
      parentId: parentId,
      kind: kind,
      status: status,
      text: text,
      materialIds: const [],
      isSideBranch: false,
      backtrackTargetNodeId: null,
      createdAt: nowUtc(),
      strategyVersion: MockStrategyVersions.practice,
    );
  }

  String _nextId(String prefix) => '$prefix-${++_idCounter}';

  ExplorationTree _requiredTree() {
    return _state.tree ?? (throw StateError('练习尚未开始'));
  }

  ExplorationScenario _requiredScenario() {
    return _state.scenario ?? (throw StateError('练习尚未开始'));
  }

  void _replace({
    required ExplorationTree tree,
    required ExplorationControllerStatus status,
    PracticeDiagnosisSuggestion? pendingDiagnosis,
    bool clearPendingDiagnosis = false,
  }) {
    _state = ExplorationControllerState(
      status: status,
      scenario: _state.scenario,
      mastery: _state.mastery,
      tree: tree,
      pendingDiagnosis: clearPendingDiagnosis
          ? null
          : pendingDiagnosis ?? _state.pendingDiagnosis,
    );
    _notifySafely();
  }

  void _notifySafely() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  static String _diagnosisLabel(DifficultyDiagnosisKind kind) {
    return switch (kind) {
      DifficultyDiagnosisKind.conceptGap => '概念不熟',
      DifficultyDiagnosisKind.conditionGap => '成立条件不清楚',
      DifficultyDiagnosisKind.methodSelection => '方法不会选择',
      DifficultyDiagnosisKind.reasoningBreak => '推理步骤断裂',
      DifficultyDiagnosisKind.calculationGap => '计算能力不过关',
      DifficultyDiagnosisKind.promptMisread => '题意理解偏差',
      DifficultyDiagnosisKind.uncertain => '暂时不确定',
    };
  }
}

/// Mock 策略版本随事件保存，后续替换 Skill 时可比较和回滚。
abstract final class MockStrategyVersions {
  static const practice = 'mock-practice-v1';
}
