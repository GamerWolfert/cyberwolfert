import 'package:flutter/material.dart';
import 'app_logo.dart';

/// Eigen AeroSeek-errorpagina: nooit Edge/Firefox/Chrome-teksten,
/// altijd in AeroSurf-style met opnieuw-proberen.
class WolfErrorView extends StatelessWidget {
  final String url;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback? onHome;
  const WolfErrorView({
    super.key,
    required this.url,
    this.detail,
    required this.onRetry,
    this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 96),
            const SizedBox(height: 16),
            Text(
              url,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            const Text(
              'Deze pagina is niet bereikbaar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              detail ?? 'Controleer de verbinding en probeer het opnieuw.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Opnieuw proberen'),
                ),
                if (onHome != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.home),
                    label: const Text('Startpagina'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
