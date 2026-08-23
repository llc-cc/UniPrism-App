import 'dart:math' as math;

import 'package:flutter/material.dart';

const _ink = Color(0xFF101828);
const _blue = Color(0xFF315CF5);

/// 通过直接拖动曲线切点完成目标斜率任务，不使用答案按钮或滑块。
final class DerivativeTangentGame extends StatefulWidget {
  const DerivativeTangentGame({super.key});

  @override
  State<DerivativeTangentGame> createState() => _DerivativeTangentGameState();
}

final class _DerivativeTangentGameState extends State<DerivativeTangentGame> {
  static const _missions = <_TangentMission>[
    _TangentMission(
      equation: 'f(x) = −2x² + 1',
      a: -2,
      b: 0,
      c: 1,
      targetSlope: 0,
      sourceHint: '曲线 y=−2x²+1 在 (0,1) 处的切线斜率',
    ),
    _TangentMission(
      equation: 'f(x) = 2x² + 4x',
      a: 2,
      b: 4,
      c: 0,
      targetSlope: 16,
      sourceHint: '资料题：切线斜率为 16，确定切点 P',
    ),
    _TangentMission(
      equation: 'f(x) = x²',
      a: 1,
      b: 0,
      c: 0,
      targetSlope: 4,
      sourceHint: '让切线与直线 y=4x+3 平行',
    ),
  ];

  var _missionIndex = 0;
  var _x = -1.5;
  var _attempts = 0;
  var _locked = false;

  _TangentMission get _mission => _missions[_missionIndex];
  double get _y => _mission.valueAt(_x);
  double get _slope => _mission.slopeAt(_x);

  void _moveTo(double localDx, double width) {
    if (_locked) return;
    const left = 48.0;
    const right = 20.0;
    final usable = math.max(1.0, width - left - right);
    final raw = -4 + ((localDx - left) / usable) * 8;
    final snapped = (raw * 4).round() / 4;
    setState(() => _x = snapped.clamp(-4.0, 4.0));
  }

  void _lockTangent() {
    final success = (_slope - _mission.targetSlope).abs() < .01;
    setState(() {
      _attempts += 1;
      _locked = success;
    });
  }

  void _nextMission() {
    setState(() {
      _missionIndex = (_missionIndex + 1) % _missions.length;
      _x = -1.5;
      _attempts = 0;
      _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = (_slope - _mission.targetSlope).abs();
    final precision = (1 - error / 20).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MissionHeader(
          index: _missionIndex,
          count: _missions.length,
          equation: _mission.equation,
          targetSlope: _mission.targetSlope,
          sourceHint: _mission.sourceHint,
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111C33),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22101C34),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      color: Color(0xFF8EA9FF),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE TANGENT FIELD',
                      style: TextStyle(
                        color: Color(0xFFA9B8D2),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _locked ? 'TARGET LOCKED' : 'DRAG THE POINT',
                      style: TextStyle(
                        color: _locked
                            ? const Color(0xFF5CE1B2)
                            : const Color(0xFFFFCF70),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    key: const ValueKey('tangent-graph'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _moveTo(details.localPosition.dx, constraints.maxWidth),
                    onPanUpdate: (details) =>
                        _moveTo(details.localPosition.dx, constraints.maxWidth),
                    child: SizedBox(
                      height: 390,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _TangentFieldPainter(
                          mission: _mission,
                          x: _x,
                          locked: _locked,
                        ),
                      ),
                    ),
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
            final telemetry = _TelemetryPanel(
              x: _x,
              y: _y,
              slope: _slope,
              target: _mission.targetSlope,
              precision: precision,
              attempts: _attempts,
            );
            final controls = _TangentControls(
              locked: _locked,
              slopeError: error,
              x: _x,
              y: _y,
              slope: _slope,
              onLock: _lockTangent,
              onNext: _nextMission,
            );
            return compact
                ? Column(
                    children: [telemetry, const SizedBox(height: 12), controls],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: telemetry),
                      const SizedBox(width: 12),
                      Expanded(child: controls),
                    ],
                  );
          },
        ),
      ],
    );
  }
}

final class _MissionHeader extends StatelessWidget {
  const _MissionHeader({
    required this.index,
    required this.count,
    required this.equation,
    required this.targetSlope,
    required this.sourceHint,
  });

