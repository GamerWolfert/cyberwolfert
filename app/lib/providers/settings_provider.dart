import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/startpage/night_scape.dart';

/// Globale UI-state: thema + achtergrond, gesynchroniseerd met backend (per gebruiker).
class SettingsProvider extends ChangeNotifier {
  final ApiService api = ApiService();

  String theme = 'dark';
  String backgroundType = 'color';
  String backgroundValue = '#050805';
  String accentColor = '#3CFF5C';
  bool loading = true;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final s = await api.loadSettings();
      theme = (s['theme'] ?? 'dark').toString();
      backgroundType = (s['background_type'] ?? 'color').toString();
      backgroundValue = (s['background_value'] ?? '#050805').toString();
      accentColor = (s['accent_color'] ?? '#3CFF5C').toString();
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
          errorBuilder: (_, __, ___) => Container(color: _hex('#050805')));
    } else if (backgroundType == 'theme') {
      bg = Container(decoration: BoxDecoration(gradient: themeGradient(backgroundValue)));
    } else if (backgroundValue.replaceAll(' ', '').toUpperCase() == '#050805') {
      // Standaard: geschilderd groen kosmisch landschap (AeroSurf-look).
      bg = const NightScape(child: SizedBox.expand());
    } else {
      bg = Container(color: _hex(backgroundValue));
    }
    return Stack(fit: StackFit.expand, children: [Positioned.fill(child: bg), child]);
  }

  /// Thema-presets als echte gradients (aero-groen, nachtblauw, pulse-rood...).
  static LinearGradient themeGradient(String name) {
    switch (name) {
      case 'pulse-red':
        return const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF3D0B16), Color(0xFF12060A), Color(0xFF080304)]);
      case 'midnight':
        return const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF101A33), Color(0xFF070B18), Color(0xFF03040A)]);
      case 'wolf-dark':
        return const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1E42), Color(0xFF071026), Color(0xFF040912)]);
      case 'aerosurf':
      default:
        return const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0B2E16), Color(0xFF061409), Color(0xFF030705)]);
    }
  }

  Color get accent {
    try {
      var h = accentColor.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFF3CFF5C);
    }
  }

  Color _hex(String hex) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFF050805);
    }
  }
}
