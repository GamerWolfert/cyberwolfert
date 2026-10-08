import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_logo.dart';

/// Eigen AeroSeek-errorpagina: nooit Edge/Firefox/Chrome-teksten of
/// standaard "papiertje met gezichtje" — altijd AeroSurf-stijl met
/// duidelijke reden, tips en opnieuw-proberen.
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

  static const _accent = Color(0xFF3CFF5C);

  IconData get _icoon {
    final d = (detail ?? '').toLowerCase();
    if (d.contains('domein') || d.contains('spelling') || d.contains('gevonden')) {
      return Icons.search_off_rounded;
    }
    if (d.contains('ssl') || d.contains('cert') || d.contains('tls')) {
      return Icons.lock_outline_rounded;
    }
    if (d.contains('verbinding') || d.contains('bereikbaar') || d.contains('netwerk')) {
      return Icons.wifi_off_rounded;
    }
    if (d.contains('timeout') || d.contains('reageert')) {
      return Icons.hourglass_disabled_rounded;
    }
    if (d.contains('lokaal') || d.contains('netwerk') || d.contains('proxy')) {
      return Icons.router_outlined;
    }
    return Icons.public_off_rounded;
  }

  List<String> get _tips {
    final d = (detail ?? '').toLowerCase();
    if (d.contains('domein') || d.contains('spelling')) {
      return ['Check de spelling van het adres', 'Probeer het domein zonder www.'];
    }
    if (d.contains('ssl') || d.contains('cert')) {
      return ['Deze site heeft een verouderd of fout beveiligingscertificaat',
          'Openen op eigen risico kan via "Extern openen"'];
    }
    if (d.contains('timeout') || d.contains('reageert')) {
      return ['De site is traag of tijdelijk overbelast', 'Even wachten en opnieuw proberen'];
    }
    if (d.contains('lokaal') || d.contains('proxy')) {
      return ['Dit adres bestaat alleen in je eigen netwerk',
          'Open de app op hetzelfde WiFi-netwerk'];
    }
    return ['Controleer je internetverbinding', 'Probeer het adres opnieuw te typen'];
  }

  Future<void> _extern() async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final tips = _tips;
    return Container(
      width: double.infinity,
      color: const Color(0xFF050805),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 72),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E140E),
                  shape: BoxShape.circle,
                  border: Border.all(color: _accent.withValues(alpha: 0.35)),
                ),
                child: Icon(_icoon, size: 44, color: _accent),
              ),
              const SizedBox(height: 20),
              const Text(
                'Deze pagina is niet bereikbaar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E140E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 15, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        url,
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  detail ?? 'Controleer de verbinding en probeer het opnieuw.',
                  style: const TextStyle(
                      fontSize: 14, height: 1.4, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B100B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wat je kunt proberen',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white54)),
                    const SizedBox(height: 8),
                    for (final t in tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(color: _accent)),
                            Expanded(
                              child: Text(t,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Opnieuw proberen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _extern,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Extern openen'),
                  ),
                  if (onHome != null)
                    OutlinedButton.icon(
                      onPressed: onHome,
                      icon: const Icon(Icons.home_rounded, size: 18),
                      label: const Text('Startpagina'),
                    ),
                ],
              ),
              if (w < 420) const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
