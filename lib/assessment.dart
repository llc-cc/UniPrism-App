part of 'main.dart';

enum AssessmentQuestionKind { single, rank, scale, open }

/// The option arrangement is part of a question's presentation contract.
/// It keeps the native mobile UI aligned with the mini-program as the bank
/// gains new question formats.
enum AssessmentOptionLayout { cards, chips, grid }

class AssessmentOption {
  const AssessmentOption(this.id, this.label);

  final String id;
  final String label;
}

class AssessmentStage {
  const AssessmentStage(this.id, this.label, this.shortLabel);

  final String id;
  final String label;
  final String shortLabel;
}

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.stageId,
    required this.kind,
    required this.title,
    this.subtitle,
    this.options = const [],
    this.scaleItems = const [],
    this.optionLayout,
    this.gridColumns = 2,
    this.minRank = 1,
    this.maxRank = 3,
    this.optional = false,
    this.placeholder,
  });

  final String id;
  final String stageId;
  final AssessmentQuestionKind kind;
  final String title;
  final String? subtitle;
  final List<AssessmentOption> options;
  final List<AssessmentOption> scaleItems;
  final AssessmentOptionLayout? optionLayout;
  final int gridColumns;
  final int minRank;
  final int maxRank;
  final bool optional;
  final String? placeholder;
}

bool _isAssessmentAnswerComplete(AssessmentQuestion question, Map<String, dynamic>? value) {
  if (value == null) return false;
  switch (question.kind) {
    case AssessmentQuestionKind.single:
      return '${value['selectedOptionId'] ?? ''}'.isNotEmpty;
    case AssessmentQuestionKind.rank:
      return (value['rankedOptionIds'] is List && (value['rankedOptionIds'] as List).length >= question.minRank) ||
          '${value['text'] ?? ''}'.trim().isNotEmpty;
    case AssessmentQuestionKind.scale:
      final ratings = value['ratings'];
      return ratings is Map && question.scaleItems.every((item) => ratings[item.id] != null);
    case AssessmentQuestionKind.open:
      return question.optional || '${value['text'] ?? ''}'.trim().isNotEmpty;
  }
}

class AssessmentBank {
  static const stages = [
    AssessmentStage('interest', '兴趣探索测评', '兴趣探索'),
    AssessmentStage('personality', '性格测评', '性格测评'),
    AssessmentStage('thinking_ability', '思维方式与能力', '思维能力'),
    AssessmentStage('values', '偏好与价值观', '价值观'),
    AssessmentStage('future_requirements', '对未来的要求', '未来要求'),
  ];

