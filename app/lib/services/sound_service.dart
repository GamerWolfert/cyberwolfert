import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_fs.dart' as fs;

/// Startsound: standaard yippee-mp3, of je EIGEN mp3 (uploaden via menu).
/// Daarnaast meldings- en belgeluiden (standaard Discord-mp3's uit assets,
/// of zelf gekozen bestanden).
class SoundService {
  static const _onKey = 'sound_on';
  static const _customKey = 'sound_custom_path';
  static const _notifPathKey = 'notif_sound_path';
  static const _notifNameKey = 'notif_sound_name';
  static const _callPathKey = 'call_sound_path';
  static const _callNameKey = 'call_sound_name';
  static final _player = AudioPlayer();
  static final _notifPlayer = AudioPlayer();
  static final _callPlayer = AudioPlayer();
  static bool _played = false;

  static Future<SharedPreferences> get _p async => SharedPreferences.getInstance();

  static String _pathKey(String kind) => kind == 'call' ? _callPathKey : _notifPathKey;
  static String _nameKey(String kind) => kind == 'call' ? _callNameKey : _notifNameKey;

  static Future<bool> enabled() async {
    final p = await _p;
    return p.getBool(_onKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await _p;
    await p.setBool(_onKey, v);
  }

  /// Berichtgeluid aan/uit (zelfde schakelaar als in AeroTalk → Meldingen).
  static Future<bool> notifEnabled() async {
    final p = await _p;
    return p.getBool('ws_notif_sound') ?? true;
  }

  static Future<bool> callEnabled() async {
    final p = await _p;
    return p.getBool('ws_call_sound_on') ?? true;
  }

  /// Welk geluid staat er nu ingesteld ('Standaard' of de bestandsnaam).
  static Future<String> soundLabel(String kind) async {
    final p = await _p;
    return p.getString(_nameKey(kind)) ?? 'Standaard';
  }

  /// Eigen mp3 kiezen voor melding of telefoon (niet op Web).
  static Future<String?> pickSound(String kind) async {
    if (kIsWeb) return null;
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      final src = files.isNotEmpty ? files.first.path : null;
      if (src == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/${kind}_sound.mp3';
      await fs.copyFile(src, dest);
      final p = await _p;
      await p.setString(_pathKey(kind), dest);
      await p.setString(_nameKey(kind), src.split(RegExp(r'[\\/]')).last);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// Terug naar het standaardgeluid (Discord-mp3 uit de app).
  static Future<void> resetSound(String kind) async {
    final p = await _p;
    await p.remove(_pathKey(kind));
    await p.remove(_nameKey(kind));
  }

  static Future<void> _play(AudioPlayer player, String kind, String asset) async {
    try {
      final p = await _p;
      final custom = p.getString(_pathKey(kind));
      if (custom != null && await fs.fileExists(custom)) {
        await player.stop();
        await player.play(DeviceFileSource(custom));
      } else {
        await player.stop();
        await player.play(AssetSource(asset));
      }
    } catch (_) {}
  }

  /// Meldingsgeluid (nieuw bericht, nieuwe mail, update, AI-antwoord).
  static Future<void> playNotif() async {
    if (!await notifEnabled()) return;
    await _play(_notifPlayer, 'notif', 'notif.mp3');
  }

  /// Belgeluid (inkomend gesprek / oproep).
  static Future<void> playCall() async {
    if (!await callEnabled()) return;
    try {
      await _callPlayer.setReleaseMode(ReleaseMode.release);
    } catch (_) {}
    await _play(_callPlayer, 'call', 'call.mp3');
  }

  /// Belgeluid herhalen tot [stopCallRing] (inkomende oproep die nog rinkelt).
  static Future<void> startCallRing() async {
    if (!await callEnabled()) return;
    try {
      await _callPlayer.setReleaseMode(ReleaseMode.loop);
      final p = await _p;
      final custom = p.getString(_callPathKey);
      await _callPlayer.stop();
      if (custom != null && await fs.fileExists(custom)) {
        await _callPlayer.play(DeviceFileSource(custom));
      } else {
        await _callPlayer.play(AssetSource('call.mp3'));
      }
    } catch (_) {}
  }

  /// Belussen stoppen (aangenomen, geweigerd of opgehangen).
  static Future<void> stopCallRing() async {
    try {
      await _callPlayer.stop();
      await _callPlayer.setReleaseMode(ReleaseMode.release);
    } catch (_) {}
  }

  static Future<String?> customPath() async {
    final p = await _p;
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
