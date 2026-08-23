import 'package:flutter/material.dart';

import 'math_lab/derivative_tangent_game.dart';
import 'math_lab/formula_derivation_game.dart';
import 'math_lab/math_lab_content_catalog.dart';
import 'math_lab/probability_sample_space_game.dart';
import 'math_lab/set_modeling_game.dart';

const _ink = Color(0xFF101828);
const _surface = Color(0xFFF2F4F8);

/// 功能区 A 的多类型数学实验中心；只读取接入内容，不写入正式练习记录。
final class MathInteractionLabPage extends StatefulWidget {
  const MathInteractionLabPage({super.key});

  @override
  State<MathInteractionLabPage> createState() => _MathInteractionLabPageState();
}

final class _MathInteractionLabPageState extends State<MathInteractionLabPage> {
  var _selectedKind = MathLabKind.formulaDerivation;

  MathLabChallenge get _selectedChallenge => MathLabContentCatalog.challenges
      .firstWhere((challenge) => challenge.kind == _selectedKind);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 4,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '数学交互实验区',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              '功能区 A · 北师大版高中数学实验中心',
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 18),
            child: Chip(
              avatar: Icon(Icons.science_outlined, size: 16),
              label: Text('INTERACTION LAB'),
              side: BorderSide(color: Color(0xFFDDE3EC)),
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: _ink,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          if (compact) {
            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _CompactSourceSummary(
                  selectedKind: _selectedKind,
                  onSelected: _select,
                ),
                const SizedBox(height: 14),
                _ExperimentContent(challenge: _selectedChallenge),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 318,
                child: _ExperimentSidebar(
                  selectedKind: _selectedKind,
                  onSelected: _select,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _ExperimentContent(challenge: _selectedChallenge),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _select(MathLabKind kind) {
    setState(() => _selectedKind = kind);
  }
}

final class _ExperimentSidebar extends StatelessWidget {
  const _ExperimentSidebar({
    required this.selectedKind,
    required this.onSelected,
  });

  final MathLabKind selectedKind;
  final ValueChanged<MathLabKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '本地数学资料库',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              '北师大版高中数学资料包',
              style: TextStyle(color: Color(0xFF667085), fontSize: 11),
            ),
            const SizedBox(height: 14),
            const _SourceMetrics(),
            const SizedBox(height: 20),
            const Text(
              '已接入实验',
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 9),
            for (final challenge in MathLabContentCatalog.challenges) ...[
              _ExperimentCard(
                challenge: challenge,
                selected: challenge.kind == selectedKind,
                onTap: () => onSelected(challenge.kind),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: const Text(
                '首批不是同一套换皮题：\n图像直接操控 · 事件矩阵 · 约束建模',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 10,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CompactSourceSummary extends StatelessWidget {
  const _CompactSourceSummary({
    required this.selectedKind,
    required this.onSelected,
  });

  final MathLabKind selectedKind;
  final ValueChanged<MathLabKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDE3EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SourceMetrics(),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final challenge in MathLabContentCatalog.challenges) ...[
                  _ExperimentCard(
                    challenge: challenge,
                    selected: challenge.kind == selectedKind,
                    onTap: () => onSelected(challenge.kind),
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _SourceMetrics extends StatelessWidget {
  const _SourceMetrics();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('math-source-summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5E0FF)),
      ),
      child: const Row(
        children: [
          _SourceMetric(value: '2,539', label: '资料文件'),
          _MetricDivider(),
          _SourceMetric(value: '4', label: '教材分册'),
          _MetricDivider(),
          _SourceMetric(value: '15', label: '题型方向'),
        ],
      ),
    );
  }
}

final class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFCBD7F5),
    );
  }
}

final class _SourceMetric extends StatelessWidget {
  const _SourceMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF315CF5),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF667085), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

final class _ExperimentCard extends StatelessWidget {
  const _ExperimentCard({
    required this.challenge,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final MathLabChallenge challenge;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(challenge.kind);
    return SizedBox(
      width: compact ? 235 : null,
      child: InkWell(
        key: ValueKey('math-lab-${challenge.kind.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? visual.color.withValues(alpha: .1)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? visual.color.withValues(alpha: .55)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      challenge.section,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.play_arrow_rounded, color: visual.color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ExperimentContent extends StatelessWidget {
  const _ExperimentContent({required this.challenge});

  final MathLabChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(challenge.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFDDE3EC)),
          ),
          child: Row(
            children: [
              Icon(visual.icon, color: visual.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${challenge.volume} · ${challenge.section}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '内容依据：${challenge.sourceFile.split(r'\').last}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  challenge.subtitle,
                  style: TextStyle(
                    color: visual.color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        KeyedSubtree(
          key: ValueKey('math-game-${challenge.kind.name}'),
          child: switch (challenge.kind) {
            MathLabKind.formulaDerivation => const FormulaDerivationGame(),
            MathLabKind.derivative => const DerivativeTangentGame(),
            MathLabKind.probability => const ProbabilitySampleSpaceGame(),
            MathLabKind.setModeling => const SetModelingGame(),
          },
        ),
      ],
    );
  }
}

({IconData icon, Color color}) _visualFor(MathLabKind kind) => switch (kind) {
  MathLabKind.formulaDerivation => (
    icon: Icons.functions_rounded,
    color: const Color(0xFFB65C00),
  ),
  MathLabKind.derivative => (
    icon: Icons.show_chart_rounded,
    color: const Color(0xFF315CF5),
  ),
  MathLabKind.probability => (
    icon: Icons.casino_outlined,
    color: const Color(0xFF7047EB),
  ),
  MathLabKind.setModeling => (
    icon: Icons.hub_outlined,
    color: const Color(0xFF0788A5),
  ),
};
