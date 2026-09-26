import 'dart:math';
import 'package:flutter/material.dart';

/// Geschilderd nachtwolf-landschap (default achtergrond).
class NightScape extends StatelessWidget {
  final Widget child;
  const NightScape({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NightPainter(),
      child: child,
    );
  }
}

class _NightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // ignore: prefer_const_declarations (createShader is geen const)
    final sky = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF0C2148), Color(0xFF071026), Color(0xFF040912)],
    ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = sky);

    final rnd = Random(42);
    for (var i = 0; i < 140; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h * 0.55;
      final r = rnd.nextDouble() * 1.4 + 0.4;
      final a = rnd.nextDouble() * 0.6 + 0.15;
      canvas.drawCircle(Offset(x, y), r,
          Paint()..color = Colors.white.withValues(alpha: a));
    }

    final moon = Offset(w * 0.78, h * 0.16);
    final mr = min(w, h) * 0.055;
    canvas.drawCircle(moon, mr * 2.6,
        Paint()..color = const Color(0xFF9FD8FF).withValues(alpha: 0.10));
    canvas.drawCircle(moon, mr * 1.6,
        Paint()..color = const Color(0xFF9FD8FF).withValues(alpha: 0.16));
    canvas.drawCircle(moon, mr, Paint()..color = const Color(0xFFE8F4FF));
    canvas.drawCircle(moon + Offset(-mr * 0.25, -mr * 0.15), mr * 0.82,
        Paint()..color = const Color(0xFF0C2148).withValues(alpha: 0.12));

    _ridge(canvas, w, h, 0.52, 0.10, const Color(0xFF0E2450), 7);
    _ridge(canvas, w, h, 0.62, 0.13, const Color(0xFF081433), 11);
    _pines(canvas, w, h, 0.62);

    final lakeTop = h * 0.74;
    canvas.drawRect(
      Rect.fromLTWH(0, lakeTop, w, h - lakeTop),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D2653), Color(0xFF03060F)],
        ).createShader(Rect.fromLTWH(0, lakeTop, w, h - lakeTop)),
    );
    final streakX = moon.dx;
    for (var i = 0; i < 14; i++) {
      final y = lakeTop + 6 + i * ((h - lakeTop - 12) / 14);
      final ww = mr * (0.5 + (i / 14) * 1.6) * (0.8 + Random(i).nextDouble() * 0.4);
      canvas.drawRRect(
        RRect.fromLTRBR(streakX - ww, y, streakX + ww, y + 2.2, const Radius.circular(2)),
        Paint()..color = const Color(0xFFBFE6FF).withValues(alpha: 0.28 - i * 0.016),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.3, h * 0.70), width: w * 0.5, height: 26),
      Paint()..color = const Color(0xFF9FD8FF).withValues(alpha: 0.07),
    );
  }

  void _ridge(Canvas canvas, double w, double h, double baseY, double amp, Color color, int seed) {
    final rnd = Random(seed);
    final path = Path()..moveTo(0, h * baseY + rnd.nextDouble() * 20);
    const n = 9;
    for (var i = 1; i <= n; i++) {
      final x = w * i / n;
      final y = h * baseY - rnd.nextDouble() * h * amp;
      path.lineTo(x - w / (n * 2), y);
      path.lineTo(x, h * baseY + rnd.nextDouble() * 14);
    }
    path.lineTo(w, h);
    path.lineTo(0, h);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _pines(Canvas canvas, double w, double h, double baseY) {
    final rnd = Random(99);
    final paint = Paint()..color = const Color(0xFF040A1C);
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * w;
      final th = 26 + rnd.nextDouble() * 60;
      final tw = 10 + rnd.nextDouble() * 14;
      final y = h * baseY + rnd.nextDouble() * h * 0.10;
      final p = Path()
        ..moveTo(x, y - th)
        ..lineTo(x - tw / 2, y)
        ..lineTo(x - tw / 4, y)
        ..lineTo(x + tw / 4, y)
        ..lineTo(x + tw / 2, y)
        ..close();
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
