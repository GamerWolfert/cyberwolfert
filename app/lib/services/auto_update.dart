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
  /// Vanaf deze build is de APK met de release-tekening gebouwd. Oudere
  /// installaties (debug-tekening) kunnen niet over-the-air updaten: Android
  /// zegt dan "App niet geïnstalleerd". Die krijgen de handmatige route.
  static const int releaseSignedBuild = 27;

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
      if (UpdateService.currentBuild < releaseSignedBuild) {
        await _handmatigeUpdate(context, url, versie, current);
        return true;
      }
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
        await _installHelp(context);
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

  /// Oude installatie met de debug-tekening: de release-getekende APK gaat er
  /// niet overheen ("App niet geïnstalleerd"). Daarom downloaden naar de
  /// Downloadmap (blijft bewaard), app verwijderen, dan pas installeren.
  static Future<void> _handmatigeUpdate(BuildContext context, String url,
      String versie, Map<String, dynamic> current) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📲 Update = opnieuw installeren'),
        content: Text(
            '$versie is klaar.\n\n${current['notes'] ?? ''}\n\n'
            'Je huidige installatie heeft een andere tekening dan de nieuwe APK, dus '
            'Android zegt "App niet geïnstalleerd". Volg deze drie stappen:\n\n'
            '1. Tik op "Nieuwe APK downloaden" — het bestand komt in je Downloadmap en '
            'blijft daar bewaard, ook als je de app verwijdert.\n'
            '2. Verwijder daarna deze app (lang drukken op het pictogram → Verwijderen).\n'
            '3. Open het gedownloade bestand in je Downloadmap en installeer het.\n\n'
            'Waarschuwt Play Protect? Tik op Details → Toch installeren. '
            'Na deze ene keer updaten normaal via de app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later')),
          FilledButton(
              onPressed: () {
                Navigator.pop(context);
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text('Nieuwe APK downloaden')),
        ],
      ),
    );
  }

  /// Play Protect blokkeert sideloaded APK's ("App geblokkeerd om je apparaat
  /// te beschermen"). Uitleg geven zodat updaten wél lukt.
  static Future<void> _installHelp(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📲 Installatie afronden'),
        content: const Text(
            'Android kan deze update blokkeren met Play Protect.\n\n'
            '1. Tik op Details.\n'
            '2. Tik op "Toch installeren".\n\n'
            'Wordt het toch geblokkeerd? Zet Play Protect even uit (Play Store → je profiel → '
            'Play Protect → scans uitschakelen), installeer de update en zet het daarna weer aan.\n\n'
            'Staat er "App niet geïnstalleerd"? Verwijder eerst de oude CyberWolfert-app, '
            'installeer de APK opnieuw en log daarna gewoon weer in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Begrepen')),
        ],
      ),
    );
  }
}
