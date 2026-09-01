import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Live camera feed, every frame decoded on the device.
///
/// Gerfaut drives the camera itself instead of using the view the
/// decoder package ships with: that one reads a small square in the
/// middle of the sensor image and waits a full second between two
/// attempts. A descriptor code fills the viewfinder, so it never fell
/// inside that square, and an animated code loops far faster than one
/// frame per second. Here the whole frame is read, as often as the
/// decoder keeps up and at most fifteen times a second, the way the
/// desktop scanner already works.
class QrCamera extends StatefulWidget {
  const QrCamera({super.key, required this.onFrame});

  /// Called with the text of each decoded frame, repeats included: the
  /// caller decides what to make of a frame it has already seen.
  final ValueChanged<String> onFrame;

  /// 1080p. A dense descriptor code carries around a hundred modules
  /// per side; 720p leaves too few pixels on each of them to survive a
  /// hand-held shot.
  static const ResolutionPreset resolution = ResolutionPreset.veryHigh;

  /// The least time between two decodes: 66 ms, at most fifteen a
  /// second. Every decode copies the frame's whole luminance plane,
  /// about two megabytes at 1080p, over to the decoder; a phone
  /// streaming thirty frames a second would otherwise spend its time
  /// copying rather than reading. A frame arriving sooner is dropped,
  /// never queued, so the scanner still works on the freshest picture,
  /// and an animated code at five frames a second is still read three
  /// times per frame. A fixed pause between attempts is what made the
  /// packaged view unusable; this is a ceiling, not a pause.
  static const Duration minDecodeInterval = Duration(milliseconds: 66);

  /// Whether a frame arriving at [now] is decoded, given when the last
  /// decode started (null before the first). Pure, so the cadence is
  /// tested without a camera.
  @visibleForTesting
  static bool shouldDecode(DateTime? lastStartedAt, DateTime now) =>
      lastStartedAt == null ||
      now.difference(lastStartedAt) >= minDecodeInterval;

  /// How a frame is handed to the decoder: the whole image, never a
  /// crop, read as a luminance plane. Exposed for the test that guards
  /// it, because a crop here stays invisible until a real code fails.
  @visibleForTesting
  static zxing.DecodeParams decodeParams(int width, int height) =>
      zxing.DecodeParams(
        imageFormat: zxing.ImageFormat.lum,
        format: zxing.Format.qrCode,
        width: width,
        height: height,
        tryRotate: true,
        // Finds a code that fills the frame in one downscaled pass
        // instead of walking the full resolution first.
        tryDownscale: true,
      );

  @override
  State<QrCamera> createState() => _QrCameraState();
}

/// What the camera is doing, and why it may be showing nothing.
enum _Feed { starting, running, denied, unavailable }

class _QrCameraState extends State<QrCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  _Feed _feed = _Feed.starting;
  bool _torch = false;

  /// A decode is in flight: further frames are dropped rather than
  /// queued, so the scanner always works on the freshest picture.
  bool _decoding = false;

  /// When the last decode started, for [QrCamera.shouldDecode].
  DateTime? _lastDecodeStartedAt;

  /// Set on dispose: a decode that returns late must not touch the
  /// tree, and the camera must not be started again.
  bool _closed = false;

  /// A start is under way. Two of them at once would open the sensor
  /// twice and leak the first one, which the lifecycle makes easy: an
  /// app can be resumed before the previous start has finished.
  bool _starting = false;

  /// The decoder itself broke down, as opposed to a frame that simply
  /// held no code. The second is the normal case and says nothing; the
  /// first would otherwise look exactly like a camera pointed at a
  /// wall, which is how a scanner stays broken for weeks.
  String? _trouble;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    zxing.zx.stopCameraProcessing();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_controller == null) unawaited(_start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // The camera belongs to whatever is in front: a scanner left
        // behind keeps neither the sensor nor the lamp.
        unawaited(_stop());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _start() async {
    if (_starting || _closed) return;
    _starting = true;
    try {
      await zxing.zx.startCameraProcessing();
      final cameras = await availableCameras();
      if (_closed || !mounted) return;
      if (cameras.isEmpty) {
        setState(() => _feed = _Feed.unavailable);
        return;
      }
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        QrCamera.resolution,
        enableAudio: false,
        // Named rather than left to the platform: the decoder reads a
        // luminance plane, and a device streaming anything else would
        // hand it bytes it cannot make sense of.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (_closed || !mounted) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onImage);
      if (_closed || !mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _torch = false;
        _feed = _Feed.running;
      });
    } on CameraException catch (error) {
      if (_closed || !mounted) return;
      setState(
        () => _feed = error.code == 'CameraAccessDenied'
            ? _Feed.denied
            : _Feed.unavailable,
      );
    } catch (_) {
      if (_closed || !mounted) return;
      setState(() => _feed = _Feed.unavailable);
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    if (mounted && !_closed) setState(() => _feed = _Feed.starting);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // A controller the platform already tore down: nothing to stop.
    }
    await controller.dispose();
  }

  Future<void> _onImage(CameraImage image) async {
    if (_decoding || _closed || !mounted) return;
    final now = DateTime.now();
    if (!QrCamera.shouldDecode(_lastDecodeStartedAt, now)) return;
    _lastDecodeStartedAt = now;
    _decoding = true;
    // A debug build times every decode and prints it under the
    // `flutter` log tag, each line starting with `qr-decode`: what a
    // real phone makes of a frame is one
    // `adb logcat -s flutter | grep qr-decode` away.
    final clock = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      final code = await zxing.zx.processCameraImage(
        image,
        QrCamera.decodeParams(image.width, image.height),
      );
      if (clock != null) {
        debugPrint(
          'qr-decode ${clock.elapsedMilliseconds} ms, '
          '${image.width}x${image.height}, '
          '${code.isValid ? 'code' : 'nothing'}',
        );
      }
      final text = code.text?.trim();
      if (_closed || !mounted || !code.isValid) return;
      if (text != null && text.isNotEmpty) widget.onFrame(text);
    } catch (error) {
      // Said once, then the loop carries on: a decoder that refuses
      // every frame must not pass for an empty viewfinder.
      if (_trouble == null && mounted && !_closed) {
        setState(() => _trouble = 'The decoder failed: $error');
      }
    } finally {
      _decoding = false;
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final wanted = !_torch;
    try {
      await controller.setFlashMode(wanted ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = wanted);
    } on CameraException {
      // A camera without a lamp: the button simply does nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _CameraNotice(feed: _feed);
    }
    final trouble = _trouble;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Cover(controller: controller),
        const Positioned.fill(child: IgnorePointer(child: _FrameGuide())),
        Positioned(
          top: GerfautSpacing.md,
          right: GerfautSpacing.md,
          child: _TorchButton(on: _torch, onPressed: _toggleTorch),
        ),
        if (trouble != null)
          Positioned(
            left: GerfautSpacing.md,
            right: GerfautSpacing.md,
            bottom: GerfautSpacing.md,
            child: _Trouble(message: trouble),
          ),
      ],
    );
  }
}