  static final questions = <AssessmentQuestion>[
    const AssessmentQuestion(
      id: 'v020_interest_q1_orientation',
      stageId: 'interest',
      kind: AssessmentQuestionKind.single,
      title: '经过中学阶段的学习，你对未来的专业和职业是否有一个大致方向？',
      options: [
        AssessmentOption('humanities', '文科类，需要理解力、表达、共情的'),
        AssessmentOption('stem', '理工科类，需要逻辑推理、思考、实验的'),
        AssessmentOption('mixed', '两者都可以，没有明确偏好'),
      ],
    ),
    const AssessmentQuestion(
      id: 'v020_interest_q2_subjects',
      stageId: 'interest',
      kind: AssessmentQuestionKind.rank,
      optionLayout: AssessmentOptionLayout.grid,
      gridColumns: 3,
      title: '中学阶段的学习中，你最喜欢并可能作为专业的学科是？',
      subtitle: '请选择 2-3 个，并按喜欢程度排序（Top 1 最喜欢）。',
      minRank: 2,
      options: [
        AssessmentOption('physics', '物理'), AssessmentOption('chemistry', '化学'),
        AssessmentOption('biology', '生物'), AssessmentOption('history', '历史'),
        AssessmentOption('geography', '地理'), AssessmentOption('politics', '政治'),
        AssessmentOption('math', '数学'), AssessmentOption('chinese', '语文 / 文学'),
        AssessmentOption('foreign_language', '外语'),
      ],
    ),
    const AssessmentQuestion(
      id: 'v020_interest_q3_activities',
      stageId: 'interest',
      kind: AssessmentQuestionKind.rank,
      optionLayout: AssessmentOptionLayout.chips,
      title: '中学阶段的学习中，以下你最感兴趣的活动是？',
      subtitle: '请选择 2-3 个，并按兴趣强度排序（Top 1 最感兴趣）。',
      minRank: 2,
      options: [
        AssessmentOption('information_technology', '信息技术'), AssessmentOption('music_content', '音乐'),
        AssessmentOption('visual_art', '美术'), AssessmentOption('hands_on_making', '手工制作'),
        AssessmentOption('science_experiment', '科学实验'), AssessmentOption('writing', '写作'),
        AssessmentOption('public_speaking', '演讲'), AssessmentOption('organizing', '组织集体活动'),
        AssessmentOption('debate', '辩论 / 模拟法庭 / 模拟联合国'),
        AssessmentOption('business_practice', '商业实践（义卖、社团经营等）'),
      ],
    ),
    const AssessmentQuestion(
      id: 'v020_interest_q4_hobbies',
      stageId: 'interest',
      kind: AssessmentQuestionKind.rank,
      optionLayout: AssessmentOptionLayout.grid,
      gridColumns: 2,
      title: '在节假日，你最喜欢的兴趣爱好是？',
      subtitle: '请选择 2-3 个；如果没有你最喜欢的，可以补充一句。',
      minRank: 2,
      placeholder: '上面没有我最喜欢的，想自己写。',
      options: [
        AssessmentOption('video_games', '电子游戏'), AssessmentOption('short_video', '拍短视频'),
        AssessmentOption('friends_outing', '和朋友出门'), AssessmentOption('art_creation', '艺术创造'),
        AssessmentOption('small_robot', '小型机器人'), AssessmentOption('software_building', '开发软件'),
        AssessmentOption('volunteering', '志愿服务 / 帮助照顾他人'),
        AssessmentOption('outdoor_exploration', '户外与自然探索（徒步、研学、观星等）'),
      ],
    ),
    ..._paired('personality', [
      ('v020_personality_q1_inner_interest', '我更在乎自己喜欢的事物，无论他人是否了解', '如果大家都在谈论某个事物，我也会想去了解'),
      ('v020_personality_q2_teamwork', '小组作业自己一个人组队可以省去麻烦', '和大家一起组队完成更容易取得成功'),
      ('v020_personality_q3_goal_style', '我有非常明确的梦想、目标并愿意为之奋斗', '我倾向根据实际的情况、现实条件不断调整'),
      ('v020_personality_q4_principle', '如果有些事情违背我的原则，那么我一定不做', '在特定条件下，我也可以做某些不常见的事情'),
      ('v020_personality_q5_decision_basis', '是否做一件事情受到我当天的情绪、感受而影响', '是否做一件事情取决于它的性质、条件和要求'),
      ('v020_personality_q6_planning', '只要没有人、DDL 催促我，我会把作业拖到最后一天', '我有明确的完成作业计划，并支配剩下的自由时间'),
      ('v020_personality_q7_abstraction_expression', '代码、公式等抽象但有规律的事物是我喜欢的', '写作、绘画等非标准但有趣的事物是我喜欢的'),
      ('v020_personality_q8_failure_response', '当我失败时，我更关注原因以及下一次如何成功', '当我失败时，我更关注体验以及过程收获的成长'),
      ('v020_personality_q9_decision_facts', '做重要决定时，我更看重客观事实和利弊分析，即使与感受冲突', '做重要决定时，我更看重自己和身边人的感受，即使利弊上不太划算'),
    ]),
    ..._thinkingQuestions(),
    ..._paired('values', [
      ('v020_values_q1_autonomy_rule', '我希望未来有较大的自主空间，可以自己安排做事方式、节奏和表达风格', '我更希望环境规则清楚、要求明确，只要知道怎么做就能稳定得到结果'),
      ('v020_values_q2_innovation_mature', '如果一件事有机会提出新想法、新方案或新表达，我会明显更有兴趣', '如果一件事方法成熟、风险较低，即使枯燥我也可以长期认真投入'),
      ('v020_values_q3_growth_risk', '我愿意为了更大的成长空间，接受一段时间的不确定、竞争和试错压力', '我更适合路径清楚、培养稳定、风险可控的方向，不喜欢长期不确定'),
      ('v020_values_q4_reward_value', '我希望未来的成绩能被认可，例如排名、奖金、晋升、作品传播或项目影响力', '即使外界反馈不明显，只要事情本身有长期价值或符合兴趣，我也能接受'),
      ('v020_values_q5_intensity_boundary', '为了更快成长、更高收入或更好的机会，我可以接受阶段性的高强度投入', '我更看重长期生活质量，希望工作之外还能保留稳定的休息、家庭和个人时间'),
      ('v020_values_q6_repetition_tolerance', '如果一份工作每天面对相似流程和相似评价标准，我会比较容易感到消耗', '如果职责清楚、收入稳定、规则明确，几年内内容变化不大我也能接受'),
      ('v020_values_q7_inner_standard', '当规则和结果冲突时，我更在意事情是否符合我内心的标准', '当现实情况复杂时，我会根据问题情形判断规则是否需要灵活处理'),
      ('v020_values_q8_means_boundary', '只要目标值得，我可以接受绕路、妥协或使用更现实的方式达成结果', '如果达成目标的方式让我觉得违背原则，即使结果很好我会犹豫'),
    ], placeholder: '如果这题不能完全表达你，可以补充一句自己的真实想法。'),
    ..._paired('future_requirements', [
      ('v020_future_q1_time_boundary', '我希望未来的工作生活边界比较清楚，晚上、周末和假期尽量稳定', '如果事情本身有吸引力，我可以接受阶段性比较忙碌'),
      ('v020_future_q2_place_mobility', '我更喜欢固定地点、固定团队和稳定日程，最好每天的变化不要太大', '我更喜欢可以移动、外出、跨场景或自己安排地点的工作状态'),
      ('v020_future_q3_work_scene', '我更能接受坐在办公室、教室、实验室或电脑前，长时间处理信息和任务', '我更希望未来能接触现场、户外、设备、人群或真实空间，不想一直坐着'),
      ('v020_future_q4_path_clarity', '我更愿意选择培养路径、考试规则、晋升方式比较明确的专业或职业', '如果一个方向前期不确定但成长空间大，我愿意用实习、项目和试错去验证'),
      ('v020_future_q5_city_major_tradeoff', '如果一座城市资源更多、机会更大，我愿意优先考虑它，再调整专业方向', '如果一个专业方向足够适合我，我可以接受去不那么热门的城市或学校深耕'),
      ('v020_future_q6_income_freedom', '我对收入压力比较敏感，未来收入上限会明显影响我的专业和职业判断', '我愿意为了自由度、兴趣匹配或生活节奏，接受收入增长慢一些的方向'),
      ('v020_future_q7_visible_feedback', '我希望未来能看到清楚反馈，例如成绩、作品、客户评价、数据增长或晋升结果', '我更能接受反馈慢的方向，只要能长期积累能力、理解问题或形成专业判断'),
      ('v020_future_q9_rhythm_predictability', '我希望工作节奏可预期，加班、出差最好能提前知道', '我可以接受节奏随项目阶段波动，忙闲不均也没关系'),
    ], placeholder: '如果你对未来生活、城市、收入、节奏还有补充，可以写在这里。'),
    const AssessmentQuestion(
      id: 'v020_future_q8_life_sentence',
      stageId: 'future_requirements',
      kind: AssessmentQuestionKind.open,
      title: '一句话总结你想要的人生',
      subtitle: '可以写成目标、画面、底线或提醒。',
      optional: true,
      placeholder: '例如：有稳定生活，也能持续做出自己的作品。',
    ),
  ];

