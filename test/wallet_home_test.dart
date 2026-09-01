import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:gerfaut/widgets/sync_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';
import 'policy_fixtures.dart';

void main() {
  testWidgets('wallet home shows the balance and masks it on demand', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 123456);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 123456)},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cold storage'), findsOneWidget);
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
    // One unit only: the balance never echoes the other unit.
    expect(find.textContaining(formatSats(123456)), findsNothing);
    expect(find.text('Never synced'), findsOneWidget);
    // A wallet that never reached a backend never pretends to hold zero.
    expect(find.text('Not synced yet.'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);

    // The eye masks every amount, and the preference is persisted.
    await tester.tap(find.byTooltip('Hide balances'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.00123456', findRichText: true), findsNothing);
    expect(find.textContaining('•••••', findRichText: true), findsWidgets);
    expect(bridge.appPrefs['mobile.masked'], '1');
  });

  testWidgets('a failed sync stays visible on the wallet screen', (
    tester,
  ) async {
    const stamp = SyncStamp(
      at: 1755000000,
      tipHeight: 100,
      backend: 'mempool.space',
    );
    final meta = makeMeta(totalSats: 123456, lastSync: stamp);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 123456)},
    );
    bridge.onSyncWallet = (_) =>
        throw const BridgeException('sync', 'mempool.space: timed out');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync'));
    await tester.pumpAndSettle();

    // Freshness line, the reason under it, and the balance note: the
    // snackbar is not the only trace of the failure.
    expect(find.textContaining('Sync failed · last sync'), findsOneWidget);
    expect(find.text('mempool.space: timed out'), findsOneWidget);
    expect(
      find.text('Sync failed: showing the last known balance.'),
      findsOneWidget,
    );
    // The last known balance stays on screen.
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('every action of the wallet is in its header', (tester) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing hides under a menu any more, and the name keeps the room
    // that buys: it starts against the back arrow.
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byTooltip('Hide balances'), findsOneWidget);
    expect(find.byTooltip('Sync'), findsOneWidget);
    expect(find.byTooltip('Broadcast'), findsOneWidget);
    expect(find.byTooltip('Export CSV'), findsOneWidget);
    expect(
      tester.getRect(find.text('Cold storage')).left,
      lessThan(tester.getRect(find.byTooltip('Hide balances')).left),
    );

    await tester.tap(find.byTooltip('Broadcast'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNED TRANSACTION OR PSBT'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export CSV'));
    await tester.pumpAndSettle();
    expect(
      find.text("This wallet's transaction history as a CSV file."),
      findsOneWidget,
    );
  });

  testWidgets('a transaction row reads in one line, date included', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 5000);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(
          meta: meta,
          totalSats: 5000,
          txs: [
            TxSummary(
              txid: 'a' * 64,
              netSats: 5000,
              feeSats: 141,
              status: TxStatus.confirmed(height: 100, timestamp: 1755000000),
              confirmations: 10,
            ),
            TxSummary(
              txid: 'b' * 64,
              netSats: -2000,
              feeSats: 141,
              status: TxStatus.pending(),
              confirmations: 0,
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The direction is already an arrow, a sign and a colour: the word
    // would be a fourth telling, and it costs the date its room.
    expect(find.text('Received'), findsNothing);
    expect(find.text('Sent'), findsNothing);
    expect(find.text(formatTimestamp(1755000000)), findsOneWidget);
    expect(find.byType(StatusPill), findsNothing);
    expect(find.byType(StatusGlyph), findsNWidgets(2));
    // Shape, not colour: a check for a mined transaction, a clock for
    // one still waiting.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
    // The whole row still fits the list rhythm.
    expect(
      tester.getSize(find.byIcon(LucideIcons.arrowDownLeft)).height,
      lessThanOrEqualTo(48),
    );
  });

  testWidgets('tapping the title renames the wallet, over the page', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No pencil next to the title: the ink under the finger and the
    // spoken label are the whole affordance.
    expect(find.byIcon(LucideIcons.pencil), findsNothing);
    expect(find.byTooltip('Rename this wallet'), findsOneWidget);
    // And the title still starts where every other page's does.
    expect(tester.getRect(find.text('Cold storage')).height, greaterThan(0));

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();

    // The page is still behind it: renaming never navigates away.
    expect(find.text('Rename wallet'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller?.text, 'Cold storage');

    await tester.enterText(field, 'Vault');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(bridge.wallets.single.name, 'Vault');
    expect(find.text('Wallet renamed'), findsOneWidget);
    // The header carries the new name without a reopen.
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Cold storage'), findsNothing);

    // Flush the snackbar timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('leaving mid-rename does not fault on a dead screen', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    final gate = Completer<void>();
    bridge.renameGate = gate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Vault',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    // The screen goes while the core is still writing. All that is
    // left to do is refresh a page that no longer exists.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    // The name was written; nothing was thrown on the way back.
    expect(bridge.wallets.single.name, 'Vault');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty or unchanged name writes nothing', (tester) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder field() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    // Cancelling closes on the name it opened with.
    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'Vault');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(bridge.wallets.single.name, 'Cold storage');

    // An empty field, and the same name again: both close in silence.
    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    await tester.enterText(field(), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Wallet renamed'), findsNothing);

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet renamed'), findsNothing);
    expect(bridge.wallets.single.name, 'Cold storage');
  });

  testWidgets('the sync icon turns while the sync runs', (tester) async {
    final meta = makeMeta(totalSats: 5000);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 5000)},
    );
    final gate = Completer<void>();
    bridge.syncGate = gate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const WalletHomeScreen(walletId: 'w1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    RotationTransition spinner() => tester.widget<RotationTransition>(
      find.descendant(
        of: find.byType(SyncButton),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(spinner().turns.value, 0);

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Turning, and saying so in words as well: motion is never the only
    // channel.
    expect(spinner().turns.value, greaterThan(0));
    expect(find.byTooltip('Syncing…'), findsOneWidget);
    expect(find.textContaining('Syncing…'), findsWidgets);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sync'), findsOneWidget);
  });
  Widget homeOf(FakeBridge bridge) => ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const WalletHomeScreen(walletId: 'w1'),
    ),
  );
  const synced = SyncStamp(
    at: 1755000000,
    tipHeight: 100,
    backend: 'mempool.space',
  );

  testWidgets('a settled balance says nothing about being settled', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 123456, lastSync: synced);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 123456)},
    );
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();

    // The normal state does not announce itself: no note, no clock.
    expect(find.text('All funds confirmed.'), findsNothing);
    expect(find.textContaining('pending'), findsNothing);
    expect(find.byIcon(LucideIcons.clock), findsNothing);
  });

  testWidgets('what is still out of a block reads under the total, signed', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 173456, lastSync: synced);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(
          meta: meta,
          totalSats: 173456,
          pendingNetSats: 50000,
        ),
      },
    );
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();

    // The total already counts the arriving funds; the line under it
    // says how much of it is still waiting, in the unit of the total.
    expect(
      find.textContaining('0.00173456', findRichText: true),
      findsOneWidget,
    );
    final figure = formatAmountSigned(50000, AmountUnit.btc);
    expect(find.text(figure), findsOneWidget);
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(figure)).style!.color,
      GerfautTokens.light.pending,
    );
    expect(
      find.text('Includes pending funds not yet confirmed.'),
      findsNothing,
    );

    // Masked, the figure hides and the clock stays: that something is
    // in flight is not an amount.
    await tester.tap(find.byTooltip('Hide balances'));
    await tester.pumpAndSettle();
    expect(find.text(figure), findsNothing);
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
  });

  testWidgets('a spend the chain has not taken yet reads as a minus', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 69000, lastSync: synced);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(
          meta: meta,
          totalSats: 69000,
          pendingNetSats: -31000,
        ),
      },
    );
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();

    final figure = formatAmountSigned(-31000, AmountUnit.btc);
    expect(figure, startsWith('-'));
    expect(find.text(figure), findsOneWidget);
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
  });

  testWidgets('a sync failure outranks the pending line', (tester) async {
    final meta = makeMeta(totalSats: 173456, lastSync: synced);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(
          meta: meta,
          totalSats: 173456,
          pendingNetSats: 50000,
        ),
      },
    );
    bridge.onSyncWallet = (_) =>
        throw const BridgeException('sync', 'mempool.space: timed out');
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sync'));
    await tester.pumpAndSettle();

    // A figure whose source is in doubt is not one to detail.
    expect(
      find.text('Sync failed: showing the last known balance.'),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.clock), findsNothing);
  });

  testWidgets('the balance card links the policy page', (tester) async {
    final meta = makeMeta(totalSats: 5000);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 5000)},
    );
    bridge.policies['w1'] = PolicySnapshot.fromJson(multisigPolicyJson());
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();

    expect(find.text('Policy'), findsOneWidget);
    expect(find.text('2 of 3 keys'), findsOneWidget);

    // The digest is structure, not an amount: the eye leaves it alone.
    await tester.tap(find.byTooltip('Hide balances'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 keys'), findsOneWidget);

    await tester.tap(find.text('Policy'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 keys sign.'), findsOneWidget);
  });

  testWidgets('a policy that cannot be read still opens its page', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    bridge.onWalletPolicy = (_) =>
        throw const BridgeException('descriptor', 'the policy cannot be read');
    await tester.pumpWidget(homeOf(bridge));
    await tester.pumpAndSettle();

    // The row stands without its digest, and still leads to the page.
    expect(find.text('Policy'), findsOneWidget);
    await tester.tap(find.text('Policy'));
    await tester.pumpAndSettle();
    expect(find.byType(GerfautNotice), findsOneWidget);
    expect(find.text('the policy cannot be read'), findsOneWidget);
  });
}
