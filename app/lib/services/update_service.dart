import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

/// Update-check: vergelijkt build-nummer met backend/version.json.
class UpdateService {
  static const int currentBuild = 17;

  static Future<Map<String, dynamic>?> _fetch(String path) async {
    try {
      final r = await http.get(Uri.parse('${AppConfig.baseUrl}$path'),
          headers: const {'ngrok-skip-browser-warning': '1'}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    final j = await _fetch('/update-check?build=$currentBuild');
    if (j == null || j['updateAvailable'] != true) return null;
    final v = await _fetch('/version');
    return {'current': j['current'], 'downloads': v?['downloads']};
  }

  static String? pickDownload(Map<String, dynamic>? downloads) {
    if (downloads == null) return null;
    if (kIsWeb) return downloads['bundle'] as String?;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return (downloads['apk'] ?? downloads['bundle']) as String?;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return (downloads['windows'] ?? downloads['bundle']) as String?;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return (downloads['ios'] ?? downloads['bundle']) as String?;
      default:
        return downloads['bundle'] as String?;
    }
  }

  static Future<String?> bundleUrl() async {
    final v = await _fetch('/version');
    return v?['downloads']?['bundle'] as String?;
  }

  static Future<void> openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static Future<void> checkAndPrompt(BuildContext context) async {
    final info = await checkForUpdate();
    if (info == null || !context.mounted) return;
    final current = info['current'] as Map<String, dynamic>? ?? {};
    final url = pickDownload(info['downloads'] as Map<String, dynamic>?);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🐺 Update beschikbaar'),
        content: Text(
            'Versie ${current['version']} (build ${current['build']}) is uit.\n\n${current['notes'] ?? ''}\n\nAlle apps krijgen precies dezelfde update.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          if (url != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                openUrl(url);
              },
              child: const Text('Update downloaden'),
            ),
        ],
      ),
    );
  }
}