  static List<AssessmentQuestion> _paired(
    String stageId,
    List<(String, String, String)> rows, {
    String? placeholder,
  }) => rows.map((row) => AssessmentQuestion(
        id: row.$1,
        stageId: stageId,
        kind: AssessmentQuestionKind.single,
        title: '下面哪条描述更符合你？',
        placeholder: placeholder,
        options: [
          AssessmentOption('a_strong', row.$2),
          const AssessmentOption('a_lean', '多数时候更符合第一条'),
          const AssessmentOption('b_lean', '多数时候更符合最后一条'),
          AssessmentOption('b_strong', row.$3),
        ],
      )).toList();

  static List<AssessmentQuestion> _thinkingQuestions() => const [
        AssessmentQuestion(
          id: 'v020_thinking_q1_detail_routine', stageId: 'thinking_ability', kind: AssessmentQuestionKind.single,
          title: '下面哪条描述更符合你？',
          options: [
            AssessmentOption('a_strong', '当我了解一类题 / 一类事怎么做后，重复使我感到厌烦'),
            AssessmentOption('a_lean', '多数时候更符合第一条'),
            AssessmentOption('b_lean', '多数时候更符合最后一条'),
            AssessmentOption('b_strong', '即使我掌握了规律，把每道题细节做好才是最重要的'),
          ],
        ),
        AssessmentQuestion(
          id: 'v020_thinking_q2_principle_result', stageId: 'thinking_ability', kind: AssessmentQuestionKind.single,
          title: '下面哪条描述更符合你？',
          options: [
            AssessmentOption('a_strong', '我更关注现象背后的原理，例如社会规律、物理法则、经济理论'),
            AssessmentOption('a_lean', '多数时候更符合第一条'),
            AssessmentOption('b_lean', '多数时候更符合最后一条'),
            AssessmentOption('b_strong', '我更关注现象产生的结果，例如实验结论、市场反馈、生活改善'),
          ],
        ),
        AssessmentQuestion(
          id: 'v020_thinking_q3_expression', stageId: 'thinking_ability', kind: AssessmentQuestionKind.scale,
          title: '我认为对下面列出事情的擅长程度是', subtitle: '1 表示很不擅长，5 表示很擅长。',
          scaleItems: [
            AssessmentOption('writing_expression', '写作文'), AssessmentOption('public_speaking', '演讲'),
            AssessmentOption('stranger_communication', '与陌生人交流'), AssessmentOption('creative_ideation', '想一个新点子'),
          ],
        ),
        AssessmentQuestion(
          id: 'v020_thinking_q4_formal_system', stageId: 'thinking_ability', kind: AssessmentQuestionKind.scale,
          title: '我认为对下面列出事情的擅长程度是', subtitle: '1 表示很不擅长，5 表示很擅长。',
          scaleItems: [
            AssessmentOption('formal_calculation', '复杂公式计算'), AssessmentOption('abstract_problem_solving', '解一道抽象奥数题'),
            AssessmentOption('complex_system_play', '完成机制复杂的游戏（如星际争霸2）'),
          ],
        ),
        AssessmentQuestion(
          id: 'v020_thinking_q5_practice_field', stageId: 'thinking_ability', kind: AssessmentQuestionKind.scale,
          title: '我认为对下面列出事情的擅长程度是', subtitle: '1 表示很不擅长，5 表示很擅长。',
          scaleItems: [
            AssessmentOption('lab_hands_on', '动手做实验（物理、化学、生物等）'),
            AssessmentOption('sports_activity', '体育运动（球类、跑步、骑行等）'),
            AssessmentOption('field_site_tolerance', '长时间在户外、现场或站立环境做事（野外考察、场馆值守等）'),
          ],
        ),
      ];

