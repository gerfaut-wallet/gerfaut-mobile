// The main screens, filled with the same made-up wallets as the widget
// tests, drawn at the size of the device they run on. A screen that
// overflows the window fails the test, as it does in a widget test.
//
//   flutter test integration_test/screens_test.dart -d <simulator id>
//
// Each screen is then drawn again at the size of the iPhone Duo's inner
// display, upright and sideways, which the simulator cannot be told to
// open to: the layout of a wide window is checked on every run.
//
// With `--dart-define=GERFAUT_SHOTS=1`, the pictures are kept in a
// `shots` folder of the app's Documents: the app's own drawing of each
// screen, as the device shows it and at the inner display's sizes. The
// test also writes `<name>.ready` there and waits until something on
// the host has written `<name>.done` beside it: CI's iPhone Duo job
// answers with `xcrun simctl io <id> screenshot`, which keeps the status
// bar, the camera and the safe areas the app really gets.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/add_wallet.dart';
import 'package:gerfaut/screens/receive.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/tx_detail.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/screens/welcome.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import '../test/fakes.dart';

// Any value turns the pictures on; bool.fromEnvironment reads only
// "true", and CI passes 1.
const bool _shots = String.fromEnvironment('GERFAUT_SHOTS') != '';

/// What the iPhone Duo simulator reports for its inner display:
/// 2007 by 2853 pixels at 3 pixels a point.
const Size _inner = Size(669, 951);

const Key _frame = Key('frame');

/// Pumps [app] in a boundary the test can draw to a picture.
Future<void> _show(WidgetTester tester, Widget app) =>
    tester.pumpWidget(RepaintBoundary(key: _frame, child: app));

Future<Directory> _shotsDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/shots')..createSync(recursive: true);
}

/// The app's own drawing of what is on screen, as `<file>.png`.
Future<void> _save(WidgetTester tester, String file) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  final ratio = tester.view.devicePixelRatio;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = await _shotsDir();
  File('${dir.path}/$file.png').writeAsBytesSync(bytes!);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _meta = makeMeta(totalSats: 123456);
const _txid =
    'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff00112233445566778899aabbccddeeff';

FakeBridge _vault() => FakeBridge(
  wallets: [
    _meta,
    makeMeta(id: 'w2', name: 'Family vault', totalSats: 2500000),
  ],
  snapshots: {
    'w1': makeSnapshot(
      meta: _meta,
      totalSats: 123456,
      txs: const [
        TxSummary(
          txid: _txid,
          netSats: 125456,
          feeSats: 141,
          status: TxStatus.confirmed(height: 100, timestamp: 1755000000),
          confirmations: 10,
        ),
        TxSummary(
          txid: 'abababababababababababababababababababababababababababababababab',
          netSats: -2000,
          feeSats: 141,
          status: TxStatus.pending(),
          confirmations: 0,
        ),
      ],
    ),
  },
  txDetails: {
    'w1:$_txid': const TxDetail(
      summary: TxSummary(
        txid: _txid,
        netSats: 125456,
        feeSats: 141,
        status: TxStatus.confirmed(height: 100, timestamp: 1755000000),
        confirmations: 10,
      ),
      inputs: [
        TxIo(
          address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
          valueSats: 130000,
          isMine: false,
        ),
      ],
      outputs: [
        TxIo(
          address: 'bc1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl',
          valueSats: 125456,
          isMine: true,
        ),
        TxIo(
          address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
          valueSats: 4403,
          isMine: false,
        ),
      ],
      vsize: 141,
      feeRateSatVb: 1.0,
    ),
  },
  settings: const Settings(
    preferences: kPreferences,
    activeNetwork: Network.mainnet,
    backends: {},
    appPrefs: {'onboarding.seen': '1'},
  ),
);

/// [screen] with the made-up vault, in the app's light theme.
Widget _alone(Widget screen) => ProviderScope(
  retry: noRetry,
  overrides: [bridgeProvider.overrideWithValue(_vault())],
  child: creditedApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: screen,
  ),
);

/// Says what the window is, for the log of the run, keeps the pictures
/// when they are wanted, then draws the screen again at the inner
/// display's sizes.
Future<void> _settle(WidgetTester tester, String name) async {
  await _frames(tester);
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  final padding = view.padding;
  final ratio = view.devicePixelRatio;
  // ignore: avoid_print, the run's log is where the sizes are read
  print(
    'screen $name: window ${size.width.toStringAsFixed(1)} x '
    '${size.height.toStringAsFixed(1)}, ratio $ratio, safe area '
    'left ${padding.left / ratio} top ${padding.top / ratio} '
    'right ${padding.right / ratio} bottom ${padding.bottom / ratio}',
  );
  if (_shots) {
    await _save(tester, '$name-device');
    final dir = await _shotsDir();
    File('${dir.path}/$name.ready').writeAsStringSync('');
    final done = File('${dir.path}/$name.done');
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (!done.existsSync()) {
      if (DateTime.now().isAfter(end)) fail('no picture of $name');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  // The inner display, upright then sideways. Its safe areas are not
  // known without opening the simulator: none are drawn.
  addTearDown(tester.view.reset);
  for (final (pose, size) in [
    ('inner-upright', _inner),
    ('inner-sideways', _inner.flipped),
  ]) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding.zero;
    await _frames(tester);
    if (_shots) await _save(tester, '$name-$pose');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('welcome', (tester) async {
    await _show(tester, _alone(const WelcomeScreen()));
    await _settle(tester, '1-welcome');
    expect(find.text('Watch, never spend'), findsOneWidget);
  });

  testWidgets('home', (tester) async {
    await _show(
      tester,
      ProviderScope(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(_vault()),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
        child: const GerfautApp(),
      ),
    );
    await _settle(tester, '2-home');
    expect(find.text('Family vault'), findsOneWidget);
  });

  testWidgets('wallet', (tester) async {
    await _show(tester, _alone(const WalletHomeScreen(walletId: 'w1')));
    await _settle(tester, '3-wallet');
    expect(find.text('Receive'), findsOneWidget);
  });

  testWidgets('transaction', (tester) async {
    await _show(
      tester,
      _alone(
        const TxDetailScreen(
          walletId: 'w1',
          txid: _txid,
          network: Network.mainnet,
        ),
      ),
    );
    await _settle(tester, '4-transaction');
  });

  testWidgets('receive', (tester) async {
    await _show(tester, _alone(const ReceiveScreen(walletId: 'w1')));
    await _settle(tester, '5-receive');
  });

  testWidgets('settings', (tester) async {
    await _show(tester, _alone(const SettingsScreen()));
    await _settle(tester, '6-settings');
  });

  testWidgets('add a wallet', (tester) async {
    await _show(tester, _alone(const AddWalletScreen()));
    await _settle(tester, '7-add-wallet');
  });
}
