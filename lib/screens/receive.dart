import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/count_badge.dart';
import '../widgets/status_pill.dart';

/// Side of the small QR code in the address block; tapping it opens the
/// large one.
const double _qrSide = 140;

/// Rows an address card shows before "Show all".
const int _collapsedRows = 5;

/// Receive: the next unused address first, with its QR code, copy with
/// explicit feedback and a way to skip ahead; then the audit of every
/// revealed address, external and change in their own cards. The whole
/// screen scrolls as one. Single-address wallets show their one address
/// and one card.
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  void _enlarge(String address) {
    showDialog<void>(
      context: context,
      barrierLabel: 'Close',
      builder: (_) => _QrDialog(address: address),
    );
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
    final audit = ref.watch(addressListProvider(widget.walletId));

    return Scaffold(
      appBar: GerfautAppBar.text('Receive'),
      body: SafeArea(
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
            : ListView(
                padding: const EdgeInsets.all(GerfautSpacing.md),
                children: [
                  _AddressBlock(
                    entry: entry,
                    single: single,
                    offset: _offset,
                    gapLimit: gapLimit,
                    copied: _copied,
                    onCopy: () => _copy(entry.address),
                    onEnlarge: () => _enlarge(entry.address),
                    onNext: () => setState(() => _offset += 1),
                    onFirst: () => setState(() => _offset = 0),
                  ),
                  const SizedBox(height: GerfautSpacing.lg),
                  ..._auditCards(tokens, audit, single),
                ],
              ),
      ),
    );
  }

  /// The revealed addresses, one card per keychain.
  List<Widget> _auditCards(
    GerfautTokens tokens,
    AsyncValue<AddressList> audit,
    bool single,
  ) {
    final list = audit.valueOrNull;
    if (list == null) {
      return [
        Text(
          audit.hasError
              ? 'Addresses could not be loaded.'
              : 'Loading addresses…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ];
    }
    return [
      if (single)
        _AddressCard(
          title: 'Watched address',
          hint: 'The one address this wallet watches.',
          rows: list.external,
        )
      else ...[
        _AddressCard(
          title: 'External',
          hint: 'Receive addresses, in derivation order.',
          rows: list.external,
        ),
        const SizedBox(height: GerfautSpacing.gutter),
        _AddressCard(
          title: 'Change',
          hint: 'Internal addresses used by outgoing transactions.',
          rows: list.internal,
          emptyText: 'No change addresses revealed yet.',
        ),
      ],
      if (list.truncated) ...[
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Long keychains are capped: only the first 200 addresses of each '
          'are listed.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    ];
  }
}

/// The address on offer: a small QR code beside its identity, the full
/// address in mono, the actions, and the warnings that go with it.
class _AddressBlock extends StatelessWidget {
  const _AddressBlock({
    required this.entry,
    required this.single,
    required this.offset,
    required this.gapLimit,
    required this.copied,
    required this.onCopy,
    required this.onEnlarge,
    required this.onNext,
    required this.onFirst,
  });

  final AddressEntry entry;
  final bool single;
  final int offset;
  final int gapLimit;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onEnlarge;
  final VoidCallback onNext;
  final VoidCallback onFirst;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final label = single
        ? 'WATCHED ADDRESS'
        : offset == 0
        ? 'NEXT UNUSED ADDRESS · INDEX ${entry.index}'
        : 'UNUSED ADDRESS · INDEX ${entry.index}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Address QR code, tap to enlarge',
              child: InkWell(
                borderRadius: BorderRadius.circular(GerfautRadius.lg),
                onTap: onEnlarge,
                child: _QrCard(address: entry.address, side: _qrSide),
              ),
            ),
            const SizedBox(width: GerfautSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tokens.label.copyWith(color: tokens.textMuted),
                  ),
                  if (entry.derivation != null) ...[
                    const SizedBox(height: GerfautSpacing.sm),
                    Text(
                      'DERIVATION PATH',
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(entry.derivation!, style: tokens.data),
                  ],
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Tap the code to enlarge it.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.md),
        Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: SelectableText(
            entry.address,
            style: tokens.data.copyWith(
              fontSize: tokens.body.fontSize,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: GerfautSpacing.md),
        PrimaryButton(
          label: copied ? 'Copied' : 'Copy address',
          icon: copied ? LucideIcons.check : LucideIcons.copy,
          expand: true,
          onPressed: onCopy,
        ),
        if (!single) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Next address',
                  icon: LucideIcons.skipForward,
                  onPressed: onNext,
                ),
              ),
              if (offset > 0) ...[
                const SizedBox(width: GerfautSpacing.sm),
                GhostButton(
                  label: 'First unused',
                  icon: LucideIcons.rotateCcw,
                  onPressed: onFirst,
                ),
              ],
            ],
          ),
        ],
        if (!single && offset >= gapLimit) ...[
          const SizedBox(height: GerfautSpacing.md),
          // Peeking this far outruns what scanning software derives:
          // state it in the pending tint, not as an alarm.
          _Notice(
            color: tokens.pending,
            surface: tokens.pendingSurface,
            bordered: false,
            title:
                'This is $offset addresses past the next unused one. Beyond '
                'the gap limit of $gapLimit, other wallet software may not '
                'detect funds received here.',
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        // The one warning that must not read as small print: a
        // highlighted panel, not a muted footnote.
        _Notice(
          color: tokens.alert,
          surface: tokens.alertSurface,
          bordered: true,
          title:
              'Verify this address on your signing device before sharing it.',
          hint: 'Gerfaut only watches: it never holds the keys behind it.',
        ),
      ],
    );
  }
}