  static AssessmentStage stageFor(String id) => stages.firstWhere((stage) => stage.id == id);
  static List<AssessmentQuestion> questionsFor(String stageId) => questions.where((question) => question.stageId == stageId).toList();
}

class AssessmentPage extends StatefulWidget {
  const AssessmentPage({super.key});

  @override
  State<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage> {
  final _textController = TextEditingController();
  final Map<String, Map<String, dynamic>> _answers = {};
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _draft = {};

  AssessmentQuestion get _question => AssessmentBank.questions[_index];
  AssessmentStage get _stage => AssessmentBank.stageFor(_question.stageId);
  List<AssessmentQuestion> get _stageQuestions => AssessmentBank.questionsFor(_question.stageId);
  int get _stageIndex => _stageQuestions.indexWhere((question) => question.id == _question.id);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      await AuthService.instance.ensureExploreSession();
      final rows = await AuthService.instance.loadAssessmentAnswers();
      for (final row in rows) {
        final questionId = row['questionId']?.toString();
        final value = row['value'];
        if (questionId != null && value is Map) _answers[questionId] = Map<String, dynamic>.from(value);
      }
      final next = AssessmentBank.questions.indexWhere((question) => !_isAssessmentAnswerComplete(question, _answers[question.id]));
      _index = next < 0 ? AssessmentBank.questions.length - 1 : next;
    } catch (_) {
      // The form remains usable and will retry saving on the first answer.
    } finally {
      _loadDraft();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadDraft() {
    final saved = _answers[_question.id];
    _draft = saved == null
        ? {'questionKind': _question.kind.name, 'rankedOptionIds': <String>[], 'ratings': <String, int>{}, 'text': ''}
        : Map<String, dynamic>.from(saved);
    _textController.text = '${_draft['text'] ?? ''}';
  }

  bool get _canContinue => _isAssessmentAnswerComplete(_question, _draft);

  void _select(String id) => setState(() => _draft = {..._draft, 'questionKind': 'single', 'selectedOptionId': id});

  void _toggleRank(String id) {
    final selected = List<String>.from(_draft['rankedOptionIds'] as List? ?? const <String>[]);
    if (selected.contains(id)) {
      selected.remove(id);
    } else if (selected.length < _question.maxRank) {
      selected.add(id);
    }
    setState(() => _draft = {..._draft, 'questionKind': 'rank', 'rankedOptionIds': selected, 'text': ''});
    _textController.clear();
  }

  void _setRating(String id, int rating) {
    final current = _draft['ratings'];
    final ratings = current is Map ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    ratings[id] = rating;
    setState(() => _draft = {..._draft, 'questionKind': 'scale-grid', 'ratings': ratings});
  }

  void _setText(String text) => setState(() => _draft = {..._draft, 'questionKind': _question.kind == AssessmentQuestionKind.open ? 'open' : _question.kind.name, 'text': text});

  Future<void> _openCustomAnswerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
                TextField(
                  controller: _textController,
                  minLines: 6,
                  maxLines: 8,
                  maxLength: 1200,
                  onChanged: (text) {
                    _setText(text);
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: _question.placeholder,
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF8F2FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF8E4DFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF6B23FF), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _AssessmentButton(
                  label: '继续',
                  enabled: _textController.text.trim().isNotEmpty,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _next() async {
    if (!_canContinue) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先完成当前题目。')));
      return;
    }
    _answers[_question.id] = Map<String, dynamic>.from(_draft);
    setState(() => _saving = true);
    try {
      final rows = _answers.entries.map((entry) {
        final question = AssessmentBank.questions.firstWhere((item) => item.id == entry.key);
        return {
          'questionId': question.id,
          'value': entry.value,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'stageId': question.stageId,
          'source': 'flutter-v020',
        };
      }).toList();
      await AuthService.instance.saveAssessmentAnswers(rows);
      if (!mounted) return;
      final endOfStage = _stageIndex == _stageQuestions.length - 1;
      final endOfAll = _index == AssessmentBank.questions.length - 1;
      if (endOfStage && !endOfAll) {
        final preview = await AuthService.instance.loadAssessmentStagePreview(
          stageId: _stage.id,
          answers: rows,
        );
        if (!mounted) return;
        await _showStageComplete(preview);
        if (!mounted) return;
      }
      if (endOfAll) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _index += 1);
      _loadDraft();
    } on ApiRequestException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showStageComplete(Map<String, dynamic> preview) => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => _StageFilterPage(
            stage: _stage,
            completedStageCount: AssessmentBank.stages.indexOf(_stage) + 1,
            preview: preview,
          ),
        ),
      );

