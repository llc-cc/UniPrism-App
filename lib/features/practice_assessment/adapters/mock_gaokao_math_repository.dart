import '../core/practice_models.dart';
import '../core/practice_ports.dart';
import '../core/rule_based_attempt_assessor.dart';

/// 提供新高考数学 19 题结构演示；题干为自造内容，不冒充官方真题。
final class MockGaokaoMathRepository implements PracticeRepository {
  MockGaokaoMathRepository({AttemptAssessor? assessor})
    : _assessor = assessor ?? const RuleBasedAttemptAssessor();

  final AttemptAssessor _assessor;
  final Map<String, AttemptAssessment> _assessments = {};

  bool failNextSubmission = false;

  @override
  PracticeConnectionMode get connectionMode => PracticeConnectionMode.mock;

  Map<String, AttemptAssessment> get assessments =>
      Map.unmodifiable(_assessments);

  @override
  Future<PracticePaper> loadPaper() async => _paper;

  @override
  Future<PracticeSessionSnapshot> loadOrCreateSession() async =>
      PracticeSessionSnapshot(
        sessionId: 'mock-practice-session',
        status: PracticeRemoteSessionStatus.active,
        revision: 0,
        currentQuestionNumber: 1,
        paper: _paper,
        drafts: const {},
        results: _assessments,
        assessorMode: 'RULES',
      );

  @override
  Future<PracticeDraft> saveDraft({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required int currentQuestionNumber,
  }) async => draft.copyWith(serverVersion: draft.serverVersion + 1);

  @override
  Future<void> recordEvents({
    required String sessionId,
    required List<PracticeEvent> events,
  }) async {}

  @override
  Future<AttemptAssessment> submitAttempt({
    required String sessionId,
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  }) async {
    if (failNextSubmission) {
      failNextSubmission = false;
      throw StateError('模拟网络失败');
    }
    final assessment = _assessor.assess(
      question: question,
      draft: draft,
      facts: facts,
    );
    _assessments[question.id] = assessment;
    return assessment;
  }

  @override
  Future<void> completeSession(String sessionId) async {}
}

final PracticePaper _paper = PracticePaper(
  id: 'cn-gaokao-2026-new-i-math-v1',
  title: '2026 新高考 I 卷数学结构演示',
  subtitle: '19 道自造演示题，仅用于验证练习评分流程，不是官方试题。',
  source: PracticeContentSource.demonstration,
  contentVersion: 'demo-v1',
  questions: <PracticeQuestion>[
    _choice(
      1,
      '一组数据 3、5、6、8、11 的中位数是（ ）。',
      'B',
      <String, String>{'A': '5', 'B': '6', 'C': '7', 'D': '8'},
      <String>['统计', '中位数'],
      <String>['排序', '中间'],
    ),
    _choice(
      2,
      '向量 a、b 不共线，若 3a+yb=xa-2b，则 x、y 为（ ）。',
      'A',
      <String, String>{'A': '3，-2', 'B': '-3，2', 'C': '2，-3', 'D': '-2，3'},
      <String>['平面向量'],
      <String>['不共线', '比较系数'],
    ),
    _choice(
      3,
      '集合 A={-1,0,1}，B={0,1,2}，则 A∩B 为（ ）。',
      'C',
      <String, String>{
        'A': '{-1,2}',
        'B': '{0}',
        'C': '{0,1}',
        'D': '{-1,0,1,2}',
      },
      <String>['集合'],
      <String>['交集', '共同元素'],
    ),
    _choice(
      4,
      '函数 y=x²+2x 在 x=1 处的切线斜率为（ ）。',
      'D',
      <String, String>{'A': '1', 'B': '2', 'C': '3', 'D': '4'},
      <String>['导数'],
      <String>['求导', '代入'],
    ),
    _choice(
      5,
      '抛物线 y²=8x 的焦点坐标为（ ）。',
      'B',
      <String, String>{'A': '(1,0)', 'B': '(2,0)', 'C': '(0,1)', 'D': '(0,2)'},
      <String>['圆锥曲线'],
      <String>['标准方程', '焦点'],
    ),
    _choice(
      6,
      '函数 f(x)=x·e^(-x) 的最大值在何处取得（ ）。',
      'C',
      <String, String>{'A': 'x=-1', 'B': 'x=0', 'C': 'x=1', 'D': 'x=2'},
      <String>['函数', '导数'],
      <String>['求导', '单调性'],
    ),
    _choice(
      7,
      '六个奇数两两分组，若组和构成等差数列，判断公差奇偶性（ ）。',
      'B',
      <String, String>{'A': '必为奇数', 'B': '必为偶数', 'C': '必为零', 'D': '无法判断'},
      <String>['数列', '不变量'],
      <String>['总和约束', '奇偶性', '构造验证'],
      highReasoning: true,
    ),
    _choice(
      8,
      '从关于原点对称的有限点集中等可能取一点，坐标和的期望为（ ）。',
      'A',
      <String, String>{'A': '0', 'B': '1', 'C': '-1', 'D': '与点数相同'},
      <String>['概率', '期望'],
      <String>['对称性', '期望'],
    ),
    _multiple(
      9,
      '设 z=1+i，下列关于共轭、模和平方的结论正确的是（多选）。',
      'AC',
      <String, String>{
        'A': '共轭为 1-i',
        'B': '模为 2',
        'C': '平方为 2i',
        'D': '实部为 0',
      },
      <String>['复数'],
      <String>['共轭', '模', '平方'],
    ),
    _multiple(
      10,
      '空间向量题中，下列可用于证明线面垂直的条件正确的是（多选）。',
      'BC',
      <String, String>{
        'A': '垂直平面内一条线',
        'B': '垂直平面内两条相交线',
        'C': '方向向量与法向量平行',
        'D': '与平面内一条线平行',
      },
      <String>['立体几何'],
      <String>['定义', '法向量', '反例'],
    ),
    _multiple(
      11,
      '关于圆的弦长，下列由圆心到直线距离可推出的结论正确的是（多选）。',
      'BD',
      <String, String>{
        'A': '距离越大弦越长',
        'B': '等距对应等弦长',
        'C': '距离可超过半径仍相交',
        'D': '距离为零时弦最长',
      },
      <String>['圆', '解析几何'],
      <String>['弦长公式', '取值范围'],
    ),
    _fill(
      12,
      '双曲线 x²/4-y²/5=1 的离心率为______。',
      '3/2',
      <String>['双曲线'],
      <String>['标准方程', '离心率'],
    ),
    _fill(
      13,
      '函数 f(x)=sin(x+π/2)，则 f(0)=______。',
      '1',
      <String>['三角函数'],
      <String>['诱导公式', '代入'],
    ),
    _fill(
      14,
      '数列每三个连续分块的和依次为 2n，写出相邻块和之差______。',
      '2',
      <String>['数列', '分块'],
      <String>['分块', '作差'],
      highReasoning: true,
    ),
    _solution(
      15,
      '在直三棱柱中证明一条中点连线平行于指定侧面，并求两者距离。',
      '2',
      <String>['立体几何'],
      <String>['中位线', '线面平行', '建立坐标系', '距离'],
    ),
    _solution(
      16,
      '已知三角形两边及夹角，先求第三边，再求一个外接构造中的线段长。',
      '3',
      <String>['解三角形'],
      <String>['余弦定理', '相似', '勾股定理'],
    ),
    _solution(
      17,
      '独立重复试验在首次成功或达到上限时停止，写出分布列并证明条件概率关系。',
      '(1-p)^k',
      <String>['概率'],
      <String>['分布列', '独立性', '条件概率'],
    ),
    _solution(
      18,
      '椭圆中过焦点的弦与中心对称点构成角，求角的最值。',
      '4√3',
      <String>['解析几何'],
      <String>['设直线', '韦达定理', '向量夹角', '基本不等式'],
      highReasoning: true,
    ),
    _solution(
      19,
      '给定一个新定义的增量集合，完成集合计算、包含关系证明与单调性证明。',
      '证明完成',
      <String>['函数', '集合', '新定义'],
      <String>['理解定义', '分类讨论', '集合包含', '反证', '单调性'],
      highReasoning: true,
    ),
  ],
);

