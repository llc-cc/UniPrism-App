import 'package:flutter/foundation.dart';

/// 与后端 `teacher-agent-bnu-math-set-chapter.json` 对齐的北师大 1.1.1 完整验收数据。
abstract final class TeacherAgentTestSeed {
  static const autoLoadChapterInDev = bool.fromEnvironment(
    'TEACHER_AGENT_TEST_SEED',
    defaultValue: false,
  );

  static bool get shouldAutoLoadChapter => kDebugMode && autoLoadChapterInDev;

  static const chapterId = 'bnu-math-ch1-set-concept';
  static const chapterTitle = '【北师大必修一·1.1.1】集合的概念与表示';
  static const atomId = 'bnu-set-concept-representation';
  static const recommendedNodeId = 'set-notation-methods';
  static const entryQuestion = '{1,2,3} 与 {3,2,1} 是同一个集合吗？';
  static const scenarioId = 'prestudy';

  static const g1DiagnosticAnswer = '元素要么属于 A（∈），要么不属于 A（∉）。集合元素具有确定性、互异性和无序性。';
  static const g2DiagnosticAnswer =
      '列举法适合元素有限且可一一列出的集合，如 {1,2,3}；描述法用 {x|条件} 表示满足共同性质的所有元素，如 {x|x<10,x∈N*}。';

  static const designArenaOptions = [
    (skill: 'MORE_EXAMPLES', label: '多看几个例子', icon: '📚'),
    (skill: 'INTERACTIVE_EXPLORATION', label: '动手判断 ∈/∉', icon: '🎮'),
    (skill: 'CONCEPT_HISTORY', label: '了解概念由来', icon: '🕰'),
  ];

  static const g1PracticeFail = (
    practiceId: 'set-same-collection-v1',
    reasoning: '我觉得顺序不同就不是同一个集合',
    answer: '不是同一个集合',
  );

  static const g1PracticePass = (
    practiceId: 'set-same-collection-v1',
    reasoning: '两个集合元素完全相同，只是排列顺序不同；集合具有无序性，顺序不影响集合本身。',
    answer: '是同一个集合',
  );

  static const g1RepairPass = (
    practiceId: 'set-determinacy-v1',
    reasoning: '“高个子”没有统一明确的标准，无法确定每名同学是否属于这个整体，违反集合元素的确定性。',
    answer: '不能构成集合',
  );

  static const g2RosterPracticePass = (
    practiceId: 'set-roster-v1',
    reasoning: '小于 10 的正整数数量有限，可以逐个列出，所以适合使用列举法。',
    answer: '{1,2,3,4,5,6,7,8,9}',
  );

  static const g2PracticePass = (
    practiceId: 'set-builder-v1',
    reasoning: '描述法用条件描述元素的共同性质，小于 10 的正整数满足 0<x<10 且 x 是正整数。',
    answer: '{x | 0<x<10, x∈N*}',
  );

  static const materialEventInteractive = (
    eventType: 'SET_MEMBERSHIP_VERIFIED',
    element: 3,
    setLabel: 'A',
    relation: 'member',
  );

  static const diagnosticAnswers = <String, String>{
    'bnu-set-concept-representation': g1DiagnosticAnswer,
    'chemical-reaction-conservation':
        '因为改下标会改变物质本身，只有系数表示分子个数，所以只能调整系数来保持原子守恒。',
    'negative-times-negative': '连续两次取相反数会回到原方向，所以同号相乘结果为正，负负得正。',
    'quadratic-function': 'h 控制顶点横坐标，k 控制纵坐标；a 为正开口向上，a 为负开口向下。',
    'inequality-proof': '基本不等式要求变量为正数，等号在两边相等时成立。',
    'force-and-motion': '根据 F=ma，合力不变时质量加倍加速度减半，力加倍则加速度加倍。',
  };

  static String diagnosticAnswerFor(String atomId, {int goalIndex = 0}) {
    if (atomId == TeacherAgentTestSeed.atomId) {
      return goalIndex >= 1 ? g2DiagnosticAnswer : g1DiagnosticAnswer;
    }
    return diagnosticAnswers[atomId] ?? '我先用自己的话说说核心依据，再请老师继续带我学。';
  }
}
