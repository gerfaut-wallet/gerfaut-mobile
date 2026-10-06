// Touch targets: what a finger can press is never smaller than
// Android's 48 dp, whatever is drawn, and two targets never overlap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/add_wallet.dart';
import 'package:gerfaut/screens/broadcast.dart';
import 'package:gerfaut/screens/export.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/tx_detail.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/tap_target.dart';

import 'fakes.dart';

Widget _page(Widget body) => MaterialApp(
  theme: themeFrom(GerfautTokens.light, Brightness.light),
  home: Scaffold(body: Center(child: body)),
);

Widget _screen(FakeBridge bridge, Widget home) => ProviderScope(
  overrides: [
    bridgeProvider.overrideWithValue(bridge),
    disguiseServiceProvider.overrideWithValue(FakeDisguise()),
  ],
  child: MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: home,
  ),
);

/// A phone tall enough that every page lays out whole. Wider for a page
/// whose row of two buttons the test font, wider than the app's, would
/// push past a phone's edge.
void _usePhone(WidgetTester tester, {double width = 411}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

final String _txid = 'a' * 64;

/// One wallet with a transaction each way, a coin, a partial history and
/// the detail of one transaction: every control of its pages on screen.
FakeBridge _bridge() {
  final meta = makeMeta(
    totalSats: 123456,
    lastSync: const SyncStamp(at: 1755000000, tipHeight: 100, backend: 'x'),
  );
  final summary = TxSummary(
    txid: _txid,
    netSats: 5000,
    feeSats: 141,
    status: const TxStatus.confirmed(height: 100, timestamp: 1755000000),
    confirmations: 10,
  );
  return FakeBridge(
    wallets: [
      meta,
      makeMeta(id: 'w2', name: 'Spending', totalSats: 5000),
    ],
    settings: const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
    snapshots: {
      'w1': makeSnapshot(
        meta: meta,
        totalSats: 123456,
        truncated: true,
        txs: [
          summary,
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
    utxos: {
      'w1': [
        UtxoInfo(
          txid: _txid,
          vout: 1,
          address: 'bc1qcoinaddress',
          valueSats: 123456,
          status: const TxStatus.confirmed(height: 100),
          keychain: 'external',
          derivationIndex: 0,
        ),
      ],
    },
    txDetails: {
      'w1:$_txid': TxDetail(
        summary: summary,
        inputs: const [
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
      ),
    },
  );
}

void main() {
  test('the target is at least the one Android asks for', () {
    expect(GerfautTouch.target, greaterThanOrEqualTo(48));
    expect(GerfautTouch.control, lessThanOrEqualTo(GerfautTouch.target));
  });

  group('a tap target', () {
    testWidgets('grows the hit area and not what is drawn', (tester) async {
      await tester.pumpWidget(
        _page(
          TapTarget(
            child: SizedBox(key: const Key('drawn'), width: 20, height: 20),
          ),
        ),
      );
      final box = tester.getRect(find.byType(TapTarget));
      final drawn = tester.getRect(find.byKey(const Key('drawn')));
      expect(box.size, const Size.square(GerfautTouch.target));
      expect(drawn.size, const Size.square(20));
      expect(drawn.center, box.center);
    });

    testWidgets('a tap in the margin presses what is drawn', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _page(
          TapTarget(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 120, height: 30),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(TapTarget));
      await tester.tapAt(box.topLeft + const Offset(1, 1));
      await tester.tapAt(box.bottomRight - const Offset(1, 1));
      expect(taps, 2);
    });

    testWidgets('a tap past its edge goes to the neighbour', (tester) async {
      var first = 0;
      var second = 0;
      await tester.pumpWidget(
        _page(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TapTarget(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => first++,
                  child: const SizedBox(width: 120, height: 30),
                ),
              ),
              TapTarget(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => second++,
                  child: const SizedBox(width: 120, height: 30),
                ),
              ),
            ],
          ),
        ),
      );
      final upper = tester.getRect(find.byType(TapTarget).first);
      final lower = tester.getRect(find.byType(TapTarget).last);
      // The two targets meet and never overlap.
      expect(lower.top, upper.bottom);
      await tester.tapAt(Offset(lower.center.dx, lower.top + 1));
      expect((first, second), (0, 1));
      await tester.tapAt(Offset(upper.center.dx, upper.bottom - 1));
      expect((first, second), (1, 1));
    });

    testWidgets('a screen reader finds it where the finger does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _page(
          TapTarget(
            child: Semantics(
              button: true,
              label: 'Small',
              onTap: () {},
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      );
      expect(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  testWidgets('every button is drawn a control high and pressed over a '
      'full target', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      _page(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(label: 'Primary', onPressed: () => pressed.add('p')),
            SecondaryButton(
              label: 'Secondary',
              onPressed: () => pressed.add('s'),
            ),
            GhostButton(label: 'Ghost', onPressed: () => pressed.add('g')),
            DangerButton(label: 'Danger', onPressed: () => pressed.add('d')),
          ],
        ),
      ),
    );
    for (final (type, label) in [
      (PrimaryButton, 'Primary'),
      (SecondaryButton, 'Secondary'),
      (GhostButton, 'Ghost'),
      (DangerButton, 'Danger'),
    ]) {
      final target = tester.getRect(find.byType(type));
      final drawn = tester.getRect(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(target.height, GerfautTouch.target, reason: label);
      expect(drawn.height, GerfautTouch.control, reason: label);
      // Just above what is drawn still presses it.
      await tester.tapAt(Offset(drawn.center.dx, target.top + 1));
      await tester.pump();
    }
    expect(pressed, ['p', 's', 'g', 'd']);
  });

  group('every control of a screen is a full target', () {
    Future<void> check(
      WidgetTester tester,
      Widget home, {
      double width = 411,
    }) async {
      _usePhone(tester, width: width);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_screen(_bridge(), home));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    }

    testWidgets('the wallet list', (tester) async {
      _usePhone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(_bridge()),
            disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          ],
          child: const GerfautApp(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a wallet, its transactions and its coins', (tester) async {
      await check(tester, const WalletHomeScreen(walletId: 'w1'));
      await tester.tap(find.text('UTXOs'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('a transaction', (tester) async {
      await check(
        tester,
        TxDetailScreen(walletId: 'w1', txid: _txid, network: Network.mainnet),
      );
    });

    testWidgets('the export', (tester) async {
      await check(tester, const ExportScreen(walletId: 'w1'));
    });

    testWidgets('broadcast', (tester) async {
      await check(tester, const BroadcastScreen(), width: 800);
    });

    testWidgets('adding a wallet', (tester) async {
      await check(tester, const AddWalletScreen());
    });

    for (final section in SettingsSection.values) {
      testWidgets('the ${section.title} settings', (tester) async {
        await check(tester, SettingsSectionScreen(section: section));
      });
    }
  });
}