PracticeQuestion _choice(
  int number,
  String prompt,
  String answer,
  Map<String, String> options,
  List<String> knowledge,
  List<String> keywords, {
  bool highReasoning = false,
}) => _question(
  number,
  PracticeQuestionType.singleChoice,
  prompt,
  answer,
  options,
  knowledge,
  keywords,
  highReasoning,
);

PracticeQuestion _multiple(
  int number,
  String prompt,
  String answer,
  Map<String, String> options,
  List<String> knowledge,
  List<String> keywords,
) => _question(
  number,
  PracticeQuestionType.multipleChoice,
  prompt,
  answer,
  options,
  knowledge,
  keywords,
  true,
);

PracticeQuestion _fill(
  int number,
  String prompt,
  String answer,
  List<String> knowledge,
  List<String> keywords, {
  bool highReasoning = false,
}) => _question(
  number,
  PracticeQuestionType.fillBlank,
  prompt,
  answer,
  const <String, String>{},
  knowledge,
  keywords,
  highReasoning,
);

PracticeQuestion _solution(
  int number,
  String prompt,
  String answer,
  List<String> knowledge,
  List<String> keywords, {
  bool highReasoning = false,
}) => _question(
  number,
  PracticeQuestionType.solution,
  prompt,
  answer,
  const <String, String>{},
  knowledge,
  keywords,
  highReasoning,
);

PracticeQuestion _question(
  int number,
  PracticeQuestionType type,
  String prompt,
  String answer,
  Map<String, String> options,
  List<String> knowledge,
  List<String> keywords,
  bool highReasoning,
) {
  final id = 'gk-2026-n1-math-q${number.toString().padLeft(2, '0')}';
  final dimensions = <AbilityDimension>{
    AbilityDimension.understanding,
    AbilityDimension.calculation,
    AbilityDimension.reasoning,
    AbilityDimension.expression,
    if (highReasoning) AbilityDimension.technique,
  };
  return PracticeQuestion(
    id: id,
    number: number,
    type: type,
    prompt: prompt,
    options: options,
    knowledgePoints: knowledge,
    difficulty: QuestionDifficultyProfile(
      knowledgeLoad: number <= 4
          ? 1
          : number <= 14
          ? 2
          : 3,
      readingLoad: highReasoning ? 3 : 1,
      reasoningLoad: highReasoning
          ? 4
          : number >= 15
          ? 3
          : 1,
      calculationLoad: number >= 15 ? 3 : 2,
      techniqueDependency: highReasoning ? 4 : 1,
      stepDepth: number >= 15 ? 4 : keywords.length.clamp(1, 4),
    ),
    rubric: QuestionRubric(
      version: 'rubric-v1',
      expectedAnswers: <String>[answer],
      steps: <RubricStep>[
        for (var index = 0; index < keywords.length; index++)
          RubricStep(
            id: '$id-step-${index + 1}',
            description: keywords[index],
            keywords: <String>[keywords[index]],
            dimensions: dimensions,
          ),
      ],
      observableDimensions: dimensions,
      errorTags: const <String>['concept-gap', 'calculation-slip'],
    ),
  );
}
