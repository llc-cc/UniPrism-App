import 'dart:math' as math;

import 'package:flutter/material.dart';

const _ink = Color(0xFF101828);
const _cyan = Color(0xFF0788A5);

/// 集合应用题实验：先解约束参数，再用区域编码完成集合运算。
final class SetModelingGame extends StatefulWidget {
  const SetModelingGame({super.key});

  @override
  State<SetModelingGame> createState() => _SetModelingGameState();
}

final class _SetModelingGameState extends State<SetModelingGame> {
  var _intersection = 0;
  var _attempts = 0;
  var _locked = false;
  final Set<_VennRegion> _selectedRegions = {};
  bool? _regionCorrect;

  int get _onlyRunning => 20 - _intersection;
  int get _onlyJumping => 11 - _intersection;
  int get _modeledTotal => _onlyRunning + _intersection + _onlyJumping + 4;

  void _updateIntersection(double localDx, double width) {
    if (_locked) return;
    final ratio = (localDx / math.max(width, 1)).clamp(0.0, 1.0);
    setState(() => _intersection = (ratio * 11).round());
  }

  void _validateModel() {
    setState(() {
      _attempts += 1;
      _locked = _modeledTotal == 30;
    });
  }

  void _toggleRegion(_VennRegion region) {
    if (!_locked) return;
    setState(() {
      _regionCorrect = null;
      if (!_selectedRegions.add(region)) _selectedRegions.remove(region);
    });
  }

  void _validateRegions() {
    const expected = {
      _VennRegion.onlyRunning,
      _VennRegion.intersection,
      _VennRegion.onlyJumping,
    };
    setState(() {
      _regionCorrect =
          _selectedRegions.length == expected.length &&
          _selectedRegions.containsAll(expected);
    });
  }

  void _reset() {
    setState(() {
      _intersection = 0;
      _attempts = 0;
      _locked = false;
      _selectedRegions.clear();
      _regionCorrect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                'CONSTRAINT MODEL / 01',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '30 人班级的运动会报名模型',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                '赛跑 20 人，跳跃 11 人，两项都未报名 4 人。拖动交集参数，让四个区域同时满足总人数约束。',
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0D222B),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'DYNAMIC VENN FIELD',
                    style: TextStyle(
                      color: Color(0xFF9BC2C9),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重置'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB6D3D8),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 330,
                child: CustomPaint(
                  painter: _VennPainter(
                    onlyRunning: _onlyRunning,
                    intersection: _intersection,
                    onlyJumping: _onlyJumping,
                    neither: 4,
                    selectedRegions: Set.unmodifiable(_selectedRegions),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!_locked)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      key: const ValueKey('intersection-control'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _updateIntersection(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      onPanUpdate: (details) => _updateIntersection(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      child: SizedBox(
                        height: 54,
                        child: CustomPaint(
                          painter: _ConstraintTrackPainter(
                            value: _intersection,
                            max: 11,
                          ),
                        ),
                      ),
                    );
                  },
                )
              else
                _RegionSelector(
                  selected: _selectedRegions,
                  onToggle: _toggleRegion,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final constraintsPanel = _ConstraintStatusPanel(
              intersection: _intersection,
              modeledTotal: _modeledTotal,
              attempts: _attempts,
            );
            final actionPanel = _SetActionPanel(
              locked: _locked,
              intersection: _intersection,
              regionCorrect: _regionCorrect,
              selectedValue: _selectedRegions.fold<int>(0, (sum, region) {
                return sum +
                    switch (region) {
                      _VennRegion.onlyRunning => _onlyRunning,
                      _VennRegion.intersection => _intersection,
                      _VennRegion.onlyJumping => _onlyJumping,
                      _VennRegion.neither => 4,
                    };
              }),
              onValidateModel: _validateModel,
              onValidateRegions: _validateRegions,
            );
            return compact
                ? Column(
                    children: [
                      constraintsPanel,
                      const SizedBox(height: 12),
                      actionPanel,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: constraintsPanel),
                      const SizedBox(width: 12),
                      Expanded(child: actionPanel),
                    ],
                  );
          },
        ),
      ],
    );
  }
}

final class _ConstraintStatusPanel extends StatelessWidget {
  const _ConstraintStatusPanel({
    required this.intersection,
    required this.modeledTotal,
    required this.attempts,
  });

  final int intersection;
  final int modeledTotal;
  final int attempts;