  void _previous() {
    if (_index == 0) return;
    setState(() => _index -= 1);
    _loadDraft();
  }

  void _goBack() {
    if (_index == 0) {
      Navigator.of(context).pop();
      return;
    }
    _previous();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final progress = (_index + 1) / AssessmentBank.questions.length;
    final hasCustomAnswer = _question.kind == AssessmentQuestionKind.rank && _question.placeholder != null;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned.fill(
            child: Opacity(
              // Keep this in sync with UniApp's .v020-bg.
              opacity: 0.84,
              child: Image.network(
                AppAssets.welcomeCampusBackground,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // Figma node 2524:12074:
                  // linear-gradient(-72.055681deg,
                  //   rgba(151,98,255,.38) 14.899%, transparent 77.998%).
                  // The shorter Y component preserves the Figma angle on a tall phone screen.
                  begin: const Alignment(0.951, 0.147),
                  end: const Alignment(-0.951, -0.147),
                  colors: [
                    const Color(0xFF9762FF).withOpacity(0.25),
                    const Color(0xFF9762FF).withOpacity(0.10),
                    const Color(0xFF9762FF).withOpacity(0),
                  ],
                  stops: const [0.08, 0.58, 0.94],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 35,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: _index == 0 ? '返回主页' : '上一题',
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                      color: const Color(0xFF333333),
                      onPressed: _saving ? null : _goBack,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 9,
                      color: const Color(0xFF9257FF),
                      backgroundColor: const Color(0xFFEDEBF0),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      transitionBuilder: _questionPageTransition,
                      child: _QuestionBody(
                        key: ValueKey(_question.id),
                        question: _question,
                        draft: _draft,
                        textController: _textController,
                        onSelect: _select,
                        onRankTap: _toggleRank,
                        onRating: _setRating,
                        onTextChanged: _setText,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.paddingOf(context).bottom),
                  child: hasCustomAnswer
                      ? Row(
                          children: [
                            Expanded(
                              child: _AssessmentButton(
                                label: '以上都没有我自己写',
                                enabled: !_saving,
                                secondary: true,
                                onPressed: _openCustomAnswerDialog,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _AssessmentButton(
                                label: _saving ? '正在保存…' : '继续',
                                enabled: _canContinue && !_saving,
                                onPressed: _next,
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: SizedBox(
                            width: 210,
                            child: _AssessmentButton(
                              label: _saving ? '正在保存…' : _index == AssessmentBank.questions.length - 1 ? '完成测评' : '继续',
                              enabled: _canContinue && !_saving,
                              onPressed: _next,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionPageTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final isLeaving = animation.status == AnimationStatus.reverse;
    final position = Tween<Offset>(
      begin: isLeaving ? const Offset(-0.06, 0) : const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: position, child: child),
    );
  }
}

class _StageFilterPage extends StatefulWidget {
  const _StageFilterPage({
    required this.stage,
    required this.completedStageCount,
    required this.preview,
  });

  final AssessmentStage stage;
  final int completedStageCount;
  final Map<String, dynamic> preview;

  @override
  State<_StageFilterPage> createState() => _StageFilterPageState();
}

class _StageFilterPageState extends State<_StageFilterPage> with TickerProviderStateMixin {
  late final AnimationController _deckController;
  late final AnimationController _revealController;
  Timer? _filteringTimer;
  Timer? _doneTimer;
  bool _filtering = false;
  bool _done = false;

  List<_StageReviewMajor> get _allMajors => _parseMajors(widget.preview['eliminatedMajors']);

  List<_StageReviewMajor> get _previewMajors {
    final provided = _parseMajors(widget.preview['previewTop5']);
    return (provided.isEmpty ? _allMajors : provided).take(5).toList();
  }

  String get _title {
    if (_done) {
      final supplied = '${widget.preview['title'] ?? ''}'.trim();
      if (supplied.isNotEmpty) return supplied;
      return _allMajors.isEmpty ? '筛选完毕，候选池已完成本阶段校准' : '筛选完毕，已将部分不匹配的专业移出候选池';
    }
    return _filtering ? '正在结合你的测评结果，筛选匹配度较低的专业方向' : '专属专业筛选池已开启，正在匹配你的阶段特征';
  }

  String get _subtitle {
    if (_done) {
      final supplied = '${widget.preview['subtitle'] ?? ''}'.trim();
      return supplied.isNotEmpty ? supplied : '下一阶段会继续依据你的选择缩小候选范围。';
    }
    return _filtering ? '正在淘汰适配度靠后的专业，精简候选名单。' : '正在调取本阶段的测评答案进行匹配运算。';
  }

  @override
  void initState() {
    super.initState();
    // Same timing as UniApp: ready 700ms → 1800ms card gather/flip → reveal at 2600ms.
    _deckController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _revealController = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
    _filteringTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _filtering = true);
      _deckController.repeat();
    });
    _doneTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      _deckController.stop();
      setState(() => _done = true);
      _revealController.forward();
    });
  }

  @override
  void dispose() {
    _filteringTimer?.cancel();
    _doneTimer?.cancel();
    _deckController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.completedStageCount / AssessmentBank.stages.length;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned.fill(
            child: Opacity(
              opacity: 0.84,
              child: Image.network(
                AppAssets.welcomeCampusBackground,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0.951, 0.147),
                  end: const Alignment(-0.951, -0.147),
                  colors: [
                    const Color(0xFF9762FF).withOpacity(0.25),
                    const Color(0xFF9762FF).withOpacity(0.10),
                    const Color(0xFF9762FF).withOpacity(0),
                  ],
                  stops: const [0.08, 0.58, 0.94],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 9,
                      color: const Color(0xFF9257FF),
                      backgroundColor: const Color(0xFFE9E5ED),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.48, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
                  const SizedBox(height: 12),
                  Text(_subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.5, color: const Color(0xFF333333).withOpacity(0.62))),
                  const SizedBox(height: 25),
                  SizedBox(
                    height: 205,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        FadeTransition(
                          opacity: Tween<double>(begin: 1, end: 0).animate(_revealController),
                          child: _StageReviewDeck(controller: _deckController, filtering: _filtering),
                        ),
                        if (_done)
                          FadeTransition(
                            opacity: _revealController,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic)),
                              child: _previewMajors.isEmpty
                                  ? const Center(child: Text('本阶段没有新增淘汰专业。', style: TextStyle(color: Color(0xFF5A427A))))
                                  : ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      itemCount: _previewMajors.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                                      itemBuilder: (context, index) => _EliminatedMajorCard(
                                        major: _previewMajors[index],
                                        animation: CurvedAnimation(
                                          parent: _revealController,
                                          curve: Interval(index * 0.08, 1, curve: Curves.easeOutBack),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    opacity: _done ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Text('本阶段已完成筛选，下一阶段会继续缩小候选范围', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF5A427A))),
                  ),
                  const Spacer(flex: 3),
                  SizedBox(
                    width: 210,
                    child: _AssessmentButton(
                      label: _done ? '继续下一阶段' : '正在筛选…',
                      enabled: _done,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_StageReviewMajor> _parseMajors(dynamic raw) {
  if (raw is! List) return const <_StageReviewMajor>[];
  return raw.whereType<Map>().map(_StageReviewMajor.fromJson).where((major) => major.name.isNotEmpty).toList();
}

class _StageReviewMajor {
  const _StageReviewMajor({required this.name, this.iconUrl});

  factory _StageReviewMajor.fromJson(Map raw) {
    final data = raw.map((key, value) => MapEntry('$key', value));
    return _StageReviewMajor(
      name: '${data['name'] ?? data['majorName'] ?? data['label'] ?? ''}',
      iconUrl: '${data['iconPath'] ?? data['iconUrl'] ?? data['imageUrl'] ?? ''}',
    );
  }

  final String name;
  final String? iconUrl;

  String? get resolvedIconUrl {
    final value = (iconUrl ?? '').trim();
    if (value.isEmpty) return null;
    return value.startsWith('/') ? 'https://assets.uniprism.cn$value' : value;
  }
}

class _StageReviewDeck extends StatelessWidget {
  const _StageReviewDeck({required this.controller, required this.filtering});

  final AnimationController controller;
  final bool filtering;

  @override
  Widget build(BuildContext context) {
    const order = [0, 1, 3, 4, 2];
    const offsets = [-104.0, -52.0, 0.0, 52.0, 104.0];
    const scales = [0.76, 0.86, 1.0, 0.86, 0.76];
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final time = filtering ? controller.value : 0.0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (final index in order)
              _StageDeckCard(
                offset: offsets[index],
                baseScale: scales[index],
                time: time,
              ),
          ],
        );
      },
    );
  }
}

class _StageDeckCard extends StatelessWidget {
  const _StageDeckCard({required this.offset, required this.baseScale, required this.time});

  final double offset;
  final double baseScale;
  final double time;

  @override
  Widget build(BuildContext context) {
    final gathering = time <= 0.24 ? 1 - time / 0.24 : time < 0.72 ? 0.0 : (time - 0.72) / 0.28;
    final angle = time < 0.40 ? 0.0 : time < 0.54 ? (time - 0.40) / 0.14 * math.pi : time < 0.72 ? math.pi : math.pi + (time - 0.72) / 0.28 * math.pi;
    final scale = time <= 0.24 ? baseScale + (1 - baseScale) * (time / 0.24) : time < 0.72 ? 1.0 : 1 - (1 - baseScale) * ((time - 0.72) / 0.28);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..translate(offset * gathering)
        ..rotateY(angle)
        ..scale(scale),
      child: Container(
        width: 116,
        height: 168,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const RadialGradient(colors: [Color(0xFFCFC2FF), Color(0xFF8E7EFF), Color(0xFF7491FF)]),
          boxShadow: [
            BoxShadow(color: const Color(0xFF816AFF).withOpacity(0.34), blurRadius: 16),
            BoxShadow(color: const Color(0xFF4E39B4).withOpacity(0.14), blurRadius: 22, offset: const Offset(0, 10)),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 3),
        ),
        child: Icon(Icons.change_history_rounded, size: 48, color: Colors.white.withOpacity(0.78), shadows: [Shadow(color: const Color(0xFF4838AA).withOpacity(0.22), blurRadius: 12, offset: const Offset(0, 6))]),
      ),
    );
  }
}

class _EliminatedMajorCard extends StatelessWidget {
  const _EliminatedMajorCard({required this.major, required this.animation});

  final _StageReviewMajor major;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation,
          child: Container(
            width: 125,
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9AB5FF), Color(0xFF7E92FF)]),
              border: Border.all(color: Colors.white.withOpacity(0.92), width: 2),
              boxShadow: [BoxShadow(color: const Color(0xFF48377E).withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 7))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(7)),
                  child: major.resolvedIconUrl == null
                      ? const Icon(Icons.school_outlined, color: Color(0xFF6B23FF))
                      : Image.network(major.resolvedIconUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_outlined, color: Color(0xFF6B23FF))),
                ),
                const SizedBox(height: 10),
                Text(major.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, height: 1.35, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    super.key,
    required this.question, required this.draft, required this.textController, required this.onSelect,
    required this.onRankTap, required this.onRating, required this.onTextChanged,
  });

  final AssessmentQuestion question;
  final Map<String, dynamic> draft;
  final TextEditingController textController;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRankTap;
  final void Function(String, int) onRating;
  final ValueChanged<String> onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            question.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
          ),
        ),
        if (question.subtitle != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Text(question.subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF888888))),
          ),
        ],
        const SizedBox(height: 24),
        switch (question.kind) {
          AssessmentQuestionKind.single => _SingleOptions(options: question.options, selectedId: '${draft['selectedOptionId'] ?? ''}', onSelect: onSelect),
          AssessmentQuestionKind.rank => question.optionLayout == AssessmentOptionLayout.grid
              ? _RankGrid(question: question, draft: draft, onTap: onRankTap)
              : question.optionLayout == AssessmentOptionLayout.cards
                  ? _RankCards(question: question, draft: draft, onTap: onRankTap)
                  : _RankOptions(question: question, draft: draft, onTap: onRankTap),
          AssessmentQuestionKind.scale => _ScaleOptions(items: question.scaleItems, draft: draft, onRating: onRating),
          AssessmentQuestionKind.open => const SizedBox.shrink(),
        },
        if (question.placeholder != null && question.kind != AssessmentQuestionKind.rank) ...[
          const SizedBox(height: 18),
          SizedBox(
            // UniApp .v020-textarea--single-supplement: min-height 344rpx.
            height: 172,
            child: TextField(
              controller: textController,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              maxLength: 1200,
              onChanged: onTextChanged,
              decoration: InputDecoration(
                hintText: question.placeholder,
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF9661FF).withOpacity(0.12),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF9762FF).withOpacity(0.72), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFF9762FF).withOpacity(0.72), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF9762FF), width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SingleOptions extends StatelessWidget {
  const _SingleOptions({required this.options, required this.selectedId, required this.onSelect});
  final List<AssessmentOption> options;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final option in options) ...[
            _FlipOptionCard(
              label: option.label,
              selected: selectedId == option.id,
              onTap: () => onSelect(option.id),
            ),
            if (option != options.last) const SizedBox(height: 9),
          ],
        ],
      );
}

