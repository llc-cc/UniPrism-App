import '../core/exploration_models.dart';
import '../core/exploration_ports.dart';
import '../mastery/student_mastery.dart';

/// 教学端口根据掌握证据构造受控请求，不在 Widget 内做教学决策。
final class TeachingExplorationStrategy {
  const TeachingExplorationStrategy({required this.gateway});

  static const List<String> questionScaffolds = [
    '是什么',
    '为什么会这样',
    '如果……会怎样',
    '这和 X 有什么关系',
    '这有什么用',
  ];

  static const int maxQuestionLength = 240;

  final ExplorationGateway gateway;

  Future<ExplorationTurnResponse> respond({
    required ExplorationScenario scenario,
    required StudentMasterySnapshot mastery,
    required String question,
    required List<String> ancestorTexts,
  }) {
    final normalized = question.trim();
    if (normalized.isEmpty) {
      throw const ExplorationInputRejectedException('请输入一个想探索的问题。');
    }
    if (normalized.length > maxQuestionLength) {
      throw const ExplorationInputRejectedException('问题过长，请拆成一个更具体的问题。');
    }
    return gateway.reply(
      ExplorationTurnRequest(
        scenarioId: scenario.id,
        scenarioKind: scenario.kind,
        atomId: scenario.atomId,
        question: normalized,
        masteryLevel: mastery.level,
        misconceptionTags: mastery.misconceptionTags,
        ancestorTexts: ancestorTexts,
        allowedMaterialIds: scenario.allowedMaterialIds,
      ),
    );
  }
}
