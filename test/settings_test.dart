import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  testWidgets('wallet rows share one icon, the subtitle tells the kind', (
    tester,
  ) async {
    final bridge = FakeBridge(
      wallets: [
        makeMeta(id: 'w1', name: 'Cold storage'),
        makeMeta(
          id: 'w2',
          name: 'Donation address',
          kind: const SingleAddressKind(address: 'bc1qwatched'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: const GerfautApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Descriptor wallet'), 200);
    await tester.pumpAndSettle();

    expect(find.text('Descriptor wallet'), findsOneWidget);
    expect(find.text('Single address'), findsOneWidget);
    // One icon per row plus the section header, all the same glyph.
    expect(find.byIcon(LucideIcons.wallet), findsNWidgets(3));
    expect(find.byIcon(LucideIcons.mapPin), findsNothing);
  });
}
