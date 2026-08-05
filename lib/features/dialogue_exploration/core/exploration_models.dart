import 'dart:collection';

/// 1.2 首版支持的复用场景；场景只改变策略，不复制思维树内核。
enum ExplorationScenarioKind { teaching, practice, publicDemo }

/// 对话内可调度的教学素材类型，正式数据后续由 1.1 知识库提供。
enum ExplorationMaterialKind { figure, video, interactive, formula }

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
    );
  }
}
