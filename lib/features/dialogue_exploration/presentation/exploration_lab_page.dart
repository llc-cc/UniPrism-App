import 'package:flutter/material.dart';

import '../adapters/mock_exploration_content_repository.dart';
import '../core/exploration_models.dart';
import '../mastery/mock_student_mastery_repository.dart';
import '../mastery/student_mastery.dart';
import 'exploration_session_page.dart';

/// 1.2 对话优先入口；学生只提出问题，掌握档位与教学策略均由系统自动决定。
final class ExplorationLabPage extends StatefulWidget {
  const ExplorationLabPage({super.key});

  @override
  State<ExplorationLabPage> createState() => _ExplorationLabPageState();
}

final class _ExplorationLabPageState extends State<ExplorationLabPage> {
  static const _seedQuestions = [
    '为什么两个负数相乘会得到正数？',
    '二次函数的顶点为什么在这里？',
    '怎样证明 x + 1/x ≥ 2？',
    '一家咖啡店怎么赚钱？',
  ];

  final _contentRepository = MockExplorationContentRepository();
  final _masteryRepository = MockStudentMasteryRepository();
  final _inputController = TextEditingController();
  List<ExplorationScenario> _scenarios = const [];
  bool _isOpening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scenarios = await _contentRepository.loadScenarios();
    if (!mounted) return;
    setState(() => _scenarios = scenarios);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(title: const Text('1.2 对话探索实验室')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  const _MockNotice(),
                  const SizedBox(height: 18),
                  const _TutorOpeningBubble(),
                  const SizedBox(height: 14),
                  const Text(
                    '也可以从一个问题开始',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _seedQuestions
                        .map(
                          (question) => ActionChip(
                            label: Text(question),
                            onPressed: () => setState(() {
                              _inputController.text = question;
                            }),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 18),
                  const _AutomaticStrategyNotice(),
                ],
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('exploration-topic-input'),
                controller: _inputController,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _openQuestion(),
                decoration: const InputDecoration(
                  hintText: '输入一个你真正想弄懂的问题…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              key: const ValueKey('exploration-start-session'),
              tooltip: '开始互动微课',
              onPressed: _isOpening || _scenarios.isEmpty
                  ? null
                  : _openQuestion,
              icon: _isOpening
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQuestion() async {
    final question = _inputController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写下一个想弄懂的问题')));
      return;
    }
    setState(() => _isOpening = true);
    final baseScenario = _resolveScenario(question);
    final scenario = _withOpeningQuestion(baseScenario, question);
    final profiles = await _masteryRepository.availableProfiles(
      scenario.atomId,
    );
    // Mock 阶段模拟画像聚合结果；学生端不暴露掌握档位选择器。
    final mastery = profiles.singleWhere(
      (item) => item.level == StudentMasteryLevel.developing,
    );
    if (!mounted) return;
    setState(() => _isOpening = false);
    final page = scenario.kind == ExplorationScenarioKind.practice
        ? PracticeExplorationPage(scenario: scenario, mastery: mastery)
        : TeachingExplorationPage(scenario: scenario, mastery: mastery);
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  ExplorationScenario _resolveScenario(String question) {
    if (_containsAny(question, const ['不等式', '1/x', '证明'])) {
      return _byId('practice-inequality');
    }
    if (_containsAny(question, const ['咖啡', '赚钱', '商业模式', 'Business'])) {
      return _byId('demo-coffee-business-model');
    }
    if (_containsAny(question, const ['负负', '负数', '相反数'])) {
      return _byId('teaching-negative-multiplication');
    }
    if (_containsAny(question, const ['二次函数', '顶点', '抛物线', '配方'])) {
      return _byId('teaching-quadratic');
    }
    return ExplorationScenario(
      id: 'teaching-free-question',
      title: '围绕你的问题展开',
      kind: ExplorationScenarioKind.teaching,
      atomId: 'free-question',
      openingPrompt: question,
      seedQuestions: [question],
      allowedMaterialIds: const {},
    );
  }

  ExplorationScenario _byId(String id) {
    return _scenarios.singleWhere((item) => item.id == id);
  }

  static ExplorationScenario _withOpeningQuestion(
    ExplorationScenario source,
    String question,
  ) {
    return ExplorationScenario(
      id: source.id,
      title: source.title,
      kind: source.kind,
      atomId: source.atomId,
      openingPrompt: question,
      seedQuestions: source.seedQuestions,
      allowedMaterialIds: source.allowedMaterialIds,
    );
  }

  static bool _containsAny(String value, List<String> signals) {
    return signals.any(value.contains);
  }
}

final class _TutorOpeningBubble extends StatelessWidget {
  const _TutorOpeningBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0E9FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今天想弄懂什么？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text('你只管提出真实问题。我会根据你的回答追问、换例子、保留错误思路，并在结束时请你用自己的话解释。'),
          ],
        ),
      ),
    );
  }
}

final class _AutomaticStrategyNotice extends StatelessWidget {
  const _AutomaticStrategyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3DDEC)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: Color(0xFF6B23FF)),
          SizedBox(width: 10),
          Expanded(child: Text('AI 自动编排约 10 分钟的互动微课；教学方式会根据你的表达变化，无需手动选择模式。')),
        ],
      ),
    );
  }
}

final class _MockNotice extends StatelessWidget {
  const _MockNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text('测试数据 · 学生画像、回答和素材均为 Mock，退出实验室后清空。'),
    );
  }
}
