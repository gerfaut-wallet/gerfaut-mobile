import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// Receive address display: the full address in mono, copy with
/// explicit feedback, index shown, and a way to skip to the next
/// unused index. Single-address wallets show their one address.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  bool _copied = false;

  /// Peek distance past the next unused address. Skipping retires
  /// nothing, and leaving the screen returns to the first unused one.
  int _offset = 0;

  Future<void> _copy(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final meta = ref.watch(snapshotProvider(widget.walletId)).valueOrNull?.meta;
    final single = meta?.isSingleAddress ?? false;
    final gapLimit = meta?.gapLimit ?? 20;
    final addresses = ref.watch(
      receiveProvider((walletId: widget.walletId, lookahead: _offset)),
    );
    final list = addresses.valueOrNull;
    final entry = list == null || list.isEmpty
        ? null
        : list[min(_offset, list.length - 1)];

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: addresses.hasError
              ? Center(
                  child: Text(
                    'The receive address could not be derived.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                )
              : entry == null
              ? Center(
                  child: Text(
                    'Deriving address…',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Semantics(
                                label: 'Address QR code',
                                image: true,
                                child: Container(
                                  width: 220,
                                  padding: const EdgeInsets.all(
                                    GerfautSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: GerfautQr.background,
                                    borderRadius: BorderRadius.circular(
                                      GerfautRadius.lg,
                                    ),
                                    border: Border.all(color: tokens.border),
                                  ),
                                  child: QrImageView(
                                    data: entry.address,
                                    backgroundColor: GerfautQr.background,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: GerfautQr.foreground,
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape:
                                          QrDataModuleShape.square,
                                      color: GerfautQr.foreground,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: GerfautSpacing.md),
                            Text(
                              single
                                  ? 'WATCHED ADDRESS'
                                  : _offset == 0
                                  ? 'NEXT UNUSED ADDRESS · INDEX '
                                        '${entry.index}'
                                  : 'UNUSED ADDRESS · INDEX ${entry.index}',
                              style: tokens.label.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: GerfautSpacing.sm),
                            Container(
                              padding: const EdgeInsets.all(GerfautSpacing.md),
                              decoration: BoxDecoration(
                                color: tokens.surfaceSunken,
                                borderRadius: BorderRadius.circular(
                                  GerfautRadius.sm,
                                ),
                              ),
                              child: SelectableText(
                                entry.address,
                                style: tokens.data.copyWith(
                                  fontSize: tokens.body.fontSize,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            if (entry.derivation != null) ...[
                              const SizedBox(height: GerfautSpacing.md),
                              Text(
                                'DERIVATION PATH',
                                style: tokens.label.copyWith(
                                  color: tokens.textMuted,
                                ),
                              ),
                              const SizedBox(height: GerfautSpacing.xs),
                              Text(entry.derivation!, style: tokens.data),
                            ],
                            if (!single && _offset >= gapLimit) ...[
                              const SizedBox(height: GerfautSpacing.md),
                              // Peeking this far outruns what scanning
                              // software derives: state it in the
                              // pending tint, not as an alarm.
                              Container(
                                padding: const EdgeInsets.all(
                                  GerfautSpacing.sm + 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.pendingSurface,
                                  borderRadius: BorderRadius.circular(
                                    GerfautRadius.md,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        LucideIcons.triangleAlert,
                                        size: 16,
                                        color: tokens.pending,
                                      ),
                                    ),
                                    const SizedBox(width: GerfautSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'This is $_offset addresses past '
                                        'the next unused one — beyond the '
                                        'gap limit of $gapLimit, other '
                                        'wallet software may not detect '
                                        'funds received here.',
                                        style: tokens.bodySmall.copyWith(
                                          color: tokens.pending,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: GerfautSpacing.md),
                            // The one warning that must not read as small
                            // print: a highlighted panel, not a muted
                            // footnote.
                            Container(
                              padding: const EdgeInsets.all(
                                GerfautSpacing.sm + 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.alertSurface,
                                borderRadius: BorderRadius.circular(
                                  GerfautRadius.md,
                                ),
                                border: Border.all(
                                  color: tokens.alert.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      LucideIcons.triangleAlert,
                                      size: 16,
                                      color: tokens.alert,
                                    ),
                                  ),
                                  const SizedBox(width: GerfautSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Verify this address on your '
                                          'signing device before sharing '
                                          'it.',
                                          style: tokens.bodySmall.copyWith(
                                            color: tokens.alert,
                                            fontWeight: FontWeight.w500,
                                            fontVariations: const [
                                              FontVariation('wght', 500),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gerfaut only watches: it never '
                                          'holds the keys behind it.',
                                          style: tokens.bodySmall.copyWith(
                                            color: tokens.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: GerfautSpacing.md),
                    PrimaryButton(
                      label: _copied ? 'Copied' : 'Copy address',
                      icon: _copied ? LucideIcons.check : LucideIcons.copy,
                      expand: true,
                      onPressed: () => _copy(entry.address),
                    ),
                    if (!single) ...[
                      const SizedBox(height: GerfautSpacing.sm),
                      SecondaryButton(
                        label: 'Next address',
                        icon: LucideIcons.skipForward,
                        onPressed: () => setState(() => _offset += 1),
                      ),
                      if (_offset > 0) ...[
                        const SizedBox(height: GerfautSpacing.sm),
                        GhostButton(
                          label: 'First unused',
                          icon: LucideIcons.rotateCcw,
                          onPressed: () => setState(() => _offset = 0),
                        ),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
