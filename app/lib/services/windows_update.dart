import 'dart:io';

import 'package:flutter/material.dart';
import 'download_service.dart';

/// Windows-updaten zonder nieuwe map of handwerk:
/// de nieuwe release-zip wordt gedownload, uitgepakt en de bestanden worden
/// in de map van de huidige exe vervangen. Een klein PowerShell-hulpbestand
/// wacht tot deze app gesloten is, kopieert alles over, ruimt op en start de
/// exe opnieuw — dus de exe in je map wordt automatisch vernieuwd.
class WindowsUpdate {
  static String get _exePath => Platform.resolvedExecutable;
  static String get _exeDir => File(_exePath).parent.path;

  /// Werkt updaten-in-place hier? (map beschrijfbaar, geen Program Files zonder
  /// rechten) — anders vallen we terug op de handmatige route.
  static bool get canReplaceInPlace {
    try {
      final f = File('$_exeDir\\.aerowrite_test');
      f.writeAsStringSync('test');
      f.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download + uitpakken + herstart. Toont zelf de voortgangs- en
  /// bevestigings-dialogen; geeft terug of de update gestart is.
  static Future<bool> install(
      BuildContext context, String url, String versie, String notes) async {
    if (!context.mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🚀 Update installeren'),
        content: Text(
            '$versie is klaar.\n\n$notes\n\n'
            'De nieuwe bestanden komen automatisch in de map van AeroSurf terecht '
            '(de exe wordt vervangen) en de app start daarna zelf opnieuw.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Nu updaten')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;

    if (!canReplaceInPlace) {
      await _handmatig(context, url, versie);
      return true;
    }

    final progress = ValueNotifier<double>(0);
    final fase = ValueNotifier<String>('Downloaden…');
    var dialogOpen = false;
    if (context.mounted) {
      dialogOpen = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('🚀 Update downloaden'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v <= 0 ? null : v),
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: fase,
                  builder: (_, f, __) =>
                      Text(f, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 6),
                Text(v <= 0 ? 'Bezig…' : '${(v * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final entry = await DownloadService.download(url,
          onProgress: (v) => progress.value = v);
      final zip = entry.path;
      if (zip == null) throw Exception('geen bestand');

      fase.value = 'Uitpakken…';
      progress.value = 0;
      final dir = await _unzip(zip);

      if (!context.mounted) return false;
      Navigator.pop(context); // voortgang
      dialogOpen = false;

      final started = await _startHelper(dir);
      if (!started) throw Exception('helper starten mislukt');

      if (context.mounted) await _confirmRestart(context);
      exit(0);
    } catch (_) {
      if (dialogOpen && context.mounted) Navigator.pop(context);
      progress.dispose();
      fase.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Update installeren mislukt. Probeer het opnieuw '
                'of download de zip handmatig.')));
      }
      return false;
    }
  }

  /// Pak de zip uit met PowerShell (standaard aanwezig, geen extra package).
  static Future<String> _unzip(String zip) async {
    final base =
        Directory('${Directory.systemTemp.path}\\aeroupdate_${DateTime.now().millisecondsSinceEpoch}');
    final files = Directory('${base.path}\\files');
    await files.create(recursive: true);
    final r = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Expand-Archive -LiteralPath '$zip' -DestinationPath '${files.path}' -Force"
        ]);
    if (r.exitCode != 0) throw Exception('uitpakken: ${r.stderr}');
    return base.path;
  }

  /// Zet het hulpscript klaar en start het los (blijft leven als wij sluiten).
  static Future<bool> _startHelper(String base) async {
    final from = '$base\\files';
    final log = '$base\\update.log';
    final script = '''
\$exe = '$_exePath'
\$from = '$from'
\$log = '$log'
\$procId = $pid
\$dest = Split-Path \$exe

while (Get-Process -Id \$procId -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 600

try {
  Copy-Item -Path (Join-Path \$from '*') -Destination \$dest -Recurse -Force -ErrorAction Stop
  Set-Content -Path \$log -Value "OK \$(Get-Date -Format s)" -Encoding UTF8
} catch {
  Set-Content -Path \$log -Value "FOUT: \$(\$_.Exception.Message)" -Encoding UTF8
}

try { Start-Process -FilePath \$exe -WorkingDirectory \$dest } catch {}
Start-Sleep -Seconds 3
Remove-Item -Path \$from -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path \$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
''';
    final scriptPath = '$base\\update.ps1';
    await File(scriptPath).writeAsString(script, flush: true);

    // Los proces (detached): blijft draaien ook als deze app sluit.
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath
      ],
      mode: ProcessStartMode.detached,
    );
    return true;
  }

  static Future<void> _confirmRestart(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✅ Update klaar'),
        content: const Text(
            'AeroSurf sluit zichzelf, installeert de nieuwe bestanden en '
            'start daarna vanzelf opnieuw.\n\n'
            'Staat de app straks nog op de oude versie? Start hem dan één '
            'keer handmatig opnieuw op.'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Oké, herstart')),
        ],
      ),
    );
  }

  /// Map niet beschrijfbaar (bijv. Program Files): gewoon de zip laten zien.
  static Future<void> _handmatig(
      BuildContext context, String url, String versie) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🚀 Update downloaden'),
        content: Text(
            '$versie staat klaar, maar deze map is niet beschrijfbaar.\n\n'
            '1. Download de zip.\n'
            '2. Pak hem uit over de map van AeroSurf (exe vervangen).\n'
            '3. Start de exe opnieuw.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Process.run('explorer.exe', ['/select,', _exePath]);
              },
              child: const Text('Map openen')),
        ],
      ),
    );
    // zip alsnog openen/downloaden
    await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "Start-Process '$url'"
    ]);
  }
}
