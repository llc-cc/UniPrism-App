import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adapters/in_memory_exploration_adapters.dart';
import '../adapters/mock_exploration_content_repository.dart';
import '../adapters/mock_exploration_gateway.dart';
import '../core/exploration_controller.dart';
import '../core/exploration_models.dart';
import '../core/exploration_outputs.dart';
import '../core/exploration_tree.dart';
import '../core/teaching_session_controller.dart';
import '../mastery/student_mastery.dart';
import '../materials/exploration_material_card.dart';
import '../materials/mock_whiteboard_launcher.dart';
import '../practice/practice_diagnosis.dart';
import '../practice/practice_exploration_strategy.dart';
import '../teaching/teaching_exploration_strategy.dart';
import '../teaching/teaching_strategy_engine.dart';
import 'exploration_tree_panel.dart';

/// 教学与 public Demo 的对话页，展示回答、素材、提问脚手架和思维树。
final class TeachingExplorationPage extends StatefulWidget {
  const TeachingExplorationPage({
    super.key,
    required this.scenario,
    required this.mastery,
  });

  final ExplorationScenario scenario;
  final StudentMasterySnapshot mastery;

  @override
  State<TeachingExplorationPage> createState() =>
      _TeachingExplorationPageState();
}

final class _TeachingExplorationPageState
    extends State<TeachingExplorationPage> {
  final _contentRepository = MockExplorationContentRepository();
  final _inputController = TextEditingController();
  final _whiteboardLauncher = const MockExplorationWhiteboardLauncher();
  late final InMemoryExplorationTraceRepository _traceRepository;
  late final InMemoryMemoryCandidateSink _memorySink;
  late final TeachingSessionController _controller;
  Map<String, ExplorationMaterial> _materials = const {};
  String? _branchFromNodeId;

  @override
  void initState() {
    super.initState();
    _traceRepository = InMemoryExplorationTraceRepository();
    _memorySink = InMemoryMemoryCandidateSink();
    _controller = TeachingSessionController(
      strategy: TeachingExplorationStrategy(
        gateway: MockExplorationGateway(delay: Duration.zero),
      ),
      traceRepository: _traceRepository,
      memoryCandidateSink: _memorySink,
      nowUtc: () => DateTime.now().toUtc(),
    )..addListener(_refresh);
    _initialize();
  }

  Future<void> _initialize() async {
    final materials = await _contentRepository.loadMaterials(
      widget.scenario.allowedMaterialIds,
    );
    if (mounted) {
      setState(
        () => _materials = {for (final item in materials) item.id: item},
      );
    }
    await _controller.start(
      scenario: widget.scenario,
      mastery: widget.mastery,
      question: widget.scenario.openingPrompt,
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final tree = state.tree;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scenario.title),
        actions: [
          if (tree != null)
            TextButton(onPressed: _saveAndExport, child: const Text('保存并导出')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _SessionMockNotice(),
            ),
            Expanded(
              child: tree == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showTree(tree),
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('查看思维树'),
                        ),
                        _strategyStatus(state),
                        const SizedBox(height: 8),
                        _messageList(tree.nodes),
                        if (state.status == TeachingSessionStatus.loading)
                          const LinearProgressIndicator(),
                        if (_branchFromNodeId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '正在从历史节点创建支线',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            _questionComposer(state.status == TeachingSessionStatus.loading),
          ],
        ),
      ),
    );
  }

  Widget _messageList(List<ExplorationNode> nodes) {
    return Column(
      key: const ValueKey('tutor-message'),
      children: nodes
          .map((node) {
            final isTutor = node.kind == ExplorationNodeKind.tutorResponse;
            return Align(
              alignment: isTutor ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 620),
                decoration: BoxDecoration(
                  color: isTutor
                      ? const Color(0xFFF4F0FF)
                      : const Color(0xFFEAF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(node.text),
                    if (isTutor) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _branchFromNodeId = node.id),
                            child: const Text('从这里继续探索'),
                          ),
                          TextButton(
                            onPressed: () => _convertMemory(node.id),
                            child: const Text('转为记忆候选'),
                          ),
                          TextButton(
                            onPressed: () => _openWhiteboard(node.id),
                            child: const Text('在白板上演示'),
                          ),
                        ],
                      ),
                      for (final id in node.materialIds)
                        if (_materials[id] case final material?)
                          ExplorationMaterialCard(material: material),
                    ],
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _strategyStatus(TeachingSessionState state) {
    final active = state.activeDecision;
    if (active == null) return const SizedBox.shrink();
    final progress = (state.strategyHistory.length / 5)
        .clamp(0.0, 1.0)
        .toDouble();
    return Card(
      key: const ValueKey('adaptive-strategy-status'),
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: const Color(0xFFEFF8F4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.mode.studentActionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('${(progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('查看本轮调整原因（开发）'),
              children: [
                for (final decision in state.strategyHistory)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(decision.mode.studentActionLabel),
                    subtitle: Text(decision.reason),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionComposer(bool disabled) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('问题库'),
                  ),
                  ...widget.scenario.seedQuestions.map(
                    (question) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(question),
                        onPressed: () => _inputController.text = question,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TeachingExplorationStrategy.questionScaffolds
                    .map(
                      (text) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(text),
                          onPressed: () => _inputController.text = text,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('exploration-question-input'),
                    controller: _inputController,
                    decoration: const InputDecoration(hintText: '继续提问……'),
                  ),
                ),
                IconButton.filled(
                  key: const ValueKey('exploration-send'),
                  onPressed: disabled ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    try {
      await _controller.submitQuestion(
        text,
        branchFromNodeId: _branchFromNodeId,
      );
      _inputController.clear();
      if (mounted) setState(() => _branchFromNodeId = null);
    } on ExplorationInputRejectedException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _convertMemory(String nodeId) async {
    await _controller.convertNodeToMemory(nodeId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已生成记忆候选（当前 ${_memorySink.items.length} 项）')),
    );
  }

  Future<void> _openWhiteboard(String nodeId) async {
    final result = await _whiteboardLauncher.open(
      context,
      nodeId: nodeId,
      atomId: widget.scenario.atomId,
      initialState: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
    );
    if (!mounted || !result.confirmed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('白板状态已带回当前探索节点（Mock）')));
  }

  void _showTree(ExplorationTree tree) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ExplorationTreePanel(tree: tree),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndExport() async {
    final reflectionController = TextEditingController();
    final reflection = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用自己的话复述'),
        content: TextField(controller: reflectionController, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reflectionController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    reflectionController.dispose();
    if (reflection == null || reflection.trim().isEmpty) return;
    final record = await _controller.saveTrace(reflection: reflection);
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(ExplorationTraceExporter.toVersionedJson(record));
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已保存并复制 JSON'),
        content: SingleChildScrollView(child: SelectableText(json)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 练习端口页面，显式展示错误验证、诊断确认、回退和第二解法分支。
final class PracticeExplorationPage extends StatefulWidget {
  const PracticeExplorationPage({
    super.key,
    required this.scenario,
    required this.mastery,
  });

  final ExplorationScenario scenario;
  final StudentMasterySnapshot mastery;

  @override
  State<PracticeExplorationPage> createState() =>
      _PracticeExplorationPageState();
}

final class _PracticeExplorationPageState
    extends State<PracticeExplorationPage> {
  late final InMemoryMasteryEvidenceSink _evidenceSink;
  late final ExplorationController _controller;
  final _reflectionController = TextEditingController();
  DifficultyDiagnosisKind? _selectedDiagnosis;

  @override
  void initState() {
    super.initState();
    _evidenceSink = InMemoryMasteryEvidenceSink();
    _controller = ExplorationController(
      practiceStrategy: const PracticeExplorationStrategy(),
      masteryEvidenceSink: _evidenceSink,
      nowUtc: () => DateTime.now().toUtc(),
    )..addListener(_refresh);
    _controller.startPractice(
      scenario: widget.scenario,
      mastery: widget.mastery,
    );
  }

  void _refresh() {
    if (!mounted) return;
    final pending = _controller.state.pendingDiagnosis;
    setState(() {
      if (pending != null) _selectedDiagnosis ??= pending.suggestedKind;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _reflectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final tree = state.tree!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.scenario.title)),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _SessionMockNotice(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: ExplorationTreePanel(tree: tree),
              ),
            ),
            _practiceControls(state),
          ],
        ),
      ),
    );
  }

  Widget _practiceControls(ExplorationControllerState state) {
    final active = state.tree!.activeLeaf!;
    if (state.pendingDiagnosis case final pending?) {
      return _controlPanel(
        children: [
          Text('候选诊断：${_diagnosisLabel(pending.suggestedKind)}'),
          Text(pending.rationale),
          DropdownButton<DifficultyDiagnosisKind>(
            value: _selectedDiagnosis ?? pending.suggestedKind,
            isExpanded: true,
            items: DifficultyDiagnosisKind.values
                .map(
                  (kind) => DropdownMenuItem(
                    value: kind,
                    child: Text(_diagnosisLabel(kind)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _selectedDiagnosis = value),
          ),
          FilledButton(
            key: const ValueKey('practice-confirm-diagnosis'),
            onPressed: () => _controller.confirmDiagnosis(
              _selectedDiagnosis ?? pending.suggestedKind,
            ),
            child: const Text('确认诊断'),
          ),
        ],
      );
    }
    if (active.kind == ExplorationNodeKind.studentQuestion ||
        active.kind == ExplorationNodeKind.backtrack) {
      return _controlPanel(
        children: [
          const Text('选择一个思路开始验证：'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('practice-try-wrong'),
                onPressed: () => _controller.submitHypothesis('直接使用柯西不等式'),
                child: const Text('尝试柯西不等式'),
              ),
              FilledButton.tonal(
                key: const ValueKey('practice-try-correct'),
                onPressed: () =>
                    _controller.submitHypothesis('令 a=x、b=1/x，使用基本不等式'),
                child: const Text('使用基本不等式'),
              ),
            ],
          ),
        ],
      );
    }
    if (active.kind == ExplorationNodeKind.studentHypothesis) {
      return _controlPanel(
        children: [
          FilledButton(
            key: const ValueKey('practice-validate'),
            onPressed: _controller.validateActiveStep,
            child: const Text('检查成立条件'),
          ),
        ],
      );
    }
    if (active.kind == ExplorationNodeKind.diagnosis) {
      final rootId = state.tree!.nodes.first.id;
      return _controlPanel(
        children: [
          FilledButton.tonal(
            key: const ValueKey('practice-backtrack'),
            onPressed: () {
              _selectedDiagnosis = null;
              _controller.backtrack(targetNodeId: rootId);
            },
            child: const Text('回退到题目，换一种方法'),
          ),
        ],
      );
    }
    if (active.kind == ExplorationNodeKind.reasoningStep &&
        active.status == ExplorationNodeStatus.validated) {
      return _controlPanel(
        children: [
          Text('步骤验证通过 · 已记录 ${_evidenceSink.items.length} 条掌握证据'),
          TextField(
            key: const ValueKey('practice-reflection'),
            controller: _reflectionController,
            decoration: const InputDecoration(hintText: '用自己的话说说：这一步为什么成立？'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('practice-complete'),
            onPressed: _completePractice,
            child: const Text('完成复述'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _controlPanel({required List<Widget> children}) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  void _completePractice() {
    final reflection = _reflectionController.text.trim();
    if (reflection.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先用自己的话复述关键思路')));
      return;
    }
    // 只有学生主动复述后才完成节点，避免把“看过答案”误记为理解。
    _controller.saveReflection(reflection);
  }

  static String _diagnosisLabel(DifficultyDiagnosisKind kind) {
    return switch (kind) {
      DifficultyDiagnosisKind.conceptGap => '概念不熟',
      DifficultyDiagnosisKind.conditionGap => '成立条件不清楚',
      DifficultyDiagnosisKind.methodSelection => '方法不会选择',
      DifficultyDiagnosisKind.reasoningBreak => '推理步骤断裂',
      DifficultyDiagnosisKind.calculationGap => '计算能力不过关',
      DifficultyDiagnosisKind.promptMisread => '题意理解偏差',
      DifficultyDiagnosisKind.uncertain => '暂时不确定',
    };
  }
}

final class _SessionMockNotice extends StatelessWidget {
  const _SessionMockNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('Mock 演示 · 当前结果不写入正式学生档案'),
    );
  }
}
