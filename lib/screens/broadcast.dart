import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/explorer.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../src/tx_file.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/buttons.dart';
import '../widgets/explorer_link.dart';
import '../widgets/facts.dart';
import '../widgets/flow_summary.dart';
import 'scan.dart';

/// How often a sent transaction is checked with the backend.
const Duration _statusPollInterval = Duration(seconds: 30);

/// Confirmations after which a broadcast stops being watched.
const int _settledConfirmations = 6;

/// What a broadcast left behind: the record kept for later checks and
/// the host that accepted it.
typedef _Sent = ({RecentBroadcast record, String backend});

/// Broadcast a transaction somebody else signed: paste, import or scan
/// it, read what it does, then hand it to the network of the workspace.
/// Gerfaut never signs and never edits the transaction; the preview
/// only makes it legible before it leaves the device.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final _inputController = TextEditingController();
  bool _decoding = false;
  String? _inputError;
  TxPreview? _preview;
  bool _sending = false;

  /// The node's refusal, verbatim.
  String? _sendError;
  _Sent? _sent;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final network = ref.read(settingsProvider).valueOrNull?.activeNetwork;
    final input = _inputController.text.trim();
    if (network == null || input.isEmpty || _decoding) return;
    setState(() {
      _decoding = true;
      _inputError = null;
    });
    try {
      final preview = await ref
          .read(bridgeProvider)
          .previewTransaction(input, network);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _sendError = null;
        _sent = null;
      });
    } on BridgeException catch (error) {
      if (mounted) setState(() => _inputError = error.message);
    } catch (error) {
      if (mounted) setState(() => _inputError = '$error');
    } finally {
      if (mounted) setState(() => _decoding = false);
    }
  }

  Future<void> _importFile() async {
    final file = await openFile();
    if (file == null) return;
    final text = transactionTextOf(await file.readAsBytes());
    if (!mounted) return;
    _inputController.text = text;
    await _decode();
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            const ScanScreen(caption: ScanScreen.transactionCaption),
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    _inputController.text = text.trim();
    await _decode();
  }

  Future<void> _confirmAndSend(TxPreview preview) async {
    final hex = preview.hex;
    if (hex == null || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(preview: preview),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final report = await ref
          .read(bridgeProvider)
          .broadcastTransaction(preview.network, hex);
      final record = RecentBroadcast(
        txid: report.txid,
        network: preview.network,
        hex: hex,
        at: report.at,
      );
      ref.read(recentBroadcastsProvider.notifier).add(record);
      if (!mounted) return;
      setState(() => _sent = (record: record, backend: report.backend));
    } on BridgeException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (error) {
      if (mounted) setState(() => _sendError = '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Back to the input, keeping the text so it can be corrected.
  void _back() {
    setState(() {
      _preview = null;
      _sendError = null;
      _sent = null;
    });
  }

  /// A fresh start after a broadcast.
  void _another() {
    _inputController.clear();
    setState(() {
      _preview = null;
      _inputError = null;
      _sendError = null;
      _sent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final network = ref.watch(settingsProvider).valueOrNull?.activeNetwork;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast')),
      body: SafeArea(
        child: network == null
            ? Center(
                child: Text(
                  'Loading…',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              )
            : preview == null
            ? _buildInputStep(tokens, network)
            : _buildPreviewStep(tokens, preview),
      ),
    );
  }

  Widget _buildInputStep(GerfautTokens tokens, Network network) {
    final recent = ref
        .watch(recentBroadcastsProvider)
        .where((b) => b.network == network)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            children: [
              FieldLabel('Signed transaction or PSBT', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              TextField(
                controller: _inputController,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'cHNidP8B… (base64) or 02000000… (hex)',
                  hintStyle: tokens.data.copyWith(
                    fontSize: tokens.body.fontSize,
                    color: tokens.textMuted,
                  ),
                  filled: true,
                  fillColor: tokens.surfaceSunken,
                  contentPadding: const EdgeInsets.all(GerfautSpacing.md),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    borderSide: BorderSide(color: tokens.primary, width: 2),
                  ),
                ),
              ),
              if (_inputError != null) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  _inputError!,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Gerfaut never signs. It reads a finished transaction, shows '
                'what it does, and hands it to the network on '
                '${network.label}.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.md),
              Row(
                children: [
                  GhostButton(
                    label: 'Import a file',
                    icon: LucideIcons.fileUp,
                    onPressed: _decoding ? null : _importFile,
                  ),
                  const SizedBox(width: GerfautSpacing.sm),
                  GhostButton(
                    label: 'Scan a QR code',
                    icon: LucideIcons.scanLine,
                    onPressed: _decoding ? null : _scan,
                  ),
                ],
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: GerfautSpacing.lg),
                FieldLabel('Recent broadcasts', tokens: tokens),
                const SizedBox(height: GerfautSpacing.sm),
                for (final (index, record) in recent.indexed) ...[
                  if (index > 0) const SizedBox(height: GerfautSpacing.gutter),
                  _StatusCard(
                    key: ValueKey(record.txid),
                    record: record,
                    showTxid: true,
                  ),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PrimaryButton(
            label: _decoding ? 'Decoding…' : 'Preview',
            expand: true,
            onPressed: _inputController.text.trim().isEmpty || _decoding
                ? null
                : _decode,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewStep(GerfautTokens tokens, TxPreview preview) {
    final sent = _sent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            children: [
              _Hero(preview: preview, tokens: tokens),
              if (sent != null) ...[
                const SizedBox(height: GerfautSpacing.lg),
                _StatusCard(
                  key: ValueKey(sent.record.txid),
                  record: sent.record,
                  sentTo: sent.backend,
                ),
              ],
              const SizedBox(height: GerfautSpacing.lg),
              FlowSummary(
                inputCount: preview.inputs.length,
                outputCount: preview.outputs.length,
                inTotal: _inputTotal(preview.inputs),
                outTotal: preview.outputs.fold<int>(
                  0,
                  (sum, o) => sum + o.valueSats,
                ),
                feeSats: preview.feeSats,
                feeRate: preview.feeRateSatVb,
                tokens: tokens,
              ),
              if (preview.warnings.isNotEmpty) ...[
                const SizedBox(height: GerfautSpacing.lg),
                FieldLabel('Before you send', tokens: tokens),
                const SizedBox(height: GerfautSpacing.sm),
                for (final (index, warning) in preview.warnings.indexed) ...[
                  if (index > 0) const SizedBox(height: GerfautSpacing.sm),
                  _WarningRow(warning: warning, tokens: tokens),
                ],
              ],
              const SizedBox(height: GerfautSpacing.lg),
              FieldLabel('Inputs (${preview.inputs.length})', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              for (final (index, input) in preview.inputs.indexed) ...[
                if (index > 0) const SizedBox(height: GerfautSpacing.sm - 2),
                _InputRow(input: input, tokens: tokens),
              ],
              const SizedBox(height: GerfautSpacing.lg),
              FieldLabel('Outputs (${preview.outputs.length})', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              for (final (index, output) in preview.outputs.indexed) ...[
                if (index > 0) const SizedBox(height: GerfautSpacing.sm - 2),
                _OutputRow(output: output, tokens: tokens),
              ],
              const SizedBox(height: GerfautSpacing.lg),
              _TechnicalCard(preview: preview, tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sendError != null) ...[
                _RefusalBlock(message: _sendError!, tokens: tokens),
                const SizedBox(height: GerfautSpacing.md),
              ],
              if (sent == null)
                Row(
                  children: [
                    GhostButton(
                      label: 'Back',
                      onPressed: _sending ? null : _back,
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: _sending ? 'Sending…' : 'Broadcast',
                        icon: LucideIcons.radio,
                        expand: true,
                        onPressed: preview.ready && !_sending
                            ? () => _confirmAndSend(preview)
                            : null,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    GhostButton(
                      label: 'Broadcast another',
                      onPressed: _another,
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Done',
                        expand: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sum of the inputs, or null as soon as one value is unknown: a
/// partial total would read as a fact.
int? _inputTotal(List<TxInputPreview> inputs) {
  var total = 0;
  for (final input in inputs) {
    final value = input.valueSats;
    if (value == null) return null;
    total += value;
  }
  return total;
}

/// The transaction's identity and where it stands: txid, container,
/// readiness.
class _Hero extends StatelessWidget {
  const _Hero({required this.preview, required this.tokens});

  final TxPreview preview;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('Transaction', tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AddressChip(value: preview.txid, head: 12, tail: 10),
        ),
        const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
        Wrap(
          spacing: GerfautSpacing.sm,
          runSpacing: GerfautSpacing.xs + 2,
          children: [
            _Pill(
              tone: _Tone.neutral,
              icon: preview.source == TxSource.psbt
                  ? LucideIcons.fileSignature
                  : LucideIcons.code,
              label: preview.source.label,
              tokens: tokens,
            ),
            _Pill(
              tone: preview.ready ? _Tone.confirmed : _Tone.pending,
              icon: preview.ready
                  ? LucideIcons.circleCheck
                  : LucideIcons.penOff,
              label: preview.ready ? 'Ready to broadcast' : 'Not fully signed',
              tokens: tokens,
            ),
            if (preview.network != Network.mainnet)
              _Pill(
                tone: _Tone.neutral,
                label: preview.network.label,
                tokens: tokens,
              ),
          ],
        ),
      ],
    );
  }
}

enum _Tone { neutral, pending, confirmed, accent, alert }

/// A bordered pill: icon, label, and a tone that carries the meaning.
/// Every tone shares the same anatomy; the word carries the sense.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.tone,
    required this.label,
    required this.tokens,
    this.icon,
  });

  final _Tone tone;
  final String label;
  final GerfautTokens tokens;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink, Color outline) = switch (tone) {
      _Tone.pending => (
        tokens.pendingSurface,
        tokens.pending,
        tokens.pending.withValues(alpha: 0.25),
      ),
      _Tone.confirmed => (
        tokens.confirmedSurface,
        tokens.confirmed,
        tokens.confirmed.withValues(alpha: 0.25),
      ),
      _Tone.alert => (
        tokens.alertSurface,
        tokens.alert,
        tokens.alert.withValues(alpha: 0.25),
      ),
      _Tone.accent => (
        tokens.primary.withValues(alpha: 0.08),
        tokens.primary,
        tokens.primary.withValues(alpha: 0.25),
      ),
      _Tone.neutral => (tokens.surfaceSunken, tokens.textMuted, tokens.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: GerfautSpacing.xs),
          ],
          Text(
            label,
            style: tokens.label.copyWith(fontSize: 11, color: ink),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

IconData _warningIcon(TxWarningKind kind) => switch (kind) {
  TxWarningKind.unsigned => LucideIcons.penOff,
  TxWarningKind.highFeeRate => LucideIcons.flame,
  TxWarningKind.highFeeShare => LucideIcons.percent,
  TxWarningKind.locked => LucideIcons.clock,
  TxWarningKind.inputUnknown => LucideIcons.circleHelp,
  TxWarningKind.inputSpent => LucideIcons.ban,
  TxWarningKind.feeUnknown => LucideIcons.circleHelp,
  TxWarningKind.dustOutput => LucideIcons.coins,
  TxWarningKind.spendsWatched => LucideIcons.wallet,
  TxWarningKind.other => LucideIcons.info,
};

/// One caution: what will go wrong reads in the alert style, what is
/// worth a look in the pending one.
class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning, required this.tokens});

  final TxWarning warning;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final blocking = warning.kind.blocking;
    final color = blocking ? tokens.alert : tokens.pending;
    final surface = blocking ? tokens.alertSurface : tokens.pendingSurface;
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_warningIcon(warning.kind), size: 16, color: color),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          Expanded(
            child: Text(
              warning.message,
              style: tokens.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 32px role chip of an input or output row.
class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.icon,
    required this.hint,
    required this.tokens,
    this.tone = _Tone.neutral,
  });

  final IconData icon;
  final String hint;
  final GerfautTokens tokens;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final (Color ink, Color fill) = switch (tone) {
      _Tone.accent => (tokens.primary, tokens.primary.withValues(alpha: 0.10)),
      _Tone.pending => (tokens.pending, tokens.pendingSurface),
      _Tone.alert => (tokens.alert, tokens.alertSurface),
      _Tone.confirmed => (tokens.confirmed, tokens.confirmedSurface),
      _Tone.neutral => (tokens.textMuted, tokens.surfaceSunken),
    };
    return Tooltip(
      message: hint,
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 15, color: ink),
      ),
    );
  }
}

/// The bordered card of one input or output: role chip, identity,
/// amount. A row on a watched wallet carries a Glacier edge.
class _IoCard extends StatelessWidget {
  const _IoCard({
    required this.mine,
    required this.chip,
    required this.identity,
    required this.amount,
    required this.tokens,
  });

  final bool mine;
  final Widget chip;
  final Widget identity;
  final Widget amount;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm + 2),
      decoration: BoxDecoration(
        color: mine ? tokens.primary.withValues(alpha: 0.04) : tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(
          color: mine ? tokens.primary.withValues(alpha: 0.4) : tokens.border,
        ),
      ),
      child: Row(
        children: [
          chip,
          const SizedBox(width: GerfautSpacing.sm + 2),
          Expanded(child: identity),
          const SizedBox(width: GerfautSpacing.sm),
          amount,
        ],
      ),
    );
  }
}

/// The lines under an address: the wallet it belongs to, whether it is
/// change, whether the input still lacks a signature.
class _Markers extends StatelessWidget {
  const _Markers({
    required this.tokens,
    this.wallet,
    this.change = false,
    this.unsigned = false,
  });

  final GerfautTokens tokens;
  final WalletRef? wallet;
  final bool change;
  final bool unsigned;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: GerfautSpacing.xs + 2,
      runSpacing: GerfautSpacing.xs,
      children: [
        if (wallet != null)
          _Pill(
            tone: _Tone.accent,
            icon: LucideIcons.wallet,
            label: wallet!.name,
            tokens: tokens,
          ),
        if (change)
          _Pill(
            tone: _Tone.neutral,
            icon: LucideIcons.undo2,
            label: 'Change',
            tokens: tokens,
          ),
        if (unsigned)
          _Pill(
            tone: _Tone.alert,
            icon: LucideIcons.penOff,
            label: 'Unsigned',
            tokens: tokens,
          ),
      ],
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.input, required this.tokens});

  final TxInputPreview input;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final mine = input.wallet != null;
    final address = input.address;
    final value = input.valueSats;
    return _IoCard(
      mine: mine,
      tokens: tokens,
      chip: _RoleChip(
        icon: mine ? LucideIcons.wallet : LucideIcons.arrowUpRight,
        tone: mine ? _Tone.accent : _Tone.neutral,
        hint: mine ? 'Spent from ${input.wallet!.name}' : 'Coin spent',
        tokens: tokens,
      ),
      identity: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AddressChip(
              value: address ?? input.outpoint,
              head: 10,
              tail: 8,
              emphasis: mine,
            ),
          ),
          if (address != null) ...[
            const SizedBox(height: 2),
            Text(
              truncateMiddle(input.outpoint, head: 10, tail: 8),
              style: tokens.data.copyWith(
                fontSize: 11,
                color: tokens.textMuted,
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ],
          if (mine || !input.signed) ...[
            const SizedBox(height: GerfautSpacing.xs),
            _Markers(
              tokens: tokens,
              wallet: input.wallet,
              unsigned: !input.signed,
            ),
          ],
        ],
      ),
      amount: value != null
          ? StackedAmount(sats: value)
          : Text(
              'n/a',
              style: tokens.figureOf(color: tokens.textMuted),
              maxLines: 1,
            ),
    );
  }
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({required this.output, required this.tokens});

  final TxOutputPreview output;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final mine = output.wallet != null;
    final opReturn = output.opReturn;
    final address = output.address;
    final (IconData icon, _Tone tone, String hint) = switch (output) {
      _ when opReturn != null => (
        LucideIcons.scrollText,
        _Tone.pending,
        'Data output',
      ),
      _ when !mine => (
        LucideIcons.arrowUpRight,
        _Tone.neutral,
        'External output',
      ),
      _ when output.change => (
        LucideIcons.undo2,
        _Tone.accent,
        'Change back to ${output.wallet!.name}',
      ),
      _ => (
        LucideIcons.arrowDownLeft,
        _Tone.accent,
        'Received by ${output.wallet!.name}',
      ),
    };
    final Widget identity;
    if (opReturn != null) {
      identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'OP_RETURN',
            style: tokens.bodySmall.copyWith(
              fontSize: 13,
              color: tokens.pending,
              fontWeight: FontWeight.w500,
              fontVariations: const [FontVariation('wght', 500)],
            ),
          ),
          Tooltip(
            message: opReturn.text ?? opReturn.hex,
            triggerMode: TooltipTriggerMode.longPress,
            child: Text(
              opReturnPreview(opReturn),
              style: tokens.data.copyWith(
                fontSize: 11,
                color: tokens.textMuted,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (address != null) {
      identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AddressChip(
              value: address,
              head: 10,
              tail: 8,
              emphasis: mine,
            ),
          ),
          if (mine) ...[
            const SizedBox(height: GerfautSpacing.xs),
            _Markers(
              tokens: tokens,
              wallet: output.wallet,
              change: output.change,
            ),
          ],
        ],
      );
    } else {
      identity = Text(
        'Script output',
        style: tokens.bodySmall.copyWith(fontSize: 13, color: tokens.textMuted),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    }
    return _IoCard(
      mine: mine,
      tokens: tokens,
      chip: _RoleChip(icon: icon, tone: tone, hint: hint, tokens: tokens),
      identity: identity,
      amount: StackedAmount(sats: output.valueSats),
    );
  }
}

