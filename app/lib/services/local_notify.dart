import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Systeemmeldingen (Android, met eigen meldingsgeluiden uit res/raw).
/// Op andere platformen blijft het bij het meldingsgeluid van de app.
class LocalNotify {
  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    try {
      final ok = await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      final a = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Kanalen met geluid: melding = Discord-notitie, gesprek = Discord-bel.
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        'aerobase',
        'AeroSurf meldingen',
        description: 'Berichten, mail en meldingen',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notif'),
      ));
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        'aerocall',
        'AeroSurf gesprekken',
        description: 'Inkomende gesprekken',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('call'),
      ));
      await a?.requestNotificationsPermission();
      _ready = ok ?? false;
    } catch (_) {}
  }

  static Future<void> show(String title, String body,
      {bool call = false}) async {
    if (!_ready || title.trim().isEmpty) return;
    try {
      await _p.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            call ? 'aerocall' : 'aerobase',
            call ? 'AeroSurf gesprekken' : 'AeroSurf meldingen',
            importance: call ? Importance.max : Importance.high,
            priority: call ? Priority.max : Priority.high,
            styleInformation: BigTextStyleInformation(
                body.trim().isEmpty ? title : body),
          ),
        ),
      );
    } catch (_) {}
  }
}
