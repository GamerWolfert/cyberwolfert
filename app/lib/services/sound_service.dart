import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_fs.dart' as fs;

/// Startsound: standaard yippee-mp3, of je EIGEN mp3 (uploaden via menu).
class SoundService {
  static const _onKey = 'sound_on';
  static const _customKey = 'sound_custom_path';
  static final _player = AudioPlayer();
  static bool _played = false;

  static Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_onKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_onKey, v);
  }

  static Future<String?> customPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_customKey);
  }

  /// Kies je eigen mp3 als startsound (alleen in de app, niet op Web).
  /// Geeft de bestandsnaam terug, of null bij annuleren/mislukken.
  static Future<String?> pickCustom() async {
    if (kIsWeb) return null;
    try {
      // file_picker v13+: geeft direct een lijst terug
      final files = await FilePicker.pickFiles(type: FileType.audio);
      final src = files.isNotEmpty ? files.first.path : null;
      if (src == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/startsound.mp3';
      await fs.copyFile(src, dest);
      final p = await SharedPreferences.getInstance();
      await p.setString(_customKey, dest);
      return dest.split('/').last;
    } catch (_) {
      return null;
    }
  }

  /// Terug naar de standaard yippee-sound.
  static Future<void> clearCustom() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_customKey);
  }

  /// Eén keer afspelen bij app-start (eigen mp3 eerst, anders standaard).
  static Future<void> playStartup() async {
    if (_played) return;
    _played = true;
    try {
      if (!await enabled()) return;
      final custom = kIsWeb ? null : await customPath();
      if (custom != null && await fs.fileExists(custom)) {
        await _player.play(DeviceFileSource(custom));
      } else {
        await _player.play(AssetSource('sound.mp3'));
      }
    } catch (_) {}
  }
}
