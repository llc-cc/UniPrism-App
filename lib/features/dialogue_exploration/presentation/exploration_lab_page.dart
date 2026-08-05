import 'package:flutter/material.dart';

import '../adapters/mock_exploration_content_repository.dart';
import '../core/exploration_models.dart';
import '../mastery/mock_student_mastery_repository.dart';
import '../mastery/student_mastery.dart';
import 'exploration_session_page.dart';

/// 1.2 独立实验室入口；正式首页接入前可单独运行和验收三个 Mock 场景。
final class ExplorationLabPage extends StatefulWidget {
  const ExplorationLabPage({super.key});

  @override
  State<ExplorationLabPage> createState() => _ExplorationLabPageState();
}

final class _ExplorationLabPageState extends State<ExplorationLabPage> {
  final _contentRepository = MockExplorationContentRepository();
  final _masteryRepository = MockStudentMasteryRepository();
  List<ExplorationScenario> _scenarios = const [];
  StudentMasteryLevel _selectedLevel = StudentMasteryLevel.developing;

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(title: const Text('1.2 对话探索实验室')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _MockNotice(),
          const SizedBox(height: 16),
          const Text('选择学生掌握程度', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _profileChip(StudentMasteryLevel.weak, '基础薄弱'),
              _profileChip(StudentMasteryLevel.developing, '正在形成'),
              _profileChip(StudentMasteryLevel.strong, '掌握较好'),
            ],
          ),
          const SizedBox(height: 20),
          const Text('选择复用场景', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_scenarios.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            ..._scenarios.map(_scenarioCard),
        ],
      ),
    );
  }

  Widget _profileChip(StudentMasteryLevel level, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedLevel == level,
      onSelected: (_) => setState(() => _selectedLevel = level),
    );
  }

  Widget _scenarioCard(ExplorationScenario scenario) {
    final description = switch (scenario.kind) {
      ExplorationScenarioKind.teaching => '教学端口 · 根据掌握程度调整解释和素材',
      ExplorationScenarioKind.practice => '练习端口 · 错误思路、诊断确认与回退',
      ExplorationScenarioKind.publicDemo => '公开 Demo · 三层发散与单位经济模型',
    };
    return Card(
      key: ValueKey('scenario-${scenario.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(_scenarioIcon(scenario.kind), color: const Color(0xFF6B23FF)),
        title: Text(scenario.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openScenario(scenario),
      ),
    );
  }

  Future<void> _openScenario(ExplorationScenario scenario) async {
    final profiles = await _masteryRepository.availableProfiles(scenario.atomId);
    final mastery = profiles.singleWhere((item) => item.level == _selectedLevel);
    if (!mounted) return;
    final page = scenario.kind == ExplorationScenarioKind.practice
        ? PracticeExplorationPage(scenario: scenario, mastery: mastery)
        : TeachingExplorationPage(scenario: scenario, mastery: mastery);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  static IconData _scenarioIcon(ExplorationScenarioKind kind) {
    return switch (kind) {
      ExplorationScenarioKind.teaching => Icons.school_outlined,
      ExplorationScenarioKind.practice => Icons.route_outlined,
      ExplorationScenarioKind.publicDemo => Icons.storefront_outlined,
    };
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
      child: const Text('测试数据 · 回答、掌握程度和素材均为 Mock，退出实验室后清空。'),
    );
  }
}
