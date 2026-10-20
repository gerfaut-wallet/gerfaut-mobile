import 'dart:collection';

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

/// Camera QR scanner for wallet material. Sends each distinct frame the
/// camera decodes, once, to a scan the core holds while the screen is
/// up; the core assembles them (a plain code, or a UR or BBQr envelope
/// animated over several frames) and the screen pops with the completed
/// [QrProgress]: the assembled text, which the caller feeds to the input
/// classifier, and what the core assumed reading the code.
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

/// What the scanner says of a code with more parts than Gerfaut reads:
/// one the core turns away by the count it announces, or by the frames
/// it took without coming together (the core keeps count). The desktop
/// app says the same.
const String _tooManyParts =
    'This code has more parts than Gerfaut can read. If the wallet offers a '
    'denser QR code, show that one instead.';

/// A code whose parts all came and add up to nothing.
const String _emptyCode =
    'This code came through empty. Export it again from the wallet.';

class ScanScreenState extends ConsumerState<ScanScreen> {
  /// The scan the core holds for this screen, opened with it and let go
  /// when it goes; a fresh one after a frame fails.
  late Future<int> _scan;
  late final GerfautBridge _bridge;
  bool _released = false;

  /// A lone frame sent a second time, to a fresh scan, after its first
  /// try failed: only a second refusal bars it.
  String? _secondTry;

  /// Distinct frames seen in this collection; the core holds them.
  final Set<String> _seen = {};

  /// Frames seen while a call was out, sent in order after it.
  final ListQueue<String> _queue = ListQueue();

  /// Frames the core took in this collection, and the first of them:
  /// the one at fault when it is alone.
  int _taken = 0;
  String? _lone;

  /// Frames the core turned down on their own. Without them the code
  /// left under the camera is handed back several times a second, for
  /// the same answer every time.
  final Set<String> _refused = {};

  /// True once the screen popped, or the scan stopped: frames still
  /// decoded are ignored.
  bool _done = false;

  /// The scan stopped on a code too large to read: the camera is off,
  /// and the reason stays.
  bool _stopped = false;

  /// The screen is held on: from the start until the camera goes.
  bool _keeping = true;

  /// A call is in flight; frames seen meanwhile wait in `_queue`.
  bool _busy = false;

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
    // The bridge is read here: `ref` is not to be used once disposing.
    _bridge = ref.read(bridgeProvider);
    _openScan();
  }

  void _openScan() {
    _scan = _bridge.openQrScan();
    // A scan that would not open is said by the first frame sent to it.
    _scan.ignore();
  }

  void _closeScan() => _scan.then(_bridge.closeQrScan).ignore();

  /// A fresh scan in the core, the old one let go. After any failure:
  /// the core starts its own scan over when it refuses, but a scan it
  /// dropped (more scans open than it keeps), one that never opened, or
  /// a call that failed on the way holds nothing the screen can count
  /// on, and a fresh one is the same state on both sides.
  void _reopen() {
    _closeScan();
    _openScan();
  }

  @override
  void dispose() {
    _letScreenGo();
    _release();
    super.dispose();
  }

  /// Lets the core drop the scan, once.
  void _release() {
    if (_released) return;
    _released = true;
    _closeScan();
  }

  void _letScreenGo() {
    if (!_keeping) return;
    _keeping = false;
    _keeper.release();
  }

  /// Feeds one decoded frame. A repeat and a frame already turned down
  /// are dropped; a new frame goes to the core, once.
  @visibleForTesting
  void onFrame(String text) {
    if (_done || !mounted || _refused.contains(text) || !_seen.add(text)) {
      return;
    }
    _queue.add(text);
    if (_busy) return;
    _assemble();
  }

  Future<void> _assemble() async {
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final frame = _queue.removeFirst();
        final again = _secondTry == frame;
        _secondTry = null;
        _taken++;
        if (_taken == 1) _lone = frame;
        final collection = _collection;
        final QrProgress progress;
        try {
          progress = await _bridge.pushQrFrame(await _scan, frame);
        } on BridgeException catch (e) {
          // A refusal landing after the pop belongs to a scan the user
          // has walked away from.
          if (!mounted || _done) return;
          // Or to a collection already dropped meanwhile.
          if (collection != _collection) continue;
          // The core refused what was collected: a PSBT or an envelope
          // it cannot open starts over; a code past what Gerfaut reads
          // stops the scan.
          if (e.kind == 'too_many_parts') {
            _stop(_tooManyParts);
            return;
          }
          _reopen();
          if (_taken == 1 && !again) {
            // Not yet proven at fault: it may have met a scan the core
            // no longer held. Once more, on the fresh scan.
            _taken = 0;
            _lone = null;
            _secondTry = frame;
            _queue.addFirst(frame);
            continue;
          }
          // The core's sentence says what it saw and what to show
          // instead; a private key is said as at the import.
          _startOver(materialRefusal(e));
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
            _startOver(_emptyCode);
            return;
          }
          _done = true;
          _release();
          Navigator.of(context).pop(progress);
          return;
        }
        setState(() {
          _progress = progress;
          _error = null;
        });
      }
    } finally {
      _busy = false;
    }
  }

  /// Drops the collection and says why, leaving the camera running; the
  /// core has started its scan again on the same answer.
  ///
  /// The counter goes with it: what it counted is no longer being
  /// assembled, and a bar left standing would show progress towards
  /// nothing. Only a lone frame is provably the one at fault — further
  /// along any of them could be, so none is barred from a fresh try.
  void _startOver(String reason) {
    _collection++;
    final lone = _lone;
    if (_taken == 1 && lone != null) _refused.add(lone);
    _forget();
    setState(() {
      _progress = null;
      _error = reason;
    });
  }

  /// Ends the scan on a code too large to read: the camera goes and the
  /// reason stays. A fountain code never runs out of new frames, and
  /// scanning on would only start a collection the core refuses again,
  /// a moment later, the reason gone meanwhile.
  void _stop(String reason) {
    _done = true;
    _collection++;
    _forget();
    _release();
    _letScreenGo();
    setState(() {
      _stopped = true;
      _progress = null;
      _error = reason;
    });
  }

  /// Forgets the frames of the collection, those still waiting too.
  void _forget() {
    _queue.clear();
    _seen.clear();
    _taken = 0;
    _lone = null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final progress = _progress;
    // Out of the tree, the camera lets the sensor go.
    final camera = _stopped
        ? ColoredBox(color: tokens.surfaceSunken)
        : widget.cameraBuilder?.call(onFrame) ?? QrCamera(onFrame: onFrame);
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
