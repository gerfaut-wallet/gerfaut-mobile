import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../theme/tokens.dart';

/// Camera QR scanner for wallet material. Pops with the decoded text of
/// the first valid code; the caller feeds it to the input classifier.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  void _onScan(Code code) {
    final text = code.text;
    if (_done || text == null || text.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a QR code')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ReaderWidget(
                codeFormat: Format.qrCode,
                showGallery: false,
                showToggleCamera: false,
                tryHarder: true,
                onScan: _onScan,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: Text(
                'Point the camera at a descriptor, extended public key, or '
                'address QR code.',
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
