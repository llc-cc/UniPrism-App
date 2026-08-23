import 'package:flutter/material.dart';

const _ink = Color(0xFF101828);
const _amber = Color(0xFFB65C00);

/// 等差数列求和公式实验：通过倒序配对、恒等式组装和迁移题形成公式。
final class FormulaDerivationGame extends StatefulWidget {
  const FormulaDerivationGame({super.key});

  @override
  State<FormulaDerivationGame> createState() => _FormulaDerivationGameState();
}

final class _FormulaDerivationGameState extends State<FormulaDerivationGame> {
  static const _sequence = [3, 5, 7, 9, 11, 13];
  static const _formulaCandidates = [
    'n ÷ 2',
    '(a₁ + aₙ)',
    'n',
    '(a₁ − aₙ)',
    'd',
  ];

  final _transferController = TextEditingController();
  final List<String> _formulaTokens = [];
  var _stage = 0;
  String? _feedback;
  bool? _transferCorrect;

  @override
  void dispose() {
    _transferController.dispose();
    super.dispose();
  }

  void _reverseSequence() {
    setState(() {
      _stage = 1;
      _feedback = '倒序后，每一列都得到相同的和 16。现在把这个规律写成一般形式。';
    });
  }

  void _selectFormulaToken(String token) {
    if (_stage != 1 || _formulaTokens.length >= 2) return;
    setState(() {
      _formulaTokens.add(token);
      _feedback = null;
    });
  }

  void _removeFormulaToken(int index) {
    if (_stage != 1) return;
    setState(() {
      _formulaTokens.removeAt(index);
      _feedback = null;
    });
  }

  void _validateIdentity() {
    final correct =
        _formulaTokens.length == 2 &&
        _formulaTokens[0] == 'n' &&
        _formulaTokens[1] == '(a₁ + aₙ)';
    setState(() {
      if (correct) {
        _stage = 2;
        _feedback = '恒等式成立。下一步要在保持等式成立的前提下把 Sₙ 单独留下。';
      } else {
        _feedback = '当前右侧不能表示“n 个相同的首末项之和”。检查因子及排列顺序。';
      }
    });
  }

  void _applyOperation(String operation) {
    if (_stage != 2) return;
    setState(() {
      if (operation == '两边同时除以 2') {
        _stage = 3;
        _feedback = '公式推导完成。请用它解决资料中的迁移题。';
      } else {
        _feedback = '该变形不能把 2Sₙ 化为 Sₙ，或没有保持等式两边同步变化。';
      }
    });
  }

  void _validateTransfer() {
    final answer = int.tryParse(_transferController.text.trim());
    setState(() {
      _transferCorrect = answer == 54;
      _feedback = answer == 54
          ? '迁移通过：S₉=9×(2+10)÷2=54。你完成了从结构观察到公式应用的完整链路。'
          : '结果还不正确。先确认 n=9、首项为2、末项为10，再代入刚推导出的公式。';
    });
  }