class _RankGrid extends StatelessWidget {
  const _RankGrid({required this.question, required this.draft, required this.onTap});

  final AssessmentQuestion question;
  final Map<String, dynamic> draft;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = List<String>.from(draft['rankedOptionIds'] as List? ?? const <String>[]);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: question.gridColumns,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        mainAxisExtent: 43,
      ),
      itemCount: question.options.length,
      itemBuilder: (context, index) {
        final option = question.options[index];
        final rank = selected.indexOf(option.id);
        return _FlipOptionCard(
          label: option.label,
          selected: rank >= 0,
          compact: true,
          rank: rank >= 0 ? rank + 1 : null,
          onTap: () => onTap(option.id),
        );
      },
    );
  }
}

class _FlipOptionCard extends StatelessWidget {
  const _FlipOptionCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.rank,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return _OptionCardFace(
      label: label,
      selected: selected,
      compact: compact,
      rank: rank,
      onTap: onTap,
    );
  }
}

class _OptionCardFace extends StatelessWidget {
  const _OptionCardFace({
    required this.label,
    required this.selected,
    required this.compact,
    required this.rank,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool compact;
  final int? rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 43 : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            constraints: BoxConstraints(minHeight: compact ? 43 : 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              // Same selected surface as UniApp .v020-option--selected.
              color: selected ? Colors.white.withOpacity(0.94) : Colors.white.withOpacity(0.88),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? const Color(0xFF9258FF) : Colors.white.withOpacity(0.9), width: 1),
              boxShadow: selected
                  ? [
                      const BoxShadow(color: Color(0xFF9258FF), offset: Offset(0, 3.5)),
                      BoxShadow(color: const Color(0xFF6323FF).withOpacity(0.13), blurRadius: 20, offset: const Offset(0, 11)),
                    ]
                  : [BoxShadow(color: const Color(0xFF67588F).withOpacity(0.055), blurRadius: 21, offset: const Offset(0, 9))],
            ),
            child: compact
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 17,
                        height: 17,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Color(0xFFE5F5FF), shape: BoxShape.circle),
                        child: Text('${rank ?? '◈'}', style: const TextStyle(fontSize: 9, color: Color(0xFF268BE0), fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 4),
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF333333)))),
                    ],
                  )
                : Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.35, color: Color(0xFF333333))),
          ),
        ),
      ),
    );
  }
}

