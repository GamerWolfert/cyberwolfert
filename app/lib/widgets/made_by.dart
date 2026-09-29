import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../services/api_service.dart';

/// "v1.x • Made by GamerWolfertYT" — versie live van de backend.
class MadeBy extends StatefulWidget {
  final double fontSize;
  const MadeBy({super.key, this.fontSize = 12});

  @override
  State<MadeBy> createState() => _MadeByState();
}

class _MadeByState extends State<MadeBy> {
  String? _versie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiService();
      await api.resolveBase();
      final r = await http
          .get(Uri.parse('${api.base}/version'),
              headers: const {'ngrok-skip-browser-warning': '1'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && mounted) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _versie = 'v${j['version']}+${j['build']}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      [_versie, 'Made by ${AppConfig.maker} 🐺']
          .where((e) => e != null && e.isNotEmpty)
          .join(' • '),
      style: TextStyle(fontSize: widget.fontSize, color: Colors.white54),
    );
  }
}
