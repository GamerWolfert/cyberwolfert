import 'package:flutter/foundation.dart' show kIsWeb;

/// Centrale configuratie: Mini-PC adres + branding + tunnel-support.
///
/// - Web: praat automatisch met de server die de pagina serveert (same-origin).
/// - APK/Windows/iOS: --dart-define=API_BASE_URL=... of LAN-fallback.
class AppConfig {
  static const String miniPcIp = '192.168.1.42';
  static const int backendPort = 43711;

  static const String _override = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.startsWith('http')) return '$origin/api';
      } catch (_) {}
    }
    if (_override.isNotEmpty) return _override.replaceAll(RegExp(r'/$'), '');
    return 'http://$miniPcIp:$backendPort/api';
  }

  static const String browserName = 'CyberWolfert Browser';
  static const String searchName = 'WolfPulse';
  static const String aiName = 'CyberWolf AI';
  static const String maker = 'GamerWolfertYT';
}
