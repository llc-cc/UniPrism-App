import 'package:flutter/material.dart';

/// 用参数实时绘制抛物线，确保互动素材不是不可操作的静态截图。
final class ParabolaPainter extends CustomPainter {
  const ParabolaPainter({required this.a, required this.h, required this.k});

  final double a;
  final double h;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = const Color(0xFFB8B2C2)
      ..strokeWidth = 1;
    final curvePaint = Paint()
      ..color = const Color(0xFF6B23FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final vertexPaint = Paint()..color = const Color(0xFFFF8A4C);
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);

    const scaleX = 28.0;
    const scaleY = 16.0;
    final path = Path();
    var hasStarted = false;
    for (var pixelX = 0.0; pixelX <= size.width; pixelX += 2) {
      final x = (pixelX - center.dx) / scaleX;
      final y = a * (x - h) * (x - h) + k;
      final point = Offset(pixelX, center.dy - y * scaleY);
      if (!hasStarted) {
        path.moveTo(point.dx, point.dy);
        hasStarted = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(path, curvePaint);
    final vertex = Offset(center.dx + h * scaleX, center.dy - k * scaleY);
    canvas.drawCircle(vertex, 5, vertexPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ParabolaPainter oldDelegate) {
    return oldDelegate.a != a || oldDelegate.h != h || oldDelegate.k != k;
  }
}
