import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../providers/auth_provider.dart';

/// Alle netwerkcalls naar de backend (token automatisch mee, nooit adressen in fouten).
class ApiService {
  String get base => AppConfig.baseUrl;

  Future<Map<String, String>> _h({bool json = false}) async {
    final m = <String, String>{
      'ngrok-skip-browser-warning': '1',
    };
    if (json) m['Content-Type'] = 'application/json';
    final t = await AuthStore.get();
    if (t != null) m['Authorization'] = 'Bearer $t';
    return m;
  }

  Future<T> _guard<T>(String wat, Future<T> Function() fn) async {
    try {
      return await fn().timeout(const Duration(seconds: 15));
    } catch (_) {
      throw Exception('$wat is mislukt. Controleer de verbinding en probeer opnieuw.');
    }
  }

  Future<bool> health() async {
    try {
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

  // --- Generiek (voor WolfSyn e.a.) ---
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
      _guard('CyberWolf AI', () async {
        final r = await http.post(Uri.parse('$base/ai/chat'),
            headers: await _h(json: true),
            body: jsonEncode({'message': message, 'history': history}));
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.statusCode != 200) throw Exception('bad status');
        return (j['reply'] ?? '') as String;
      });

  Future<String> askAiWithImage(
      String message, List<Map<String, String>> history, String imagePath) =>
      _guard('CyberWolf AI', () async {
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
