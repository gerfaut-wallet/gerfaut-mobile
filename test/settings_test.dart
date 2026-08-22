import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/state.dart';

import 'fakes.dart';

void main() {
  testWidgets('switching the theme applies it and persists the pref', (
    tester,
  ) async {
    final bridge = FakeBridge();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: const GerfautApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Light is the default.
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Dark'), 100);
    await tester.ensureVisible(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(bridge.appPrefs['mobile.theme'], 'dark');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(bridge.appPrefs['mobile.theme'], 'system');
  });
}
