import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../services/auto_update.dart';
import '../services/download_service.dart';
import '../services/download_fs.dart' as fs;
import '../services/update_service.dart';
import '../widgets/app_logo.dart';

/// Downloadlijst zoals in echte browsers: alles wat je via CyberWolfert
/// downloadt staat hier en is vanuit de browser te openen.
class DownloadsScreen extends StatefulWidget {
  final void Function(String url) onOpenUrl;
  const DownloadsScreen({super.key, required this.onOpenUrl});

  /// Bestand direct openen (lokaal) of link extern (web/geen bestand)
  static Future<void> openEntry(BuildContext context, DownloadEntry e) async {
    if (!kIsWeb && e.path != null && await fs.fileExists(e.path!)) {
      await OpenFile.open(e.path!);
    } else if (e.url.isNotEmpty) {
      await UpdateService.openUrl(e.url);
    }
  }

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadEntry> _items = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await DownloadService.load();
    if (mounted) {
      setState(() {
        _items = items;
        _busy = false;
      });
    }
  }

  Future<void> _open(DownloadEntry e) =>
      DownloadsScreen.openEntry(context, e);

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.apk')) return Icons.android;
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) {
      return Icons.folder_zip;
    }
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (n.endsWith('.mp3') || n.endsWith('.m4a')) return Icons.audio_file;
    if (n.endsWith('.mp4')) return Icons.video_file;
    if (n.endsWith('.exe') || n.endsWith('.msi')) return Icons.desktop_windows;
    if (RegExp(r'\.(jpg|jpeg|png|webp|gif)$').hasMatch(n)) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 28, showName: false),
            SizedBox(width: 8),
            Text('Downloads'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'Controleren op updates',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(
                  content: Text('Controleren op updates…')));
              final updated =
                  await AutoUpdate.checkAndInstall(context);
              if (!updated && context.mounted) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Je hebt de nieuwste versie. 🐺')));
              }
            },
          ),
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Alles wissen',
              onPressed: () async {
                await DownloadService.clear();
                _load();
              },
            ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_done,
                          size: 64, color: Color(0xFF29B6F6)),
                      const SizedBox(height: 12),
                      const Text('Nog geen downloads',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                          'Bestanden die je via CyberWolfert downloadt\nkomen hier te staan.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.search),
                        label: const Text('Zoeken met WolfPulse'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final e = _items[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(_icon(e.name),
                            color: const Color(0xFF29B6F6)),
                        title: Text(e.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${DownloadService.prettySize(e.size)} • ${e.date.length >= 10 ? e.date.substring(0, 10) : e.date}',
                            style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await DownloadService.remove(e);
                            _load();
                          },
                        ),
                        onTap: () => _open(e),
                      ),
                    );
                  },
                ),
    );
  }
}
