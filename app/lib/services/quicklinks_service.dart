import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Snelle links met echte brand-iconen (SVG) waar beschikbaar.
class QuickLink {
  final String naam;
  final String url;
  final String emoji;
  final String? svg;
  const QuickLink(this.naam, this.url, this.emoji, [this.svg]);

  static const defaults = [
    QuickLink('YouTube', 'https://youtube.com', '▶️', 'assets/brands/youtube.svg'),
    QuickLink('Twitch', 'https://twitch.tv', '💜', 'assets/brands/twitch.svg'),
    QuickLink('Discord', 'https://discord.com', '💬', 'assets/brands/discord.svg'),
    QuickLink('Minecraft', 'https://minecraft.net', '🟩'),
    QuickLink('GTA V', 'https://rockstargames.com/V', '🅥', 'assets/brands/rockstargames.svg'),
    QuickLink('Fortnite', 'https://fortnite.com', '🅕', 'assets/brands/fortnite.svg'),
  ];
}

class QuickLinksService {
  static const _key = 'quick_links';

  static Future<List<QuickLink>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return List.of(QuickLink.defaults);
    try {
      final List<dynamic> arr = jsonDecode(raw);
      return arr
          .map((e) => QuickLink(
              (e['naam'] ?? '').toString(),
              (e['url'] ?? '').toString(),
              (e['emoji'] ?? '🔗').toString(),
              (e['svg'] as String?)?.isNotEmpty == true ? e['svg'] as String : null))
          .where((e) => e.naam.isNotEmpty && e.url.isNotEmpty)
          .toList();
    } catch (_) {
      return List.of(QuickLink.defaults);
    }
  }

  static Future<void> save(List<QuickLink> links) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key,
        jsonEncode(links.map((l) => {'naam': l.naam, 'url': l.url, 'emoji': l.emoji, 'svg': l.svg}).toList()));
  }
}