class _AssessmentButton extends StatelessWidget {
  const _AssessmentButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final fill = enabled ? (secondary ? const Color(0xFF5A16D7) : const Color(0xFF6B16FF)) : const Color(0xFFC8A7F4);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF3D0AA8) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: enabled ? 5 : 0),
        child: SizedBox(
          // UniApp .v020-primary-btn: 100rpx.
          height: 50,
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              elevation: 0,
              backgroundColor: fill,
              disabledBackgroundColor: fill,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white.withOpacity(0.82),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _RankOptions extends StatelessWidget {
  const _RankOptions({required this.question, required this.draft, required this.onTap});
  final AssessmentQuestion question;
  final Map<String, dynamic> draft;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = List<String>.from(draft['rankedOptionIds'] as List? ?? const <String>[]);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 9,
        runSpacing: 16,
        children: [
          for (final option in question.options)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: ChoiceChip(
                label: Text(
                  selected.contains(option.id) ? 'Top ${selected.indexOf(option.id) + 1}  ${option.label}' : option.label,
                ),
                selected: selected.contains(option.id),
                onSelected: (_) => onTap(option.id),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: selected.contains(option.id) ? const Color(0xFF5420BF) : const Color(0xFF55515A),
                  fontWeight: selected.contains(option.id) ? FontWeight.w600 : FontWeight.w400,
                ),
                backgroundColor: const Color(0xFFFCF8FD),
                selectedColor: const Color(0xFFECE2FF),
                side: BorderSide(color: selected.contains(option.id) ? const Color(0xFF6B23FF) : const Color(0xFFE5DDE8)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Long ranked answers can opt into full-width cards while preserving the
/// exact same ordered answer value used by the compact chip layout.
class _RankCards extends StatelessWidget {
  const _RankCards({required this.question, required this.draft, required this.onTap});

  final AssessmentQuestion question;
  final Map<String, dynamic> draft;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = List<String>.from(draft['rankedOptionIds'] as List? ?? const <String>[]);
    return Column(
      children: [
        for (final option in question.options) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onTap(option.id),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                backgroundColor: selected.contains(option.id) ? const Color(0xFFF0E8FF) : Colors.white,
                side: BorderSide(color: selected.contains(option.id) ? const Color(0xFF6B23FF) : const Color(0xFFE5E5E5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                children: [
                  if (selected.contains(option.id)) ...[
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Color(0xFF6B23FF), shape: BoxShape.circle),
                      child: Text('${selected.indexOf(option.id) + 1}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(option.label, style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF222222)))),
                ],
              ),
            ),
          ),
          if (option != question.options.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ScaleOptions extends StatelessWidget {
  const _ScaleOptions({required this.items, required this.draft, required this.onRating});
  final List<AssessmentOption> items;
  final Map<String, dynamic> draft;
  final void Function(String, int) onRating;

  @override
  Widget build(BuildContext context) {
    final raw = draft['ratings'];
    final ratings = raw is Map ? raw : const <String, dynamic>{};
    return Column(
      children: [
        for (final item in items) ...[
          Text(item.label, style: const TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var rating = 1; rating <= 5; rating++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: rating == 5 ? 0 : 7),
                    child: OutlinedButton(
                      onPressed: () => onRating(item.id, rating),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: const Size(0, 40),
                        backgroundColor: ratings[item.id] == rating ? const Color(0xFF6B23FF) : Colors.white,
                        foregroundColor: ratings[item.id] == rating ? Colors.white : const Color(0xFF333333),
                        side: BorderSide(color: ratings[item.id] == rating ? const Color(0xFF6B23FF) : const Color(0xFFE0E0E0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('$rating'),
                    ),
                  ),
                ),
            ],
          ),
          if (item != items.last) const SizedBox(height: 24),
        ],
      ],
    );
  }
}
