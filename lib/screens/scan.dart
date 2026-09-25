import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/bridge.dart';
import '../src/models.dart';
import '../src/screen.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/qr_camera.dart';

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

/// The most distinct frames one scan collects before the code says how
/// many parts it has. Every new frame sends the whole collection to the
/// core again, so an endless stream of distinct frames would cost more
/// at each one.
@visibleForTesting
const int maxScanFrames = 2000;

/// The most distinct frames any scan collects. A fountain code keeps
/// sending new frames that mix parts, and a camera that misses half of
/// them needs about twice as many frames as the code has parts: a large
/// PSBT shown at low density runs to well over a thousand parts.
@visibleForTesting
const int maxScanFramesCeiling = 10000;

/// The frames a scan may collect once the code has announced [total]
/// parts: three times as many, within [maxScanFrames] and
/// [maxScanFramesCeiling].
@visibleForTesting
int scanFrameLimit(int? total) =>
    ((total ?? 0) * 3).clamp(maxScanFrames, maxScanFramesCeiling);

class ScanScreenState extends ConsumerState<ScanScreen> {
  /// Distinct frames in scan order; the set makes the repeat check O(1).
  final List<String> _frames = [];
  final Set<String> _seen = {};

  /// Frames the core turned down on their own. Without them the code
  /// left under the camera is handed back several times a second, for
  /// the same answer every time.
  final Set<String> _refused = {};

  /// True once the screen popped: frames still decoded are ignored.
  bool _done = false;

  /// An assembly call is in flight; `_pending` remembers that a frame
  /// arrived meanwhile and the list must be fed again after it.
  bool _busy = false;
  bool _pending = false;

  /// Counts the collections dropped, so an answer about one that is
  /// gone is not taken for an answer about the next.
  int _collection = 0;

  QrProgress? _progress;
  String? _error;

  /// Holds the screen on while the camera is up: an animated code can
  /// take a while to line up, and a phone that dims meanwhile drops
  /// the frames collected so far along with the picture.
  late final ScreenKeeper _keeper = ref.read(screenKeeperProvider);

  @override
  void initState() {
    super.initState();
    _keeper.keepOn();
  }

  @override
  void dispose() {
    _keeper.release();
    super.dispose();
  }

  /// Feeds one decoded frame. A repeat and a frame already turned down
  /// are dropped; a new frame sends the whole collection to the core.
  @visibleForTesting
  void onFrame(String text) {
    if (_done || !mounted || _refused.contains(text) || !_seen.add(text)) {
      return;
    }
    if (_frames.length >= scanFrameLimit(_progress?.total)) {
      _startOver('This code has more parts than Gerfaut can read.');
      return;
    }
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
        if (_frames.isEmpty) return;
        final collection = _collection;
        final bridge = ref.read(bridgeProvider);
        final QrProgress progress;
        try {
          progress = await bridge.assembleQr(List.of(_frames));
        } on BridgeException catch (e) {
          // A refusal landing after the pop belongs to a scan the user
          // has walked away from.
          if (!mounted || _done) return;
          // Or to a collection already dropped meanwhile.
          if (collection != _collection) continue;
          // The core refused what was collected: a PSBT, an envelope it
          // cannot open.
          _startOver(e.message);
          return;
        }
        if (!mounted || _done) return;
        // The collection was dropped while this call was out: what it
        // says is about frames that are gone.
        if (collection != _collection) continue;
        final text = progress.text;
        if (progress.complete) {
          if (text == null || text.trim().isEmpty) {
            // Every part arrived and they add up to nothing. Popping on
            // that hands the caller an empty scan, which is exactly what
            // a scanner closing on its own looks like from the page
            // underneath.
            _startOver('This code came out empty.');
            return;
          }
          _done = true;
          Navigator.of(context).pop(text);
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

  /// Drops the collection and says why, leaving the camera running.
  ///
  /// The counter goes with it: what it counted is no longer being
  /// assembled, and a bar left standing would show progress towards
  /// nothing. Only a lone frame is provably the one at fault — further
  /// along any of them could be, so none is barred from a fresh try.
  void _startOver(String reason) {
    _collection++;
    if (_frames.length == 1) _refused.add(_frames.first);
    _frames.clear();
    _seen.clear();
    setState(() {
      _progress = null;
      _error = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final progress = _progress;
    final camera =
        widget.cameraBuilder?.call(onFrame) ?? QrCamera(onFrame: onFrame);
    return Scaffold(
      appBar: GerfautAppBar.text('Scan a QR code'),
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
              // A refusal arrives while the camera holds the eye, so it
              // is announced; the standing caption is not, or it would
              // be read out on every rebuild.
              child: Semantics(
                liveRegion: _error != null,
                child: Text(
                  _error ?? widget.caption,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  textAlign: TextAlign.center,
                ),
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
              // The value of a progress bar is spoken as a percentage,
              // and the count of frames is the whole point here; the
              // label is the only part that takes words.
              semanticsLabel:
                  'Animated code progress, ${progress.received} of '
                  '${progress.total} frames received',
            ),
          ),
        ],
      ),
    );
  }
}
