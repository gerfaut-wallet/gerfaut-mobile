import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/tx_detail.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

Widget app(FakeBridge bridge, {Widget? home}) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: home == null
        ? const GerfautApp()
        : MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: home,
          ),
  );
}

TxDetail makeTxDetail() {
  return TxDetail(
    summary: TxSummary(
      txid: 'f' * 64,
      netSats: 5000,
      feeSats: 141,
      status: const TxStatus.confirmed(height: 100, timestamp: 1755000000),
      confirmations: 10,
    ),
    inputs: const [
      TxIo(address: 'bc1qinputaddress', valueSats: 10000, isMine: false),
    ],
    outputs: const [
      TxIo(address: 'bc1qoutputaddress', valueSats: 5000, isMine: true),
      TxIo(address: 'bc1qchangeaddress', valueSats: 4859, isMine: false),
    ],
    vsize: 141,
    feeRateSatVb: 1.0,
  );
}

void main() {
  testWidgets('switching the unit changes every rendered amount', (
    tester,
  ) async {
    final meta = makeMeta(totalSats: 123456);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta, totalSats: 123456)},
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // BTC by default.
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('sats'), 100);
    await tester.ensureVisible(find.text('sats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sats'));
    await tester.pumpAndSettle();
    expect(bridge.appPrefs['display.unit'], 'sats');

    await tester.pageBack();
    await tester.pumpAndSettle();

    // The wallet card's primary line now follows the sats unit: an
    // exact match on the sats figure exists only in sats mode.
    expect(
      find.text(formatSats(123456), findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a failed sync is stated on the freshness line', (tester) async {
    final meta = makeMeta(totalSats: 0);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    bridge.onSyncWallet = (_) =>
        throw const BridgeException('sync', 'sync failed via mempool.space');
    await tester.pumpWidget(
      app(bridge, home: const WalletHomeScreen(walletId: 'w1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sync failed'), findsOneWidget);
  });

  testWidgets('the explorer link warns before opening', (tester) async {
    final bridge = FakeBridge(
      txDetails: {'w1:${'f' * 64}': makeTxDetail()},
    );
    await tester.pumpWidget(
      app(
        bridge,
        home: TxDetailScreen(
          walletId: 'w1',
          txid: 'f' * 64,
          network: Network.mainnet,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('View on mempool.space'), 200);
    await tester.ensureVisible(find.text('View on mempool.space'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on mempool.space'));
    await tester.pumpAndSettle();

    expect(find.text('Open an external explorer'), findsOneWidget);
    expect(
      find.textContaining('can link this transaction to your IP address'),
      findsOneWidget,
    );
    expect(find.text('Open explorer'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open an external explorer'), findsNothing);
  });

  testWidgets('an acknowledged explorer warning is skipped', (tester) async {
    final launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    final txid = 'f' * 64;
    final detail = makeTxDetail();
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(meta: meta, txs: [detail.summary]),
      },
      txDetails: {'w1:$txid': detail},
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'privacy.explorer_ack': '1'},
      ),
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('View on mempool.space'), 200);
    await tester.ensureVisible(find.text('View on mempool.space'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on mempool.space'));
    await tester.pumpAndSettle();

    // No dialog: the stored acknowledgement opens the page directly.
    expect(find.text('Open an external explorer'), findsNothing);
    expect(launcher.launched, ['https://mempool.space/tx/$txid']);
  });

  testWidgets('the do-not-show-again choice persists', (tester) async {
    final launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(
      app(
        bridge,
        home: TxDetailScreen(
          walletId: 'w1',
          txid: 'f' * 64,
          network: Network.mainnet,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('View on mempool.space'), 200);
    await tester.ensureVisible(find.text('View on mempool.space'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on mempool.space'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Do not show this warning again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open explorer'));
    await tester.pumpAndSettle();

    expect(bridge.appPrefs['privacy.explorer_ack'], '1');
    expect(launcher.launched.length, 1);

    // The next visit skips the dialog entirely.
    await tester.tap(find.text('View on mempool.space'));
    await tester.pumpAndSettle();
    expect(find.text('Open an external explorer'), findsNothing);
    expect(launcher.launched.length, 2);
  });

  testWidgets('the tx detail net amount follows the unit setting', (
    tester,
  ) async {
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(
      app(
        bridge,
        home: TxDetailScreen(
          walletId: 'w1',
          txid: 'f' * 64,
          network: Network.mainnet,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(formatAmountSigned(5000, AmountUnit.btc)), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TxDetailScreen)),
      listen: false,
    );
    container.read(unitProvider.notifier).set(AmountUnit.sats);
    await tester.pumpAndSettle();

    expect(
      find.text(formatAmountSigned(5000, AmountUnit.sats)),
      findsOneWidget,
    );
    expect(bridge.appPrefs['display.unit'], 'sats');
  });

  testWidgets('removing a wallet confirms with the alert banner', (
    tester,
  ) async {
    final meta = makeMeta(name: 'Cold storage');
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Remove'), 200);
    await tester.ensureVisible(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('You are removing "Cold storage" from Gerfaut'),
      findsOneWidget,
    );
    expect(find.text('Remove wallet'), findsOneWidget);

    await tester.ensureVisible(find.text('Remove wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove wallet'));
    await tester.pumpAndSettle();

    expect(find.text('No wallets on this network yet.'), findsOneWidget);

    // Flush the confirmation snackbar timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