/// Block heights and unix times share the locktime field: below this
/// value it is a height (BIP-65).
const int _locktimeThreshold = 500000000;

class _TechnicalCard extends StatelessWidget {
  const _TechnicalCard({required this.preview, required this.tokens});

  final TxPreview preview;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final locktime = preview.locktime;
    return FactsCard(
      title: 'Technical',
      tokens: tokens,
      rows: [
        FactRow(
          label: 'Network',
          tokens: tokens,
          child: FactValue(preview.network.label, tokens),
        ),
        FactRow(
          label: 'Size',
          tokens: tokens,
          child: FactValue('${groupThousands('${preview.size}')} B', tokens),
        ),
        FactRow(
          label: 'Virtual size',
          tokens: tokens,
          child: FactValue('${groupThousands('${preview.vsize}')} vB', tokens),
        ),
        FactRow(
          label: 'Weight',
          tokens: tokens,
          child: FactValue('${groupThousands('${preview.weight}')} WU', tokens),
        ),
        FactRow(
          label: 'Version',
          tokens: tokens,
          child: FactValue('${preview.version}', tokens),
        ),
        FactRow(
          label: 'Locktime',
          tokens: tokens,
          child: locktime == 0
              ? FactValue('none', tokens, muted: true)
              : locktime < _locktimeThreshold
              ? FactValue('block ${groupThousands('$locktime')}', tokens)
              : FactValue(formatTimestamp(locktime), tokens),
        ),
        FactRow(
          label: 'Replaceable',
          tokens: tokens,
          child: FactValue(preview.rbf ? 'Yes (BIP-125)' : 'No', tokens),
        ),
      ],
    );
  }
}

