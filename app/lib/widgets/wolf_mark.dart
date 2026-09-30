import 'package:flutter/material.dart';

/// Neon-wolfmark (fallback + AI-avatar).
class WolfMark extends StatelessWidget {
  final double size;
  const WolfMark({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WolfPainter()),
    );
  }
}

class _WolfPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);

    final head = Path()
      ..moveTo(0.50, 0.30)
      ..lineTo(0.66, 0.20)
      ..lineTo(0.90, 0.04)
      ..lineTo(0.84, 0.32)
      ..lineTo(0.88, 0.52)
      ..lineTo(0.76, 0.62)
      ..lineTo(0.72, 0.80)
      ..lineTo(0.60, 0.92)
      ..lineTo(0.50, 1.00)
      ..lineTo(0.40, 0.92)
      ..lineTo(0.28, 0.80)
      ..lineTo(0.24, 0.62)
      ..lineTo(0.12, 0.52)
      ..lineTo(0.16, 0.32)
      ..lineTo(0.10, 0.04)
      ..lineTo(0.34, 0.20)
      ..close();
    canvas.drawPath(
        head,
        Paint()
          ..color = const Color(0xFF0A1628)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        head,
        Paint()
          ..color = const Color(0xFF3CFF5C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.022
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(
        head,
        Paint()
          ..color = const Color(0xFF3CFF5C).withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    final eyePaint = Paint()..color = const Color(0xFF7CFFB0);
    final eyeGlow = Paint()
      ..color = const Color(0xFF7CFFB0).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final leftEye = Path()
      ..moveTo(0.28, 0.50)
      ..lineTo(0.44, 0.55)
      ..lineTo(0.42, 0.60)
      ..lineTo(0.28, 0.56)
      ..close();
    final rightEye = Path()
      ..moveTo(0.72, 0.50)
      ..lineTo(0.56, 0.55)
      ..lineTo(0.58, 0.60)
      ..lineTo(0.72, 0.56)
      ..close();
    for (final e in [leftEye, rightEye]) {
      canvas.drawPath(e, eyeGlow);
      canvas.drawPath(e, eyePaint);
    }
    canvas.drawCircle(
        p(0.50, 0.86), s * 0.035, Paint()..color = const Color(0xFF050805));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
