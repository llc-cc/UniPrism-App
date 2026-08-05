import 'package:flutter/material.dart';

import '../core/exploration_models.dart';
import 'parabola_painter.dart';

/// 在对话流内呈现可操作素材；只管理视觉交互，不承担教学决策。
final class ExplorationMaterialCard extends StatelessWidget {
  const ExplorationMaterialCard({super.key, required this.material});

  final ExplorationMaterial material;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      color: const Color(0xFFF7F4FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE1D7FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(material.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            switch (material.kind) {
              ExplorationMaterialKind.figure => _FigureMaterial(material: material),
              ExplorationMaterialKind.video => _MockVideoMaterial(material: material),
              ExplorationMaterialKind.interactive => _InteractiveMaterial(
                material: material,
              ),
              ExplorationMaterialKind.formula => _FormulaMaterial(material: material),
            },
          ],
        ),
      ),
    );
  }
}

final class _FigureMaterial extends StatelessWidget {
  const _FigureMaterial({required this.material});

  final ExplorationMaterial material;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('exploration-figure'),
      height: 180,
      width: double.infinity,
      child: CustomPaint(
        painter: ParabolaPainter(
          a: _number(material.payload['a'], 1),
          h: _number(material.payload['h'], 0),
          k: _number(material.payload['k'], 0),
        ),
      ),
    );
  }
}

final class _MockVideoMaterial extends StatefulWidget {
  const _MockVideoMaterial({required this.material});

  final ExplorationMaterial material;

  @override
  State<_MockVideoMaterial> createState() => _MockVideoMaterialState();
}

final class _MockVideoMaterialState extends State<_MockVideoMaterial> {
  var _isPlaying = false;
  var _progress = 0.25;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Chip(
          avatar: Icon(Icons.science_outlined, size: 18),
          label: Text('模拟视频'),
        ),
        Row(
          children: [
            IconButton(
              key: const ValueKey('mock-video-toggle'),
              onPressed: () => setState(() => _isPlaying = !_isPlaying),
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            Expanded(
              child: Slider(
                value: _progress,
                onChanged: (value) => setState(() => _progress = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _InteractiveMaterial extends StatelessWidget {
  const _InteractiveMaterial({required this.material});

  final ExplorationMaterial material;

  @override
  Widget build(BuildContext context) {
    if (material.payload.containsKey('price')) {
      return _BusinessInteraction(material: material);
    }
    return _ParabolaInteraction(material: material);
  }
}

final class _ParabolaInteraction extends StatefulWidget {
  const _ParabolaInteraction({required this.material});

  final ExplorationMaterial material;

  @override
  State<_ParabolaInteraction> createState() => _ParabolaInteractionState();
}

final class _ParabolaInteractionState extends State<_ParabolaInteraction> {
  late double _a = _number(widget.material.payload['a'], 1);
  late double _h = _number(widget.material.payload['h'], 0);
  late double _k = _number(widget.material.payload['k'], 0);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: ParabolaPainter(a: _a, h: _h, k: _k)),
        ),
        Text('a = ${_a.toStringAsFixed(1)}'),
        Slider(
          key: const ValueKey('parabola-a-slider'),
          value: _a,
          min: -2,
          max: 2,
          divisions: 16,
          onChanged: (value) => setState(() => _a = value.abs() < 0.1 ? 0.25 : value),
        ),
        Text('h = ${_h.toStringAsFixed(1)}，k = ${_k.toStringAsFixed(1)}'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _h,
                min: -3,
                max: 3,
                divisions: 12,
                onChanged: (value) => setState(() => _h = value),
              ),
            ),
            Expanded(
              child: Slider(
                value: _k,
                min: -3,
                max: 3,
                divisions: 12,
                onChanged: (value) => setState(() => _k = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _BusinessInteraction extends StatefulWidget {
  const _BusinessInteraction({required this.material});

  final ExplorationMaterial material;

  @override
  State<_BusinessInteraction> createState() => _BusinessInteractionState();
}

final class _BusinessInteractionState extends State<_BusinessInteraction> {
  late double _price = _number(widget.material.payload['price'], 28);
  late double _orders = _number(widget.material.payload['dailyOrders'], 120);

  @override
  Widget build(BuildContext context) {
    final revenue = (_price * _orders).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('客单价：¥${_price.round()}'),
        Slider(
          key: const ValueKey('business-price-slider'),
          value: _price,
          min: 10,
          max: 60,
          divisions: 25,
          onChanged: (value) => setState(() => _price = value),
        ),
        Text('每日订单：${_orders.round()}'),
        Slider(
          value: _orders,
          min: 20,
          max: 300,
          divisions: 28,
          onChanged: (value) => setState(() => _orders = value),
        ),
        Text('日收入：¥$revenue', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

final class _FormulaMaterial extends StatelessWidget {
  const _FormulaMaterial({required this.material});

  final ExplorationMaterial material;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        material.payload['formula']?.toString() ?? '暂无公式',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }
}

double _number(Object? value, double fallback) {
  return value is num ? value.toDouble() : fallback;
}
