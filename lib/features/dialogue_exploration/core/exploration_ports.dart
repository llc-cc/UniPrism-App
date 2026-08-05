import 'exploration_models.dart';
import '../mastery/student_mastery.dart';
import '../practice/practice_diagnosis.dart';

/// 为 1.2 提供原子、问题与素材；正式接入时由 1.1 API 实现替换。
abstract interface class ExplorationContentRepository {
  Future<List<ExplorationScenario>> loadScenarios();

  Future<List<ExplorationMaterial>> loadMaterials(Set<String> ids);

  Future<Set<String>> allowedMaterialIds(String atomId);

  /// 开发期检查 fixture 引用，避免 Mock 掩盖未来知识库边界错误。
  Future<List<String>> validateFixtures();
}

/// 对话策略传给 Gateway 的受控上下文，allowedMaterialIds 是素材安全边界。
final class ExplorationTurnRequest {
  ExplorationTurnRequest({
    required this.scenarioId,
    required this.scenarioKind,
    required this.atomId,
    required this.question,
    required this.masteryLevel,
    required List<String> misconceptionTags,
    required List<String> ancestorTexts,
    required Set<String> allowedMaterialIds,
  }) : misconceptionTags = List.unmodifiable(misconceptionTags),
       ancestorTexts = List.unmodifiable(ancestorTexts),
       allowedMaterialIds = Set.unmodifiable(allowedMaterialIds);

  final String scenarioId;
  final ExplorationScenarioKind scenarioKind;
  final String atomId;
  final String question;
  final StudentMasteryLevel masteryLevel;
  final List<String> misconceptionTags;
  final List<String> ancestorTexts;
  final Set<String> allowedMaterialIds;
}

/// 正式 Skill 与确定性 Mock 共用的回答接口。
abstract interface class ExplorationGateway {
  Future<ExplorationTurnResponse> reply(ExplorationTurnRequest request);
}

/// 掌握证据输出端口；实现必须保留证据来源，不能把模型候选伪装成确认结果。
abstract interface class MasteryEvidenceSink {
  Future<void> write(MasteryEvidence evidence);
}