/// The node's refusal, verbatim, in the alert style: a refused
/// broadcast is not a form error and must not vanish like a toast.
class _RefusalBlock extends StatelessWidget {
  const _RefusalBlock({required this.message, required this.tokens});

  final String message;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
      decoration: BoxDecoration(
        color: tokens.alertSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.alert.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.circleX, size: 16, color: tokens.alert),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The network refused this transaction',
                  style: tokens.bodySmall.copyWith(
                    color: tokens.alert,
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  message,
                  style: tokens.bodySmall.copyWith(color: tokens.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last word before anything leaves the device: the fee, and the
/// fact that there is no way back.
class _ConfirmDialog extends ConsumerWidget {
  const _ConfirmDialog({required this.preview});

  final TxPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final fee = preview.feeSats;
    final rate = preview.feeRateSatVb;
    final feeLine = fee == null
        ? 'Its fee could not be established.'
        : 'It pays a fee of ${masked ? maskedValue : formatAmount(fee, unit)}'
              '${rate != null ? ' (${rate.toStringAsFixed(1)} sat/vB)' : ''}.';
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text('Broadcast this transaction?', style: tokens.h2),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feeLine, style: tokens.bodySmall),
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'Once the network has it, this cannot be undone.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          label: 'Broadcast',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Where a sent transaction stands, checked with the backend every
/// [_statusPollInterval] until it settles, and on demand.
class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({
    super.key,
    required this.record,
    this.sentTo,
    this.showTxid = false,
  });

  final RecentBroadcast record;

  /// Host that accepted the broadcast, when it happened in this session.
  final String? sentTo;

  /// Shows the txid on the card: the recent list has no hero above it.
  final bool showTxid;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  BroadcastStatus? _status;
  String? _error;
  bool _checking = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    _timer?.cancel();
    if (mounted && !_checking) setState(() => _checking = true);
    try {
      final status = await ref
          .read(bridgeProvider)
          .transactionStatus(widget.record.network, widget.record.hex);
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        _arm();
      }
    }
  }

