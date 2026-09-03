import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/about_section.dart';
import 'package:gerfaut/screens/settings/network_section.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:gerfaut/widgets/wallet_icon.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

/// The settings opened on [section], or on the root list of sections.
Widget settingsApp(FakeBridge bridge, {SettingsSection? section}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: SettingsScreen(section: section),
    ),
  );
}

/// A surface tall enough to build every settings section at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Two made-up SHA-256 fingerprints, in the shape the core stores them:
/// thirty-two uppercase hex pairs joined by colons.
const String _fingerprint =
    '4B:CD:74:1F:2A:39:58:67:76:85:94:A3:B2:C1:D0:EF:'
    '0E:1D:2C:3B:4A:59:68:77:86:95:A4:B3:C2:D1:E0:FF';
const String _otherFingerprint =
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    '99:88:77:66:55:44:33:22:11:00:FF:EE:DD:CC:BB:AA';

/// The public server picker, for the options it offers.
GerfautSelect<String?> serverField(WidgetTester tester) {
  return tester.widget<GerfautSelect<String?>>(
    find.byType(GerfautSelect<String?>),
  );
}

void main() {
  testWidgets('switching the theme applies it and persists the pref', (
    tester,
  ) async {
    // A vault opened before: the welcome tour is behind this user.
    final bridge = FakeBridge(
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
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
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(
      settingsApp(FakeBridge(), section: SettingsSection.general),
    );
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
    await tester.pumpWidget(
      settingsApp(FakeBridge(), section: SettingsSection.wallets),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'How many unused addresses Gerfaut scans past the last used one.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('20 is the norm'), findsNothing);

    await tester.pumpWidget(
      settingsApp(FakeBridge(), section: SettingsSection.general),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Shows the fiat value next to every amount.'),
      findsOneWidget,
    );
    expect(find.textContaining('IP address'), findsNothing);

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

  testWidgets('wallet rows wear their icon, the subtitle tells the kind', (
    tester,
  ) async {
    final bridge = FakeBridge(
      wallets: [
        makeMeta(id: 'w1', name: 'Cold storage'),
        makeMeta(
          id: 'w2',
          name: 'Donation address',
          icon: WalletIcon.mapPin,
          kind: const SingleAddressKind(address: 'bc1qwatched'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
        child: const GerfautApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallets'));
    await tester.pumpAndSettle();

    expect(find.text('Descriptor wallet'), findsOneWidget);
    expect(find.text('Single address'), findsOneWidget);
    // The section header and the first row wear the generic wallet;
    // the second row wears the glyph its owner picked.
    expect(find.byIcon(LucideIcons.wallet), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.mapPin), findsOneWidget);
  });

  group('wallet icons', () {
    testWidgets('the icon action offers the seven glyphs and stores the pick', (
      tester,
    ) async {
      useTallSurface(tester);
      final handle = tester.ensureSemantics();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Icon'));
      await tester.pumpAndSettle();

      expect(find.text('Wallet icon'), findsOneWidget);
      // Seven choices, in the core's order, each named for the screen
      // reader and sized for a thumb; the current one announced as such,
      // and every one activatable by that reader, not only by a finger.
      for (final icon in WalletIcon.values) {
        final tile = find.bySemanticsLabel(icon.label);
        expect(tile, findsOneWidget, reason: icon.label);
        final size = tester.getSize(tile);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        final semantics = tester.getSemantics(tile);
        expect(
          semantics.flagsCollection.isSelected,
          icon == WalletIcon.wallet ? Tristate.isTrue : Tristate.isFalse,
          reason: icon.label,
        );
        expect(
          semantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: icon.label,
        );
      }
      expect(find.byType(WalletIconPicker), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Snowflake'));
      await tester.pumpAndSettle();

      expect(bridge.iconCalls, [(id: 'w1', icon: WalletIcon.snowflake)]);
      expect(find.byType(WalletIconPicker), findsNothing);
      // The row wears it at once, and the change is confirmed.
      expect(find.byIcon(LucideIcons.snowflake), findsOneWidget);
      expect(find.text('Setting saved'), findsOneWidget);
      handle.dispose();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('picking the icon already worn writes nothing', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Icon'));
      await tester.pumpAndSettle();
      // The grid's wallet tile, not the row's glyph or the card's.
      await tester.tap(
        find.descendant(
          of: find.byType(WalletIconPicker),
          matching: find.byIcon(LucideIcons.wallet),
        ),
      );
      await tester.pumpAndSettle();

      expect(bridge.iconCalls, isEmpty);
      expect(find.byType(WalletIconPicker), findsNothing);
    });
  });

  group('wallet order', () {
    FakeBridge two() => FakeBridge(
      wallets: [
        makeMeta(id: 'w1', name: 'Cold storage'),
        makeMeta(id: 'w2', name: 'Spending'),
      ],
    );

    /// Where a wallet's name sits, top to bottom.
    double top(WidgetTester tester, String name) =>
        tester.getTopLeft(find.text(name)).dy;

    testWidgets('dragging a row by its handle stores the new order', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = two();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      final handles = find.byIcon(LucideIcons.gripVertical);
      expect(handles, findsNWidgets(2));
      expect(top(tester, 'Cold storage'), lessThan(top(tester, 'Spending')));

      // The handle starts the drag at once: no hold to wait out.
      // Three quarters of a row down: far enough for the row to take
      // the next one's place, not so far that it overshoots it.
      final pitch = top(tester, 'Spending') - top(tester, 'Cold storage');
      final from = tester.getCenter(handles.first);
      final to = from + Offset(0, pitch * 0.75);
      final gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 30));
      await tester.pumpAndSettle();
      await gesture.moveTo(to);
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      // The ids of the rows shown, in their new order, and nothing else.
      expect(bridge.reorderCalls, [
        ['w2', 'w1'],
      ]);
      expect(bridge.wallets.map((w) => w.id), ['w2', 'w1']);
      expect(top(tester, 'Spending'), lessThan(top(tester, 'Cold storage')));
    });

    testWidgets('a refused order falls back and says why', (tester) async {
      useTallSurface(tester);
      final bridge = two();
      bridge.onReorderWallets = (_) =>
          throw const BridgeException('vault', 'the vault is read only');
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      final handles = find.byIcon(LucideIcons.gripVertical);
      // Three quarters of a row down: far enough for the row to take
      // the next one's place, not so far that it overshoots it.
      final pitch = top(tester, 'Spending') - top(tester, 'Cold storage');
      final from = tester.getCenter(handles.first);
      final to = from + Offset(0, pitch * 0.75);
      final gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 30));
      await tester.pumpAndSettle();
      await gesture.moveTo(to);
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(bridge.reorderCalls, hasLength(1));
      expect(find.text('the vault is read only'), findsOneWidget);
      // Back where the vault has it.
      expect(top(tester, 'Cold storage'), lessThan(top(tester, 'Spending')));
    });

    testWidgets('one wallet has no handle', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(
          FakeBridge(wallets: [makeMeta()]),
          section: SettingsSection.wallets,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.gripVertical), findsNothing);
    });
  });

  testWidgets(
    'removing a wallet asks in a panel, the buttons under the words',
    (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta(name: 'Cold storage')]);
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      const sentence =
          'You are removing "Cold storage" from Gerfaut. This only stops '
          'watching. Nothing moves on chain.';
      final notice = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(notice.tone, NoticeTone.info);
      expect(notice.actionsBelow, isTrue);
      expect(find.text(sentence), findsOneWidget);

      // The sentence has the whole width; the two buttons share a row of
      // their own under it, the way out first and the destructive one at
      // the end.
      final words = tester.getRect(find.text(sentence));
      final cancel = tester.getRect(find.widgetWithText(GhostButton, 'Cancel'));
      final remove = tester.getRect(
        find.widgetWithText(DangerButton, 'Remove wallet'),
      );
      final panel = tester.getRect(find.byType(GerfautNotice));
      expect(words.width, greaterThan(panel.width * 0.7));
      expect(cancel.top, greaterThanOrEqualTo(words.bottom));
      expect(remove.top, greaterThanOrEqualTo(words.bottom));
      expect(cancel.center.dy, closeTo(remove.center.dy, 1));
      expect(cancel.right, lessThan(remove.left));
      expect(remove.right, closeTo(panel.right - 12, 1));
      expect(remove.height, 44);

      // Nothing has moved yet; Cancel closes the panel and keeps the row.
      expect(bridge.wallets, hasLength(1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(GerfautNotice), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove wallet'));
      await tester.pumpAndSettle();
      expect(bridge.wallets, isEmpty);
      expect(find.text('Wallet removed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );

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
    await tester.pumpWidget(
      settingsApp(bridge, section: SettingsSection.wallets),
    );
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
    await tester.pumpWidget(
      settingsApp(bridge, section: SettingsSection.wallets),
    );
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

    GerfautSelect<FiatCurrency> currencyField(WidgetTester tester) {
      return tester.widget<GerfautSelect<FiatCurrency>>(
        find.byType(GerfautSelect<FiatCurrency>),
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
      await tester.pumpWidget(
        settingsApp(FakeBridge(), section: SettingsSection.general),
      );
      await tester.pumpAndSettle();
      await enableFiat(tester);

      final groups = currencyField(tester).groups;
      // Thirty currencies, in the core's order, in two named groups.
      expect(groups, hasLength(2));
      expect([
        for (final group in groups) ...group.items.map((i) => i.value),
      ], FiatCurrency.values);
      // The seven every source quotes come first, then the ones
      // CoinGecko alone serves.
      expect(groups.first.label, 'Every source');
      expect(groups.first.items, hasLength(7));
      expect(groups.last.label, 'CoinGecko only');
      expect(groups.last.items, hasLength(23));
    });

    testWidgets('the currency list reads group by group', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(FakeBridge(), section: SettingsSection.general),
      );
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.byType(GerfautSelect<FiatCurrency>));
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.general),
      );
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.byType(GerfautSelect<FiatCurrency>));
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.general),
      );
      await tester.pumpAndSettle();
      await enableFiat(tester);

      await tester.tap(find.text('Kraken'));
      await tester.pumpAndSettle();
      expect(bridge.appPrefs['display.fiat_source'], 'kraken');
      expect(sourcePill(tester, 'mempool.space').onTap, isNotNull);

      currencyField(tester).onChanged(FiatCurrency.ngn);
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
      currencyField(tester).onChanged(FiatCurrency.chf);
      await tester.pumpAndSettle();
      expect(sourcePill(tester, 'Kraken').onTap, isNotNull);
      expect(find.textContaining('the only source that quotes'), findsNothing);
    });

    testWidgets('CoinGecko is credited while it serves the price', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(FakeBridge(), section: SettingsSection.general),
      );
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
      await tester.pumpWidget(
        settingsApp(FakeBridge(), section: SettingsSection.general),
      );
      await tester.pumpAndSettle();
      await enableFiat(tester);

      currencyField(tester).onChanged(FiatCurrency.krw);
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      // The Tor card offers an "Automatic" of its own: this one is the
      // server picker's.
      expect(
        find.descendant(
          of: find.byType(GerfautSelect<String?>),
          matching: find.text('Automatic'),
        ),
        findsOneWidget,
      );
      expect(find.text('Rotates over every public Esplora.'), findsOneWidget);
      // The hint says who answers, and nothing about fee estimates: the
      // app no longer serves any.
      expect(find.textContaining('fee estimates'), findsNothing);

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
      await tester.pumpWidget(
        settingsApp(FakeBridge(), section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      final items = serverField(tester).items;
      // The automatic rotation, then every mainnet server the core
      // lists, in its order, each labelled with its host.
      expect(items.first.title, 'Automatic');
      expect(items.first.value, isNull);
      expect(
        items.skip(1).map((item) => item.title).toList(),
        defaultPublicServers[Network.mainnet]!.map((s) => s.label).toList(),
      );
      // Three Esplora instances, eight Electrum servers, each marked.
      expect(items.where((i) => i.subtitle == 'Esplora'), hasLength(3));
      expect(
        items.where((i) => i.subtitle?.startsWith('Electrum') ?? false),
        hasLength(8),
      );
    });

    testWidgets('choosing a server stores its identifier', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GerfautSelect<String?>));
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('An Electrum server cannot serve a single-address wallet.'),
        findsNothing,
      );

      final field = tester.widget<GerfautSelect<String?>>(
        find.byType(GerfautSelect<String?>),
      );
      field.onChanged('electrum:frigate.2140.dev');
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<GerfautSelect<String?>>(find.byType(GerfautSelect<String?>))
            .value,
        'blockstream.info',
      );

      await tester.tap(find.text('Signet'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<GerfautSelect<String?>>(find.byType(GerfautSelect<String?>))
            .value,
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
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GerfautSelect<String?>), findsNothing);
      expect(
        find.textContaining('No public server exists on Regtest'),
        findsOneWidget,
      );
    });

    testWidgets('a self-signed server says so before it is picked', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      final items = serverField(tester).items;
      final selfSigned = items.firstWhere(
        (item) => item.title == 'bitcoin.lu.ke:50002',
      );
      expect(selfSigned.subtitle, 'Electrum · signs its own certificate');
      // A server a public authority vouches for says nothing more.
      expect(
        items.firstWhere((i) => i.title == 'frigate.2140.dev:50002').subtitle,
        'Electrum',
      );

      // Picked, it repeats it under the field: the hint line closes
      // with the menu.
      serverField(tester).onChanged('electrum:bitcoin.lu.ke');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This server signs its own certificate. Gerfaut shows you its '
          'fingerprint before it connects.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unreachable catalogue degrades to a quiet line', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPublicServers = (_) {
        throw const BridgeException('not_initialized', 'call init first');
      };
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GerfautSelect<String?>), findsNothing);
      expect(
        find.textContaining('The server list is unavailable'),
        findsOneWidget,
      );
      // The backend still saves: automatic is the fallback anyway.
      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
      expect(bridge.savedBackends[Network.mainnet], isA<PublicEsplora>());
    });
  });

  group('electrum certificates', () {
    /// A workspace already pointed at a self-hosted Electrum server, so
    /// saving the backend is one tap.
    FakeBridge ownElectrum({Map<String, String> certs = const {}}) {
      return FakeBridge(
        settings: Settings(
          activeNetwork: Network.mainnet,
          backends: const {
            Network.mainnet: CustomElectrum(url: 'ssl://node.local:50002'),
          },
          appPrefs: const {},
          electrumCerts: certs,
        ),
      );
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
    }

    const unknown = UnknownCertificate(
      fingerprint: _fingerprint,
      reason:
          'self-signed, or signed by an authority this machine does '
          'not know',
      subject: 'CN=node.local',
      expires: 1893456000,
    );

    testWidgets('an unvouched certificate is shown before anything is saved', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onInspectCertificate = (_) => unknown;
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      // Checked over the endpoint the backend is about to use.
      expect(bridge.inspectedCertificates, ['ssl://node.local:50002']);
      expect(
        find.text('This server signs its own certificate'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'No public authority vouches for the certificate of node.local:50002',
        ),
        findsOneWidget,
      );

      // The fingerprint, in mono, in rows of eight byte pairs.
      final digits = tester.widget<Text>(
        find.text(groupFingerprint(_fingerprint)),
      );
      expect(digits.style!.fontFamily, GerfautTokens.light.data.fontFamily);
      expect(groupFingerprint(_fingerprint).split('\n'), hasLength(4));

      // What the certificate says about itself, and why nothing vouches.
      expect(
        find.text(
          'Why it is asked: self-signed, or signed by an authority this '
          'machine does not know',
        ),
        findsOneWidget,
      );
      expect(find.text('Subject: CN=node.local'), findsOneWidget);
      expect(
        find.text('Valid until: ${formatTimestamp(1893456000)}'),
        findsOneWidget,
      );
      // And how to read the same string off the server itself.
      expect(
        find.text('openssl x509 -noout -fingerprint -sha256 -in <cert>'),
        findsOneWidget,
      );

      // Nothing is decided yet.
      expect(bridge.trustedCertificates, isEmpty);
      expect(bridge.savedBackends, isEmpty);
    });

    testWidgets('cancelling trusts nothing and saves nothing', (tester) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onInspectCertificate = (_) => unknown;
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('This server signs its own certificate'), findsNothing);
      expect(bridge.trustedCertificates, isEmpty);
      expect(bridge.savedBackends, isEmpty);
      expect(bridge.settings.electrumCerts, isEmpty);
      expect(find.text('Trusted certificates'), findsNothing);
    });

    testWidgets('accepting records the fingerprint, then saves', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onInspectCertificate = (_) => unknown;
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      await tester.tap(find.text('Accept and save'));
      await tester.pumpAndSettle();

      expect(bridge.trustedCertificates, [
        (url: 'ssl://node.local:50002', fingerprint: _fingerprint),
      ]);
      expect(
        (bridge.savedBackends[Network.mainnet]! as CustomElectrum).url,
        'ssl://node.local:50002',
      );
      // Recorded against the socket, and listed from there on.
      expect(bridge.settings.electrumCerts, {'node.local:50002': _fingerprint});
      expect(find.text('Trusted certificates'), findsOneWidget);
    });

    testWidgets('a certificate a public authority vouches for asks nothing', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.text('This server signs its own certificate'), findsNothing);
      expect(bridge.trustedCertificates, isEmpty);
      expect(bridge.savedBackends[Network.mainnet], isA<CustomElectrum>());
    });

    testWidgets('a plain TCP server is saved, and said so calmly', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onInspectCertificate = (_) => const NotTlsCertificate();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(bridge.savedBackends[Network.mainnet], isA<CustomElectrum>());
      expect(
        find.text(
          'Plain TCP, no certificate: what Gerfaut asks this server and '
          'what it answers travel in the clear.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a server that does not answer is saved anyway', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onInspectCertificate = (_) =>
          const UnreachableCertificate(detail: 'connection refused');
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(bridge.savedBackends[Network.mainnet], isA<CustomElectrum>());
      expect(
        find.text(
          'The certificate could not be checked yet. Gerfaut asks about it '
          'on the first connection.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a changed certificate is refused, and never by default', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum(
        certs: const {'node.local:50002': _fingerprint},
      );
      bridge.onInspectCertificate = (_) => const ChangedCertificate(
        stored: _fingerprint,
        presented: _otherFingerprint,
      );
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.text("This server's certificate changed"), findsOneWidget);
      expect(
        find.textContaining(
          'node.local:50002 was accepted with one certificate and now '
          'presents another',
        ),
        findsOneWidget,
      );
      // One panel component carries both tones, so no caller derives
      // its own — and this one is red, which is what a fingerprint that
      // changed under you is for.
      expect(
        tester
            .widget<GerfautNotice>(
              find.ancestor(
                of: find.textContaining('was accepted with one certificate'),
                matching: find.byType(GerfautNotice),
              ),
            )
            .tone,
        NoticeTone.alert,
      );
      // Both fingerprints, side by side, so the difference is visible.
      expect(find.text('ACCEPTED BEFORE'), findsOneWidget);
      expect(find.text('PRESENTED NOW'), findsOneWidget);
      expect(find.text(groupFingerprint(_otherFingerprint)), findsOneWidget);
      // Backing out is the prominent action, trusting is not.
      expect(find.widgetWithText(PrimaryButton, 'Cancel'), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryButton, 'Trust the new certificate'),
        findsNothing,
      );

      // One tap accepts nothing: it only asks again, in so many words.
      await tester.tap(find.text('Trust the new certificate'));
      await tester.pumpAndSettle();
      expect(bridge.trustedCertificates, isEmpty);
      expect(
        find.textContaining('Do it only if you know why it changed.'),
        findsOneWidget,
      );

      // Backing out at the second step leaves everything as it was.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bridge.trustedCertificates, isEmpty);
      expect(bridge.savedBackends, isEmpty);
      expect(bridge.settings.electrumCerts, {'node.local:50002': _fingerprint});
    });

    testWidgets('the new certificate is taken only after two deliberate taps', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum(
        certs: const {'node.local:50002': _fingerprint},
      );
      bridge.onInspectCertificate = (_) => const ChangedCertificate(
        stored: _fingerprint,
        presented: _otherFingerprint,
      );
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();
      await save(tester);

      await tester.tap(find.text('Trust the new certificate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust it anyway'));
      await tester.pumpAndSettle();

      expect(bridge.trustedCertificates, [
        (url: 'ssl://node.local:50002', fingerprint: _otherFingerprint),
      ]);
      expect(bridge.savedBackends[Network.mainnet], isA<CustomElectrum>());
      expect(bridge.settings.electrumCerts, {
        'node.local:50002': _otherFingerprint,
      });
    });

    testWidgets('accepted certificates are listed, and forgotten on request', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum(
        certs: const {'node.local:50002': _fingerprint},
      );
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trusted certificates'), findsOneWidget);
      expect(find.text('node.local:50002'), findsOneWidget);
      expect(find.text(groupFingerprint(_fingerprint)), findsOneWidget);

      // Forgetting asks first.
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      expect(bridge.forgottenCertificates, isEmpty);
      expect(
        find.text(
          'Gerfaut asks again the next time it connects to node.local:50002.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bridge.forgottenCertificates, isEmpty);
      expect(bridge.settings.electrumCerts, isNotEmpty);

      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget certificate'));
      await tester.pumpAndSettle();

      expect(bridge.forgottenCertificates, ['node.local:50002']);
      expect(bridge.settings.electrumCerts, isEmpty);
      // The section goes with the last certificate it listed.
      expect(find.text('Trusted certificates'), findsNothing);
    });

    testWidgets('every electrum server is checked before it is saved', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      // A public Esplora is reached over the web PKI like any web site:
      // there is nothing to settle.
      await save(tester);
      expect(bridge.inspectedCertificates, isEmpty);

      // Every Electrum server is checked, whether the catalogue calls it
      // self-signed or not: what it presents today is what counts.
      serverField(tester).onChanged('electrum:frigate.2140.dev');
      await tester.pumpAndSettle();
      await save(tester);
      expect(bridge.inspectedCertificates, ['ssl://frigate.2140.dev:50002']);

      serverField(tester).onChanged('electrum:bitcoin.lu.ke');
      await tester.pumpAndSettle();
      await save(tester);
      expect(bridge.inspectedCertificates, [
        'ssl://frigate.2140.dev:50002',
        'ssl://bitcoin.lu.ke:50002',
      ]);
    });
  });

  group('the Tor card', () {
    FakeBridge withTor(TorMode mode) {
      return FakeBridge(
        settings: Settings(
          activeNetwork: Network.mainnet,
          backends: const {},
          appPrefs: const {},
          tor: TorSettings(mode: mode),
        ),
      );
    }

    testWidgets('the system proxy is named for what it is on a phone', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(withTor(TorMode.system), section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      // Any app may hold the local port first and answer for the
      // server: the card says so, and says what Automatic does about it.
      expect(
        find.text(
          'Only the Tor on this device, at 127.0.0.1:9050. On a phone any '
          'app can answer on that port and pose as Tor, which is why '
          'Automatic never falls back to it on Android.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('automatic is the built-in client and nothing else', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        settingsApp(withTor(TorMode.auto), section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      // On Android the core never falls back to a local port under
      // Automatic: a Tor app on the phone is used only when chosen.
      expect(
        find.text(
          'The built-in Tor. A Tor app on this device is used only when '
          'you choose it below.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('if it answers'), findsNothing);
      expect(find.textContaining('built-in Tor first'), findsNothing);
    });

    testWidgets('a build without its own Tor says what to choose', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withTor(TorMode.auto);
      bridge.onTorStatus = (tor) => TorStatus(
        mode: tor.mode,
        socksProxy: '127.0.0.1:9050',
        via: null,
        socks: null,
        running: false,
        bootstrapped: false,
        bootstrapPercent: 0,
        error: null,
        embeddedAvailable: false,
      );
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.network),
      );
      await tester.pumpAndSettle();

      // Starting Orbot is not enough on its own: Automatic would still
      // not use it, so the card names the mode to pick.
      expect(
        find.text(
          'An address ending in .onion goes through Tor. This build has no '
          'Tor of its own: choose System below, with a Tor app such as '
          'Orbot running on this device.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('start Tor or Orbot first'), findsNothing);
    });
  });

  group('scanning a server address', () {
    /// What the form says of a scanned onion address, under the default
    /// Tor mode.
    const onionNote =
        'A Tor hidden service: reached through Tor only (mode: Automatic).';

    /// The settings screen with the camera replaced by a button that
    /// hands one frame over, the way a printed code in front of the
    /// lens does.
    Widget settingsWithCamera(FakeBridge bridge, String frame) {
      return ProviderScope(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: SettingsScreen(
            section: SettingsSection.network,
            cameraBuilder: (onFrame) => TextButton(
              onPressed: () => onFrame(frame),
              child: const Text('frame'),
            ),
          ),
        ),
      );
    }

    /// A workspace already pointed at an Electrum server over TLS: the
    /// form a scan comes to overwrite.
    FakeBridge ownElectrum() {
      return FakeBridge(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {
            Network.mainnet: CustomElectrum(url: 'ssl://node.local:50002'),
          },
          appPrefs: {},
        ),
      );
    }

    Future<void> scan(WidgetTester tester) async {
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('frame'));
      await tester.pumpAndSettle();
    }

    /// What every field of the form holds, in reading order: the
    /// backend fields first, the gap limit last.
    List<String> fieldTexts(WidgetTester tester) {
      return tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller!.text)
          .toList();
    }

    /// Where the TLS toggle of the Electrum form stands.
    bool tlsOn(WidgetTester tester) {
      return tester
          .widget<Switch>(
            find.descendant(
              of: find
                  .ancestor(of: find.text('TLS'), matching: find.byType(Row))
                  .first,
              matching: find.byType(Switch),
            ),
          )
          .value;
    }

    testWidgets('the one-liner a node prints fills the form as scanned', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onParseBackend = (_) => const ScannedBackend(
        kind: 'electrum',
        url: 'tcp://gerfautexample123.onion:50001',
        host: 'gerfautexample123.onion',
        port: 50001,
        tls: false,
        onion: true,
      );
      await tester.pumpWidget(
        settingsWithCamera(bridge, 'gerfautexample123.onion:50001:t'),
      );
      await tester.pumpAndSettle();
      expect(tlsOn(tester), isTrue);

      // The same scanner as the wallet import, told what it is for.
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.text(NetworkSection.backendScanCaption), findsOneWidget);
      await tester.tap(find.text('frame'));
      await tester.pumpAndSettle();

      // Read by the core, never by the screen.
      expect(bridge.parsedBackends, ['gerfautexample123.onion:50001:t']);
      expect(fieldTexts(tester).take(2), ['gerfautexample123.onion', '50001']);
      expect(tlsOn(tester), isFalse);
      // What the core made of the address is said under the fields,
      // with the Tor mode in force; nothing is saved or switched for it.
      expect(find.text(onionNote), findsOneWidget);
      expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      expect(bridge.savedBackends, isEmpty);
      expect(bridge.torSettingsCalls, isEmpty);

      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
      expect(
        (bridge.savedBackends[Network.mainnet]! as CustomElectrum).url,
        'tcp://gerfautexample123.onion:50001',
      );
    });

    testWidgets('the onion fact names the Tor mode in force', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {
            Network.mainnet: CustomElectrum(url: 'ssl://node.local:50002'),
          },
          appPrefs: {},
          tor: TorSettings(mode: TorMode.embedded),
        ),
      );
      bridge.onParseBackend = (_) => const ScannedBackend(
        kind: 'esplora',
        url: 'http://gerfautexample123.onion/api',
        host: 'gerfautexample123.onion',
        port: null,
        tls: false,
        onion: true,
      );
      await tester.pumpWidget(
        settingsWithCamera(bridge, 'http://gerfautexample123.onion/api'),
      );
      await tester.pumpAndSettle();

      await scan(tester);

      // An Esplora endpoint on an onion address: the note sits under
      // its URL field just the same.
      expect(find.text('SERVER URL'), findsOneWidget);
      expect(
        find.text(
          'A Tor hidden service: reached through Tor only (mode: Built-in).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the onion fact goes with the fields it described', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onParseBackend = (_) => const ScannedBackend(
        kind: 'electrum',
        url: 'tcp://gerfautexample123.onion:50001',
        host: 'gerfautexample123.onion',
        port: 50001,
        tls: false,
        onion: true,
      );
      await tester.pumpWidget(
        settingsWithCamera(bridge, 'gerfautexample123.onion:50001:t'),
      );
      await tester.pumpAndSettle();
      await scan(tester);
      expect(find.text(onionNote), findsOneWidget);

      // A keystroke in the host: the fields no longer hold what was
      // scanned, so the fact no longer describes them.
      await tester.enterText(find.byType(TextField).first, 'node.local');
      await tester.pumpAndSettle();
      expect(find.text(onionNote), findsNothing);

      // Scanned again, then another backend option chosen: gone again.
      await scan(tester);
      expect(find.text(onionNote), findsOneWidget);
      await tester.tap(find.text('My own Esplora'));
      await tester.pumpAndSettle();
      expect(find.text(onionNote), findsNothing);
    });

    testWidgets('an Esplora endpoint scanned here switches the choice', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      bridge.onParseBackend = (_) => const ScannedBackend(
        kind: 'esplora',
        url: 'https://esplora.example.org/api',
        host: 'esplora.example.org',
        port: null,
        tls: true,
        onion: false,
      );
      await tester.pumpWidget(
        settingsWithCamera(bridge, 'https://esplora.example.org/api'),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOST'), findsOneWidget);

      await scan(tester);

      // Refusing it would be pedantic: the QR says which backend it is.
      expect(find.text('SERVER URL'), findsOneWidget);
      expect(find.text('HOST'), findsNothing);
      expect(fieldTexts(tester).first, 'https://esplora.example.org/api');
      // A plain host on the web: nothing to say about Tor.
      expect(find.byIcon(LucideIcons.eyeOff), findsNothing);

      await tester.tap(find.text('Save backend'));
      await tester.pumpAndSettle();
      expect(
        (bridge.savedBackends[Network.mainnet]! as CustomEsplora).url,
        'https://esplora.example.org/api',
      );
    });

    testWidgets('wallet material is refused in the words of the core', (
      tester,
    ) async {
      useTallSurface(tester);
      const reason =
          'this is an extended public key, not the address of a server';
      final bridge = ownElectrum();
      bridge.onParseBackend = (_) =>
          throw const BridgeException('server', reason);
      await tester.pumpWidget(
        settingsWithCamera(bridge, 'xpub661MyMwAqRbcFexample'),
      );
      await tester.pumpAndSettle();

      await scan(tester);

      expect(find.text(reason), findsOneWidget);
      // A hint under the field, not a panel — but announced: it lands
      // in reaction to a scan, the camera has closed by then, and
      // nothing else on screen says the code was turned down.
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text(reason)).flagsCollection.isLiveRegion,
        isTrue,
      );
      handle.dispose();
      // Not one field moved, and the choice is where it was.
      expect(find.text('HOST'), findsOneWidget);
      expect(fieldTexts(tester).take(2), ['node.local', '50002']);
      expect(tlsOn(tester), isTrue);
      expect(bridge.savedBackends, isEmpty);

      // Typing drops the refusal: it no longer describes the field.
      await tester.enterText(find.byType(TextField).first, 'other.local');
      await tester.pumpAndSettle();
      expect(find.text(reason), findsNothing);
    });

    testWidgets('a scan that reads nothing leaves the form alone', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = ownElectrum();
      await tester.pumpWidget(settingsWithCamera(bridge, 'node.local:50002:s'));
      await tester.pumpAndSettle();

      // Backing out of the scanner asks the core nothing.
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(bridge.parsedBackends, isEmpty);
      expect(fieldTexts(tester).take(2), ['node.local', '50002']);
    });
  });

  group('the root list', () {
    /// A wallet is watched, the gap limit is not the default: two facts
    /// the rows have to say.
    FakeBridge bridge() => FakeBridge(
      wallets: [makeMeta()],
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {},
        gapLimit: 25,
      ),
    );

    testWidgets('names seven sections and says where each stands', (
      tester,
    ) async {
      await tester.pumpWidget(settingsApp(bridge()));
      await tester.pumpAndSettle();

      // The desktop's taxonomy, word for word, in its order.
      expect(SettingsSection.values.map((s) => s.title), [
        'General',
        'Network',
        'Wallets',
        'Security',
        'Notifications',
        'Backup & sync',
        'About',
      ]);
      for (final section in SettingsSection.values) {
        expect(find.text(section.title), findsOneWidget);
        expect(find.byIcon(section.icon), findsOneWidget);
      }
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(7));
      // One line each, from state the root already holds.
      expect(find.text('BTC · no fiat · Light theme'), findsOneWidget);
      expect(find.text('Mainnet · Public API'), findsOneWidget);
      expect(find.text('1 wallet · gap limit 25'), findsOneWidget);
      expect(find.text('No app lock'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Export or restore the wallet list'), findsOneWidget);
      expect(find.text('Gerfaut $appVersion'), findsOneWidget);
      // Nothing of the sections themselves is on the root.
      expect(find.text('Gap limit'), findsNothing);
      expect(find.text('Save backend'), findsNothing);
      // A row is a 44px target at the least.
      for (final section in SettingsSection.values) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(section.title),
                  matching: find.byType(InkWell),
                ),
              )
              .height,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('the rows follow the state they summarise', (tester) async {
      final locked = bridge()
        ..lock = const AppLock(kind: LockKind.pin, biometric: true);
      await tester.pumpWidget(settingsApp(locked));
      await tester.pumpAndSettle();
      expect(find.text('PIN lock · biometrics'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      container.read(unitProvider.notifier).set(AmountUnit.sats);
      container.read(fiatEnabledProvider.notifier).set(true);
      container.read(themeProvider.notifier).set(ThemePref.dark);
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      container.read(backgroundCheckProvider.notifier).hydrate('900');
      await tester.pumpAndSettle();
      expect(find.text('sats · EUR · Dark theme'), findsOneWidget);
      expect(find.text('On · every 15 min'), findsOneWidget);
    });

    testWidgets('each row opens a page titled after it, with its cards', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(bridge()));
      await tester.pumpAndSettle();

      const cards = <SettingsSection, List<String>>{
        SettingsSection.general: ['Display', 'Appearance'],
        SettingsSection.network: [
          'Backend · Mainnet',
          'Only wallets on the selected network are shown.',
          'Test the connection',
        ],
        SettingsSection.wallets: ['Gap limit', 'Cold storage'],
        SettingsSection.security: ['App lock'],
        SettingsSection.notifications: [
          'New transactions',
          'Show balances on widgets',
        ],
        SettingsSection.backup: ['Export…', 'Restore…'],
        SettingsSection.about: ['Check for updates', 'Show the welcome tour'],
      };
      for (final entry in cards.entries) {
        await tester.tap(find.text(entry.key.title));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsSectionScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, entry.key.title), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        for (final card in entry.value) {
          expect(find.text(card), findsOneWidget, reason: card);
        }
        // The other sections stay on the root.
        for (final other in SettingsSection.values) {
          if (other != entry.key) expect(find.text(other.title), findsNothing);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SettingsSectionScreen), findsNothing);
      }
    });

    testWidgets('a section opens directly, and the back arrow leaves it', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(bridge()),
            disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => SettingsScreen.open(
                    context,
                    section: SettingsSection.wallets,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The Wallets page and nothing of the root: no list of sections
      // stands between the caller and the wallet rows.
      expect(find.widgetWithText(AppBar, 'Wallets'), findsOneWidget);
      expect(find.text('Gap limit'), findsOneWidget);
      expect(find.text('Cold storage'), findsOneWidget);
      expect(find.text('General'), findsNothing);
      expect(find.text('Settings'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });
  });

  group('rescan', () {
    TextButton button(WidgetTester tester, String label) {
      return tester.widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      );
    }

    SyncReport report(String id, int newTxCount) => SyncReport(
      walletId: id,
      newTxCount: newTxCount,
      balance: makeBalance(0),
      tipHeight: 100,
      tookMs: 1,
      backend: 'mempool.space',
    );

    testWidgets('rescanning says so, then how many transactions it found', (
      tester,
    ) async {
      useTallSurface(tester);
      final gate = Completer<void>();
      var found = 2;
      final bridge = FakeBridge(wallets: [makeMeta()]);
      bridge.onRescan = (id) => gate.future.then((_) => report(id, found));
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Rescan a wallet to look again from its first address.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Rescan'));
      await tester.pump();

      expect(bridge.rescanCalls, 1);
      expect(find.text('Rescanning…'), findsOneWidget);
      expect(find.text('Rescan'), findsNothing);
      // The row's other actions wait for it.
      expect(button(tester, 'Rescanning…').onPressed, isNull);
      expect(button(tester, 'Rename').onPressed, isNull);
      expect(button(tester, 'Remove').onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Rescanned · 2 new transactions'), findsOneWidget);
      expect(find.text('Rescan'), findsOneWidget);
      expect(button(tester, 'Rename').onPressed, isNotNull);
      expect(button(tester, 'Remove').onPressed, isNotNull);

      // Flush the snackbar timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Singular, and nothing found, are said as such.
      found = 1;
      await tester.tap(find.text('Rescan'));
      await tester.pumpAndSettle();
      expect(find.text('Rescanned · 1 new transaction'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      found = 0;
      await tester.tap(find.text('Rescan'));
      await tester.pumpAndSettle();
      expect(find.text('Rescanned · no new transactions'), findsOneWidget);
      expect(bridge.rescanCalls, 3);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a failed rescan states why under the row', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      bridge.onRescan = (_) =>
          throw const BridgeException('sync', 'backend unreachable: timed out');
      await tester.pumpWidget(
        settingsApp(bridge, section: SettingsSection.wallets),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rescan'));
      await tester.pumpAndSettle();

      expect(bridge.rescanCalls, 1);
      expect(find.text('backend unreachable: timed out'), findsOneWidget);
      expect(find.textContaining('Rescanned'), findsNothing);
      // Back to an offer, with the row's other actions in reach.
      expect(find.text('Rescan'), findsOneWidget);
      expect(button(tester, 'Rename').onPressed, isNotNull);
    });
  });
}