/// A tinted panel with an icon, a line that matters and an optional
/// quieter one under it.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.surface,
    required this.bordered,
    required this.title,
    this.hint,
  });

  final Color color;
  final Color surface;
  final bool bordered;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: bordered
            ? Border.all(color: color.withValues(alpha: 0.25))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.triangleAlert, size: 16, color: color),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tokens.bodySmall.copyWith(
                    color: color,
                    fontWeight: hint != null ? FontWeight.w500 : null,
                    fontVariations: hint != null
                        ? const [FontVariation('wght', 500)]
                        : null,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A QR code on its white card. QR codes stay dark on light in every
/// theme: scanners expect it.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.address, required this.side});

  final String address;
  final double side;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      width: side,
      height: side,
      padding: const EdgeInsets.all(GerfautSpacing.sm),
      decoration: BoxDecoration(
        color: GerfautQr.background,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: QrImageView(
        data: address,
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
    );
  }
}

/// The QR code at a size a camera reads from across a table, on a
/// white card over the dimmed page. A tap anywhere, Escape or back
/// closes it.
class _QrDialog extends StatelessWidget {
  const _QrDialog({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = min(size.width, size.height) - 2 * GerfautSpacing.xl;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          button: true,
          label: 'Address QR code, tap to close',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QrCard(address: address, side: side),
                  const SizedBox(height: GerfautSpacing.md),
                  Text(
                    'Tap anywhere to close',
                    // The line sits on the dimmed barrier in both themes:
                    // the dark theme's text is the one that reads on it.
                    style: GerfautTokens.dark.bodySmall.copyWith(
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One keychain: a card with its label, a hint, the first rows and a
/// way to unfold the rest. Each card unfolds on its own.
class _AddressCard extends StatefulWidget {
  const _AddressCard({
    required this.title,
    required this.hint,
    required this.rows,
    this.emptyText,
  });

  final String title;
  final String hint;
  final List<AddressRow> rows;

  /// Shown in place of the rows when the keychain has none.
  final String? emptyText;

  @override
  State<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends State<_AddressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final rows = widget.rows;
    final shown = _expanded ? rows : rows.take(_collapsedRows).toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: tokens.label.copyWith(color: tokens.textMuted),
                    ),
                    if (rows.isNotEmpty) ...[
                      const SizedBox(width: GerfautSpacing.xs + 2),
                      CountBadge(count: rows.length),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.hint,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: GerfautSpacing.sm),
          if (rows.isEmpty && widget.emptyText != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GerfautSpacing.md,
              ),
              child: Text(
                widget.emptyText!,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            )
          else
            for (final row in shown) ...[
              Divider(height: 1, thickness: 1, color: tokens.border),
              _AddressRowTile(row: row),
            ],
          if (rows.length > _collapsedRows) ...[
            Divider(height: 1, thickness: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.only(
                left: GerfautSpacing.sm,
                top: GerfautSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GhostButton(
                  label: _expanded ? 'Show less' : 'Show all ${rows.length}',
                  icon: _expanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One revealed address: index, chip, usage, balance. 44px minimum.
class _AddressRowTile extends StatelessWidget {
  const _AddressRowTile({required this.row});

  final AddressRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm,
      ),
      child: Row(
        children: [
          // The derivation index anchors the row; a fixed slot keeps
          // the address column aligned.
          SizedBox(
            width: 36,
            child: Text(
              '${row.index}',
              style: tokens.figureOf(color: tokens.textMuted),
            ),
          ),
          Expanded(child: AddressChip(value: row.address, head: 8, tail: 6)),
          const SizedBox(width: GerfautSpacing.sm),
          AddressStatePill(used: row.used),
          const SizedBox(width: GerfautSpacing.sm),
          if (row.balanceSats > 0)
            StackedAmount(sats: row.balanceSats)
          else
            Text('—', style: tokens.figureOf(color: tokens.textMuted)),
        ],
      ),
    );
  }
}