/// The picture, filling the box without distorting it. The preview
/// widget takes the shape of the sensor for the current orientation,
/// so the box is measured from that ratio rather than guessed.
class _Cover extends StatelessWidget {
  const _Cover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sensor = controller.value.aspectRatio;
        final upright =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        final preview = upright ? 1 / sensor : sensor;
        final box = constraints.maxWidth / constraints.maxHeight;
        final width = preview > box
            ? constraints.maxHeight * preview
            : constraints.maxWidth;
        final height = preview > box
            ? constraints.maxHeight
            : constraints.maxWidth / preview;
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: width,
              height: height,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

/// A decoder that broke down, said on the picture itself.
class _Trouble extends StatelessWidget {
  const _Trouble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final dark = GerfautTokens.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: dark.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(GerfautRadius.md),
      ),
      child: Text(
        message,
        style: dark.bodySmall.copyWith(color: dark.alert),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Why the picture is missing, in one sentence. A black rectangle would
/// leave a starting camera and a refused permission looking the same.
class _CameraNotice extends StatelessWidget {
  const _CameraNotice({required this.feed});

  final _Feed feed;

  @override
  Widget build(BuildContext context) {
    final dark = GerfautTokens.dark;
    final message = switch (feed) {
      _Feed.starting || _Feed.running => 'Starting the camera…',
      _Feed.denied =>
        'Gerfaut has no access to the camera. Grant it in the system '
            'settings, or paste the descriptor in by hand.',
      _Feed.unavailable =>
        'No camera answered on this device. Paste the descriptor in by '
            'hand instead.',
    };
    return ColoredBox(
      color: dark.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.lg),
          child: Text(
            message,
            style: dark.bodySmall.copyWith(color: dark.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// The lamp, for a code printed on paper. A dark island like the
/// assembly panel: the live picture belongs to neither theme.
class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = GerfautTokens.dark;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Turn the light off' : 'Turn the light on',
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: dark.surface.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              on ? LucideIcons.flashlight : LucideIcons.flashlightOff,
              size: 20,
              color: on ? dark.primary : dark.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Four corner brackets around the middle of the picture. A hint, not a
/// mask: the whole frame is read, so nothing outside them is lost.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FrameGuidePainter(GerfautTokens.dark.primary));
  }
}

class _FrameGuidePainter extends CustomPainter {
  const _FrameGuidePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.72;
    final square = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final arm = side * 0.14;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final (corner, dx, dy) in <(Offset, double, double)>[
      (square.topLeft, 1, 1),
      (square.topRight, -1, 1),
      (square.bottomLeft, 1, -1),
      (square.bottomRight, -1, -1),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * arm)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx + dx * arm, corner.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_FrameGuidePainter old) => old.color != color;
}
