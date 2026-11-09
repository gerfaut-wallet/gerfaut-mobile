import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart' show themeFrom;
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/qr_camera.dart';

const _starting = 'Starting the camera…';
const _denied =
    'Gerfaut has no access to the camera. Grant it in the system settings, '
    'or paste the code in by hand.';
const _unavailable =
    'No camera answered on this device. Paste the code in by hand instead.';

/// The picture the stand-in controller shows once it streams.
const _preview = Key('preview');

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// A controller with no sensor behind it. Its start can be held at
/// `initialize`, the await a permission prompt or a slow sensor makes
/// long on a phone, and it records what the scanner did with it.
class _FakeController extends CameraController {
  _FakeController(
    CameraDescription description,
    this._device,
    this._hold,
    this._refusal,
  ) : super(description, QrCamera.resolution, enableAudio: false);

  final _FakeDevice _device;
  final Future<void>? _hold;
  final String? _refusal;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    await _hold;
    final refusal = _refusal;
    if (refusal != null) throw CameraException(refusal, 'refused');
    if (!disposed) {
      value = value.copyWith(
        isInitialized: true,
        previewSize: const Size(1920, 1080),
      );
    }
  }

  @override
  Future<void> startImageStream(onLatestImageAvailable onAvailable) async {
    value = value.copyWith(isStreamingImages: true);
  }

  @override
  Future<void> stopImageStream() async {
    if (_device.streamStopFails) {
      throw CameraException('stopImageStream', 'no session');
    }
    value = value.copyWith(isStreamingImages: false);
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  Widget buildPreview() => const SizedBox.expand(key: _preview);

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _device.disposal?.future;
    await super.dispose();
  }

  /// Opened and handing frames over: the sensor is in use.
  bool get live => !disposed && value.isStreamingImages;
}

/// The phone as the scanner sees it, with every controller it handed out.
class _FakeDevice extends QrCameraDevice {
  final controllers = <_FakeController>[];

  /// Holds the next controller's start until completed.
  Completer<void>? hold;

  /// Holds every controller's disposal until completed: the platform
  /// takes its time to release a sensor.
  Completer<void>? disposal;

  /// Every stream stop fails, as on a session the platform tore down.
  bool streamStopFails = false;

  /// The next decoder start fails, as an isolate that would not spawn.
  bool decoderFails = false;

  /// The error code the next controller's start fails with.
  String? refusal;

  List<CameraDescription> cameraList = const [_back];

  /// Holds the decoder's start until completed.
  Completer<void>? decoderHold;

  /// Starts of the decoder not yet matched by a stop. The decoder counts
  /// its callers, as zxing does, and only lets its worker go at zero; a
  /// stop with nothing started does nothing.
  int decoderUsers = 0;
  int decoderStarts = 0;

  @override
  Future<void> startDecoder() async {
    decoderStarts += 1;
    await decoderHold?.future;
    if (decoderFails) {
      decoderFails = false;
      throw StateError('no isolate');
    }
    decoderUsers += 1;
  }

  @override
  void stopDecoder() {
    if (decoderUsers > 0) decoderUsers -= 1;
  }

  @override
  Future<List<CameraDescription>> cameras() async => cameraList;

  @override
  CameraController controller(CameraDescription camera) {
    final controller = _FakeController(camera, this, hold?.future, refusal);
    controllers.add(controller);
    return controller;
  }

  Iterable<_FakeController> get live => controllers.where((c) => c.live);
}

