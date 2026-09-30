import 'package:flutter/material.dart';
import 'app_logo.dart';

/// Eigen AeroSeek-errorpagina: nooit merkteksten van andere browsers.
class WolfErrorView extends StatelessWidget {
  final String url;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  const WolfErrorView({
    super.key,
    required this.url,
    this.detail,
    required this.onRetry,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 96),
              const SizedBox(height: 20),
              const Text('Pagina niet bereikbaar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 12),
              const Text(
                'Controleer de verbinding en het adres en probeer het opnieuw.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Opnieuw'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.home),
                    label: const Text('Startpagina'),
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
