import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_fs.dart' as fs;

/// Downloadbeheer zoals in echte browsers: alles wat je via AeroSurf
/// downloadt komt in de lijst en is vanuit de browser te openen.
class DownloadEntry {
  final String name;
  final String url;
  final String? path; // lokaal bestand (null op Web)
  final int size;
  final String date;
  const DownloadEntry(
      {required this.name,
      required this.url,
      this.path,
      this.size = 0,
      required this.date});

  Map<String, dynamic> toJson() =>
      {'name': name, 'url': url, 'path': path, 'size': size, 'date': date};

  static DownloadEntry fromJson(Map<String, dynamic> j) => DownloadEntry(
        name: (j['name'] ?? 'Download').toString(),
        url: (j['url'] ?? '').toString(),
        path: j['path']?.toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        date: (j['date'] ?? '').toString(),
      );
}

class DownloadService {
  static const _key = 'downloads';

  static String fileNameOf(String url) {
    try {
      final seg = Uri.parse(url).pathSegments;
      final last = seg.isNotEmpty ? seg.last : '';
      if (last.contains('.')) return Uri.decodeComponent(last);
    } catch (_) {}
    return 'download-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Bestandsextensies die we automatisch als download behandelen (mobiel).
  static bool looksLikeFile(String url) {
    final u = url.toLowerCase().split('?').first;
    return RegExp(r'\.(apk|zip|pdf|mp3|mp4|m4a|exe|msi|rar|7z|tar\.gz|doc|docx|xls|xlsx|ppt|pptx|epub|csv|jpg|jpeg|png|webp|gif)$')
        .hasMatch(u);
  }

  static Future<List<DownloadEntry>> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final List<dynamic> arr = jsonDecode(p.getString(_key) ?? '[]');
      return arr.map((e) => DownloadEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<DownloadEntry> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> add(DownloadEntry e) async {
    final list = await load();
    list.removeWhere((x) => x.url == e.url && x.name == e.name);
    list.insert(0, e);
    await _save(list.take(50).toList());
  }

  static Future<void> remove(DownloadEntry e) async {
    final list = await load();
    list.removeWhere((x) => x.url == e.url && x.name == e.name);
    await _save(list);
    if (!kIsWeb && e.path != null) {
      await fs.deleteFile(e.path!);
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  /// Downloadt een URL naar app-opslag en registreert hem. Geeft entry terug.
  static Future<DownloadEntry> download(String url,
      {void Function(double progress)? onProgress}) async {
    final name = fileNameOf(url);
    if (kIsWeb) {
      // Web: browser regelt het bestand; wij registreren de link
      final e = DownloadEntry(
          name: name,
          url: url,
          date: DateTime.now().toIso8601String());
      await add(e);
      return e;
    }
    final req = http.Request('GET', Uri.parse(url));
    req.headers['ngrok-skip-browser-warning'] = '1';
    final streamed = await req.send();
    if (streamed.statusCode != 200) throw Exception('download mislukt');
    final total = streamed.contentLength ?? 0;
    final dir = await getApplicationDocumentsDirectory();
    final dlPath = '${dir.path}/downloads';
    await fs.ensureDir(dlPath);
    var done = 0;
    final counted = streamed.stream.map((chunk) {
      done += chunk.length;
      if (total > 0) onProgress?.call(done / total);
      return chunk;
    });
    final savedPath = await fs.writeStream('$dlPath/$name', counted);
    final e = DownloadEntry(
        name: name,
        url: url,
        path: savedPath,
        size: await fs.fileLength(savedPath),
        date: DateTime.now().toIso8601String());
    await add(e);
    return e;
  }

  static String prettySize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
