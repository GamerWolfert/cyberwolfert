import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/constants.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/browser_home.dart';
import 'services/notify_service.dart';

void main() {
  runApp(const CyberWolfertApp());
}

/// Root van de AeroSurf Browser.
class CyberWolfertApp extends StatefulWidget {
  const CyberWolfertApp({super.key});

  @override
  State<CyberWolfertApp> createState() => _CyberWolfertAppState();
}

class _CyberWolfertAppState extends State<CyberWolfertApp> {
  final AuthProvider auth = AuthProvider();
  final SettingsProvider settings = SettingsProvider();

  @override
  void initState() {
    super.initState();
    // Eerst inloggen, dán instellingen laden: anders wordt de achtergrond
    // van de gast-laag geladen en lijkt hij bij elke herstart weg.
    auth.load().then((_) {
      if (mounted) settings.load();
      // Meldingsgeluiden + systeemmeldingen (berichten, mail, verzoeken).
      NotifyService.start();
    });
  }

  @override
  void dispose() {
    auth.dispose();
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: Consumer<SettingsProvider>(
        builder: (ctx, s, _) => MaterialApp(
          title: AppConfig.browserName,
          debugShowCheckedModeBanner: false,
          themeMode: s.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: s.accent),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: const Color(0xFF050805),
            colorScheme: ColorScheme.fromSeed(
                seedColor: s.accent, brightness: Brightness.dark),
          ),
          home: const BrowserHomeScreen(),
        ),
      ),
    );
  }
}
