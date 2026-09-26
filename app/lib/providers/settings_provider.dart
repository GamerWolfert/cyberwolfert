import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Globale UI-state: thema + achtergrond, gesynchroniseerd met backend (per gebruiker).
class SettingsProvider extends ChangeNotifier {
  final ApiService api = ApiService();

  String theme = 'dark';
  String backgroundType = 'color';
  String backgroundValue = '#0B1020';
  String accentColor = '#E63946';
  bool loading = true;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final s = await api.loadSettings();
      theme = (s['theme'] ?? 'dark').toString();
      backgroundType = (s['background_type'] ?? 'color').toString();
      backgroundValue = (s['background_value'] ?? '#0B1020').toString();
      accentColor = (s['accent_color'] ?? '#E63946').toString();
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  Future<void> update({String? theme, String? type, String? value, String? accent}) async {
    if (theme != null) this.theme = theme;
    if (type != null) backgroundType = type;
    if (value != null) backgroundValue = value;
    if (accent != null) accentColor = accent;
    notifyListeners();
    try {
      await api.saveSettings({
        'theme': this.theme,
        'background_type': backgroundType,
        'background_value': backgroundValue,
        'accent_color': accentColor,
      });
    } catch (_) {}
  }

  Widget buildBackground({required Widget child}) {
    Widget bg;
    if (backgroundType == 'image' &&
        (backgroundValue.startsWith('http://') || backgroundValue.startsWith('https://'))) {
      bg = Image.network(backgroundValue, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: _hex('#0B1020')));
    } else {
      bg = Container(color: _hex(backgroundValue));
    }
    return Stack(fit: StackFit.expand, children: [Positioned.fill(child: bg), child]);
  }

  Color _hex(String hex) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFF0B1020);
    }
  }
}
