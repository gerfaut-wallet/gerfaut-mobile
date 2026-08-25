import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

Widget settingsApp(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const SettingsScreen(),
    ),
  );
}

/// A surface tall enough to build every settings section at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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

  testWidgets('the gap limit is seeded from the settings and committed', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {},
        gapLimit: 25,
      ),
    );
    await tester.pumpWidget(settingsApp(bridge));
    await tester.pumpAndSettle();

    // Seeded from the vault settings.
    expect(find.text('Gap limit'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '25'), '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(bridge.lastGapLimitSet, 45);
    expect(bridge.settings.gapLimit, 45);
    expect(find.text('Setting saved'), findsOneWidget);

    // Flush the snackbar timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('an invalid gap limit snaps back without noise', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge();
    await tester.pumpWidget(settingsApp(bridge));
    await tester.pumpAndSettle();

    // Out of range: nothing saved, the field returns to the current
    // value, no toast.
    await tester.enterText(find.widgetWithText(TextField, '20'), '600');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(bridge.lastGapLimitSet, isNull);
    expect(bridge.settings.gapLimit, 20);
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);
    expect(find.text('Setting saved'), findsNothing);

    // Cleared entirely: same silent return.
    await tester.enterText(find.widgetWithText(TextField, '20'), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(bridge.lastGapLimitSet, isNull);
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);
  });
}
