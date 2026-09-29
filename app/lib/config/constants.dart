import 'package:flutter/foundation.dart' show kIsWeb;

/// Centrale configuratie: Mini-PC adres + branding + tunnel-support.
///
/// - Web: praat automatisch met de server die de pagina serveert (same-origin).
/// - APK/Windows/iOS: --dart-define=API_BASE_URL=... of LAN-fallback.
class AppConfig {
  static const String miniPcIp = '192.168.1.42';
  static const int backendPort = 43711;
  static const String tunnelUrl =
      'https://train-entrust-boozy.ngrok-free.dev/api';

  static const String _override = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Alleen-bouwtijd override (release-workflow zet dit op de LAN-adres).
  static String get override => _override.replaceAll(RegExp(r'/$'), '');

  static String get baseUrl {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.startsWith('http')) return '$origin/api';
      } catch (_) {}
    }
    if (_override.isNotEmpty) return override;
    return 'http://$miniPcIp:$backendPort/api';
  }

  /// Mogelijke backend-adressen, op volgorde van voorkeur. De app probeert
  /// ze allemaal en onthoudt degene die het doet (thuis LAN, elders tunnel).
  static List<String> get candidates {
    final out = <String>[];
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.startsWith('http')) out.add('$origin/api');
      } catch (_) {}
    }
    if (_override.isNotEmpty) out.add(override);
    out.add('http://$miniPcIp:$backendPort/api');
    out.add(tunnelUrl);
    return out.toSet().toList();
  }

  static const String browserName = 'CyberWolfert Browser';
  static const String searchName = 'WolfPulse';
  static const String aiName = 'CyberWolf AI';
  static const String maker = 'GamerWolfertYT';
}
