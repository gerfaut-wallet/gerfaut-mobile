import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:gerfaut/widgets/brand.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'menu.dart';

Widget app(FakeBridge bridge, {Future<void> Function()? bootstrap}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: GerfautApp(bootstrap: bootstrap),
  );
}

/// A vault that has been opened before: the welcome tour is behind it,
/// so the app lands on the wallets like it does every other day.
FakeBridge returning({List<WalletMeta> wallets = const []}) {
  return FakeBridge(
    wallets: wallets,
    settings: const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
}

/// Drags whatever sits at [from] down by [by], after holding it for
/// [hold]: the home cards lift on a long press, the settings handles at
/// once. Three quarters of a row is the usual distance: far enough for
/// the row to take the next one's place, not so far as to overshoot it.
Future<void> dragDown(
  WidgetTester tester,
  Offset from,
  double by, {
  Duration hold = Duration.zero,
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(hold);
  await tester.pumpAndSettle();
  await gesture.moveTo(from + const Offset(0, 30));
  await tester.pumpAndSettle();
  await gesture.moveTo(from + Offset(0, by));
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('the wallet cards', () {
    testWidgets('wear the icon their owner picked', (tester) async {
      await tester.pumpWidget(
        app(
          returning(
            wallets: [
              makeMeta(id: 'w1', name: 'Cold storage'),
              makeMeta(id: 'w2', name: 'Savings', icon: WalletIcon.piggyBank),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.wallet), findsOneWidget);
      expect(find.byIcon(LucideIcons.piggyBank), findsOneWidget);
    });

    testWidgets('a held card moves, and the order reaches the vault', (
      tester,
    ) async {
      final bridge = returning(
        wallets: [
          makeMeta(id: 'w1', name: 'Cold storage'),
          makeMeta(id: 'w2', name: 'Spending'),
        ],
      );
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('Cold storage'), lessThan(top('Spending')));

      // Hold, then drag three quarters of a card down.
      final pitch = top('Spending') - top('Cold storage');
      await dragDown(
        tester,
        tester.getCenter(find.text('Cold storage')),
        pitch * 0.75,
        hold: kLongPressTimeout + kPressTimeout,
      );

      expect(bridge.reorderCalls, [
        ['w2', 'w1'],
      ]);
      expect(top('Spending'), lessThan(top('Cold storage')));

      // A tap still opens a card, and a pull still syncs the list.
      await tester.tap(find.text('Spending'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletHomeScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      final before = bridge.syncAllCalls;
      await tester.fling(find.text('Spending'), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(bridge.syncAllCalls, before + 1);
    });

    testWidgets('follow an order set in the settings meanwhile', (
      tester,
    ) async {
      final bridge = returning(
        wallets: [
          makeMeta(id: 'w1', name: 'Cold storage'),
          makeMeta(id: 'w2', name: 'Spending'),
        ],
      );
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      final pitch = top('Spending') - top('Cold storage');
      await dragDown(
        tester,
        tester.getCenter(find.text('Cold storage')),
        pitch * 0.75,
        hold: kLongPressTimeout + kPressTimeout,
      );
      expect(top('Spending'), lessThan(top('Cold storage')));

      // In the settings, the rows go back the other way round.
      await pickFromMenu(tester, 'Settings');
      await tester.tap(find.text('Wallets'));
      await tester.pumpAndSettle();
      final rowPitch = top('Cold storage') - top('Spending');
      await dragDown(
        tester,
        tester.getCenter(find.byIcon(LucideIcons.gripVertical).first),
        rowPitch * 0.75,
      );
      expect(bridge.wallets.map((w) => w.id), ['w1', 'w2']);

      // Back on the home screen, the cards stand as the vault has them,
      // not as they were last dropped here.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(top('Cold storage'), lessThan(top('Spending')));
    });
  });

  testWidgets('empty state shows the guidance and its single action', (
    tester,
  ) async {
    await tester.pumpWidget(app(returning()));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
    // The first screen anyone sees carries the whole logo, wordmark
    // included: it is the one place the app introduces itself.
    expect(find.byType(GerfautLockup), findsOneWidget);
  });

  testWidgets('the header wears the falcon, not the word', (tester) async {
    await tester.pumpWidget(app(returning()));
    await tester.pumpAndSettle();

    // Whoever opened the app knows its name; the mark says it in the
    // room of a glyph and leaves the bar to the actions.
    expect(find.byType(GerfautMark), findsWidgets);
    expect(find.text('Gerfaut'), findsNothing);
    expect(find.bySemanticsLabel('Gerfaut'), findsWidgets);
  });

  testWidgets('a faked bootstrap resolves into the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(app(returning(), bootstrap: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
  });

  testWidgets('nothing asks the core before the vault is open', (tester) async {
    final bridge = _ClosedUntilOpen();
    await tester.pumpWidget(
      app(
        bridge,
        bootstrap: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          bridge.open = true;
        },
      ),
    );
    await tester.pump();
    expect(find.text('Opening the vault\u2026'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('No wallets yet'), findsOneWidget);
  });

  testWidgets('every wallet card carries the same generic icon', (
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
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // The wallet kind is stated in words where it matters, never as a
    // different icon on the card.
    expect(find.byIcon(LucideIcons.wallet), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.mapPin), findsNothing);
  });

  testWidgets('a wallet card carries a name and a balance, nothing else', (
    tester,
  ) async {
    const stamp = SyncStamp(
      at: 1755000000,
      tipHeight: 100,
      backend: 'mempool.space',
    );
    final bridge = FakeBridge(
      wallets: [makeMeta(totalSats: 123456, lastSync: stamp)],
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    expect(find.text('Cold storage'), findsOneWidget);
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
    // The freshness line lives on the wallet's own page: a whole row per
    // card for an answer nobody looks for while scanning the list.
    expect(find.textContaining('Synced'), findsNothing);
    expect(find.textContaining('mempool.space'), findsNothing);
    expect(find.text('Never synced'), findsNothing);
  });

  testWidgets('a failed sync still shows on the card', (tester) async {
    final bridge = FakeBridge(wallets: [makeMeta(totalSats: 123456)]);
    bridge.onSyncAll = (_) => const SyncAllReport(
      reports: [],
      failures: [
        SyncFailure(walletId: 'w1', message: 'mempool.space: timed out'),
      ],
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // The one thing that contradicts the figure above it: a stale
    // balance stated as fact is a lie. Amber, one line, reason on tap.
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    final warning = tester.widget<Text>(find.text('Sync failed'));
    expect(warning.style?.color, GerfautTokens.light.pending);
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );

    // A tap on the line shows the reason and leaves the card where it
    // is: a hold is the card's own gesture, the one that lifts it.
    await tester.tap(find.text('Sync failed'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('mempool.space: timed out'), findsOneWidget);
    expect(find.byType(WalletHomeScreen), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('the home header keeps the sync and menus the rest', (
    tester,
  ) async {
    await tester.pumpWidget(app(returning(wallets: [makeMeta()])));
    await tester.pumpAndSettle();

    // Two glyphs in the bar: what is used on the way past, and the way
    // to everything else.
    expect(find.byTooltip('Sync'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Broadcast'), findsNothing);
    expect(find.byTooltip('Hide balances'), findsNothing);

    await openMenu(tester);
    const order = ['Hide balances', 'Broadcast', 'Settings'];
    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    for (var i = 0; i < order.length; i++) {
      if (i > 0) expect(top(order[i]), greaterThan(top(order[i - 1])));
      expect(menuRowHeight(tester, order[i]), greaterThanOrEqualTo(44));
    }

    // A tap beside it closes it, and the page underneath is untouched.
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Cold storage'), findsOneWidget);

    await pickFromMenu(tester, 'Broadcast');
    expect(find.text('SIGNED TRANSACTION OR PSBT'), findsOneWidget);
  });

  testWidgets('an empty vault still reaches the settings, sync aside', (
    tester,
  ) async {
    await tester.pumpWidget(app(returning()));
    await tester.pumpAndSettle();

    // Nothing to sync, so the button says so by greying out; the menu
    // is the way on either way.
    final sync = find.ancestor(
      of: find.byTooltip('Sync'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sync).onPressed, isNull);
    await pickFromMenu(tester, 'Settings');
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('the wallet list masks its balances from its own menu', (
    tester,
  ) async {
    final bridge = FakeBridge(wallets: [makeMeta(totalSats: 123456)]);
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );

    await pickFromMenu(tester, 'Hide balances');

    expect(find.textContaining('0.00123456', findRichText: true), findsNothing);
    expect(find.textContaining('•••••', findRichText: true), findsWidgets);
    expect(bridge.appPrefs['mobile.masked'], '1');

    // The entry now offers the way back, under the other label.
    await openMenu(tester);
    expect(find.byIcon(LucideIcons.eye), findsOneWidget);
    await tester.tap(find.text('Show balances'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
    expect(bridge.appPrefs['mobile.masked'], '0');
  });

  testWidgets('a failed bootstrap shows the startup error screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeBridge(),
        bootstrap: () async => throw StateError('vault init failed'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerfaut could not start'), findsOneWidget);
    expect(find.text('No wallets yet'), findsNothing);
  });
}

/// A bridge that refuses every call until the vault is open, the way the
/// real one does before the Rust bridge has been initialized.
class _ClosedUntilOpen extends FakeBridge {
  _ClosedUntilOpen()
    : super(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );

  bool open = false;

  @override
  Future<Settings> getSettings() => open
      ? super.getSettings()
      : Future.error(StateError('the core was called too early'));
}
