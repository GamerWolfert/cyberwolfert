/// Adres-herkenning voor de AeroSurf-browser: alles wat de gebruiker typt
/// wordt ofwel een webadres, ofwel (als dat geen adres is) een zoekopdracht.
class UrlUtils {
  static final _schemeRe = RegExp(r'^[a-z][a-z0-9+.\-]*:', caseSensitive: false);
  static final _hostRe = RegExp(
      r'^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:[/?#].*)?$',
      caseSensitive: false);
  static final _localRe = RegExp(
      r'^(?:localhost|127\.0\.0\.1|0\.0\.0\.0|::1)(?::\d+)?(?:[/?#].*)?$',
      caseSensitive: false);
  static final _ipRe = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?(?:[/?#].*)?$');
  /// "localhost:8080" mag niet als scheme worden gelezen (poort!).
  static final _portRe = RegExp(r'^[a-z][a-z0-9+.\-]*:\d');

  static bool _isScheme(String t) =>
      _schemeRe.hasMatch(t) && !_portRe.hasMatch(t);

  static bool isHost(String s) =>
      _hostRe.hasMatch(s) || _localRe.hasMatch(s) || _ipRe.hasMatch(s);

  /// Zet alles wat de gebruiker typt om in een adres (of null = zoekopdracht).
  /// Werkt voor "google.com", "www.a.nl/pad?x=1", "localhost:8080",
  /// "192.168.1.42:43711", "https://…", "youtube.com/watch?v=x hallo",
  /// maar niet voor "hoe maak ik een website".
  static String? asUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    // Bestaand scheme (http, https, ftp, about, file) -> nooit zoeken.
    // Let op: "localhost:8080" lijkt op een scheme maar is een poort.
    if (_isScheme(t) && !t.contains(' ')) return t;
    if (!t.contains(' ')) return isHost(t) ? t : null;
    // Met spaties: alleen als het EERSTE deel een host is én er een
    // pad/vraagteken achter zit telt het als adres (spaties eruit).
    final delen = t.split(RegExp(r'\s+'));
    if (delen.length > 1 &&
        (isHost(delen.first) || _isScheme(delen.first)) &&
        t.contains(RegExp(r'[/?#=&]'))) {
      return t.replaceAll(' ', '');
    }
    return null;
  }

  /// Scheme toevoegen als het ontbreekt: localhost/IP's krijgen http
  /// (geen certificaat), de rest https.
  static String normScheme(String u) {
    if (u.startsWith('//')) return 'https:$u';
    if (_isScheme(u)) return u;
    final host = u.split(RegExp(r'[/?#]')).first;
    final lokaal = _localRe.hasMatch(host) || _ipRe.hasMatch(host);
    return lokaal ? 'http://$u' : 'https://$u';
  }
}
