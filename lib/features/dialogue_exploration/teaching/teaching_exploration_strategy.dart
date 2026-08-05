import '../core/exploration_models.dart';
import '../core/exploration_ports.dart';
import '../mastery/student_mastery.dart';
import 'teaching_strategy_engine.dart';

/// 单轮回答与其策略决策必须绑定返回，防止控制器记录的模式和实际提示错位。
final class TeachingTurnResult {
  const TeachingTurnResult({required this.decision, required this.response});

  final TeachingStrategyDecision decision;
  final ExplorationTurnResponse response;
}

/// 教学端口根据掌握证据构造受控请求，不在 Widget 内做教学决策。
final class TeachingExplorationStrategy {
  const TeachingExplorationStrategy({
    required this.gateway,
    this.engine = const TeachingStrategyEngine(),
  });

  static const List<String> questionScaffolds = [
    '是什么',
    '为什么会这样',
    '如果……会怎样',
    '这和 X 有什么关系',
    '这有什么用',
  ];

  static const int maxQuestionLength = 240;

  final ExplorationGateway gateway;
  final TeachingStrategyEngine engine;

  Future<ExplorationTurnResponse> respond({
    required ExplorationScenario scenario,
    required StudentMasterySnapshot mastery,
    required String question,
    required List<String> ancestorTexts,
    int turnIndex = 0,
    int consecutiveErrors = 0,
    bool isClosing = false,
  }) async {
    final result = await respondWithDecision(
      scenario: scenario,
      mastery: mastery,
      question: question,
      ancestorTexts: ancestorTexts,
      turnIndex: turnIndex,
      consecutiveErrors: consecutiveErrors,
      isClosing: isClosing,
    );
    return result.response;
  }

  Future<TeachingTurnResult> respondWithDecision({
    required ExplorationScenario scenario,
    required StudentMasterySnapshot mastery,
    required String question,
    required List<String> ancestorTexts,
    required int turnIndex,
    required int consecutiveErrors,
    required bool isClosing,
  }) async {
    final normalized = question.trim();
    if (normalized.isEmpty) {
      throw const ExplorationInputRejectedException('请输入一个想探索的问题。');
    }
    if (normalized.length > maxQuestionLength) {
      throw const ExplorationInputRejectedException('问题过长，请拆成一个更具体的问题。');
    }
    final decision = engine.decide(
      turnIndex: turnIndex,
      studentText: normalized,
      consecutiveErrors: consecutiveErrors,
      isClosing: isClosing,
      mastery: mastery,
    );
    final response = await gateway.reply(
      ExplorationTurnRequest(
        scenarioId: scenario.id,
        scenarioKind: scenario.kind,
        atomId: scenario.atomId,
        question: normalized,
        masteryLevel: mastery.level,
        misconceptionTags: mastery.misconceptionTags,
        ancestorTexts: ancestorTexts,
        allowedMaterialIds: scenario.allowedMaterialIds,
        teachingMode: decision.mode.name,
        teachingGoal: decision.goal.name,
        strategyReason: decision.reason,
      ),
    );
    return TeachingTurnResult(decision: decision, response: response);
  }
}
