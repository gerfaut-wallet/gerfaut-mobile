import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

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

  testWidgets('the overflow menu reaches addresses and export', (tester) async {
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

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Addresses'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);

    await tester.tap(find.text('Addresses'));
    await tester.pumpAndSettle();
    expect(
      find.text('Receive addresses, in derivation order.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(
      find.text("This wallet's transaction history as a CSV file."),
      findsOneWidget,
    );
  });
}
