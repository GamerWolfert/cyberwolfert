import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cyberwolfert_browser/providers/settings_provider.dart';
import 'package:cyberwolfert_browser/widgets/app_logo.dart';
import 'package:cyberwolfert_browser/widgets/startpage/start_page.dart';

void main() {
  testWidgets('Startpagina toont logo, zoeken en tegels', (WidgetTester tester) async {
    // Alleen de startpagina (met de settings-provider die hij nodig heeft):
    // de hele app eromheen opent diensten (mic, websocket) die in een test
    // geen weg hebben.
    final settings = SettingsProvider();
    await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(body: StartPage(onOpenUrl: (_) {})),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(StartPage), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(SeekLogo), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    settings.dispose();
  });
}
