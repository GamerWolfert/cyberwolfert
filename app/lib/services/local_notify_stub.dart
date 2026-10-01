/// Web-variant: geen systeemmeldingen, alleen het meldingsgeluid
/// (zie local_notify.dart voor de Android-versie met flutter_local_notifications).
class LocalNotify {
  static Future<void> init() async {}

  /// Geeft -1 terug: er is geen systeemmelding, dus het app-geluid spelen.
  static Future<int> show(String title, String body,
      {bool call = false, int? id}) async =>
      -1;

  static Future<void> cancel(int id) async {}
}
