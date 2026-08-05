import 'dart:collection';

import 'package:flutter/material.dart';

import 'parabola_painter.dart';

/// 白板关闭结果；取消时 confirmed=false 且调用方不得修改对话节点。
final class ExplorationWhiteboardResult {
  ExplorationWhiteboardResult({
    required this.confirmed,
    required Map<String, Object?> state,
  }) : state = UnmodifiableMapView(Map.of(state));

  factory ExplorationWhiteboardResult.cancelled() {
    return ExplorationWhiteboardResult(confirmed: false, state: const {});
  }

  final bool confirmed;
  final Map<String, Object?> state;
}

/// 3.3 正式白板接入点。
abstract interface class ExplorationWhiteboardLauncher {
  Future<ExplorationWhiteboardResult> open(
    BuildContext context, {
    required String nodeId,
    required String atomId,
    required Map<String, Object?> initialState,
  });
}

/// 开发期白板替身，允许拖动参数并在确认后返回状态。
final class MockExplorationWhiteboardLauncher
    implements ExplorationWhiteboardLauncher {
  const MockExplorationWhiteboardLauncher();

  @override
  Future<ExplorationWhiteboardResult> open(
    BuildContext context, {
    required String nodeId,
    required String atomId,
    required Map<String, Object?> initialState,
  }) async {
    final result = await showModalBottomSheet<ExplorationWhiteboardResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MockWhiteboard(initialState: initialState),
    );
    return result ?? ExplorationWhiteboardResult.cancelled();
  }
}

final class _MockWhiteboard extends StatefulWidget {
  const _MockWhiteboard({required this.initialState});

  final Map<String, Object?> initialState;

  @override
  State<_MockWhiteboard> createState() => _MockWhiteboardState();
}

final class _MockWhiteboardState extends State<_MockWhiteboard> {
  late double _a = _number(widget.initialState['a'], 1);
  late double _h = _number(widget.initialState['h'], 0);
  late double _k = _number(widget.initialState['k'], 0);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Mock 白板', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const Text('正式 3.3 接入后由真实白板替换'),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(painter: ParabolaPainter(a: _a, h: _h, k: _k)),
              ),
              Text('a=${_a.toStringAsFixed(1)} h=${_h.toStringAsFixed(1)} k=${_k.toStringAsFixed(1)}'),
              Slider(
                value: _a,
                min: -2,
                max: 2,
                divisions: 16,
                onChanged: (value) => setState(() => _a = value.abs() < 0.1 ? 0.25 : value),
              ),
              Slider(
                key: const ValueKey('whiteboard-h-slider'),
                value: _h,
                min: -3,
                max: 3,
                divisions: 12,
                onChanged: (value) => setState(() => _h = value),
              ),
              Slider(
                value: _k,
                min: -3,
                max: 3,
                divisions: 12,
                onChanged: (value) => setState(() => _k = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('whiteboard-confirm'),
                      onPressed: () => Navigator.of(context).pop(
                        ExplorationWhiteboardResult(
                          confirmed: true,
                          state: {'a': _a, 'h': _h, 'k': _k},
                        ),
                      ),
                      child: const Text('确认返回'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _number(Object? value, double fallback) {
  return value is num ? value.toDouble() : fallback;
}
