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

  /// The error code the next controller's start fails with.
  String? refusal;

  List<CameraDescription> cameraList = const [_back];
  int decoderStops = 0;

  @override
  Future<void> startDecoder() async {}

  @override
  void stopDecoder() => decoderStops += 1;

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
      expect(device.decoderStops, 1);
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
