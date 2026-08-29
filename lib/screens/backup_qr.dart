import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/tokens.dart';

/// How long each frame of the animated code stays on screen.
const Duration frameInterval = Duration(milliseconds: 200);

/// The sealed backup as an animated QR code: the frames loop until the
/// screen is left, and the other device may join at any of them. A
/// backup small enough for one frame shows a static code.
class BackupQrScreen extends StatefulWidget {
  const BackupQrScreen({super.key, required this.frames});

  /// UR frames, as the core hands them out.
  final List<String> frames;

  @override
  State<BackupQrScreen> createState() => _BackupQrScreenState();
}

class _BackupQrScreenState extends State<BackupQrScreen> {
  Timer? _timer;
  int _index = 0;

  bool get _animated => widget.frames.length > 1;

  @override
  void initState() {
    super.initState();
    if (_animated) {
      _timer = Timer.periodic(frameInterval, (_) {
        setState(() => _index = (_index + 1) % widget.frames.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup QR code')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            // Bytewords read the same in either case, and uppercase lets
            // the encoder use the alphanumeric mode: fewer modules for
            // the same frame, which a camera catches sooner.
            _QrCard(
              data: widget.frames[_index].toUpperCase(),
              // A QR code is silent to a screen reader unless it is
              // told what it is; the frame number also lets a test
              // watch the animation advance.
              semanticsLabel: _animated
                  ? 'Backup QR code, frame ${_index + 1} of '
                        '${widget.frames.length}'
                  : 'Backup QR code',
            ),
            const SizedBox(height: GerfautSpacing.md),
            Text(
              'Scan it with Gerfaut on the other device',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              textAlign: TextAlign.center,
            ),
            if (_animated) ...[
              const SizedBox(height: GerfautSpacing.xs),
              Text(
                '${_index + 1} / ${widget.frames.length}',
                style: tokens.figureOf(color: tokens.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The code on its white card, filling the width. A QR code is data,
/// not chrome: dark on light in both themes, the way the receive
/// screen draws it.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.data, required this.semanticsLabel});

  final String data;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm),
      decoration: BoxDecoration(
        color: GerfautQr.background,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: QrImageView(
          data: data,
          semanticsLabel: semanticsLabel,
          version: QrVersions.auto,
          // The lowest correction level keeps a dense frame readable:
          // fewer modules, each of them larger on the screen.
          errorCorrectionLevel: QrErrorCorrectLevel.L,
          backgroundColor: GerfautQr.background,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: GerfautQr.foreground,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: GerfautQr.foreground,
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