  @override
  Widget build(BuildContext context) {
    final totalMatches = modeledTotal == 30;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '约束监视器',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 13),
          _ConstraintLine(label: '|A| = 20', matched: true),
          _ConstraintLine(label: '|B| = 11', matched: true),
          _ConstraintLine(label: '两项都未参加 = 4', matched: true),
          _ConstraintLine(
            label: '区域总和 $modeledTotal = 全班 30',
            matched: totalMatches,
          ),
          const SizedBox(height: 8),
          Text(
            '当前交集参数 x=$intersection · 验证 $attempts 次',
            style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

final class _SetActionPanel extends StatelessWidget {
  const _SetActionPanel({
    required this.locked,
    required this.intersection,
    required this.regionCorrect,
    required this.selectedValue,
    required this.onValidateModel,
    required this.onValidateRegions,
  });

  final bool locked;
  final int intersection;
  final bool? regionCorrect;
  final int selectedValue;
  final VoidCallback onValidateModel;
  final VoidCallback onValidateRegions;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            locked ? '阶段 2 · 区域编码' : '阶段 1 · 参数求解',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            !locked
                ? '调节 x=|A∩B|。只有全部区域人数之和等于 30，模型才能锁定。'
                : regionCorrect == true
                ? '编码正确：A∪B 覆盖三个报名区域，共 $selectedValue 人。交集人数为 $intersection。'
                : regionCorrect == false
                ? '区域组合不符合 A∪B。全集中“两项都未参加”的区域不属于并集。'
                : '模型已锁定。请在上方选中 A∪B 覆盖的全部区域，再验证区域编码。',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: ValueKey(
              locked ? 'validate-set-regions' : 'validate-set-constraint',
            ),
            onPressed: locked ? onValidateRegions : onValidateModel,
            icon: Icon(
              locked ? Icons.layers_outlined : Icons.lock_outline_rounded,
            ),
            label: Text(locked ? '验证 A∪B 区域' : '锁定约束模型'),
            style: FilledButton.styleFrom(
              backgroundColor: _cyan,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ConstraintLine extends StatelessWidget {
  const _ConstraintLine({required this.label, required this.matched});

  final String label;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            matched ? Icons.check_circle_rounded : Icons.adjust_rounded,
            color: matched ? const Color(0xFF079455) : const Color(0xFFD97706),
            size: 17,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

final class _RegionSelector extends StatelessWidget {
  const _RegionSelector({required this.selected, required this.onToggle});

  final Set<_VennRegion> selected;
  final ValueChanged<_VennRegion> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final region in _VennRegion.values)
          FilterChip(
            key: ValueKey('venn-region-${region.name}'),
            selected: selected.contains(region),
            onSelected: (_) => onToggle(region),
            label: Text(region.label),
            selectedColor: const Color(0xFF36B8CF),
            backgroundColor: const Color(0xFF183943),
            side: const BorderSide(color: Color(0xFF35616B)),
            labelStyle: TextStyle(
              color: selected.contains(region) ? _ink : const Color(0xFFC2D9DD),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

enum _VennRegion { onlyRunning, intersection, onlyJumping, neither }

extension on _VennRegion {
  String get label => switch (this) {
    _VennRegion.onlyRunning => '只参加赛跑',
    _VennRegion.intersection => '两项都参加',
    _VennRegion.onlyJumping => '只参加跳跃',
    _VennRegion.neither => '两项都未参加',
  };
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

final class _VennPainter extends CustomPainter {
  const _VennPainter({
    required this.onlyRunning,
    required this.intersection,
    required this.onlyJumping,
    required this.neither,
    required this.selectedRegions,
  });

  final int onlyRunning;
  final int intersection;
  final int onlyJumping;
  final int neither;
  final Set<_VennRegion> selectedRegions;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * .49;
    final radius = math.min(size.width * .24, size.height * .36);
    final left = Offset(size.width * .42, centerY);
    final right = Offset(size.width * .58, centerY);
    final circleA = Path()
      ..addOval(Rect.fromCircle(center: left, radius: radius));
    final circleB = Path()
      ..addOval(Rect.fromCircle(center: right, radius: radius));
    if (selectedRegions.contains(_VennRegion.onlyRunning)) {
      final only = Path.combine(PathOperation.difference, circleA, circleB);
      canvas.drawPath(only, Paint()..color = const Color(0x8847C4DE));
    }
    if (selectedRegions.contains(_VennRegion.onlyJumping)) {
      final only = Path.combine(PathOperation.difference, circleB, circleA);
      canvas.drawPath(only, Paint()..color = const Color(0x887AA2F7));
    }
    if (selectedRegions.contains(_VennRegion.intersection)) {
      final overlap = Path.combine(PathOperation.intersect, circleA, circleB);
      canvas.drawPath(overlap, Paint()..color = const Color(0xAA71E0B5));
    }
    if (selectedRegions.contains(_VennRegion.neither)) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x2236B8CF),
      );
    }
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF6FB9C7);
    canvas.drawPath(circleA, outline);
    canvas.drawPath(circleB, outline..color = const Color(0xFF849FE1));
    _drawLabel(canvas, Offset(left.dx - radius * .52, 33), '赛跑 A', 12);
    _drawLabel(canvas, Offset(right.dx + radius * .3, 33), '跳跃 B', 12);
    _drawValue(canvas, Offset(left.dx - radius * .55, centerY), onlyRunning);
    _drawValue(canvas, Offset(size.width * .5, centerY), intersection);
    _drawValue(canvas, Offset(right.dx + radius * .55, centerY), onlyJumping);
    _drawLabel(
      canvas,
      Offset(size.width * .5, size.height - 24),
      '两项都未参加  $neither',
      11,
    );
  }

  void _drawValue(Canvas canvas, Offset center, int value) {
    _drawLabel(canvas, center, value.toString(), 24, bold: true);
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    String text,
    double size, {
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _VennPainter oldDelegate) =>
      oldDelegate.intersection != intersection ||
      oldDelegate.selectedRegions != selectedRegions;
}

final class _ConstraintTrackPainter extends CustomPainter {
  const _ConstraintTrackPainter({required this.value, required this.max});

  final int value;
  final int max;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0;
    final y = size.height * .42;
    final track = Rect.fromLTRB(inset, y - 3, size.width - inset, y + 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(8)),
      Paint()..color = const Color(0xFF31505A),
    );
    final x = inset + (size.width - inset * 2) * value / max;
    canvas.drawLine(
      Offset(inset, y),
      Offset(x, y),
      Paint()
        ..color = const Color(0xFF36B8CF)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(x, y), 10, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(x, y),
      10,
      Paint()
        ..color = const Color(0xFF36B8CF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final text = TextPainter(
      text: TextSpan(
        text: '交集人数 x = $value',
        style: const TextStyle(
          color: Color(0xFFC2D9DD),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(inset, size.height - 16));
  }

  @override
  bool shouldRepaint(covariant _ConstraintTrackPainter oldDelegate) =>
      oldDelegate.value != value;
}
