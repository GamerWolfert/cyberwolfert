import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Startsound (yippee-mp3) bij het opstarten van de app. Aan/uit via menu.
class SoundService {
  static const _key = 'sound_on';
  static final _player = AudioPlayer();
  static bool _played = false;

  static Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }

  /// Eén keer afspelen bij app-start (niet bij elke rebuild).
  static Future<void> playStartup() async {
    if (_played) return;
    _played = true;
    try {
      if (await enabled()) {
        await _player.play(AssetSource('sound.mp3'));
      }
    } catch (_) {}
  }
}
