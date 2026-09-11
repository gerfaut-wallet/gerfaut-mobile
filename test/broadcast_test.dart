import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/broadcast.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/tx_file.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/amounts.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/tx_diagram.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'menu.dart';

/// The palette of a theme, so a test can walk both.
GerfautTokens tokensOf(Brightness brightness) =>
    brightness == Brightness.dark ? GerfautTokens.dark : GerfautTokens.light;

Widget broadcastApp(
  FakeBridge bridge, {
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: MaterialApp(
      theme: themeFrom(tokensOf(brightness), brightness),
      home: const BroadcastScreen(),
    ),
  );
}

/// A surface tall enough to build the whole preview at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pastes [text] and opens the preview.
Future<void> preview(WidgetTester tester, [String text = 'cHNidP8B']) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();
}

/// The provider container behind the running screen.
ProviderContainer containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(BroadcastScreen)),
    listen: false,
  );
}

/// Decoration of the block carrying [text].
BoxDecoration blockOf(WidgetTester tester, String text) {
  return tester
          .widget<Container>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Container))
                .first,
          )
          .decoration!
      as BoxDecoration;
}

/// The card a status pill sits on: the second Container up, the pill
/// itself being the first.
BoxDecoration cardAround(WidgetTester tester, String pill) {
  return tester
          .widget<Container>(
            find
                .ancestor(of: find.text(pill), matching: find.byType(Container))
                .at(1),
          )
          .decoration!
      as BoxDecoration;
}

FilledButton primaryButton(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(
    find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
  );
}

