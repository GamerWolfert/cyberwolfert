import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Platform-zaken voor de altijd-aan luisterdienst en trillen (alleen Android).
/// Op andere platformen is het een stille no-op zodat de code overal werkt.
class VoicePlatform {
  static const MethodChannel _ch = MethodChannel('cyberwolfert/voice');
  static bool _active = false;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Luisterdienst aanhouden (Hey Nova blijft wakker, app wordt niet doodgemaakt).
  static Future<void> keepAlive({required bool on}) async {
    if (!_android || _active == on) return;
    _active = on;
    try {
      if (on) {
        await _ch.invokeMethod('start');
      } else {
        await _ch.invokeMethod('stop');
      }
    } catch (_) {
      _active = false;
    }
  }

  /// Eén trilling (bv. wakewoord gehoord).
  static Future<void> vibrate([int ms = 250]) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('vibrate', {'ms': ms});
    } catch (_) {}
  }

  /// Trillingen herhalen tot [stop] wordt aangeroepen (inkomende oproep).
  static Future<void> ringVibrate() async {
    if (!_android) return;
    // Eén lange, goed voelbare trilling; de ringlus herhaalt dit.
    try {
      await _ch.invokeMethod('vibrate', {'ms': 700});
    } catch (_) {}
  }
}