  /// Schedules the next check unless the transaction has settled.
  void _arm() {
    _timer?.cancel();
    final status = _status;
    if (status != null &&
        status.confirmed &&
        status.confirmations >= _settledConfirmations) {
      return;
    }
    _timer = Timer(_statusPollInterval, _check);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final record = widget.record;
    final status = _status;
    final sentTo = widget.sentTo;
    // One sentence, whoever answered: which host holds it, that the
    // mempool is where it sits and how often Gerfaut asks are facts the
    // user can do nothing with. What is waited for is a block.
    const waiting = 'Waiting to be mined.';
    // A past broadcast nobody has asked about yet says when it left,
    // not where it stands.
    final unchecked = sentTo != null
        ? waiting
        : 'Sent ${formatTimestamp(record.at)}';
    final (
      IconData icon,
      Color color,
      Color surface,
      String title,
    ) = switch (status) {
      null when _error != null => (
        LucideIcons.triangleAlert,
        tokens.pending,
        tokens.pendingSurface,
        'Could not check with the backend',
      ),
      null => (
        LucideIcons.hourglass,
        tokens.pending,
        tokens.pendingSurface,
        unchecked,
      ),
      BroadcastStatus(confirmed: true) => (
        LucideIcons.circleCheck,
        tokens.confirmed,
        tokens.confirmedSurface,
        'Confirmed · ${groupThousands('${status.confirmations}')} '
            'confirmation${status.confirmations == 1 ? '' : 's'}'
            '${status.blockHeight != null ? ' · block ${groupThousands('${status.blockHeight}')}' : ''}',
      ),
      BroadcastStatus(found: false) => (
        LucideIcons.eyeOff,
        tokens.pending,
        tokens.pendingSurface,
        'Not seen by ${status.backend}',
      ),
      _ => (
        LucideIcons.hourglass,
        tokens.pending,
        tokens.pendingSurface,
        waiting,
      ),
    };
    final hint = status != null && !status.confirmed && !status.found
        ? 'It may have been dropped from the mempool or replaced by another '
              'transaction.'
        : _error;
    final explorer = explorerTxUrl(record.network, record.txid);
    final checked = _checking
        ? 'Checking…'
        : status != null
        ? 'Checked ${relativeTime(status.at)}'
        : 'Not checked yet';

    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTxid) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AddressChip(value: record.txid, head: 12, tail: 10),
            ),
            const SizedBox(height: GerfautSpacing.sm),
          ],
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: tokens.bodySmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: GerfautSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: GerfautSpacing.lg),
              child: Text(
                hint,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ),
          ],
          const SizedBox(height: GerfautSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  checked,
                  style: tokens.label.copyWith(color: tokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Check again',
                onPressed: _checking ? null : _check,
                iconSize: 16,
                color: tokens.textMuted,
                icon: const Icon(LucideIcons.refreshCw),
              ),
            ],
          ),
          if (explorer != null) ExplorerLink(url: explorer),
        ],
      ),
    );
  }
}
