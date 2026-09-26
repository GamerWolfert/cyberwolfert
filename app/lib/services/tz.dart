/// Mini-tijdzonedatabase. Standaard Europe/Amsterdam (auto zomer/wintertijd).
class TzZone {
  final String id;
  final String label;
  const TzZone(this.id, this.label);

  static const system = TzZone('system', 'Systeem');
  static const amsterdam = TzZone('Europe/Amsterdam', 'Amsterdam');

  static const List<TzZone> zones = [
    system,
    amsterdam,
    TzZone('Europe/Berlin', 'Berlijn'),
    TzZone('Europe/London', 'Londen'),
    TzZone('America/New_York', 'New York'),
    TzZone('Asia/Tokyo', 'Tokio'),
    TzZone('Australia/Sydney', 'Sydney'),
    TzZone('UTC', 'UTC'),
  ];

  static TzZone byId(String? id) =>
      zones.firstWhere((z) => z.id == id, orElse: () => amsterdam);

  DateTime now() {
    if (id == 'system') return DateTime.now();
    return DateTime.now().toUtc().add(Duration(minutes: offsetMinutes()));
  }

  int offsetMinutes() {
    final utc = DateTime.now().toUtc();
    switch (id) {
      case 'Europe/Amsterdam':
      case 'Europe/Berlin':
        return _inEuDst(utc) ? 120 : 60;
      case 'Europe/London':
        return _inEuDst(utc) ? 60 : 0;
      case 'America/New_York':
        return _inUsDst(utc) ? -240 : -300;
      case 'Australia/Sydney':
        return _inAuDst(utc) ? 660 : 600;
      case 'Asia/Tokyo':
        return 540;
      default:
        return 0;
    }
  }

  static bool _inEuDst(DateTime utc) {
    final start = DateTime.utc(utc.year, 3, _lastSunday(utc.year, 3), 1);
    final end = DateTime.utc(utc.year, 10, _lastSunday(utc.year, 10), 1);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static bool _inUsDst(DateTime utc) {
    final start = DateTime.utc(utc.year, 3, _nthSunday(utc.year, 3, 2), 7);
    final end = DateTime.utc(utc.year, 11, _nthSunday(utc.year, 11, 1), 6);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static bool _inAuDst(DateTime utc) {
    final start = DateTime.utc(utc.year, 10, _nthSunday(utc.year, 10, 1), 16);
    final end = DateTime.utc(utc.year + 1, 4, _nthSunday(utc.year + 1, 4, 1), 16);
    final prevEnd = DateTime.utc(utc.year, 4, _nthSunday(utc.year, 4, 1), 16);
    final prevStart = DateTime.utc(utc.year - 1, 10, _nthSunday(utc.year - 1, 10, 1), 16);
    return (!utc.isBefore(start) && utc.isBefore(end)) ||
        (!utc.isBefore(prevStart) && utc.isBefore(prevEnd));
  }

  static int _lastSunday(int year, int month) {
    var d = DateTime.utc(year, month + 1, 0);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d.day;
  }

  static int _nthSunday(int year, int month, int n) {
    var d = DateTime.utc(year, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.day + (n - 1) * 7;
  }

  static const weekdagen = [
    'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'
  ];
  static const maanden = [
    'januari', 'februari', 'maart', 'april', 'mei', 'juni',
    'juli', 'augustus', 'september', 'oktober', 'november', 'december'
  ];

  static String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String datumLang(DateTime t) =>
      '${weekdagen[t.weekday - 1]} ${t.day} ${maanden[t.month - 1]} ${t.year}';
}
