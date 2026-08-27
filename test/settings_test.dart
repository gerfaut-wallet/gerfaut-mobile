import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/bridge.dart';
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

  testWidgets('the theme options carry a glyph each', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(settingsApp(FakeBridge()));
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.sun), findsOneWidget);
    expect(find.byIcon(LucideIcons.moon), findsOneWidget);
    expect(find.byIcon(LucideIcons.monitor), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    // Tapping the glyph selects the option like tapping its label.
    await tester.tap(find.byIcon(LucideIcons.moon));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.moon)).color,
      GerfautTokens.light.onPrimary,
    );
  });

  testWidgets('the display and wallet hints read as one sentence each', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(settingsApp(FakeBridge()));
    await tester.pumpAndSettle();

    expect(
      find.text('Shows the fiat value next to every amount.'),
      findsOneWidget,
    );
    expect(find.textContaining('IP address'), findsNothing);
    expect(
      find.text(
        'How many unused addresses Gerfaut scans past the last used one.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('20 is the norm'), findsNothing);

    // The price source hint only shows once fiat is on.
    expect(
      find.text('Serves the fiat value and the overview price.'),
      findsNothing,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Serves the fiat value and the overview price.'),
      findsOneWidget,
    );
    expect(find.textContaining('One request per minute'), findsNothing);
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

  group('display currency', () {
    /// Turns the fiat display on: the currency and source controls only
    /// exist once it is.
    Future<void> enableFiat(WidgetTester tester) async {
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
    }

    DropdownButton<FiatCurrency> currencyField(WidgetTester tester) {
      return tester.widget<DropdownButton<FiatCurrency>>(
        find.byType(DropdownButton<FiatCurrency>),
      );
    }

    InkWell sourcePill(WidgetTester tester, String label) {
      return tester.widget<InkWell>(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
    }

    testWidgets('every currency is offered, grouped by what quotes it', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();
      await enableFiat(tester);

      final items = currencyField(tester).items!;
      // Thirty currencies, in the core's order, plus one header each
      // for the group they belong to.
      expect(
        items.where((item) => item.value != null).map((item) => item.value),
        FiatCurrency.values,
      );
      final headers = items.where((item) => !item.enabled).toList();
      expect(headers, hasLength(2));
      expect(items.first, headers.first);
      // The seven every source quotes come first, then the header of
      // the ones CoinGecko alone serves.
      expect(items[8], headers.last);
    });

    testWidgets('the currency list reads group by group', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.byType(DropdownButton<FiatCurrency>));
      await tester.pumpAndSettle();

      expect(find.text('EVERY SOURCE'), findsOneWidget);
      expect(find.text('Euro'), findsWidgets);
      expect(find.text('US dollar'), findsOneWidget);

      // The second group sits below the fold of a phone-sized menu.
      await tester.scrollUntilVisible(
        find.text('COINGECKO ONLY'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('COINGECKO ONLY'), findsOneWidget);
      expect(find.text('Indian rupee'), findsOneWidget);
    });

    testWidgets('picking a currency saves it', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.byType(DropdownButton<FiatCurrency>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('US dollar'));
      await tester.pumpAndSettle();

      expect(currencyField(tester).value, FiatCurrency.usd);
      expect(bridge.appPrefs['display.fiat_currency'], 'usd');
    });

    testWidgets('a CoinGecko-only currency moves the source over', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.text('Kraken'));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs['display.fiat_source'], 'kraken');
      expect(sourcePill(tester, 'mempool.space').onTap, isNotNull);

      currencyField(tester).onChanged!(FiatCurrency.ngn);
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['display.fiat_currency'], 'ngn');
      expect(bridge.appPrefs['display.fiat_source'], 'coingecko');
      expect(
        find.text('CoinGecko is the only source that quotes NGN.'),
        findsOneWidget,
      );
      // The two sources that cannot quote it are out of reach, not
      // silently wrong.
      expect(sourcePill(tester, 'Kraken').onTap, isNull);
      expect(sourcePill(tester, 'mempool.space').onTap, isNull);
      expect(sourcePill(tester, 'CoinGecko').onTap, isNotNull);
      expect(
        tester.widget<Text>(find.text('Kraken')).style!.color,
        GerfautTokens.light.textMuted,
      );

      // Back to a currency everyone quotes: the sources return.
      currencyField(tester).onChanged!(FiatCurrency.chf);
      await tester.pumpAndSettle();
      expect(sourcePill(tester, 'Kraken').onTap, isNotNull);
      expect(find.textContaining('the only source that quotes'), findsNothing);
    });

    testWidgets('CoinGecko is credited while it serves the price', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();
      expect(find.text('Powered by CoinGecko'), findsNothing);

      await enableFiat(tester);
      expect(find.text('Powered by CoinGecko'), findsOneWidget);
      // The API terms ask for a legible line, not a hidden one.
      expect(
        tester.widget<Text>(find.text('Powered by CoinGecko')).style!.fontSize!,
        greaterThanOrEqualTo(10),
      );

      await tester.tap(find.text('Kraken'));
      await tester.pumpAndSettle();
      expect(find.text('Powered by CoinGecko'), findsNothing);
    });

    testWidgets('a disabled source announces itself as such', (tester) async {
      useTallSurface(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();
      await enableFiat(tester);

      currencyField(tester).onChanged!(FiatCurrency.krw);
      await tester.pumpAndSettle();

      final kraken = tester.getSemantics(find.text('Kraken'));
      expect(kraken.label, 'Kraken');
      expect(kraken.flagsCollection.isEnabled, Tristate.isFalse);
      final coingecko = tester.getSemantics(find.text('CoinGecko'));
      expect(coingecko.flagsCollection.isEnabled, Tristate.isTrue);
      expect(coingecko.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('public server choice', () {
    testWidgets('the public backend defaults to the automatic rotation', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Rotates over every public Esplora.'), findsOneWidget);
      // The hint says who answers and what else they serve.
      expect(find.textContaining('fee estimates'), findsOneWidget);

      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();

      final saved = bridge.savedBackends[Network.mainnet]! as PublicEsplora;
      expect(saved.server, isNull);
      expect(saved.toJson(), {'type': 'public_esplora'});
    });

    testWidgets('every server of the network is offered, protocol included', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(FakeBridge()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();

      // The seven mainnet servers, each labelled with its host.
      for (final server in defaultPublicServers[Network.mainnet]!) {
        expect(find.text(server.label), findsOneWidget);
      }
      // Three Esplora instances, four Electrum servers, each marked.
      expect(find.text('Esplora'), findsNWidgets(3));
      expect(find.text('Electrum'), findsNWidgets(4));
    });

    testWidgets('choosing a server stores its identifier', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('blockstream.info').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();

      final saved = bridge.savedBackends[Network.mainnet]! as PublicEsplora;
      expect(saved.server, 'blockstream.info');
      expect(saved.toJson(), {
        'type': 'public_esplora',
        'server': 'blockstream.info',
      });
    });

    testWidgets('an Electrum server says what it cannot serve', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(
        find.text('An Electrum server cannot serve a single-address wallet.'),
        findsNothing,
      );

      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>),
      );
      dropdown.onChanged!('electrum:frigate.2140.dev');
      await tester.pumpAndSettle();

      expect(
        find.text('An Electrum server cannot serve a single-address wallet.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
      expect(
        (bridge.savedBackends[Network.mainnet]! as PublicEsplora).server,
        'electrum:frigate.2140.dev',
      );
    });

    testWidgets('the choice is re-seeded when the network changes', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {
            Network.mainnet: PublicEsplora(server: 'blockstream.info'),
            Network.signet: PublicEsplora(server: 'mempool.emzy.de'),
          },
          appPrefs: {},
        ),
      );
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(
        tester.widget<DropdownButton<String?>>(
          find.byType(DropdownButton<String?>),
        ).value,
        'blockstream.info',
      );

      await tester.tap(find.text('Signet'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<DropdownButton<String?>>(
          find.byType(DropdownButton<String?>),
        ).value,
        'mempool.emzy.de',
      );
      // Signet has no frigate.2140.dev: the list follows the network.
      expect(find.text('frigate.2140.dev:50002'), findsNothing);
    });

    testWidgets('a network without a public server says so', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        settings: const Settings(
          activeNetwork: Network.regtest,
          backends: {},
          appPrefs: {},
        ),
      );
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String?>), findsNothing);
      expect(find.textContaining('No public server exists on Regtest'), findsOneWidget);
    });

    testWidgets('an unreachable catalogue degrades to a quiet line', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPublicServers = (_) {
        throw const BridgeException('not_initialized', 'call init first');
      };
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String?>), findsNothing);
      expect(find.textContaining('The server list is unavailable'), findsOneWidget);
      // The backend still saves: automatic is the fallback anyway.
      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
      expect(bridge.savedBackends[Network.mainnet], isA<PublicEsplora>());
    });
  });
}
