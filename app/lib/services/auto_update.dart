import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';

/// Automatisch updaten:
/// - Android: downloadt de nieuwe APK met voortgang en opent hem (installatieprompt).
/// - Windows: downloadt de nieuwe zip en opent de map.
/// - Web/iOS: website is altijd actueel; iOS opent de download.
class AutoUpdate {
  /// Controleert én installeert bij een update. Geeft true terug als er iets is gedaan.
  /// Toont zelf voortgangsdialogen; roep aan bij opstarten of via knop.
  static Future<bool> checkAndInstall(BuildContext context) async {
    if (kIsWeb) return false; // website is altijd de nieuwste
    final info = await UpdateService.checkForUpdate();
    if (info == null || !context.mounted) return false;
    final downloads = info['downloads'] as Map<String, dynamic>?;
    final current = info['current'] as Map<String, dynamic>? ?? {};
    final versie = 'Versie ${current['version']} (build ${current['build']})';

    if (Platform.isAndroid) {
      final url = UpdateService.pickDownload(downloads);
      if (url == null || !context.mounted) return false;
      final doen = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🐺 Automatische update'),
          content: Text('$versie is klaar.\n\n${current['notes'] ?? ''}\n\nDownloaden en installeren?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Updaten')),
          ],
        ),
      );
      if (doen != true || !context.mounted) return false;
      await _downloadAndInstallAndroid(context, url);
      return true;
    }

    if ((Platform.isWindows || Platform.isLinux) && context.mounted) {
      final url = UpdateService.pickDownload(downloads);
      if (url == null) return false;
      final doen = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('🐺 Update beschikbaar'),
          content: Text('$versie is klaar.\n\n${current['notes'] ?? ''}\n\nDownload openen? (Daarna zip uitpakken en opnieuw starten.)'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Downloaden')),
          ],
        ),
      );
      if (doen == true) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return true;
      }
    }
    return false;
  }

  static Future<void> _downloadAndInstallAndroid(BuildContext context, String url) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('🐺 Update downloaden'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v <= 0 ? null : v),
              const SizedBox(height: 8),
              Text(v <= 0 ? 'Bezig…' : '${(v * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['ngrok-skip-browser-warning'] = '1';
      final streamed = await req.send();
      if (streamed.statusCode != 200) throw Exception('download mislukt');
      final total = streamed.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/cyberwolfert-update.apk');
      final sink = file.openWrite();
      var done = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) progress.value = done / total;
      }
      await sink.close();
      if (context.mounted) Navigator.pop(context);
      // Opent de APK -> Android toont de installatieprompt (incl. "onbekende bronnen")
      await OpenFile.open(file.path, type: 'application/vnd.android.package-archive');
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update downloaden mislukt. Probeer het opnieuw.')),
        );
      }
    } finally {
      progress.dispose();
    }
  }
}
