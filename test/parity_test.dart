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
import 'package:gerfaut/widgets/tx_diagram.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

TxDetail makeTxDetail({
  TxExtras? extras,
  List<TxIo>? inputs,
  List<TxIo>? outputs,
}) {
  return TxDetail(
    summary: TxSummary(
      txid: 'f' * 64,
      netSats: 5000,
      feeSats: 141,
      status: const TxStatus.confirmed(height: 100, timestamp: 1755000000),
      confirmations: 10,
    ),
    inputs:
        inputs ??
        const [
          TxIo(address: 'bc1qinputaddress', valueSats: 10000, isMine: false),
        ],
    outputs:
        outputs ??
        const [
          TxIo(address: 'bc1qoutputaddress', valueSats: 5000, isMine: true),
          TxIo(address: 'bc1qchangeaddress', valueSats: 4859, isMine: false),
        ],
    vsize: 141,
    feeRateSatVb: 1.0,
    extras: extras,
  );
}

TxExtras makeExtras({
  bool rbfSignaled = false,
  bool segwit = false,
  bool taproot = false,
  bool isCoinbase = false,
  String? coinbasePool,
  int? coinbaseHeight,
  String? coinbaseTag,
  int locktime = 0,
  String rawHex = '',
}) {
  return TxExtras(
    sizeBytes: 226,
    vsize: 141,
    weightWu: 564,
    version: 2,
    locktime: locktime,
    rbfSignaled: rbfSignaled,
    segwit: segwit,
    taproot: taproot,
    isCoinbase: isCoinbase,
    coinbasePool: coinbasePool,
    coinbaseHeight: coinbaseHeight,
    coinbaseTag: coinbaseTag,
    sigops: 8,
    rawHex: rawHex,
  );
}

