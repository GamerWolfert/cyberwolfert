import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/constants.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/browser_home.dart';

void main() {
  runApp(const CyberWolfertApp());
}

/// Root van de CyberWolfert Browser.
class CyberWolfertApp extends StatelessWidget {
  const CyberWolfertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..load()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (ctx, s, _) => MaterialApp(
          title: AppConfig.browserName,
          debugShowCheckedModeBanner: false,
          themeMode: s.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF29B6F6)),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: const Color(0xFF0B1020),
          ),
          home: const BrowserHomeScreen(),
        ),
      ),
    );
  }
}
