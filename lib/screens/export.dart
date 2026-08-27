import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/share.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// CSV export of one wallet's history: date and direction filters, a
/// live count of what they keep, and the system share sheet at the end.
/// Everything happens on this device.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTime? _from;
  DateTime? _to;

  /// Null keeps both directions.
  ExportDirection? _direction;
  bool _includePending = true;
  bool _exporting = false;

  /// Inclusive unix-second bounds of the picked days, local time.
  int? get _fromSecs => _from == null
      ? null
      : DateTime(
              _from!.year,
              _from!.month,
              _from!.day,
            ).millisecondsSinceEpoch ~/
            1000;

  int? get _toSecs => _to == null
      ? null
      : DateTime(
              _to!.year,
              _to!.month,
              _to!.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch ~/
            1000;

  ExportOptions get _options => ExportOptions(
    from: _fromSecs,
    to: _toSecs,
    direction: _direction,
    includePending: _includePending,
  );

  /// Mirror of gerfaut-core's `export::passes`, so the counter states
  /// exactly what the file will hold.
  bool _passes(TxSummary tx) {
    if (_direction == ExportDirection.incoming && tx.netSats < 0) return false;
    if (_direction == ExportDirection.outgoing && tx.netSats >= 0) return false;
    final unbounded = _fromSecs == null && _toSecs == null;
    if (!tx.status.confirmed) return _includePending && unbounded;
    final at = tx.status.timestamp;
    if (at == null) return unbounded;
    return (_fromSecs == null || at >= _fromSecs!) &&
        (_toSecs == null || at <= _toSecs!);
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = (from ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2009),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _export(WalletSnapshot snapshot) async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(bridgeProvider)
          .exportTransactions(widget.walletId, _options);
      await ref
          .read(csvSharerProvider)
          .shareCsv(
            csv: result.csv,
            filename: '${slugify(snapshot.meta.name)}-transactions.csv',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.rows == 1
                ? '1 transaction exported'
                : '${result.rows} transactions exported',
          ),
        ),
      );
    } on BridgeException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final snapshot = ref.watch(snapshotProvider(widget.walletId)).valueOrNull;
    final total = snapshot?.txs.length ?? 0;
    final selected = snapshot?.txs.where(_passes).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(GerfautSpacing.md),
                children: [
                  Text(
                    "This wallet's transaction history as a CSV file.",
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  _SectionLabel('Date range', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _DateField(
                          placeholder: 'From',
                          date: _from,
                          onTap: () => _pickDate(from: true),
                          onClear: () => setState(() => _from = null),
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      Expanded(
                        child: _DateField(
                          placeholder: 'To',
                          date: _to,
                          onTap: () => _pickDate(from: false),
                          onClear: () => setState(() => _to = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GerfautSpacing.xs),
                  Text(
                    'Leave empty to export the full history.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  _SectionLabel('Direction', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  Wrap(
                    spacing: GerfautSpacing.sm,
                    children: [
                      _Pill(
                        label: 'All',
                        selected: _direction == null,
                        onTap: () => setState(() => _direction = null),
                      ),
                      for (final direction in ExportDirection.values)
                        _Pill(
                          label: direction.label,
                          selected: _direction == direction,
                          onTap: () => setState(() => _direction = direction),
                        ),
                    ],
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Include pending',
                              style: tokens.bodySmall.copyWith(
                                fontWeight: FontWeight.w500,
                                fontVariations: const [
                                  FontVariation('wght', 500),
                                ],
                              ),
                            ),
                            Text(
                              'Pending transactions have no date yet: they '
                              'only export without date bounds.',
                              style: tokens.bodySmall.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      Switch(
                        value: _includePending,
                        activeThumbColor: tokens.onPrimary,
                        activeTrackColor: tokens.primary,
                        inactiveThumbColor: tokens.textMuted,
                        inactiveTrackColor: tokens.surfaceSunken,
                        onChanged: (value) =>
                            setState(() => _includePending = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  Divider(height: 1, thickness: 1, color: tokens.border),
                  const SizedBox(height: GerfautSpacing.md),
                  // The premium teaser states what the server will add,
                  // nothing more: no nagging, no dead-end tap target.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: GerfautSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Fiat value at transaction time',
                                  style: tokens.bodySmall.copyWith(
                                    fontWeight: FontWeight.w500,
                                    fontVariations: const [
                                      FontVariation('wght', 500),
                                    ],
                                  ),
                                ),
                                const _PremiumPill(),
                              ],
                            ),
                            Text(
                              "Adds the price at each transaction's date to "
                              'the file.',
                              style: tokens.bodySmall.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      Switch(
                        value: false,
                        inactiveThumbColor: tokens.textMuted,
                        inactiveTrackColor: tokens.surfaceSunken,
                        onChanged: null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$selected of $total transactions selected',
                    style: tokens.figureOf(color: tokens.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  if (snapshot?.truncated ?? false) ...[
                    const SizedBox(height: GerfautSpacing.xs),
                    Text(
                      'Only the loaded transactions export. Load older '
                      'rounds first for a complete file.',
                      style: tokens.bodySmall.copyWith(color: tokens.pending),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: GerfautSpacing.sm),
                  PrimaryButton(
                    label: _exporting ? 'Exporting…' : 'Export CSV',
                    icon: LucideIcons.share2,
                    expand: true,
                    onPressed: snapshot == null || selected == 0 || _exporting
                        ? null
                        : () => _export(snapshot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.tokens});

  final String text;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: tokens.label.copyWith(color: tokens.textMuted),
    );
  }
}

/// A tappable date bound: sunken field look, clearable once set.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.placeholder,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String placeholder;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final set = date != null;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.sm),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: GerfautSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 15, color: tokens.textMuted),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: Text(
                set ? DateFormat('MMM d, y').format(date!) : placeholder,
                style: set
                    ? tokens.figureOf(color: tokens.text)
                    : tokens.bodySmall.copyWith(color: tokens.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (set)
              InkWell(
                borderRadius: BorderRadius.circular(GerfautRadius.sm),
                onTap: onClear,
                child: Semantics(
                  button: true,
                  label: 'Clear $placeholder date',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      LucideIcons.x,
                      size: 15,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: GerfautSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Direction filter pill, mirroring the settings pills.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.md),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.md),
        ),
        child: Text(
          label,
          style: tokens.bodySmall.copyWith(
            color: selected ? tokens.onPrimary : tokens.text,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
      ),
    );
  }
}

/// The Bruyère badge: premium is announced, never pushed.
class _PremiumPill extends StatelessWidget {
  const _PremiumPill();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.premiumSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: tokens.premium.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.gem, size: 12, color: tokens.premium),
          const SizedBox(width: GerfautSpacing.xs),
          Text(
            'PREMIUM',
            style: TextStyle(
              fontFamily: GerfautFonts.ui,
              fontSize: 10,
              height: 1.4,
              letterSpacing: 0.5,
              color: tokens.premium,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ],
      ),
    );
  }
}
