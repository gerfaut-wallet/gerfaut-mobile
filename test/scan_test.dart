import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/scan.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/screen.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/qr_camera.dart';

import 'fakes.dart';

const _caption =
    'Point the camera at a descriptor, extended public key, or address QR '
    'code: plain text, UR, or BBQr, animated or not.';
const _hint = 'Keep the camera on the animated code';
const _psbt = 'This QR code holds a PSBT, not a wallet to watch.';

/// What the scanner handed back to the page that opened it.
class _Outcome {
  int pops = 0;
  String? text;
}

/// A launcher page in front of the scanner, so the popped value can be
/// captured. The camera is replaced by an empty box; tests push frames
/// through [ScanScreenState.onFrame].
Widget _app(FakeBridge bridge, _Outcome outcome, {ScreenKeeper? keeper}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      if (keeper != null) screenKeeperProvider.overrideWithValue(keeper),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final text = await Navigator.of(context).push<String>(
              MaterialPageRoute<String>(
                builder: (_) =>
                    ScanScreen(cameraBuilder: (_) => const SizedBox.expand()),
              ),
            );
            outcome.pops += 1;
            outcome.text = text;
          },
          child: const Text('Open scanner'),
        ),
      ),
    ),
  );
}

Future<ScanScreenState> _open(
  WidgetTester tester,
  FakeBridge bridge,
  _Outcome outcome, {
  ScreenKeeper? keeper,
}) async {
  await tester.pumpWidget(_app(bridge, outcome, keeper: keeper));
  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
  return tester.state<ScanScreenState>(find.byType(ScanScreen));
}

/// Scripts a three-part UR: progress per frame count, assembled on the
/// third distinct frame.
QrProgress threeParts(List<String> frames) {
  if (frames.length < 3) {
    return QrProgress(
      format: QrFormat.ur,
      received: frames.length,
      total: 3,
      complete: false,
    );
  }
  return const QrProgress(
    format: QrFormat.ur,
    received: 3,
    total: 3,
    complete: true,
    text: 'wsh(sortedmulti(2,tpub.../0/*,tpub.../0/*))#assembled',
  );
}