/// A tall test surface so the whole detail screen builds at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget txDetailApp(FakeBridge bridge) {
  return app(
    bridge,
    home: TxDetailScreen(
      walletId: 'w1',
      txid: 'f' * 64,
      network: Network.mainnet,
    ),
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
    expect(find.text(formatSats(123456), findRichText: true), findsOneWidget);
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

    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.text('Sync failed: nothing fetched yet.'), findsOneWidget);
  });

  testWidgets('the explorer link warns before opening', (tester) async {
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
    // The row says its direction with the arrow, not with a word.
    await tester.tap(find.byIcon(LucideIcons.arrowDownLeft));
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

  testWidgets('feature badges render from extras', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          extras: makeExtras(rbfSignaled: true, segwit: true),
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    // The word the chain uses, never a synonym.
    expect(find.text('RBF'), findsOneWidget);
    expect(find.text('Replaceable'), findsNothing);
    expect(find.text('SegWit'), findsOneWidget);
    expect(find.text('Taproot'), findsNothing);
    // The version lives in the technical card, never as a badge.
    expect(find.text('Version 2'), findsNothing);
    expect(find.text('Version'), findsOneWidget);

    // One card of technical facts, below the lists, and nothing lost
    // on the way there.
    expect(find.text('TECHNICAL'), findsOneWidget);
    expect(find.text('DETAILS'), findsNothing);
    expect(find.text('226 B'), findsOneWidget);
    expect(find.text('564 WU'), findsOneWidget);
    expect(find.text('Sigops'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Locktime'), findsOneWidget);
    expect(find.text('none'), findsOneWidget);
    expect(find.text('Confirmations'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Fee rate'), findsOneWidget);
    // The first three facts read right under the hero.
    expect(find.text('TRANSACTION ID'), findsOneWidget);
    expect(find.text(formatTimestamp(1755000000)), findsOneWidget);
  });

  testWidgets('a pending transaction states what it lacks', (tester) async {
    useTallSurface(tester);
    final detail = makeTxDetail(extras: makeExtras());
    final pending = TxDetail(
      summary: TxSummary(
        txid: detail.summary.txid,
        netSats: -5000,
        feeSats: detail.summary.feeSats,
        status: const TxStatus.pending(),
        confirmations: 0,
      ),
      inputs: detail.inputs,
      outputs: detail.outputs,
      vsize: detail.vsize,
      feeRateSatVb: detail.feeRateSatVb,
      extras: detail.extras,
    );
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': pending});
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('SENT'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.textContaining('block '), findsNothing);
    expect(find.text('not yet mined'), findsOneWidget);
    // The date says it once; no empty block line is left to read.
    expect(find.text('—'), findsNothing);
  });

  testWidgets('neutral badges share the tinted badges\' border', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(extras: makeExtras(locktime: 840000)),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    BoxDecoration badgeDecoration(String label) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    // Final and Locktime are neutral, yet bordered like the others.
    expect(badgeDecoration('Final').border, isNotNull);
    expect(badgeDecoration('Locktime').border, isNotNull);
    // The locktime value sits on its own fact line, not in the chip.
    expect(find.text(groupThousands('840000')), findsOneWidget);
  });

  testWidgets('the tx detail header never echoes the other unit', (
    tester,
  ) async {
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    // BTC is the unit: the net amount shows once, sats nowhere near it.
    expect(find.text(formatAmountSigned(5000, AmountUnit.btc)), findsOneWidget);
    expect(find.textContaining('sats'), findsNothing);
  });

  testWidgets('an OP_RETURN output shows its decoded text', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          extras: makeExtras(segwit: true),
          outputs: const [
            TxIo(address: 'bc1qoutputaddress', valueSats: 5000, isMine: true),
            TxIo(
              address: null,
              valueSats: 0,
              isMine: false,
              opReturn: OpReturnData(
                hex: '68656c6c6f2067657266617574',
                text: 'hello gerfaut',
              ),
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    // The tag shows as a flag, as a branch of the diagram and on the
    // output row; the decoded text only on the row.
    expect(find.text('OP_RETURN'), findsNWidgets(3));
    expect(find.text('hello gerfaut'), findsOneWidget);
    expect(find.byIcon(LucideIcons.scrollText), findsNWidgets(3));
  });

  testWidgets('the raw transaction is revealed on tap', (tester) async {
    useTallSurface(tester);
    const hex = '0200000001abcdef';
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(extras: makeExtras(rawHex: hex)),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('RAW TRANSACTION'), findsOneWidget);
    expect(find.text(hex), findsNothing);

    await tester.tap(find.text('RAW TRANSACTION'));
    await tester.pumpAndSettle();
    expect(find.text(hex), findsOneWidget);
  });

  testWidgets('wallet rows carry a role icon, not a text pill', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          extras: makeExtras(),
          outputs: const [
            TxIo(address: 'bc1qoutputaddress', valueSats: 5000, isMine: true),
            TxIo(
              address: 'bc1qchangeaddress',
              valueSats: 4859,
              isMine: true,
              change: true,
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('CHANGE'), findsNothing);
    expect(find.text('MINE'), findsNothing);
    // One role chip per row, plus a plain-words subline. The diagram
    // names each role with the very same icon.
    expect(find.byIcon(LucideIcons.undo2), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.arrowDownLeft), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNWidgets(2));
    expect(find.text('Received by this wallet'), findsOneWidget);
    expect(find.text('Change back to this wallet'), findsOneWidget);
    expect(find.text('Spent from this wallet'), findsNothing);
  });

  testWidgets('the diagram carries a branch per input and output', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {'w1:${'f' * 64}': makeTxDetail(extras: makeExtras())},
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('RECEIVED'), findsOneWidget);
    expect(find.byType(TxDiagram), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    // Every branch states its amount and the row of the list below
    // states it again: each figure twice over, nowhere else.
    expect(find.text(formatAmount(10000, AmountUnit.btc)), findsNWidgets(2));
    expect(find.text(formatAmount(5000, AmountUnit.btc)), findsNWidgets(2));
    expect(find.text(formatAmount(4859, AmountUnit.btc)), findsNWidgets(2));
    // The fee: the node under the diagram, then the fact card.
    expect(find.text('Fee'), findsNWidgets(2));
    expect(find.text(formatAmount(141, AmountUnit.btc)), findsNWidgets(2));
    // The rate is a fact and stays one: the node never repeats it.
    expect(find.text('1.0 sat/vB'), findsOneWidget);
  });

  testWidgets('the diagram fits the page on a phone', (tester) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.byType(TxDiagram), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown input value makes the total n/a', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          inputs: const [
            TxIo(address: 'bc1qinputaddress', valueSats: 10000, isMine: false),
            TxIo(address: null, valueSats: null, isMine: false),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('INPUTS (2)'), findsOneWidget);
    // Neither the branch nor the row invents a value it never got.
    expect(find.text('n/a'), findsNWidgets(2));
    expect(find.text('Unknown input'), findsNWidgets(2));
  });

  testWidgets('every input gets its own row, however many', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          inputs: [
            for (var i = 0; i < 12; i++)
              TxIo(address: 'bc1qinput$i', valueSats: 1000, isMine: false),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('INPUTS (12)'), findsOneWidget);
    // The list keeps all twelve; the diagram folds the tail into one
    // row so it still fits, and says how many it stands for.
    expect(find.text('+8 more'), findsOneWidget);
    expect(find.byIcon(LucideIcons.ellipsis), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUpRight), findsNWidgets(18));
  });

  testWidgets('masking hides every amount of the page', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TxDetailScreen)),
      listen: false,
    );
    container.read(maskedProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(find.text(formatAmount(10000, AmountUnit.btc)), findsNothing);
    expect(find.text(formatAmount(141, AmountUnit.btc)), findsNothing);
    expect(find.text(formatAmountSigned(5000, AmountUnit.btc)), findsNothing);
    // Hero, three branches, the fee node, three list rows, the fee
    // fact: every figure of the page, and no other.
    expect(find.text(maskedValue), findsNWidgets(9));
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

  testWidgets('figures sit in the ui face, identifiers stay mono', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge(txDetails: {'w1:${'f' * 64}': makeTxDetail()});
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    final amount = tester.widget<Text>(
      find.text(formatAmountSigned(5000, AmountUnit.btc)),
    );
    expect(amount.style!.fontFamily, GerfautFonts.ui);
    expect(
      amount.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(amount.style!.letterSpacing, lessThan(0));

    // A vsize is a figure too, and it groups with no-break spaces.
    final vsize = tester.widget<Text>(find.text('141 vB'));
    expect(vsize.style!.fontFamily, GerfautFonts.ui);
    expect(
      vsize.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    // The transaction id is an identifier: mono, and only mono.
    final txid = tester.widget<Text>(find.text('${'f' * 8}...${'f' * 8}'));
    expect(txid.style!.fontFamily, GerfautFonts.data);
  });

  testWidgets('a truncated history loads older rounds on demand', (
    tester,
  ) async {
    useTallSurface(tester);
    final meta = makeMeta();
    final detail = makeTxDetail();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {
        'w1': makeSnapshot(meta: meta, txs: [detail.summary], truncated: true),
      },
    );
    bridge.onLoadMoreHistory = (_) => 3;
    await tester.pumpWidget(
      app(bridge, home: const WalletHomeScreen(walletId: 'w1')),
    );
    await tester.pumpAndSettle();

    // The partial list is an action, not a notice.
    expect(find.text('Load older transactions'), findsOneWidget);
    expect(find.textContaining('it loads in rounds'), findsOneWidget);
    expect(find.textContaining('the list below is partial'), findsNothing);

    await tester.tap(find.text('Load older transactions'));
    await tester.pumpAndSettle();

    expect(bridge.loadMoreHistoryCalls, 1);
    expect(find.text('3 older transactions'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // An empty round says so instead of staying silent.
    bridge.onLoadMoreHistory = (_) => 0;
    await tester.tap(find.text('Load older transactions'));
    await tester.pumpAndSettle();

    expect(bridge.loadMoreHistoryCalls, 2);
    expect(find.text('History is complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a coinbase input states its block and its reward', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          extras: makeExtras(
            isCoinbase: true,
            coinbasePool: 'Foundry USA',
            coinbaseHeight: 840000,
            coinbaseTag: '/Foundry USA Pool/',
          ),
          inputs: const [TxIo(address: null, valueSats: null, isMine: false)],
          outputs: const [
            TxIo(address: 'bc1qminer', valueSats: 312500000, isMine: false),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('BLOCK REWARD'), findsOneWidget);
    // The branch names the source, the input row names its block.
    expect(find.text('Coinbase'), findsNWidgets(2));
    expect(
      find.text('block ${groupThousands('840000')} · Foundry USA'),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.pickaxe), findsNWidgets(3));
    // A coinbase input spends nothing, so the reward stands in for
    // it: both branches of the diagram, then both rows.
    expect(find.text('n/a'), findsNothing);
    expect(
      find.text(formatAmount(312500000, AmountUnit.btc)),
      findsNWidgets(4),
    );
  });

  testWidgets('a recognized OP_RETURN payload shows its name', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:${'f' * 64}': makeTxDetail(
          extras: makeExtras(),
          outputs: [
            const TxIo(
              address: 'bc1qoutputaddress',
              valueSats: 5000,
              isMine: true,
            ),
            TxIo(
              address: null,
              valueSats: 0,
              isMine: false,
              opReturn: OpReturnData(
                hex: 'aa21a9ed${'9' * 64}',
                text: null,
                label: 'Witness commitment',
              ),
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(txDetailApp(bridge));
    await tester.pumpAndSettle();

    // The label wins over the payload on the output row.
    expect(find.text('Witness commitment'), findsOneWidget);
    expect(find.textContaining('aa21a9ed'), findsNothing);
  });
}
