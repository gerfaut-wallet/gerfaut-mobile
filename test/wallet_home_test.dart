import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    expect(find.textContaining('â€¢â€¢â€¢â€¢â€¢', findRichText: true), findsWidgets);
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
    expect(find.textContaining('Sync failed Â· last sync'), findsOneWidget);
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
    // The address audit lives on the Receive page now.
    expect(find.text('Addresses'), findsNothing);
    expect(find.text('Broadcast'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);

    await tester.tap(find.text('Broadcast'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNED TRANSACTION OR PSBT'), findsOneWidget);

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
}
