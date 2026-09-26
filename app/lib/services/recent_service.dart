import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// "Recent geopend": echte browsegeschiedenis van dit apparaat.
class RecentItem {
  final String title;
  final String url;
  final String time;
  const RecentItem(this.title, this.url, this.time);
}

class RecentService {
  static const _key = 'recent_opened';
  static const _max = 8;

  static String _titel(String url) {
    try {
      var host = Uri.parse(url).host.replaceFirst(RegExp(r'^www\.'), '');
      return host.isEmpty ? url : host;
    } catch (_) {
      return url;
    }
  }

  static Future<void> add(String url) async {
    final p = await SharedPreferences.getInstance();
    final List<dynamic> raw = jsonDecode(p.getString(_key) ?? '[]');
    raw.removeWhere((e) => (e as Map)['url'] == url);
    raw.insert(0, {
      'title': _titel(url),
      'url': url,
      'time': DateTime.now().toIso8601String(),
    });
    await p.setString(_key, jsonEncode(raw.take(_max).toList()));
  }

  static Future<List<RecentItem>> load() async {
    final p = await SharedPreferences.getInstance();
    final List<dynamic> raw = jsonDecode(p.getString(_key) ?? '[]');
    return raw
        .map((e) => RecentItem(
            (e['title'] ?? '').toString(),
            (e['url'] ?? '').toString(),
            (e['time'] ?? '').toString()))
        .where((e) => e.url.isNotEmpty)
        .toList();
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
