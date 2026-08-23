import 'dart:math';

import 'package:flutter/material.dart';

const _ink = Color(0xFF101828);
const _violet = Color(0xFF7047EB);

/// 古典概型实验：先亲手构造事件，再用随机模拟观察频率向理论概率靠近。
final class ProbabilitySampleSpaceGame extends StatefulWidget {
  const ProbabilitySampleSpaceGame({super.key});

  @override
  State<ProbabilitySampleSpaceGame> createState() =>
      _ProbabilitySampleSpaceGameState();
}

final class _ProbabilitySampleSpaceGameState
    extends State<ProbabilitySampleSpaceGame> {
  static const _people = ['A', 'B', 'a', 'b', 'c'];
  late final List<_PairOutcome> _outcomes = [
    for (var i = 0; i < _people.length; i++)
      for (var j = i + 1; j < _people.length; j++)
        _PairOutcome(_people[i], _people[j]),
  ];

  final Set<int> _selected = {};
  var _validated = false;
  var _correct = false;
  var _simulationRuns = 0;
  var _simulationHits = 0;

  bool _isFavorable(_PairOutcome outcome) =>
      outcome.first.toLowerCase() == outcome.first &&
      outcome.second.toLowerCase() == outcome.second;

  void _toggle(int index) {
    setState(() {
      _validated = false;
      if (!_selected.add(index)) _selected.remove(index);
    });
  }

  void _validate() {
    final expected = <int>{
      for (var i = 0; i < _outcomes.length; i++)
        if (_isFavorable(_outcomes[i])) i,
    };
    setState(() {
      _validated = true;
      _correct =
          _selected.length == expected.length &&
          _selected.containsAll(expected);
    });
  }

  void _simulate(int runs) {
    final random = Random(20260820 + runs + _simulationRuns);
    var hits = 0;
    for (var i = 0; i < runs; i++) {
      if (_isFavorable(_outcomes[random.nextInt(_outcomes.length)])) hits++;
    }
    setState(() {
      _simulationRuns += runs;
      _simulationHits += hits;
    });
  }

  @override
  Widget build(BuildContext context) {
    final empirical = _simulationRuns == 0
        ? 0.0
        : _simulationHits / _simulationRuns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE3EC)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SAMPLE SPACE / 01',
                style: TextStyle(
                  color: _violet,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '2 名男生 A、B 与 3 名女生 a、b、c 中任选 2 人',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                '任务：在完整样本空间中标记“恰好选中 2 名女生”的基本事件，再启动蒙特卡洛模拟验证理论概率。',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF151427),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.schema_outlined,
                    color: Color(0xFFB7A7FF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'EVENT MATRIX',
                    style: TextStyle(
                      color: Color(0xFFB9B6D2),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已标记 ${_selected.length} / ${_outcomes.length}',
                    style: const TextStyle(
                      color: Color(0xFF8E8AA8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 560 ? 2 : 5;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 1.65,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _outcomes.length,
                    itemBuilder: (context, index) {
                      final outcome = _outcomes[index];
                      final selected = _selected.contains(index);
                      final shouldSelect = _isFavorable(outcome);
                      final hasError = _validated && selected != shouldSelect;
                      return InkWell(
                        key: ValueKey('probability-outcome-$index'),
                        onTap: () => _toggle(index),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: hasError
                                ? const Color(0xFF5B2630)
                                : selected
                                ? const Color(0xFF5941B5)
                                : const Color(0xFF23223A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: hasError
                                  ? const Color(0xFFFF7D8B)
                                  : selected
                                  ? const Color(0xFFAD99FF)
                                  : const Color(0xFF3B3956),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                outcome.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                selected ? '事件 A' : '基本事件',
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFFE1DAFF)
                                      : const Color(0xFF85819F),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final validator = _ValidationConsole(
              validated: _validated,
              correct: _correct,
              selectedCount: _selected.length,
              onValidate: _validate,
            );
            final simulator = _SimulationConsole(
              enabled: _correct,
              runs: _simulationRuns,
              hits: _simulationHits,
              empirical: empirical,
              onSimulate: _simulate,
            );
            return compact
                ? Column(
                    children: [
                      validator,
                      const SizedBox(height: 12),
                      simulator,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: validator),
                      const SizedBox(width: 12),
                      Expanded(child: simulator),
                    ],
                  );
          },
        ),
      ],
    );
  }
}

final class _ValidationConsole extends StatelessWidget {
  const _ValidationConsole({
    required this.validated,
    required this.correct,
    required this.selectedCount,
    required this.onValidate,
  });

  final bool validated;
  final bool correct;
  final int selectedCount;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            correct ? '事件构造完成' : '事件判定台',
            style: TextStyle(
              color: correct ? const Color(0xFF067647) : _ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            correct
                ? '事件 A 包含 3 个基本事件，样本空间 Ω 包含 10 个等可能结果，因此 P(A)=3/10。'
                : validated
                ? '矩阵中仍有错误标记。关注“两个成员是否都是女生”，不要只看是否含女生。'
                : '点击矩阵单元，将满足条件的基本事件加入事件 A。当前已选择 $selectedCount 个。',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('validate-probability-event'),
            onPressed: onValidate,
            icon: const Icon(Icons.rule_rounded),
            label: const Text('验证事件集合'),
            style: FilledButton.styleFrom(
              backgroundColor: _violet,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SimulationConsole extends StatelessWidget {
  const _SimulationConsole({
    required this.enabled,
    required this.runs,
    required this.hits,
    required this.empirical,
    required this.onSimulate,
  });

  final bool enabled;
  final int runs;
  final int hits;
  final double empirical;
  final ValueChanged<int> onSimulate;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '随机模拟器',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            !enabled
                ? '正确构造事件 A 后解锁模拟。'
                : runs == 0
                ? '理论值 0.300。启动重复抽样，观察频率波动。'
                : '命中 $hits / $runs，实验频率 ${empirical.toStringAsFixed(3)}，理论概率 0.300。',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: runs == 0 ? 0 : empirical,
            minHeight: 8,
            borderRadius: BorderRadius.circular(9),
            backgroundColor: const Color(0xFFEDEAF8),
            color: _violet,
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('simulate-probability-100'),
                  onPressed: enabled ? () => onSimulate(100) : null,
                  child: const Text('+100 次'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: enabled ? () => onSimulate(1000) : null,
                  child: const Text('+1000 次'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDE3EC)),
      ),
      child: child,
    );
  }
}

final class _PairOutcome {
  const _PairOutcome(this.first, this.second);

  final String first;
  final String second;

  String get label => '($first, $second)';
}
