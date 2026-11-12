import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/documents.dart';
import '../src/format.dart';
import '../src/lock.dart';
import '../src/models.dart';
import '../src/share.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/choice_group.dart';
import '../widgets/facts.dart';
import '../widgets/load_failure.dart';
import '../widgets/notice.dart';
import '../widgets/setting_switch.dart';
import '../widgets/toast.dart';

/// Where an exported file goes: written where the user points, or
/// handed to the system share sheet.
enum _Destination { file, share }

/// CSV export of one wallet's history: date and direction filters, a
/// live count of what they keep, and at the end a file saved where the
/// user points or handed to the share sheet. Everything happens on this
/// device.
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

  /// Why the last export went nowhere: a sentence for the screen, and
  /// under it the other side's own words when it had any. Shown beside
  /// the buttons that were pressed, never in a toast that vanishes
  /// before it is read.
  ({String message, String? detail})? _failure;

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

  Future<void> _export(
    WalletSnapshot snapshot,
    _Destination destination,
  ) async {
    setState(() {
      _exporting = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final lock = ref.read(lockProvider.notifier);
    try {
      final result = await ref
          .read(bridgeProvider)
          .exportTransactions(widget.walletId, _options);
      final filename = '${slugify(snapshot.meta.name)}-transactions.csv';
      final rows = result.rows == 1
          ? '1 transaction'
          : '${result.rows} transactions';
      // The save dialog and the share sheet are screens of the
      // system's: Android pauses Gerfaut behind them, and coming back
      // from one is not coming back from the background. Each is
      // announced against the call that opens it, and nothing earlier.
      switch (destination) {
        case _Destination.file:
          final saver = ref.read(documentSaverProvider);
          final saved = await lock.excursion(
            () => saver.save(
              bytes: utf8.encode(result.csv),
              filename: filename,
              mimeType: 'text/csv',
            ),
            // A save refused before the dialog came up is no trip.
            cameUp: (error) =>
                error is DocumentSaveException && error.dialogOpened,
          );
          // A dialog waved away says nothing: the filters are still here.
          if (saved) {
            messenger.showSnackBar(Toast('$rows saved'));
          }
        case _Destination.share:
          final sharer = ref.read(csvSharerProvider);
          try {
            // The sheet is the feedback: what was picked there, if
            // anything, is the sheet's to know.
            await lock.excursion(
              () => sharer.shareCsv(csv: result.csv, filename: filename),
            );
          } catch (_) {
            // No sheet came up: nothing left the screen.
            _fail('The share sheet could not be opened.');
          }
      }
    } on BridgeException catch (error) {
      _fail('The file could not be built.', detail: error.message);
    } on DocumentSaveException catch (error) {
      _fail('The file could not be saved.', detail: error.message);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _fail(String message, {String? detail}) {
    if (mounted) setState(() => _failure = (message: message, detail: detail));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final snapshotAsync = ref.watch(snapshotProvider(widget.walletId));
    final snapshot = snapshotAsync.value;
    // The history that failed to load is not an empty one: said, with a
    // way to ask again, instead of "0 of 0" and two buttons that stay off.
    final failed = snapshotAsync.hasError && !snapshotAsync.isLoading;
    final total = snapshot?.txs.length ?? 0;
    final selected = snapshot?.txs.where(_passes).length ?? 0;
    final chosen = snapshot != null && selected > 0;
    final ready = chosen && !_exporting;

    return Scaffold(
      appBar: GerfautAppBar.text('Export'),
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
                  if (failed) ...[
                    LoadFailure(
                      what: 'The transactions',
                      error: snapshotAsync.error,
                      centered: false,
                      onRetry: () =>
                          ref.invalidate(snapshotProvider(widget.walletId)),
                    ),
                    const SizedBox(height: GerfautSpacing.md),
                  ],
                  // It changes what the file holds, so it is a note and
                  // not a line of grey.
                  if (snapshot?.truncated ?? false) ...[
                    const GerfautNotice(
                      tone: NoticeTone.info,
                      message:
                          'Only the loaded transactions export. Load older '
                          'transactions first for a complete file.',
                    ),
                    const SizedBox(height: GerfautSpacing.md),
                  ],
                  FieldLabel('Date range', tokens: tokens),
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
                  FieldLabel('Direction', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  ChoiceGroup<ExportDirection?>(
                    label: 'Direction',
                    value: _direction,
                    options: [
                      // Null keeps both, and reads as its own option.
                      const ChoiceOption(value: null, label: 'All'),
                      for (final direction in ExportDirection.values)
                        ChoiceOption(value: direction, label: direction.label),
                    ],
                    onChanged: (direction) =>
                        setState(() => _direction = direction),
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  SettingSwitch(
                    title: 'Include pending',
                    hint:
                        'Pending transactions have no date yet: they only '
                        'export without date bounds.',
                    value: _includePending,
                    onChanged: (value) =>
                        setState(() => _includePending = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot != null)
                    Text(
                      '$selected of $total transactions selected',
                      style: tokens.figureOf(color: tokens.textMuted),
                      textAlign: TextAlign.center,
                    )
                  else if (!failed)
                    Text(
                      'Loading…',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  if (_failure != null) ...[
                    const SizedBox(height: GerfautSpacing.sm),
                    // Amber: nothing is at risk, the file simply did
                    // not get where it was going, and the other side's
                    // words say why when it had any.
                    GerfautNotice(
                      tone: NoticeTone.info,
                      message: _failure!.message,
                      detail: _failure!.detail,
                      liveRegion: true,
                    ),
                  ],
                  const SizedBox(height: GerfautSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: _exporting ? 'Exporting…' : 'Save file',
                          icon: LucideIcons.save,
                          expand: true,
                          busy: _exporting,
                          onPressed: chosen
                              ? () => _export(snapshot, _Destination.file)
                              : null,
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      Expanded(
                        child: SecondaryButton(
                          label: 'Share',
                          icon: LucideIcons.share2,
                          onPressed: ready
                              ? () => _export(snapshot, _Destination.share)
                              : null,
                        ),
                      ),
                    ],
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

/// A tappable date bound: sunken field look, clearable once set.
///
/// Drawn a touch target tall, not a field's height: the clear button
/// sits inside it and needs a whole target of its own, which a field
/// drawn smaller and padded out could not give it.
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
    // The fill is the Material's own: a decorated box under the InkWell
    // would hide its ripple.
    return Material(
      color: tokens.surfaceSunken,
      borderRadius: BorderRadius.circular(GerfautRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        onTap: onTap,
        child: Container(
          height: GerfautTouch.target,
          padding: const EdgeInsets.only(left: GerfautSpacing.md),
          child: Row(
            children: [
              Icon(LucideIcons.calendar, size: 16, color: tokens.textMuted),
              const SizedBox(width: GerfautSpacing.sm),
              Expanded(
                child: Text(
                  set ? DateFormat('MMM d, y').format(date!) : placeholder,
                  // Which bound this is: the date alone does not say.
                  semanticsLabel: set
                      ? '$placeholder date: ${DateFormat('MMM d, y').format(date!)}'
                      : '$placeholder date',
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
                    child: SizedBox.square(
                      dimension: GerfautTouch.target,
                      child: Icon(
                        LucideIcons.x,
                        size: 16,
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
      ),
    );
  }
}
