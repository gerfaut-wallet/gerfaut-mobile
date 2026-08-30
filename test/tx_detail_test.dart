// The transaction detail as a phone shows it: what the page dropped
// after the owner read it on a real device, and what now holds the
// five sections apart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/tx_detail.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/address_chip.dart';

import 'fakes.dart';

final String _txid = 'f' * 64;

/// A transaction that puts every wallet role on the page at once — an
/// input spent, an output received, an output that came back as change
/// — plus the raw bytes, so all five sections exist.
TxDetail _detail({List<TxIo>? inputs}) {
  return TxDetail(
    summary: TxSummary(
      txid: _txid,
      netSats: 5000,
      feeSats: 141,
      status: const TxStatus.confirmed(height: 100, timestamp: 1755000000),
      confirmations: 10,
    ),
    inputs:
        inputs ??
        const [
          TxIo(address: 'bc1qinputaddress', valueSats: 10000, isMine: true),
        ],
    outputs: const [
      TxIo(address: 'bc1qoutputaddress', valueSats: 5000, isMine: true),
      TxIo(
        address: 'bc1qchangeaddress',
        valueSats: 4859,
        isMine: true,
        change: true,
      ),
    ],
    vsize: 141,
    feeRateSatVb: 1.0,
    extras: const TxExtras(
      sizeBytes: 226,
      vsize: 141,
      weightWu: 564,
      version: 2,
      locktime: 0,
      rbfSignaled: false,
      segwit: true,
      taproot: false,
      isCoinbase: false,
      coinbasePool: null,
      sigops: 8,
      rawHex: '0200000001abcdef',
    ),
  );
}

Widget _app(FakeBridge bridge, {TextScaler textScaler = TextScaler.noScaling}) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: TxDetailScreen(
            walletId: 'w1',
            txid: _txid,
            network: Network.mainnet,
          ),
        ),
      ),
    ),
  );
}

/// A phone-width surface, tall enough that the whole page lays out in
/// one pass — a section that never builds never overflows either.
void _usePhone(WidgetTester tester, {double height = 6000}) {
  tester.view.physicalSize = Size(411, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The rules between sections, told apart from the hairlines inside the
/// facts card by the one thing that differs: their colour.
Finder _sectionRules() {
  final hairline = GerfautTokens.light.border.withValues(alpha: 0.6);
  return find.byWidgetPredicate(
    (widget) => widget is Divider && widget.color == hairline,
  );
}

ProviderContainer _containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(TxDetailScreen)),
    listen: false,
  );
}

void main() {
  testWidgets('the quick facts keep the id and the date, and drop the rate', (
    tester,
  ) async {
    _usePhone(tester);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    // With fiat on there would be a price to state; the page states
    // none, because the only rate it knows is today's.
    _containerOf(tester).read(fiatEnabledProvider.notifier).set(true);
    await tester.pumpAndSettle();

    expect(find.text('TRANSACTION ID'), findsOneWidget);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('RATE'), findsNothing);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('a row states its amount in the unit, never in fiat', (
    tester,
  ) async {
    _usePhone(tester);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    _containerOf(tester).read(fiatEnabledProvider.notifier).set(true);
    await tester.pumpAndSettle();

    // The hero says what the transaction was worth, once. Three rows
    // and the rate fact used to say it four more times.
    expect(find.textContaining('€'), findsOneWidget);
    expect(find.text(formatAmount(10000, AmountUnit.btc)), findsWidgets);
  });

  testWidgets('an amount nobody could price reads n/a', (tester) async {
    _usePhone(tester);
    final bridge = FakeBridge(
      txDetails: {
        'w1:$_txid': _detail(
          inputs: const [TxIo(address: null, valueSats: null, isMine: false)],
        ),
      },
    );
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    // The branch of the diagram, the row, and the side total the one
    // unknown value makes a guess of.
    expect(find.text('n/a'), findsNWidgets(3));
  });

  testWidgets('masking covers the amount of a row', (tester) async {
    _usePhone(tester);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    _containerOf(tester).read(maskedProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(find.text(formatAmount(10000, AmountUnit.btc)), findsNothing);
    expect(find.text(maskedValue), findsWidgets);
  });

  testWidgets('no row spells its role out under the address', (tester) async {
    _usePhone(tester);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    expect(find.text('Spent from this wallet'), findsNothing);
    expect(find.text('Change back to this wallet'), findsNothing);
    expect(find.text('Received by this wallet'), findsNothing);
    // What is left still reads as a row: three addresses on the lists,
    // and the transaction id above them.
    expect(find.byType(AddressChip), findsNWidgets(4));
  });

  testWidgets('four hairlines hold the five sections apart', (tester) async {
    _usePhone(tester);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(_app(bridge));
    await tester.pumpAndSettle();

    // Header, diagram, the two lists, the facts, the raw bytes.
    expect(_sectionRules(), findsNWidgets(4));
    for (final rule in tester.widgetList<Divider>(_sectionRules())) {
      expect(rule.height, 1);
      expect(rule.thickness, 1);
    }
  });

  testWidgets('the page still fits at twice the text size', (tester) async {
    _usePhone(tester, height: 12000);
    final bridge = FakeBridge(txDetails: {'w1:$_txid': _detail()});
    await tester.pumpWidget(
      _app(bridge, textScaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    // A RenderFlex that overflowed lands here: at this size a row that
    // cannot hold its figure is the first thing to go.
    expect(tester.takeException(), isNull);
    expect(_sectionRules(), findsNWidgets(4));
  });
}