  void _reset() {
    setState(() {
      _stage = 0;
      _formulaTokens.clear();
      _transferController.clear();
      _feedback = null;
      _transferCorrect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormulaMissionHeader(stage: _stage),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF211A13),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x221D160F),
                blurRadius: 26,
                offset: Offset(0, 13),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.functions_rounded,
                    color: Color(0xFFFFBD73),
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'FORMULA DERIVATION FIELD',
                    style: TextStyle(
                      color: Color(0xFFD8C2A9),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重新推导'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD8C2A9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PairingBoard(sequence: _sequence, reversed: _stage >= 1),
              const SizedBox(height: 16),
              if (_stage == 0)
                FilledButton.icon(
                  key: const ValueKey('reverse-sequence'),
                  onPressed: _reverseSequence,
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('复制 S₆ 并执行倒序排列'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE77B19),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )
              else
                const _PairingEvidence(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final builder = _IdentityBuilder(
              enabled: _stage == 1,
              completed: _stage >= 2,
              tokens: _formulaTokens,
              candidates: _formulaCandidates,
              onTokenSelected: _selectFormulaToken,
              onTokenRemoved: _removeFormulaToken,
              onValidate: _validateIdentity,
            );
            final transform = _FormulaTransformPanel(
              stage: _stage,
              controller: _transferController,
              transferCorrect: _transferCorrect,
              onOperation: _applyOperation,
              onValidateTransfer: _validateTransfer,
            );
            return compact
                ? Column(
                    children: [builder, const SizedBox(height: 12), transform],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: builder),
                      const SizedBox(width: 12),
                      Expanded(child: transform),
                    ],
                  );
          },
        ),
        if (_feedback != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('formula-feedback'),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _transferCorrect == true
                  ? const Color(0xFFECFDF3)
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _transferCorrect == true
                    ? const Color(0xFFABEFC6)
                    : const Color(0xFFF9DBAF),
              ),
            ),
            child: Text(
              _feedback!,
              style: TextStyle(
                color: _transferCorrect == true
                    ? const Color(0xFF067647)
                    : const Color(0xFF934B00),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

final class _FormulaMissionHeader extends StatelessWidget {
  const _FormulaMissionHeader({required this.stage});

  final int stage;

  @override
  Widget build(BuildContext context) {
    const labels = ['观察结构', '组装恒等式', '等式变形', '迁移应用'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE3EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var index = 0; index < labels.length; index++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: index <= stage
                        ? const Color(0xFFFFE8D2)
                        : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${index + 1} ${labels[index]}',
                    style: TextStyle(
                      color: index <= stage ? _amber : const Color(0xFF98A2B3),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '不要背结论：用倒序相加法推导等差数列前 n 项和',
            style: TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '从 S₆=3+5+7+9+11+13 出发，找出配对不变量，再将具体规律推广为一般公式。',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

final class _PairingBoard extends StatelessWidget {
  const _PairingBoard({required this.sequence, required this.reversed});

  final List<int> sequence;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final reverseValues = sequence.reversed.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EquationPrefix(label: 'S₆'),
        const SizedBox(height: 7),
        Row(
          children: [
            for (final value in sequence)
              Expanded(child: _SequenceCell(value: value)),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          opacity: reversed ? 1 : .18,
          duration: const Duration(milliseconds: 300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EquationPrefix(label: 'S₆（倒序）'),
              const SizedBox(height: 7),
              Row(
                children: [
                  for (final value in reverseValues)
                    Expanded(
                      child: _SequenceCell(
                        value: value,
                        secondary: true,
                        showPairSum: reversed,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _EquationPrefix extends StatelessWidget {
  const _EquationPrefix({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFFD8C2A9),
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

final class _SequenceCell extends StatelessWidget {
  const _SequenceCell({
    required this.value,
    this.secondary = false,
    this.showPairSum = false,
  });

  final int value;
  final bool secondary;
  final bool showPairSum;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 55,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: secondary
                  ? const Color(0xFF54361F)
                  : const Color(0xFF3A2B20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: secondary
                    ? const Color(0xFFCE7A34)
                    : const Color(0xFF6B4B34),
              ),
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            height: 21,
            child: showPairSum
                ? const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      '= 16',
                      style: TextStyle(
                        color: Color(0xFFFFBD73),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

final class _PairingEvidence extends StatelessWidget {
  const _PairingEvidence();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF30251C),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF6B4B34)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFFFBD73)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '3+13 = 5+11 = 7+9 = 16；两行相加得到 6 个 16，所以 2S₆=6×16。',
              style: TextStyle(
                color: Color(0xFFE8D8C8),
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _IdentityBuilder extends StatelessWidget {
  const _IdentityBuilder({
    required this.enabled,
    required this.completed,
    required this.tokens,
    required this.candidates,
    required this.onTokenSelected,
    required this.onTokenRemoved,
    required this.onValidate,
  });

  final bool enabled;
  final bool completed;
  final List<String> tokens;
  final List<String> candidates;
  final ValueChanged<String> onTokenSelected;
  final ValueChanged<int> onTokenRemoved;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '一般化恒等式',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            '把“6 个首末项之和”推广到前 n 项，按顺序选择两个因子。',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 13),
          Container(
            key: const ValueKey('formula-identity-lane'),
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDE3EC)),
            ),
            child: Row(
              children: [
                const Text(
                  '2Sₙ =',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                for (final (index, token) in tokens.indexed) ...[
                  InputChip(
                    label: Text(token),
                    onDeleted: enabled ? () => onTokenRemoved(index) : null,
                    backgroundColor: const Color(0xFFFFE8D2),
                    side: const BorderSide(color: Color(0xFFF7B27A)),
                  ),
                  const SizedBox(width: 6),
                ],
                for (var index = tokens.length; index < 2; index++) ...[
                  Container(
                    width: 72,
                    height: 34,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFBFC7D4),
                        style: BorderStyle.solid,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final token in candidates)
                ActionChip(
                  key: ValueKey('formula-token-$token'),
                  onPressed: enabled && !tokens.contains(token)
                      ? () => onTokenSelected(token)
                      : null,
                  label: Text(token),
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  backgroundColor: Colors.white,
                ),
            ],
          ),
          const SizedBox(height: 13),
          FilledButton.icon(
            key: const ValueKey('validate-formula-identity'),
            onPressed: enabled && tokens.length == 2 ? onValidate : null,
            icon: Icon(completed ? Icons.check_rounded : Icons.rule_rounded),
            label: Text(completed ? '恒等式已建立' : '验证恒等式'),
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ],
      ),
    );
  }
}

final class _FormulaTransformPanel extends StatelessWidget {
  const _FormulaTransformPanel({
    required this.stage,
    required this.controller,
    required this.transferCorrect,
    required this.onOperation,
    required this.onValidateTransfer,
  });

  final int stage;
  final TextEditingController controller;
  final bool? transferCorrect;
  final ValueChanged<String> onOperation;
  final VoidCallback onValidateTransfer;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stage >= 3 ? '迁移题' : '等式变形',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (stage < 2)
            const Text(
              '先在左侧建立 2Sₙ 的一般化恒等式，随后才能进行等式变形。',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 11,
                height: 1.5,
              ),
            )
          else if (stage == 2) ...[
            const Text(
              '2Sₙ = n(a₁+aₙ)。选择合法操作，使左侧只剩 Sₙ。',
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            for (final operation in ['两边同时除以 2', '左边除以 2', '两边同时减去 2'])
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: OutlinedButton(
                  key: ValueKey('formula-operation-$operation'),
                  onPressed: () => onOperation(operation),
                  child: Text(operation),
                ),
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Sₙ = n(a₁+aₙ) / 2',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _amber,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 11),
            const Text(
              '资料题：a₁=2，a₉=10，求 S₉。',
              style: TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            TextField(
              key: const ValueKey('formula-transfer-answer'),
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '输入 S₉',
                errorText: transferCorrect == false ? '结果不符合公式' : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 9),
            FilledButton(
              key: const ValueKey('validate-formula-transfer'),
              onPressed: onValidateTransfer,
              style: FilledButton.styleFrom(backgroundColor: _amber),
              child: const Text('验证迁移结果'),
            ),
          ],
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
