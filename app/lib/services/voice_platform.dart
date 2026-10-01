import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Platform-zaken voor de altijd-aan luisterdienst en trillen (alleen Android).
/// Op andere platformen is het een stille no-op zodat de code overal werkt.
class VoicePlatform {
  static const MethodChannel _ch = MethodChannel('cyberwolfert/voice');
  static bool _active = false;
  static bool _svc = false; // laatst bekende status van de luisterdienst

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Of de luisterdienst volgens ons aan staat.
  static bool get active => _active;

  /// Of de Android-dienst daadwerkelijk draait (gevraagd aan het systeem).
  static bool get serviceRunning => _svc;

  /// Luisterdienst aanhouden (Hey Nova blijft wakker, app wordt niet doodgemaakt).
  static Future<void> keepAlive({required bool on}) async {
    if (!_android) return;
    if (_active == on && !on) return;
    _active = on;
    try {
      if (on) {
        await _ch.invokeMethod('start');
        await refresh();
      } else {
        await _ch.invokeMethod('stop');
        _svc = false;
      }
    } catch (_) {
      _active = false;
      _svc = false;
    }
  }

  /// Dienst opnieuw afdwingen als hij weg is (Android kan een
  /// foreground-service stil doodmaken, bijv. na accu-optimalisatie).
  static Future<void> ensureAlive() async {
    if (!_android || !_active) return;
    try {
      final running = await _ch.invokeMethod('running');
      _svc = running == true;
      if (_svc) return;
      await _ch.invokeMethod('start');
      await Future.delayed(const Duration(milliseconds: 400));
      final again = await _ch.invokeMethod('running');
      _svc = again == true;
    } catch (_) {}
  }

  /// Vraag na of de luisterdienst draait (voor de diagnosetekst).
  static Future<void> refresh() async {
    if (!_android) return;
    try {
      _svc = await _ch.invokeMethod('running') == true;
    } catch (_) {}
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
