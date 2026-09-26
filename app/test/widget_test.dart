import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyberwolfert_browser/main.dart';
import 'package:cyberwolfert_browser/widgets/app_logo.dart';
import 'package:cyberwolfert_browser/widgets/startpage/start_page.dart';

void main() {
  testWidgets('Startpagina toont logo, zoeken en tegels', (WidgetTester tester) async {
    await tester.pumpWidget(const CyberWolfertApp());
    await tester.pump(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(StartPage), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(AppLogo), findsWidgets);
    await tester.pumpWidget(Container());
    await tester.pump();
  });
}