  final int index;
  final int count;
  final String equation;
  final double targetSlope;
  final String sourceHint;

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Text(
                'MISSION ${(index + 1).toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${index + 1} / $count',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$equation　·　目标斜率 k = ${_number(targetSlope)}',
            style: const TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '$sourceHint。直接拖动曲线上的切点，让实时切线与目标匹配。',
            style: const TextStyle(
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

final class _TelemetryPanel extends StatelessWidget {
  const _TelemetryPanel({
    required this.x,
    required this.y,
    required this.slope,
    required this.target,
    required this.precision,
    required this.attempts,
  });

  final double x;
  final double y;
  final double slope;
  final double target;
  final double precision;
  final int attempts;

  @override
  Widget build(BuildContext context) {
    return _WhitePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '实时测量',
            style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: 'x₀', value: _number(x)),
              _Metric(label: 'f(x₀)', value: _number(y)),
              _Metric(label: 'f′(x₀)', value: _number(slope)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '目标匹配度',
                style: TextStyle(color: Color(0xFF667085), fontSize: 11),
              ),
              const Spacer(),
              Text(
                '${(precision * 100).round()}%',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: precision,
            minHeight: 7,
            borderRadius: BorderRadius.circular(9),
            backgroundColor: const Color(0xFFE9EDF5),
            color: _blue,
          ),
          const SizedBox(height: 8),
          Text(
            '目标 ${_number(target)} · 已验证 $attempts 次',
            style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

final class _TangentControls extends StatelessWidget {
  const _TangentControls({
    required this.locked,
    required this.slopeError,
    required this.x,
    required this.y,
    required this.slope,
    required this.onLock,
    required this.onNext,
  });

  final bool locked;
  final double slopeError;
  final double x;
  final double y;
  final double slope;
  final VoidCallback onLock;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _WhitePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            locked ? '切线锁定成功' : '验证控制台',
            style: TextStyle(
              color: locked ? const Color(0xFF067647) : _ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            locked
                ? '切点 P(${_number(x)}, ${_number(y)})，切线斜率 ${_number(slope)}。\n切线：y − ${_number(y)} = ${_number(slope)}(x − ${_number(x)})'
                : slopeError < 2
                ? '信号已接近目标，继续小幅拖动切点后锁定。'
                : '当前斜率与目标仍有 ${_number(slopeError)} 的差值。观察切线旋转方向。',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            key: ValueKey(locked ? 'next-tangent-mission' : 'lock-tangent'),
            onPressed: locked ? onNext : onLock,
            icon: Icon(
              locked ? Icons.skip_next_rounded : Icons.my_location_rounded,
            ),
            label: Text(locked ? '进入下一任务' : '锁定当前切线'),
            style: FilledButton.styleFrom(
              backgroundColor: locked ? const Color(0xFF087A55) : _blue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

final class _WhitePanel extends StatelessWidget {
  const _WhitePanel({required this.child});

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

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

final class _TangentMission {
  const _TangentMission({
    required this.equation,
    required this.a,
    required this.b,
    required this.c,
    required this.targetSlope,
    required this.sourceHint,
  });

  final String equation;
  final double a;
  final double b;
  final double c;
  final double targetSlope;
  final String sourceHint;

  double valueAt(double x) => a * x * x + b * x + c;
  double slopeAt(double x) => 2 * a * x + b;
}

final class _TangentFieldPainter extends CustomPainter {
  const _TangentFieldPainter({
    required this.mission,
    required this.x,
    required this.locked,
  });

  final _TangentMission mission;
  final double x;
  final bool locked;

  static const _left = 48.0;
  static const _right = 20.0;
  static const _top = 18.0;
  static const _bottom = 34.0;
  static const _minX = -4.0;
  static const _maxX = 4.0;
  static const _minY = -34.0;
  static const _maxY = 36.0;

  Offset _point(Size size, double px, double py) {
    final dx =
        _left + (px - _minX) / (_maxX - _minX) * (size.width - _left - _right);
    final dy =
        _top + (_maxY - py) / (_maxY - _minY) * (size.height - _top - _bottom);
    return Offset(dx, dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF223553)
      ..strokeWidth = 1;
    for (var gx = -4; gx <= 4; gx++) {
      final p = _point(size, gx.toDouble(), 0);
      canvas.drawLine(
        Offset(p.dx, _top),
        Offset(p.dx, size.height - _bottom),
        grid,
      );
    }
    for (var gy = -30; gy <= 30; gy += 10) {
      final p = _point(size, 0, gy.toDouble());
      canvas.drawLine(
        Offset(_left, p.dy),
        Offset(size.width - _right, p.dy),
        grid,
      );
    }
    final axis = Paint()
      ..color = const Color(0xFF7083A2)
      ..strokeWidth = 1.4;
    final origin = _point(size, 0, 0);
    canvas.drawLine(
      Offset(_left, origin.dy),
      Offset(size.width - _right, origin.dy),
      axis,
    );
    canvas.drawLine(
      Offset(origin.dx, _top),
      Offset(origin.dx, size.height - _bottom),
      axis,
    );

    final curve = Path();
    for (var index = 0; index <= 240; index++) {
      final px = _minX + (_maxX - _minX) * index / 240;
      final point = _point(size, px, mission.valueAt(px));
      if (index == 0) {
        curve.moveTo(point.dx, point.dy);
      } else {
        curve.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = const Color(0xFF6F93FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final y = mission.valueAt(x);
    final slope = mission.slopeAt(x);
    final tangentY1 = y + slope * (_minX - x);
    final tangentY2 = y + slope * (_maxX - x);
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom),
    );
    canvas.drawLine(
      _point(size, _minX, tangentY1),
      _point(size, _maxX, tangentY2),
      Paint()
        ..color = locked ? const Color(0xFF5CE1B2) : const Color(0xFFFFC857)
        ..strokeWidth = 2.2,
    );
    canvas.restore();
    final focus = _point(size, x, y);
    canvas.drawCircle(focus, 11, Paint()..color = const Color(0x331A5CFF));
    canvas.drawCircle(
      focus,
      5.5,
      Paint()..color = locked ? const Color(0xFF5CE1B2) : Colors.white,
    );
    canvas.drawCircle(
      focus,
      5.5,
      Paint()
        ..color = const Color(0xFF315CF5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TangentFieldPainter oldDelegate) {
    return oldDelegate.x != x ||
        oldDelegate.locked != locked ||
        oldDelegate.mission != mission;
  }
}

String _number(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}
