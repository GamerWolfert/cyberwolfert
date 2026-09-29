import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthStore {
  static const _key = 'auth_token';
  static String? _cached;

  static Future<String?> get() async {
    if (_cached != null) return _cached;
    final p = await SharedPreferences.getInstance();
    _cached = p.getString(_key);
    return _cached;
  }

  static Future<void> set(String? token) async {
    _cached = token;
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove(_key);
    } else {
      await p.setString(_key, token);
    }
  }
}

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? user;
  bool loading = true;

  bool get loggedIn => user != null;
  String get naam =>
      (user?['displayName'] ?? user?['username'] ?? 'Gast').toString();

  /// Stabiele apparaat-ID voor device-ban/onthouden (eenmalig aangemaakt).
  static Future<String> deviceId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('device_id');
    if (id == null || id.isEmpty) {
      id =
          '${DateTime.now().millisecondsSinceEpoch}-${(1000 + (DateTime.now().microsecond % 9000))}';
      await p.setString('device_id', id);
    }
    return id;
  }

  /// NGrok toont anders een "bezoek deze site?"-pagina in plaats van JSON;
  /// die header slaat die waarschuwing over. API-adres: eerst proberen welk
  /// adres bereikbaar is (thuis LAN, buiten de tunnel).
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': '1',
  };

  Future<Uri> apiUri(String path, {bool force = false}) async {
    final api = ApiService();
    await api.resolveBase(force: force);
    return Uri.parse('${api.base}$path');
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final t = await AuthStore.get();
      if (t != null) {
        final r = await http
            .get(await apiUri('/auth/me'),
                headers: {'Authorization': 'Bearer $t', 'ngrok-skip-browser-warning': '1'})
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          user = (jsonDecode(r.body) as Map)['user'] as Map<String, dynamic>?;
        } else {
          await AuthStore.set(null);
          user = null;
        }
      }
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  Future<String?> _auth(String path, Map<String, dynamic> body) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http
            .post(await apiUri('/auth/$path', force: attempt > 0),
                headers: jsonHeaders, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.statusCode != 200) {
          return (j['error'] ?? 'Mislukt. Probeer opnieuw.').toString();
        }
        await AuthStore.set(j['token'] as String?);
        user = (j['user'] as Map?)?.cast<String, dynamic>();
        notifyListeners();
        return null;
      } catch (_) {
        if (attempt == 0) continue; // ander adres proberen (LAN ↔ tunnel)
      }
    }
    return 'Verbinding mislukt. Controleer of de backend bereikbaar is.';
  }

  Future<String?> register(String username, String password, String display,
      String email, String deviceId, bool remember) =>
      _auth('register', {
        'username': username,
        'password': password,
        'displayName': display,
        'email': email,
        'deviceId': deviceId,
        'deviceLabel': 'App',
        'remember': remember,
      });

  Future<String?> login(
      String username, String password, String deviceId, bool remember) =>
      _auth('login', {
        'username': username,
        'password': password,
        'deviceId': deviceId,
        'deviceLabel': 'App',
        'remember': remember,
      });

  Future<String?> googleStatus() async {
    try {
      final r = await http
          .get(await apiUri('/auth/google-status'),
              headers: {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['configured'] == true) ? null : 'Google-login is nog niet ingesteld (GOOGLE_CLIENT_ID ontbreekt).';
    } catch (_) {
      return 'Verbinding mislukt.';
    }
  }

  Future<void> logout() async {
    await AuthStore.set(null);
    user = null;
    notifyListeners();
  }
}
