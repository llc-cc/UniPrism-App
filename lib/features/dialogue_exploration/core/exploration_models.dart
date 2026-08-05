import 'dart:collection';

/// 1.2 首版支持的复用场景；场景只改变策略，不复制思维树内核。
enum ExplorationScenarioKind { teaching, practice, publicDemo }

/// 对话内可调度的教学素材类型，正式数据后续由 1.1 知识库提供。
enum ExplorationMaterialKind { figure, video, interactive, formula }

/// 自由输入的边界判定需要写入节点和事件，不能只改变提示文案。
enum ExplorationInputBoundary { inScope, aboveStage, unrelated, inappropriate }

/// 当前回答采用的教学动作，便于解释为何选择该素材与追问。
enum ExplorationIntent {
  probePriorKnowledge,
  repairPrerequisite,
  clarifyBoundary,
  extendReasoning,
  connectApplication,
  exploreSideBranch,
  validateMethod,
}

/// 思维树节点表达学生提问、解法尝试、系统回应和回退等不同证据。
enum ExplorationNodeKind {
  studentQuestion,
  studentHypothesis,
  tutorResponse,
  reasoningStep,
  diagnosis,
  reflection,
  backtrack,
}

/// 节点状态保留推理结果；错误路径必须停留在 contradicted 状态。
enum ExplorationNodeStatus {
  exploring,
  validated,
  contradicted,
  abandoned,
  backtracked,
  completed,
}

/// 一次对话探索的可选起点与素材边界。
final class ExplorationScenario {
  ExplorationScenario({
    required this.id,
    required this.title,
    required this.kind,
    required this.atomId,
    required this.openingPrompt,
    required List<String> seedQuestions,
    required Set<String> allowedMaterialIds,
  }) : seedQuestions = List.unmodifiable(seedQuestions),
       allowedMaterialIds = Set.unmodifiable(allowedMaterialIds);

  final String id;
  final String title;
  final ExplorationScenarioKind kind;
  final String atomId;
  final String openingPrompt;
  final List<String> seedQuestions;
  final Set<String> allowedMaterialIds;
}

/// 知识库素材在 1.2 内的受控领域对象；页面不解析原始接口 JSON。
final class ExplorationMaterial {
  ExplorationMaterial({
    required this.id,
    required this.atomId,
    required this.kind,
    required this.title,
    required Map<String, Object?> payload,
  }) : payload = UnmodifiableMapView(Map.of(payload));

  final String id;
  final String atomId;
  final ExplorationMaterialKind kind;
  final String title;
  final Map<String, Object?> payload;
}

/// 思维树中的不可变节点，父子关系只能由 ExplorationTree 校验后写入。
final class ExplorationNode {
  ExplorationNode({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.status,
    required this.text,
    required List<String> materialIds,
    required this.isSideBranch,
    required this.backtrackTargetNodeId,
    required this.createdAt,
    required this.strategyVersion,
    this.strategyMode,
    this.strategyGoal,
    this.strategyReason,
  }) : materialIds = List.unmodifiable(materialIds);

  final String id;
  final String? parentId;
  final ExplorationNodeKind kind;
  final ExplorationNodeStatus status;
  final String text;
  final List<String> materialIds;
  final bool isSideBranch;
  final String? backtrackTargetNodeId;
  final DateTime createdAt;
  final String strategyVersion;
  final String? strategyMode;
  final String? strategyGoal;
  final String? strategyReason;

  ExplorationNode withStatus(ExplorationNodeStatus nextStatus) {
    return ExplorationNode(
      id: id,
      parentId: parentId,
      kind: kind,
      status: nextStatus,
      text: text,
      materialIds: materialIds,
      isSideBranch: isSideBranch,
      backtrackTargetNodeId: backtrackTargetNodeId,
      createdAt: createdAt,
      strategyVersion: strategyVersion,
      strategyMode: strategyMode,
      strategyGoal: strategyGoal,
      strategyReason: strategyReason,
    );
  }

  ExplorationNode asSideBranch() {
    return ExplorationNode(
      id: id,
      parentId: parentId,
      kind: kind,
      status: status,
      text: text,
      materialIds: materialIds,
      isSideBranch: true,
      backtrackTargetNodeId: backtrackTargetNodeId,
      createdAt: createdAt,
      strategyVersion: strategyVersion,
      strategyMode: strategyMode,
      strategyGoal: strategyGoal,
      strategyReason: strategyReason,
    );
  }
}

/// Gateway 返回的结构化教学动作；页面只消费该对象，不解析模型文本协议。
final class ExplorationTurnResponse {
  ExplorationTurnResponse({
    required this.answer,
    required this.followUpQuestion,
    required this.boundary,
    required this.intent,
    required Set<String> materialIds,
    required this.isSideBranchSuggested,
    required this.strategyVersion,
  }) : materialIds = Set.unmodifiable(materialIds);

  final String answer;
  final String followUpQuestion;
  final ExplorationInputBoundary boundary;
  final ExplorationIntent intent;
  final Set<String> materialIds;
  final bool isSideBranchSuggested;
  final String strategyVersion;
}

/// 输入被安全或长度规则拒绝时使用的稳定异常，拒绝内容不得生成树节点。
final class ExplorationInputRejectedException implements Exception {
  const ExplorationInputRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}