void main() {
  group('file import', () {
    test('a binary PSBT goes as hex', () {
      final bytes = Uint8List.fromList([0x70, 0x73, 0x62, 0x74, 0xff, 0x01]);
      expect(transactionTextOf(bytes), '70736274ff01');
    });

    test('a text file goes as its trimmed text', () {
      final bytes = Uint8List.fromList(utf8.encode('  cHNidP8BAA==\n'));
      expect(transactionTextOf(bytes), 'cHNidP8BAA==');
    });

    test('a binary transaction goes as hex', () {
      // A raw transaction starts with its version: bytes text would
      // never carry.
      final bytes = Uint8List.fromList([0x02, 0x00, 0x00, 0x00, 0x01]);
      expect(transactionTextOf(bytes), '0200000001');
    });
  });

  testWidgets('the preview needs something to decode', (tester) async {
    await tester.pumpWidget(broadcastApp(FakeBridge()));
    await tester.pumpAndSettle();

    expect(find.text('SIGNED TRANSACTION OR PSBT'), findsOneWidget);
    expect(primaryButton(tester, 'Preview').onPressed, isNull);
    expect(find.text('Import a file'), findsOneWidget);
    expect(find.text('Scan a QR code'), findsOneWidget);
    // Nothing sent yet: no recent list.
    expect(find.text('RECENT BROADCASTS'), findsNothing);
  });

  testWidgets('input the core cannot read is stated under the field', (
    tester,
  ) async {
    await tester.pumpWidget(broadcastApp(FakeBridge()));
    await tester.pumpAndSettle();

    await preview(tester, 'hello world');

    expect(find.textContaining('not a transaction'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a ready PSBT previews in full and can be sent', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge()..onPreview = (_, _) => makePreview();
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();

    await preview(tester);

    expect(bridge.previewInputs, ['cHNidP8B']);
    // Hero: txid chip, container, readiness.
    expect(
      find.text(truncateMiddle(fakeTxid, head: 12, tail: 10)),
      findsOneWidget,
    );
    expect(find.text('PSBT'), findsOneWidget);
    expect(find.text('Ready to broadcast'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Ready to broadcast')).style!.color,
      GerfautTokens.light.confirmed,
    );
    // The diagram, the same one the transaction detail draws.
    expect(find.byType(TxDiagram), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    // The fee node carries the amount; the rate stays a fact.
    expect(find.text('7.1 sat/vB'), findsOneWidget);
    // Inputs and outputs: the wallet pill and the change marker.
    expect(find.text('INPUTS (1)'), findsOneWidget);
    expect(find.text('OUTPUTS (2)'), findsOneWidget);
    // Each side states what it carries in all: the gap between the two
    // is the fee, which no row says on its own.
    expect(
      find.descendant(
        of: find.byType(IoListHeading),
        matching: find.text(formatAmount(100000, AmountUnit.btc)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(IoListHeading),
        matching: find.text(formatAmount(99000, AmountUnit.btc)),
      ),
      findsOneWidget,
    );
    expect(find.text('Cold storage'), findsNWidgets(2));
    expect(find.text('Change'), findsOneWidget);
    // Once on the branch of the diagram, once on the output row.
    expect(find.textContaining('0.00090000'), findsNWidgets(2));
    // Technical facts.
    expect(find.text('TECHNICAL'), findsOneWidget);
    expect(find.text('141 vB'), findsOneWidget);
    expect(find.text('561 WU'), findsOneWidget);
    // The chain's own word for it, the same as the transaction detail.
    expect(find.text('RBF'), findsOneWidget);
    expect(find.text('signalled (BIP-125)'), findsOneWidget);
    expect(find.text('none'), findsOneWidget);
    // And in the same place as on the desktop: after Locktime, before
    // Fee. One card read on two platforms is not relearned. The first
    // "Fee" on the page is the diagram's node; the card's is the last.
    expect(
      tester.getCenter(find.text('RBF')).dy,
      greaterThan(tester.getCenter(find.text('Locktime')).dy),
    );
    expect(
      tester.getCenter(find.text('RBF')).dy,
      lessThan(tester.getCenter(find.text('Fee').last).dy),
    );
    // No warning block when the core raised none.
    expect(find.text('BEFORE YOU SEND'), findsNothing);
    expect(primaryButton(tester, 'Broadcast').onPressed, isNotNull);
  });

  testWidgets('a preview line is priced in the unit, never in fiat', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge()..onPreview = (_, _) => makePreview();
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);

    final container = containerOf(tester);
    container.read(fiatEnabledProvider.notifier).set(true);
    await tester.pumpAndSettle();

    // Nothing on this page asks for a price any more, so ask here: the
    // point is that the rows stay in bitcoin even when a quote is on
    // hand, not that the source failed to answer.
    expect(await container.read(priceProvider.future), isNotNull);
    await tester.pumpAndSettle();
    expect(container.read(priceProvider).valueOrNull?.rate, 50000);
    expect(container.read(fiatCurrencyProvider), FiatCurrency.eur);

    // The preview and the transaction detail are one page with two
    // entries: a row that carries euros here and only bitcoin there
    // would be the same list drawn by two rules.
    expect(find.textContaining('€'), findsNothing);
    expect(find.text(formatAmount(90000, AmountUnit.btc)), findsWidgets);
  });

  testWidgets('an input the chain disagrees about is shown in red', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge()
      ..onPreview = (_, _) => makePreview(
        source: TxSource.psbt,
        // A PSBT that states one amount for an input while the chain
        // records another: the fee is not what the screen would compute
        // from the PSBT, and signing it can hand the difference to the
        // miner. The core calls it, and calls it alert.
        warnings: const [
          TxWarning(
            kind: TxWarningKind.inputMismatch,
            message:
                'Input 0 claims 100000 sats; the chain records 10000000 sats.',
            severity: TxSeverity.alert,
          ),
        ],
      );
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();

    await preview(tester, '0200000001deadbeef');

    expect(find.text('BEFORE YOU SEND'), findsOneWidget);
    expect(
      blockOf(
        tester,
        'Input 0 claims 100000 sats; the chain records 10000000 sats.',
      ).color,
      GerfautTokens.light.alertSurface,
    );
    expect(find.byIcon(LucideIcons.equalNot), findsOneWidget);
  });

  testWidgets('an unsigned transaction cannot be sent', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge()
      ..onPreview = (_, _) => makePreview(
        ready: false,
        source: TxSource.rawTransaction,
        // The severities are the core's, carried on the wire: the
        // screen only reads them.
        warnings: const [
          TxWarning(
            kind: TxWarningKind.unsigned,
            message: '1 of 1 inputs carry no signature.',
            severity: TxSeverity.alert,
          ),
          TxWarning(
            kind: TxWarningKind.spendsWatched,
            message: 'Spends coins of Cold storage.',
            severity: TxSeverity.info,
          ),
        ],
        inputs: const [
          TxInputPreview(
            txid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
            vout: 0,
            valueSats: 100000,
            signed: false,
          ),
        ],
      );
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();

    await preview(tester, '0200000001deadbeef');

    expect(find.text('Raw transaction'), findsOneWidget);
    expect(find.text('Not fully signed'), findsOneWidget);
    expect(primaryButton(tester, 'Broadcast').onPressed, isNull);
    expect(find.text('BEFORE YOU SEND'), findsOneWidget);

    // The tone is the core's, read off the caution: this screen has no
    // table of its own to drift out of step with the desktop's.
    final light = GerfautTokens.light;
    expect(
      blockOf(tester, '1 of 1 inputs carry no signature.').color,
      light.alertSurface,
    );
    expect(
      blockOf(tester, 'Spends coins of Cold storage.').color,
      light.pendingSurface,
    );
    // The readiness pill, the warning and the input marker all say it.
    expect(find.byIcon(LucideIcons.penOff), findsNWidgets(3));
    // The marker is `Unsigned`, the same word as the desktop, and it
    // stays red: a transaction believed ready that cannot be sent is
    // exactly what the budget is kept for.
    expect(find.text('Unsigned'), findsOneWidget);
    expect(blockOf(tester, 'Unsigned').color, light.alertSurface);
    expect(
      tester.widget<Text>(find.text('Unsigned')).style?.color,
      light.alert,
    );
    // An input without an address shows its outpoint.
    expect(
      find.text(
        truncateMiddle(
          'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90:0',
          head: 10,
          tail: 8,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    // The text stays for correction.
    expect(find.text('0200000001deadbeef'), findsOneWidget);
  });

  testWidgets('sending asks first, then follows the transaction', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge()..onPreview = (_, _) => makePreview();
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    expect(find.text('Broadcast this transaction?'), findsOneWidget);
    expect(
      find.text('It pays a fee of 0.00001000 BTC (7.1 sat/vB).'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bridge.broadcastHexes, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    // The dialog's own Broadcast button is the last one on screen.
    await tester.tap(find.text('Broadcast').last);
    await tester.pumpAndSettle();

    expect(bridge.broadcastHexes, ['0200000001deadbeef']);
    // A pill, and only what the user is waiting for.
    expect(find.text('Waiting to be mined'), findsOneWidget);
    expect(find.byIcon(LucideIcons.hourglass), findsOneWidget);
    expect(find.textContaining('waiting in the mempool'), findsNothing);
    expect(find.textContaining('Sent to mempool.space'), findsNothing);
    // The state is the pill's; the card around it is a card like the
    // others, not an amber slab.
    final light = GerfautTokens.light;
    expect(blockOf(tester, 'Waiting to be mined').color, light.pendingSurface);
    expect(
      tester.widget<Text>(find.text('Waiting to be mined')).style!.color,
      light.pending,
    );
    final card = cardAround(tester, 'Waiting to be mined');
    expect(card.color, light.surface);
    expect((card.border! as Border).top.color, light.border);
    expect(bridge.statusCalls, 1);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Broadcast another'), findsOneWidget);
    expect(find.text('View on mempool.space'), findsOneWidget);

    // Kept for a later check, as JSON in the vault.
    final stored = jsonDecode(bridge.appPrefs['broadcast.recent']!) as List;
    expect(stored, hasLength(1));
    expect((stored.single as Map)['txid'], fakeTxid);
    expect((stored.single as Map)['hex'], '0200000001deadbeef');
    expect((stored.single as Map)['network'], 'mainnet');

    // Polled every thirty seconds, until it confirms.
    bridge.onStatus = (_, _) => BroadcastStatus(
      txid: fakeTxid,
      found: true,
      confirmed: true,
      blockHeight: 850000,
      confirmations: 3,
      backend: 'mempool.space',
      at: 1755000100,
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(bridge.statusCalls, 2);
    expect(
      find.text('Mined in block ${groupThousands('850000')}'),
      findsOneWidget,
    );
    // The colour moves to the pill; the facts under it read in prose.
    expect(find.text('Confirmed'), findsOneWidget);
    expect(
      blockOf(tester, 'Confirmed').color,
      GerfautTokens.light.confirmedSurface,
    );
    expect(find.text('Waiting to be mined'), findsNothing);
    expect(
      tester.widget<Text>(find.textContaining('Mined in block')).style!.color,
      GerfautTokens.light.textMuted,
    );

    // A manual check.
    await tester.tap(find.byTooltip('Check again'));
    await tester.pumpAndSettle();
    expect(bridge.statusCalls, 3);
  });

  testWidgets('a refusal stays on screen, verbatim', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge();
    bridge.onPreview = (_, _) => makePreview();
    bridge.onBroadcast = (_, _) {
      // The node's own words, as the core relays them.
      throw const BridgeException(
        'broadcast',
        'mempool.space refused the transaction: min relay fee not met, '
            '1 < 141',
      );
    };
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broadcast').last);
    await tester.pumpAndSettle();

    // The same sentence as the desktop, period and all.
    expect(find.text('The network refused this transaction.'), findsOneWidget);
    expect(
      find.text(
        'mempool.space refused the transaction: min relay fee not met, '
        '1 < 141',
      ),
      findsOneWidget,
    );
    // Amber, not red: the node said no, nothing moved and nothing
    // leaked. Red is the budget kept for what costs funds or privacy.
    expect(
      blockOf(tester, 'The network refused this transaction.').color,
      GerfautTokens.light.pendingSurface,
    );
    expect(find.byType(SnackBar), findsNothing);
    // It lands in reaction to the tap that sent the transaction, so it
    // is announced rather than waiting to be walked into.
    expect(
      tester
          .widget<GerfautNotice>(
            find.ancestor(
              of: find.text('The network refused this transaction.'),
              matching: find.byType(GerfautNotice),
            ),
          )
          .liveRegion,
      isTrue,
    );
    // Nothing was recorded, and the transaction can be sent again.
    expect(bridge.appPrefs.containsKey('broadcast.recent'), isFalse);
    expect(primaryButton(tester, 'Broadcast').onPressed, isNotNull);
  });

  testWidgets('a side nobody can price totals n/a, not a short sum', (
    tester,
  ) async {
    useTallSurface(tester);
    final bridge = FakeBridge()
      ..onPreview = (_, _) => makePreview(
        feeSats: null,
        feeRate: null,
        inputs: const [
          TxInputPreview(
            txid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
            vout: 0,
            valueSats: 100000,
            signed: true,
          ),
          TxInputPreview(
            txid: 'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
            vout: 12,
            signed: true,
          ),
        ],
      );
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);

    expect(find.text('INPUTS (2)'), findsOneWidget);
    // A total short by an input nobody could price is worse than no
    // total: it would read as the real figure.
    expect(
      find.descendant(
        of: find.byType(IoListHeading),
        matching: find.text('n/a'),
      ),
      findsOneWidget,
    );
    // The output side is whole, so it states its sum.
    expect(
      find.descendant(
        of: find.byType(IoListHeading),
        matching: find.text(formatAmount(99000, AmountUnit.btc)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a transaction the backend lost says so', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge();
    bridge.onPreview = (_, _) => makePreview();
    bridge.onStatus = (_, _) => BroadcastStatus(
      txid: fakeTxid,
      found: false,
      confirmed: false,
      confirmations: 0,
      backend: 'mempool.space',
      at: 1755000100,
    );
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broadcast').last);
    await tester.pumpAndSettle();

    // The same words as the desktop: what it means, and that sending
    // it again costs nothing.
    expect(find.text('Not seen'), findsOneWidget);
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
    expect(
      find.text(
        'mempool.space does not have this transaction. It may not have '
        'been relayed, or it was dropped or replaced. Broadcasting it '
        'again does no harm.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Not seen')).style!.color,
      GerfautTokens.light.pending,
    );
  });

  testWidgets('a mined transaction states its block apart from its count', (
    tester,
  ) async {
    useTallSurface(tester);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bridge = FakeBridge();
    bridge.onPreview = (_, _) => makePreview();
    bridge.onStatus = (_, _) => BroadcastStatus(
      txid: fakeTxid,
      found: true,
      confirmed: true,
      blockHeight: 4611010,
      confirmations: 3,
      backend: 'mempool.space',
      at: now,
    );
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broadcast').last);
    await tester.pumpAndSettle();

    // Two lines, the same two the desktop prints. On one line the
    // grouped height swallowed the count: "block 4 611 010 · 3
    // confirmations" read as one figure whose last group was a 3.
    expect(
      find.text('Mined in block ${groupThousands('4611010')}'),
      findsOneWidget,
    );
    expect(find.text('3 confirmations as of just now'), findsOneWidget);
    expect(find.textContaining('Confirmed ·'), findsNothing);

    // And the count keeps its singular.
    bridge.onStatus = (_, _) => BroadcastStatus(
      txid: fakeTxid,
      found: true,
      confirmed: true,
      blockHeight: 4611010,
      confirmations: 1,
      backend: 'mempool.space',
      at: now,
    );
    await tester.tap(find.byTooltip('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('1 confirmation as of just now'), findsOneWidget);
  });

  testWidgets('forgetting a past broadcast asks first', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge()..onPreview = (_, _) => makePreview();
    await tester.pumpWidget(broadcastApp(bridge));
    await tester.pumpAndSettle();
    await preview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broadcast').last);
    await tester.pumpAndSettle();

    // Once the screen is left, what was sent is a past broadcast.
    await tester.tap(find.text('Broadcast another'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT BROADCASTS'), findsOneWidget);

    await tester.tap(find.byTooltip('Forget this broadcast'));
    await tester.pumpAndSettle();
    // What is lost and what is not, in words rather than in a colour.
    expect(find.text('Forget this broadcast?'), findsOneWidget);
    expect(find.text('This record cannot be brought back.'), findsOneWidget);
    expect(
      find.textContaining('on the network and is untouched'),
      findsOneWidget,
    );

    // Backing out keeps it, and keeps it in the vault.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT BROADCASTS'), findsOneWidget);
    expect(
      jsonDecode(bridge.appPrefs['broadcast.recent']!) as List,
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Forget this broadcast'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT BROADCASTS'), findsNothing);
    expect(jsonDecode(bridge.appPrefs['broadcast.recent']!) as List, isEmpty);
  });

  testWidgets('recent broadcasts come back after a restart', (tester) async {
    final bridge = FakeBridge(
      settings: Settings(
        activeNetwork: Network.mainnet,
        backends: const {},
        appPrefs: {
          'onboarding.seen': '1',
          'broadcast.recent': jsonEncode([
            {
              'txid': fakeTxid,
              'network': 'mainnet',
              'hex': '0200000001deadbeef',
              'at': 1755000000,
            },
            {
              'txid': 'e' * 64,
              'network': 'signet',
              'hex': '0200000001cafe',
              'at': 1755000000,
            },
          ]),
        },
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

    // The home screen opens the broadcast page for the workspace.
    await pickFromMenu(tester, 'Broadcast');

    expect(find.text('RECENT BROADCASTS'), findsOneWidget);
    // Only the workspace network's entries, each checked once.
    expect(
      find.text(truncateMiddle(fakeTxid, head: 12, tail: 10)),
      findsOneWidget,
    );
    expect(
      find.text(truncateMiddle('e' * 64, head: 12, tail: 10)),
      findsNothing,
    );
    expect(bridge.statusCalls, 1);
    expect(find.text('Waiting to be mined'), findsOneWidget);
    // A past broadcast says when it left, under its identifier.
    expect(find.textContaining(RegExp(r'^Sent ')), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'sending the next transaction is a primary action (${brightness.name})',
      (tester) async {
        final tokens = tokensOf(brightness);
        useTallSurface(tester);
        final bridge = FakeBridge()..onPreview = (_, _) => makePreview();
        await tester.pumpWidget(broadcastApp(bridge, brightness: brightness));
        await tester.pumpAndSettle();
        await preview(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Broadcast'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Broadcast').last);
        await tester.pumpAndSettle();

        // The app's own primary component, not a quieter cousin.
        expect(
          find.widgetWithText(PrimaryButton, 'Broadcast another'),
          findsOneWidget,
        );
        final another = primaryButton(tester, 'Broadcast another').style!;
        const resting = <WidgetState>{};
        expect(another.backgroundColor!.resolve(resting), tokens.primary);
        expect(another.foregroundColor!.resolve(resting), tokens.onPrimary);
        expect(
          tester
              .getSize(find.widgetWithText(FilledButton, 'Broadcast another'))
              .height,
          44,
        );
        // And it is the only one: leaving the screen is a navigation, so
        // Done steps back to a ghost rather than competing with it.
        expect(find.byType(PrimaryButton), findsOneWidget);
        expect(find.widgetWithText(GhostButton, 'Done'), findsOneWidget);
      },
    );
  }
}