Future<void> _show(WidgetTester tester, _FakeDevice device) async {
  // Every test leaves the app in front, as the next one expects.
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: Scaffold(
        body: QrCamera(onFrame: (_) {}, device: device),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await tester.pumpAndSettle();
}

void main() {
  group('the scanner camera', () {
    testWidgets('streams once the camera is up', (tester) async {
      final device = _FakeDevice();
      await _show(tester, device);

      expect(device.controllers, hasLength(1));
      expect(device.live, hasLength(1));
      expect(find.byKey(_preview), findsOneWidget);
      expect(find.text(_starting), findsNothing);
    });

    testWidgets('lets the sensor go when the app leaves, and opens it again '
        'on the way back', (tester) async {
      final device = _FakeDevice();
      await _show(tester, device);

      await _lifecycle(tester, AppLifecycleState.inactive);
      expect(device.controllers.single.disposed, isTrue);
      expect(find.text(_starting), findsOneWidget);

      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(device.controllers, hasLength(2));
      expect(device.live.single, same(device.controllers.last));
      expect(find.byKey(_preview), findsOneWidget);
    });

    // A permission prompt or a notification shade makes the app
    // inactive while the camera is still starting. The start in flight
    // sees the app gone and lets its sensor go, and the app comes back
    // while the platform is still releasing it. That return must still
    // end with a camera, not with "Starting the camera…" until the next
    // lifecycle change.
    testWidgets('opens the camera when the app comes back while a start '
        'lets the sensor go', (tester) async {
      final device = _FakeDevice()..hold = Completer<void>();
      await _show(tester, device);
      expect(find.text(_starting), findsOneWidget);

      await _lifecycle(tester, AppLifecycleState.inactive);
      device.disposal = Completer<void>();
      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();
      expect(device.controllers.single.disposed, isTrue);

      await _lifecycle(tester, AppLifecycleState.resumed);
      device.disposal!.complete();
      device.disposal = null;
      await tester.pumpAndSettle();

      expect(device.controllers.first.disposed, isTrue);
      expect(device.live, hasLength(1));
      expect(find.byKey(_preview), findsOneWidget);
      expect(find.text(_starting), findsNothing);
    });

    // The app in front may hold the sensor while this one is away, and
    // the start in flight fails on it. That is no fault of the camera:
    // the return to the front opens it.
    testWidgets('opens the camera on the way back after a start failed while '
        'the app was away', (tester) async {
      final device = _FakeDevice()
        ..hold = Completer<void>()
        ..refusal = 'CameraAccessRestricted';
      await _show(tester, device);
      device.refusal = null;

      await _lifecycle(tester, AppLifecycleState.inactive);
      device.disposal = Completer<void>();
      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();
      await _lifecycle(tester, AppLifecycleState.resumed);
      device.disposal!.complete();
      device.disposal = null;
      await tester.pumpAndSettle();

      expect(device.controllers, hasLength(2));
      expect(device.live.single, same(device.controllers.last));
      expect(find.text(_unavailable), findsNothing);
    });

    // The app comes back while the start in flight still waits on the
    // platform, which then fails it: the sensor was busy while the app
    // was away. The return was turned away as a second start, so the
    // failure must not be the last word.
    testWidgets('tries once more when a start fails after the app came '
        'back', (tester) async {
      final device = _FakeDevice()
        ..hold = Completer<void>()
        ..refusal = 'CameraAccessRestricted';
      await _show(tester, device);
      device.refusal = null;

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      final first = device.hold!;
      device.hold = Completer<void>();
      first.complete();
      await tester.pumpAndSettle();

      // The second try is under way: it says so, rather than the first
      // one's failure, which would send the user to paste the code.
      expect(device.controllers, hasLength(2));
      expect(find.text(_starting), findsOneWidget);
      expect(find.text(_unavailable), findsNothing);

      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();
      expect(device.live.single, same(device.controllers.last));
    });

    // Refused once, then granted in the system settings: the return
    // starts the camera, and a trip to the notification shade during
    // that start must not be read as the old refusal.
    testWidgets('a refusal granted since does not hold back a later '
        'return', (tester) async {
      final device = _FakeDevice()..refusal = 'CameraAccessDenied';
      await _show(tester, device);
      expect(find.text(_denied), findsOneWidget);

      device.refusal = null;
      device.hold = Completer<void>();
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(device.controllers, hasLength(2));

      await _lifecycle(tester, AppLifecycleState.inactive);
      device.disposal = Completer<void>();
      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();
      await _lifecycle(tester, AppLifecycleState.resumed);
      device.disposal!.complete();
      device.disposal = null;
      await tester.pumpAndSettle();

      expect(device.live, hasLength(1));
      expect(find.byKey(_preview), findsOneWidget);
    });

    testWidgets('lets the sensor go even when its stream will not stop', (
      tester,
    ) async {
      final device = _FakeDevice();
      await _show(tester, device);

      device.streamStopFails = true;
      await _lifecycle(tester, AppLifecycleState.inactive);
      expect(device.controllers.single.disposed, isTrue);
    });

    testWidgets('a decoder that failed to start is started again on the way '
        'back', (tester) async {
      final device = _FakeDevice()..decoderFails = true;
      await _show(tester, device);
      expect(find.text(_unavailable), findsOneWidget);

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(device.decoderStarts, 2);
      expect(device.live, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(device.decoderUsers, 0);
    });

    testWidgets('a start that comes back while the app is still away opens '
        'nothing', (tester) async {
      final device = _FakeDevice()..hold = Completer<void>();
      await _show(tester, device);

      await _lifecycle(tester, AppLifecycleState.inactive);
      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();

      expect(device.controllers.single.disposed, isTrue);
      expect(device.live, isEmpty);
    });

    testWidgets('closing the scanner during a start lets the sensor go', (
      tester,
    ) async {
      final device = _FakeDevice()..hold = Completer<void>();
      await _show(tester, device);

      await tester.pumpWidget(const SizedBox());
      device.hold!.complete();
      await tester.pumpAndSettle();

      expect(device.controllers.single.disposed, isTrue);
      expect(device.live, isEmpty);
      expect(device.decoderUsers, 0);
    });

    testWidgets('closing the scanner while the decoder starts lets the '
        'decoder go', (tester) async {
      final device = _FakeDevice()..decoderHold = Completer<void>();
      await _show(tester, device);

      await tester.pumpWidget(const SizedBox());
      device.decoderHold!.complete();
      await tester.pumpAndSettle();

      expect(device.decoderUsers, 0);
      expect(device.controllers, isEmpty);
    });

    testWidgets('starts the decoder once, however often the app comes back', (
      tester,
    ) async {
      final device = _FakeDevice();
      await _show(tester, device);
      for (var i = 0; i < 3; i += 1) {
        await _lifecycle(tester, AppLifecycleState.inactive);
        await _lifecycle(tester, AppLifecycleState.resumed);
      }
      expect(device.controllers, hasLength(4));
      expect(device.decoderStarts, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(device.decoderUsers, 0);
    });

    // Pulling the notification shade down and up again: the camera is
    // still being released when the app comes back. Opening it again
    // before the platform let it go meets a sensor still in use.
    testWidgets('waits for the sensor to be released before opening it '
        'again', (tester) async {
      final device = _FakeDevice();
      await _show(tester, device);

      device.disposal = Completer<void>();
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(device.controllers, hasLength(1));

      device.disposal!.complete();
      device.disposal = null;
      await tester.pumpAndSettle();
      expect(device.controllers, hasLength(2));
      expect(device.live.single, same(device.controllers.last));
      expect(find.byKey(_preview), findsOneWidget);
    });

    // The permission prompt makes the app inactive; a refusal brings it
    // back. The refusal stands: asking again at once would put the
    // prompt the user just answered back on screen.
    testWidgets('a refusal answered from the permission prompt is not asked '
        'again', (tester) async {
      final device = _FakeDevice()
        ..hold = Completer<void>()
        ..refusal = 'CameraAccessDenied';
      await _show(tester, device);

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      device.hold!.complete();
      device.hold = null;
      await tester.pumpAndSettle();

      expect(device.controllers, hasLength(1));
      expect(find.text(_denied), findsOneWidget);
    });

    testWidgets('says the camera access was refused', (tester) async {
      final device = _FakeDevice()..refusal = 'CameraAccessDenied';
      await _show(tester, device);

      expect(find.text(_denied), findsOneWidget);
      expect(device.live, isEmpty);
      // A start that failed holds nothing: its controller is let go,
      // and the next start opens the only one.
      expect(device.controllers.single.disposed, isTrue);
    });

    testWidgets('says no camera answered on a phone without one', (
      tester,
    ) async {
      final device = _FakeDevice()..cameraList = const [];
      await _show(tester, device);

      expect(find.text(_unavailable), findsOneWidget);
      expect(device.controllers, isEmpty);
    });
  });
}
