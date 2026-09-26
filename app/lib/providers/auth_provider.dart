import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

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

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final t = await AuthStore.get();
      if (t != null) {
        final r = await http.get(
          Uri.parse('${AppConfig.baseUrl}/auth/me'),
          headers: {'Authorization': 'Bearer $t'},
        ).timeout(const Duration(seconds: 8));
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
    try {
      final r = await http
          .post(Uri.parse('${AppConfig.baseUrl}/auth/$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) {
        return (j['error'] ?? 'Mislukt. Probeer opnieuw.').toString();
      }
      await AuthStore.set(j['token'] as String?);
      user = (j['user'] as Map?)?.cast<String, dynamic>();
      notifyListeners();
      return null;
    } catch (_) {
      return 'Verbinding mislukt. Controleer of de backend bereikbaar is.';
    }
  }

  Future<String?> register(String username, String password, String display) =>
      _auth('register', {'username': username, 'password': password, 'displayName': display});

  Future<String?> login(String username, String password) =>
      _auth('login', {'username': username, 'password': password});

  Future<String?> googleStatus() async {
    try {
      final r = await http
          .get(Uri.parse('${AppConfig.baseUrl}/auth/google-status'))
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
