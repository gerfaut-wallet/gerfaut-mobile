import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../src/bridge.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

/// Builds the camera view around the sink every decoded frame goes to.
typedef CameraBuilder = Widget Function(ValueChanged<String> onFrame);

/// Camera QR scanner for wallet material. Collects the distinct frames
/// the camera decodes, lets the core assemble them (a plain code, or a
/// UR or BBQr envelope animated over several frames) and pops with the
/// assembled text; the caller feeds it to the input classifier.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({
    super.key,
    this.caption = walletCaption,
    @visibleForTesting this.cameraBuilder,
  });

  /// What the scanner expects, shown under the camera.
  static const String walletCaption =
      'Point the camera at a descriptor, extended public key, or address '
      'QR code: plain text, UR, or BBQr, animated or not.';

  /// The caption for a signed transaction or PSBT.
  static const String transactionCaption =
      'Point the camera at a signed transaction or PSBT QR code: '
      'crypto-psbt UR or BBQr, animated or not.';

  final String caption;

  /// Replaces the camera view; tests use it to push frames by hand.
  final CameraBuilder? cameraBuilder;

  @override
  ConsumerState<ScanScreen> createState() => ScanScreenState();
}

class ScanScreenState extends ConsumerState<ScanScreen> {
  /// Distinct frames in scan order; the set makes the repeat check O(1).
  final List<String> _frames = [];
  final Set<String> _seen = {};

  /// True once the screen popped: frames still decoded are ignored.
  bool _done = false;

  /// An assembly call is in flight; `_pending` remembers that a frame
  /// arrived meanwhile and the list must be fed again after it.
  bool _busy = false;
  bool _pending = false;

  QrProgress? _progress;
  String? _error;

  void _onScan(Code code) {
    final text = code.text;
    if (text == null || text.isEmpty) return;
    onFrame(text);
  }

  /// Feeds one decoded frame. A repeat is dropped; a new frame sends
  /// the whole collection to the core.
  @visibleForTesting
  void onFrame(String text) {
    if (_done || !mounted || !_seen.add(text)) return;
    _frames.add(text);
    if (_busy) {
      _pending = true;
      return;
    }
    _assemble();
  }

  Future<void> _assemble() async {
    _busy = true;
    try {
      do {
        _pending = false;
        final bridge = ref.read(bridgeProvider);
        final QrProgress progress;
        try {
          progress = await bridge.assembleQr(List.of(_frames));
        } on BridgeException catch (e) {
          if (!mounted || _done) return;
          // The core refused what was collected (a PSBT, an envelope it
          // cannot open): start over, the camera keeps running.
          _frames.clear();
          _seen.clear();
          setState(() {
            _progress = null;
            _error = e.message;
          });
          return;
        }
        if (!mounted || _done) return;
        if (progress.complete) {
          _done = true;
          Navigator.of(context).pop(progress.text);
          return;
        }
        setState(() {
          _progress = progress;
          _error = null;
        });
      } while (_pending);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final progress = _progress;
    final camera =
        widget.cameraBuilder?.call(onFrame) ??
        ReaderWidget(
          codeFormat: Format.qrCode,
          showGallery: false,
          showToggleCamera: false,
          tryHarder: true,
          onScan: _onScan,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a QR code')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  camera,
                  if (progress != null && progress.inProgress)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _AssemblyPanel(progress: progress),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: Text(
                _error ?? widget.caption,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress of an animated code, laid over the bottom of the camera
/// view. The live picture belongs to neither theme, so the panel is a
/// dark island drawn with the dark tokens in both themes, the way the
/// QR colors stay fixed.
class _AssemblyPanel extends StatelessWidget {
  const _AssemblyPanel({required this.progress});

  final QrProgress progress;

  @override
  Widget build(BuildContext context) {
    final dark = GerfautTokens.dark;
    return Container(
      margin: const EdgeInsets.all(GerfautSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm + GerfautSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: dark.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(GerfautRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keep the camera on the animated code',
                  style: dark.bodySmall,
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              Text(
                '${progress.received} / ${progress.total}',
                style: dark.figureOf(weight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: GerfautSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(GerfautRadius.full),
            child: LinearProgressIndicator(
              value: progress.received / progress.total,
              minHeight: GerfautSpacing.xs,
              backgroundColor: dark.surfaceSunken,
              color: dark.primary,
              semanticsLabel: 'Animated code progress',
            ),
          ),
        ],
      ),
    );
  }
}
