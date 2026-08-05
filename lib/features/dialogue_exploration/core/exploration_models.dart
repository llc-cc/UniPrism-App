import 'dart:collection';

/// 1.2 首版支持的复用场景；场景只改变策略，不复制思维树内核。
enum ExplorationScenarioKind { teaching, practice, publicDemo }

/// 对话内可调度的教学素材类型，正式数据后续由 1.1 知识库提供。
enum ExplorationMaterialKind { figure, video, interactive, formula }

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