void main() {
  testWidgets('a plain frame pops with its text', (tester) async {
    final bridge = FakeBridge();
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);
    expect(find.text(_caption), findsOneWidget);

    state.onFrame('wpkh([9a6a2580/84h/1h/0h]tpub.../0/*)');
    await tester.pumpAndSettle();

    expect(outcome.pops, 1);
    expect(outcome.text, 'wpkh([9a6a2580/84h/1h/0h]tpub.../0/*)');
    expect(bridge.assembleCalls, [
      ['wpkh([9a6a2580/84h/1h/0h]tpub.../0/*)'],
    ]);
    expect(find.byType(ScanScreen), findsNothing);
  });

  testWidgets('an animated code counts its parts and pops once complete', (
    tester,
  ) async {
    final bridge = FakeBridge()..onAssembleQr = threeParts;
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);
    expect(find.text(_hint), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();
    expect(find.text(_hint), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    expect(outcome.pops, 0);

    state.onFrame('ur:crypto-output/2-3/part-two');
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 / 3'), findsNothing);

    state.onFrame('ur:crypto-output/3-3/part-three');
    await tester.pumpAndSettle();
    expect(outcome.pops, 1);
    expect(
      outcome.text,
      'wsh(sortedmulti(2,tpub.../0/*,tpub.../0/*))#assembled',
    );
    expect(find.byType(ScanScreen), findsNothing);
    expect(bridge.assembleCalls, [
      ['ur:crypto-output/1-3/part-one'],
      ['ur:crypto-output/1-3/part-one', 'ur:crypto-output/2-3/part-two'],
      [
        'ur:crypto-output/1-3/part-one',
        'ur:crypto-output/2-3/part-two',
        'ur:crypto-output/3-3/part-three',
      ],
    ]);
  });

  testWidgets('a repeated frame is not fed again', (tester) async {
    final bridge = FakeBridge()..onAssembleQr = threeParts;
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();
    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();
    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();

    expect(bridge.assembleCalls, hasLength(1));
    expect(find.text('1 / 3'), findsOneWidget);
    expect(outcome.pops, 0);
  });

  testWidgets('a frame decoded during an assembly call is fed after it', (
    tester,
  ) async {
    final first = Completer<QrProgress>();
    final bridge = FakeBridge();
    bridge.onAssembleQr = (frames) =>
        frames.length == 1 ? first.future : threeParts(frames);
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pump();
    state.onFrame('ur:crypto-output/2-3/part-two');
    await tester.pump();
    expect(bridge.assembleCalls, hasLength(1));

    first.complete(threeParts(['ur:crypto-output/1-3/part-one']));
    await tester.pumpAndSettle();

    expect(bridge.assembleCalls, [
      ['ur:crypto-output/1-3/part-one'],
      ['ur:crypto-output/1-3/part-one', 'ur:crypto-output/2-3/part-two'],
    ]);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a rejected code shows the reason and starts over', (
    tester,
  ) async {
    final bridge = FakeBridge()..onAssembleQr = threeParts;
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    bridge.onAssembleQr = (_) =>
        throw const BridgeException('invalid_input', _psbt);
    state.onFrame('ur:crypto-psbt/1-2/part-one');
    await tester.pumpAndSettle();

    expect(find.text(_psbt), findsOneWidget);
    expect(find.text(_caption), findsNothing);
    expect(find.text(_hint), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(outcome.pops, 0);

    // The collection was dropped: the very same frame is accepted again
    // and fed on its own, and the message clears once a scan progresses.
    bridge.onAssembleQr = threeParts;
    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();
    expect(bridge.assembleCalls.last, ['ur:crypto-output/1-3/part-one']);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    expect(find.text(_psbt), findsNothing);
  });

  testWidgets('frames decoded after the pop are ignored', (tester) async {
    final bridge = FakeBridge();
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('tb1qexample');
    await tester.pumpAndSettle();
    expect(outcome.pops, 1);

    // The camera can still deliver while the route is going away.
    state.onFrame('tb1qlate');
    await tester.pumpAndSettle();
    expect(outcome.pops, 1);
    expect(bridge.assembleCalls, hasLength(1));
  });

  testWidgets('the same refused code is not handed back again', (tester) async {
    final bridge = FakeBridge()
      ..onAssembleQr = (_) =>
          throw const BridgeException('invalid_input', _psbt);
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-psbt/1-2/part-one');
    await tester.pumpAndSettle();
    expect(bridge.assembleCalls, hasLength(1));
    expect(find.text(_psbt), findsOneWidget);

    // The refused code stays under the camera and decodes several times
    // a second. Asking again buys the same answer and nothing else.
    state.onFrame('ur:crypto-psbt/1-2/part-one');
    await tester.pumpAndSettle();
    state.onFrame('ur:crypto-psbt/1-2/part-one');
    await tester.pumpAndSettle();

    expect(bridge.assembleCalls, hasLength(1));
    expect(find.text(_psbt), findsOneWidget);
    expect(outcome.pops, 0);
  });

  testWidgets('a code that assembles to nothing is said, not popped', (
    tester,
  ) async {
    final bridge = FakeBridge();
    // Every part arrived and they add up to no text at all.
    bridge.onAssembleQr = (_) => const QrProgress(
      format: QrFormat.ur,
      received: 1,
      total: 1,
      complete: true,
    );
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:bytes/nothing-inside');
    await tester.pumpAndSettle();

    // Closing on an empty scan is exactly what a crash looks like from
    // the page underneath: the scanner stays, and says so.
    expect(outcome.pops, 0);
    expect(find.byType(ScanScreen), findsOneWidget);
    expect(find.text('This code came out empty.'), findsOneWidget);
    expect(find.text(_caption), findsNothing);
  });

  testWidgets('an assembly still running when the screen is left is dropped', (
    tester,
  ) async {
    final never = Completer<QrProgress>();
    final bridge = FakeBridge()..onAssembleQr = (_) => never.future;
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(outcome.pops, 1);
    expect(outcome.text, isNull);

    // The core answering after the user walked away must not reach a
    // screen that is gone, nor hand the caller a late scan.
    never.complete(threeParts(['ur:crypto-output/1-3/part-one']));
    await tester.pumpAndSettle();
    expect(outcome.pops, 1);
    expect(outcome.text, isNull);
  });

  testWidgets('the screen stays on while the camera is up', (tester) async {
    final keeper = FakeScreenKeeper();
    final outcome = _Outcome();
    await _open(tester, FakeBridge(), outcome, keeper: keeper);
    expect(keeper.on, isTrue);

    // Lining an animated code up takes a while; the phone must not dim
    // and drop the frames collected so far. Leaving lets it go.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(keeper.on, isFalse);
    expect(keeper.holds, 1);
    expect(keeper.releases, 1);
  });

  testWidgets('the progress bar says how many frames landed', (tester) async {
    final bridge = FakeBridge()..onAssembleQr = threeParts;
    final outcome = _Outcome();
    final state = await _open(tester, bridge, outcome);

    state.onFrame('ur:crypto-output/1-3/part-one');
    await tester.pumpAndSettle();

    // A progress bar speaks its value as a percentage, which says
    // nothing about how many frames are still to come.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      bar.semanticsLabel,
      'Animated code progress, 1 of 3 frames received',
    );
  });

  group('QrProgress.fromJson', () {
    test('reads a part of an animated code', () {
      final progress = QrProgress.fromJson({
        'format': 'bbqr',
        'received': 2,
        'total': 5,
        'complete': false,
        'text': null,
      });
      expect(progress.format, QrFormat.bbqr);
      expect(progress.received, 2);
      expect(progress.total, 5);
      expect(progress.complete, isFalse);
      expect(progress.text, isNull);
      expect(progress.inProgress, isTrue);
    });

    test('reads a complete plain frame', () {
      final progress = QrProgress.fromJson({
        'format': 'plain',
        'received': 1,
        'total': 1,
        'complete': true,
        'text': 'tb1qexample',
      });
      expect(progress.format, QrFormat.plain);
      expect(progress.complete, isTrue);
      expect(progress.text, 'tb1qexample');
      expect(progress.inProgress, isFalse);
    });
  });

  group('the camera hands the decoder a whole frame', () {
    test('nothing is cropped away before the code is read', () {
      final params = QrCamera.decodeParams(1920, 1080);
      expect(params.width, 1920);
      expect(params.height, 1080);
      // The failure this guards against: reading only a square in the
      // middle of the picture. A descriptor code fills the viewfinder,
      // so a crop cuts it in half and the scanner looks dead.
      expect(params.cropWidth, 0);
      expect(params.cropHeight, 0);
    });

    test('the frame is read as luminance, looking for QR codes only', () {
      final params = QrCamera.decodeParams(1280, 720);
      expect(params.imageFormat, zxing.ImageFormat.lum);
      expect(params.format, zxing.Format.qrCode);
      expect(params.tryRotate, isTrue);
    });

    test('the stream carries enough pixels for a dense code', () {
      expect(QrCamera.resolution, ResolutionPreset.veryHigh);
    });
  });
}
