import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Systeemmeldingen (Android, met eigen meldingsgeluiden uit res/raw).
/// Berichten komen als hoge "heads-up"-melding bovenaan het scherm (met
/// app-icoon, afzender en tekst); oproepen als volledig scherm (call-intent).
/// Op andere platformen blijft het bij het meldingsgeluid van de app.
class LocalNotify {
  static final FlutterLocalNotificationsPlugin _p =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const int callId = 999001; // vaste id: oproepmelding overschrijven

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
        // Geen kanaalgeluid: de app speelt de belussen zelf (loop), zodat
        // het in AeroTalk ingestelde belgeluid geldt en niet twee keer klinkt.
        playSound: false,
      ));
      await a?.requestNotificationsPermission();
      _ready = ok ?? false;
    } catch (_) {}
  }

  /// Melding tonen. Geeft de melding-id terug (voor [cancel]).
  /// [call] = inkomende oproep: volledig scherm + belgeluid van het kanaal.
  static Future<int> show(String title, String body,
      {bool call = false, int? id}) async {
    if (!_ready || title.trim().isEmpty) return -1;
    final mid = id ??
        (call
            ? callId
            : DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000);
    try {
      await _p.show(
        mid,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            call ? 'aerocall' : 'aerobase',
            call ? 'AeroSurf gesprekken' : 'AeroSurf meldingen',
            importance: call ? Importance.max : Importance.high,
            priority: call ? Priority.max : Priority.high,
            visibility: NotificationVisibility.public,
            category:
                call ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
            fullScreenIntent: call,
            ongoing: call,
            autoCancel: !call,
            timeoutAfter: call ? 45000 : null,
            ticker: '$title: $body',
            color: const Color(0xFF3CFF5C),
            styleInformation:
                BigTextStyleInformation(body, contentTitle: title),
          ),
        ),
      );
    } catch (_) {}
    return mid;
  }

  /// Melding verwijderen (bv. oproep aangenomen of afgewezen).
  static Future<void> cancel(int id) async {
    if (!_ready || id <= 0) return;
    try {
      await _p.cancel(id);
    } catch (_) {}
  }
}
