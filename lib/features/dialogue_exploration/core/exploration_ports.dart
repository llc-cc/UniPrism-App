import 'exploration_models.dart';

/// 为 1.2 提供原子、问题与素材；正式接入时由 1.1 API 实现替换。
abstract interface class ExplorationContentRepository {
  Future<List<ExplorationScenario>> loadScenarios();

  Future<List<ExplorationMaterial>> loadMaterials(Set<String> ids);

  Future<Set<String>> allowedMaterialIds(String atomId);

  /// 开发期检查 fixture 引用，避免 Mock 掩盖未来知识库边界错误。
  Future<List<String>> validateFixtures();
}
