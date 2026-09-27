import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'download_service.dart';
import 'update_service.dart';

/// Automatisch updaten:
/// - Android: downloadt de nieuwe APK met voortgang, zet hem in de
///   downloadlijst en opent hem (installatieprompt).
/// - Windows: downloadt de nieuwe zip en opent de download.
class AutoUpdate {
  static Future<bool> checkAndInstall(BuildContext context) async {
    if (kIsWeb) return false;
    final info = await UpdateService.checkForUpdate();
    if (info == null || !context.mounted) return false;
    final downloads = info['downloads'] as Map<String, dynamic>?;
    final current = info['current'] as Map<String, dynamic>? ?? {};
    final versie = 'Versie ${current['version']} (build ${current['build']})';

    if (defaultTargetPlatform == TargetPlatform.android) {
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

    if ((defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux) &&
        context.mounted) {
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

  static Future<void> _downloadAndInstallAndroid(
      BuildContext context, String url) async {
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
      final entry = await DownloadService.download(url,
          onProgress: (v) => progress.value = v);
      if (context.mounted) Navigator.pop(context);
      if (entry.path != null) {
        await OpenFile.open(entry.path!,
            type: 'application/vnd.android.package-archive');
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Update downloaden mislukt. Probeer het opnieuw.')),
        );
      }
    } finally {
      progress.dispose();
    }
  }
}
