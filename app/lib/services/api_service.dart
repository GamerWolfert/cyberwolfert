import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';

/// Alle netwerkcalls naar de backend (token automatisch mee, nooit adressen in fouten).
///
/// Verbinding: de app onthoudt welk adres (LAN of internet-tunnel) het doet en
/// valt automatisch terug als de verbinding wegvalt, zodat de apps nooit
/// onnodig 'offline' zijn.
class ApiService {
  static String? _active;
  static Future<bool>? _probe;
  static const String _kCustom = 'server_base';
  static const String _kLast = 'server_last';

  String get base => _active ?? AppConfig.baseUrl;

  /// Handmatig ingevoerde server-URL (null = automatisch zoeken).
  static Future<String?> customBase() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCustom);
  }

  /// URL opslaan (of wissen met null) en meteen opnieuw verbinden.
  static Future<void> setCustomBase(String? url) async {
    final p = await SharedPreferences.getInstance();
    final v = _normBase(url);
    if (v == null) {
      await p.remove(_kCustom);
    } else {
      await p.setString(_kCustom, v);
    }
    _active = null;
    _probe = null;
    await ApiService().resolveBase(force: true);
  }

  static String? _normBase(String? u) {
    if (u == null) return null;
    var s = u.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return null;
    if (!s.startsWith('http')) s = 'https://$s';
    return s.endsWith('/api') ? s : '$s/api';
  }

  /// Vraagt de backend welke externe tunnel nu actief is (alleen bereikbaar
  /// via LAN, maar dat is precies waar de URL het eerst bekend is).
  static Future<String?> _discoverTunnel() async {
    try {
      final r = await http
          .get(
              Uri.parse(
                  'http://${AppConfig.miniPcIp}:${AppConfig.backendPort}/api/tunnel'),
              headers: {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final u = _normBase((j['url'] ?? '').toString());
        if (u != null) return u;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> resolveBase({bool force = false}) {
    if (!force && _active != null) return Future.value(true);
    if (_probe != null) return _probe!;
    _probe = _doResolve().whenComplete(() => _probe = null);
    return _probe!;
  }

  Future<bool> _doResolve() async {
    final p = await SharedPreferences.getInstance();
    final cands = <String>[];
    final custom = _normBase(p.getString(_kCustom));
    final last = _normBase(p.getString(_kLast));
    if (custom != null) cands.add(custom);
    if (last != null) cands.add(last);
    cands.addAll(AppConfig.candidates);

    var found = await _firstOk(cands.toSet().toList());
    if (found == null) {
      // Alleen nu de tunnel-URL opvragen (loopt naast de gewone race, dus
      // geen extra vertraging als de LAN-ip gewoon bereikbaar is).
      final t = await _discoverTunnel();
      if (t != null) found = await _firstOk([t]);
    } else {
      unawaited(_discoverTunnel());
    }

    if (found != null) {
      _active = found;
      if (found != custom && found != AppConfig.baseUrl) {
        await p.setString(_kLast, found);
      }
      return true;
    }
    return _active != null;
  }

  /// Raced alle kandidaten; wie het eerst /version 200 teruggeeft wint.
  Future<String?> _firstOk(List<String> cands) {
    final c = Completer<String?>();
    var left = cands.length;
    for (final u in cands) {
      () async {
        try {
          final r = await http
              .get(Uri.parse('$u/version'), headers: await _h())
              .timeout(const Duration(seconds: 5));
          if (r.statusCode == 200 && !c.isCompleted) c.complete(u);
        } catch (_) {}
        if (--left == 0 && !c.isCompleted) c.complete(null);
      }();
    }
    return c.future;
  }

  Future<Map<String, String>> _h({bool json = false}) async {
    final m = <String, String>{
      'ngrok-skip-browser-warning': '1',
    };
    if (json) m['Content-Type'] = 'application/json';
    final t = await AuthStore.get();
    if (t != null) m['Authorization'] = 'Bearer $t';
    return m;
  }

  Future<T> _guard<T>(String wat, Future<T> Function() fn,
      {Duration timeout = const Duration(seconds: 20)}) async {
    await resolveBase();
    try {
      return await fn().timeout(timeout);
    } catch (e) {
      // Misschien is een ander adres bereikbaar (thuis LAN, buiten tunnel):
      // één keer opnieuw proberen, daarna de originele fout tonen.
      if (await resolveBase(force: true)) {
        try {
          return await fn().timeout(timeout);
        } catch (_) {}
      }
      if (e is Exception) rethrow;
      throw Exception('$wat is mislukt. Controleer de verbinding en probeer opnieuw.');
    }
  }

  Future<bool> health({bool force = false}) async {
    try {
      await resolveBase(force: force);
      final v = await http
          .get(Uri.parse('$base/version'), headers: await _h())
          .timeout(const Duration(seconds: 6));
      return v.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> loadSettings() => _guard('Instellingen laden', () async {
        final r = await http.get(Uri.parse('$base/settings'), headers: await _h());
        if (r.statusCode != 200) throw Exception('bad status');
        return jsonDecode(r.body) as Map<String, dynamic>;
      });

  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> body) =>
      _guard('Instellingen opslaan', () async {
        final r = await http.post(Uri.parse('$base/settings'),
            headers: await _h(json: true), body: jsonEncode(body));
        if (r.statusCode != 200) throw Exception('bad status');
        return jsonDecode(r.body) as Map<String, dynamic>;
      });

  Future<List<dynamic>> loadBackgrounds() async {
    try {
      final r = await http.get(Uri.parse('$base/settings/backgrounds'), headers: await _h());
      if (r.statusCode != 200) return [];
      return jsonDecode(r.body) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBackground(String name, String type, String value, bool active) =>
      _guard('Achtergrond opslaan', () async {
        await http.post(Uri.parse('$base/settings/backgrounds'),
            headers: await _h(json: true),
            body: jsonEncode({'name': name, 'type': type, 'value': value, 'is_active': active}));
      });

  /// Frame-check: kan deze URL ingebed worden ('open'), is proxy nodig
  /// ('blocked') of is hij onbereikbaar ('na')? null bij verbindingsfout.
  Future<String?> frameCheck(String url) async {
    try {
      final r = await http
          .get(Uri.parse('$base/frame-check?url=${Uri.encodeComponent(url)}'),
              headers: await _h())
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['framing']?.toString();
    } catch (_) {
      return null;
    }
  }

  // --- Generiek (voor AeroTalk e.a.) ---
  Future<dynamic> apiGet(String path) => _guard('Laden', () async {
        final r = await http.get(Uri.parse('$base$path'), headers: await _h());
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return jsonDecode(r.body);
      });

  Future<dynamic> apiPost(String path, [Map<String, dynamic>? body]) =>
      _guard('Versturen', () async {
        final r = await http.post(Uri.parse('$base$path'),
            headers: await _h(json: true), body: jsonEncode(body ?? {}));
        if (r.statusCode != 200 && r.statusCode != 201) {
          throw Exception(_apiFout(r.body));
        }
        return r.body.isEmpty ? {} : jsonDecode(r.body);
      });

  Future<dynamic> apiPut(String path, [Map<String, dynamic>? body]) =>
      _guard('Opslaan', () async {
        final r = await http.put(Uri.parse('$base$path'),
            headers: await _h(json: true), body: jsonEncode(body ?? {}));
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return r.body.isEmpty ? {} : jsonDecode(r.body);
      });

  Future<dynamic> apiDelete(String path) => _guard('Verwijderen', () async {
        final r =
            await http.delete(Uri.parse('$base$path'), headers: await _h());
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return r.body.isEmpty ? {} : jsonDecode(r.body);
      });

  String _apiFout(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return (j['error'] ?? 'Er ging iets mis.').toString();
    } catch (_) {
      return 'Er ging iets mis.';
    }
  }
  Future<Map<String, dynamic>> search(String q) => _guard('Zoeken', () async {
        final r = await http.get(
            Uri.parse('$base/search?q=${Uri.encodeComponent(q)}'),
            headers: await _h());
        if (r.statusCode != 200) throw Exception('bad status');
        return jsonDecode(r.body) as Map<String, dynamic>;
      });

  Future<String> askAi(String message, List<Map<String, String>> history) =>
      _guard('AeroNova AI', () async {
        final r = await http.post(Uri.parse('$base/ai/chat'),
            headers: await _h(json: true),
            body: jsonEncode({'message': message, 'history': history}));
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.statusCode != 200) throw Exception('bad status');
        return (j['reply'] ?? '') as String;
      }, timeout: const Duration(seconds: 240));

  Future<String> askAiWithImage(
      String message, List<Map<String, String>> history, String imagePath) =>
      _guard('AeroNova AI', () async {
        final req = http.MultipartRequest('POST', Uri.parse('$base/ai/chat'));
        req.headers.addAll(await _h());
        req.fields['message'] = message;
        req.fields['history'] = jsonEncode(history);
        req.files.add(await http.MultipartFile.fromPath('image', imagePath));
        final streamed = await req.send();
        final body = await streamed.stream.bytesToString();
        final j = jsonDecode(body) as Map<String, dynamic>;
        if (streamed.statusCode != 200) throw Exception('bad status');
        return (j['reply'] ?? '') as String;
      }, timeout: const Duration(seconds: 240));

  // --- Remote agent: AI maakt een plan, jij geeft toestemming, Mini-PC voert uit ---
  Future<Map<String, dynamic>> agentPlan(String goal) =>
      _guard('Agent: plan maken', () async {
        final r = await http.post(Uri.parse('$base/ai/agent/plan'),
            headers: await _h(json: true), body: jsonEncode({'goal': goal}));
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return jsonDecode(r.body) as Map<String, dynamic>;
      }, timeout: const Duration(seconds: 180));

  Future<Map<String, dynamic>> agentRun(String id) =>
      _guard('Agent: uitvoeren', () async {
        final r = await http.post(Uri.parse('$base/ai/agent/run'),
            headers: await _h(json: true), body: jsonEncode({'id': id}));
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return jsonDecode(r.body) as Map<String, dynamic>;
      });

  Future<Map<String, dynamic>> agentStatus() => _guard('Agent: status', () async {
        final r = await http.get(Uri.parse('$base/ai/agent/status'),
            headers: await _h());
        if (r.statusCode != 200) throw Exception(_apiFout(r.body));
        return jsonDecode(r.body) as Map<String, dynamic>;
      });

  Future<String> uploadImage(String filePath, String fileName) =>
      _guard('Uploaden', () async {
        final req = http.MultipartRequest('POST', Uri.parse('$base/uploads'));
        req.headers.addAll(await _h());
        req.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
        final streamed = await req.send();
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode != 200) throw Exception('bad status');
        return (jsonDecode(body) as Map<String, dynamic>)['url'].toString();
      });
}
