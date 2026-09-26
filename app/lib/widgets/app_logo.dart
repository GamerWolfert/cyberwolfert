import 'package:flutter/material.dart';
import 'wolf_mark.dart';

/// App-logo: het ECHTE WolfPulse-logo (assets/logo.png, bevat zelf WOLFPULSE-tekst).
class AppLogo extends StatelessWidget {
  final double size;
  final bool showName;
  const AppLogo({super.key, this.size = 120, this.showName = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.26),
          child: Image.asset(
            'assets/logo.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.26),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A1B3D), Color(0xFF061224)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFF29B6F6), width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x6629B6F6), blurRadius: 24, spreadRadius: 2)
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(size * 0.12),
                child: WolfMark(size: size * 0.76),
              ),
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 10),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Colors.white, Color(0xFF29B6F6)],
            ).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: const Text(
              'WOLFPULSE',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1428).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF29B6F6).withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: child,
    );
  }
}
