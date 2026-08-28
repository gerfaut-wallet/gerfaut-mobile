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
import 'package:gerfaut/src/tx_file.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

Widget broadcastApp(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
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
    // Flow: counts, totals, fee.
    expect(find.text('1 input'), findsOneWidget);
    expect(find.text('2 outputs'), findsOneWidget);
    expect(find.text('FEE'), findsOneWidget);
    expect(find.text('7.1 sat/vB'), findsOneWidget);
    // Inputs and outputs: the wallet pill and the change marker.
    expect(find.text('INPUTS (1)'), findsOneWidget);
    expect(find.text('OUTPUTS (2)'), findsOneWidget);
    expect(find.text('Cold storage'), findsNWidgets(2));
    expect(find.text('Change'), findsOneWidget);
    expect(find.textContaining('0.00090000'), findsOneWidget);
    // Technical facts.
    expect(find.text('TECHNICAL'), findsOneWidget);
    expect(find.text('141 vB'), findsOneWidget);
    expect(find.text('561 WU'), findsOneWidget);
    expect(find.text('Yes (BIP-125)'), findsOneWidget);
    expect(find.text('none'), findsOneWidget);
    // No warning block when the core raised none.
    expect(find.text('BEFORE YOU SEND'), findsNothing);
    expect(primaryButton(tester, 'Broadcast').onPressed, isNotNull);
  });

  testWidgets('an unsigned transaction cannot be sent', (tester) async {
    useTallSurface(tester);
    final bridge = FakeBridge()
      ..onPreview = (_, _) => makePreview(
        ready: false,
        source: TxSource.rawTransaction,
        warnings: const [
          TxWarning(
            kind: TxWarningKind.unsigned,
            message: '1 of 1 inputs carry no signature.',
          ),
          TxWarning(
            kind: TxWarningKind.spendsWatched,
            message: 'Spends coins of Cold storage.',
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

    // What the network will refuse reads in the alert style; a caution
    // reads in the pending one.
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
    expect(find.text('Unsigned'), findsOneWidget);
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
    // One sentence, and only what the user is waiting for.
    expect(find.text('Waiting to be mined.'), findsOneWidget);
    expect(find.textContaining('waiting in the mempool'), findsNothing);
    expect(find.textContaining('Sent to mempool.space'), findsNothing);
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
      find.text(
        'Confirmed · 3 confirmations · block ${groupThousands('850000')}',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.textContaining('Confirmed · 3 confirmations'))
          .style!
          .color,
      GerfautTokens.light.confirmed,
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

    expect(find.text('The network refused this transaction'), findsOneWidget);
    expect(
      find.text(
        'mempool.space refused the transaction: min relay fee not met, '
        '1 < 141',
      ),
      findsOneWidget,
    );
    expect(
      blockOf(tester, 'The network refused this transaction').color,
      GerfautTokens.light.alertSurface,
    );
    expect(find.byType(SnackBar), findsNothing);
    // Nothing was recorded, and the transaction can be sent again.
    expect(bridge.appPrefs.containsKey('broadcast.recent'), isFalse);
    expect(primaryButton(tester, 'Broadcast').onPressed, isNotNull);
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

    expect(find.text('Not seen by mempool.space'), findsOneWidget);
    expect(
      find.text(
        'It may have been dropped from the mempool or replaced by another '
        'transaction.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Not seen by mempool.space')).style!.color,
      GerfautTokens.light.pending,
    );
  });

  testWidgets('recent broadcasts come back after a restart', (tester) async {
    final bridge = FakeBridge(
      settings: Settings(
        activeNetwork: Network.mainnet,
        backends: const {},
        appPrefs: {
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
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: const GerfautApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The home screen opens the broadcast page for the workspace.
    await tester.tap(find.byTooltip('Broadcast'));
    await tester.pumpAndSettle();

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
    expect(find.text('Waiting to be mined.'), findsOneWidget);
  });

}
