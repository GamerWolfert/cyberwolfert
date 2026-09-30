/// Web-variant: geen systeemmeldingen, alleen het meldingsgeluid
/// (zie local_notify.dart voor de Android-versie met flutter_local_notifications).
class LocalNotify {
  static Future<void> init() async {}

  static Future<void> show(String title, String body,
      {bool call = false}) async {}
}
