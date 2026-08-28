import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/explorer.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/explorer_link.dart';
import '../widgets/facts.dart';
import '../widgets/flow_summary.dart';
import '../widgets/status_pill.dart';

/// Transaction detail: the amount and its status first, the flow in
/// one glance, then two calm fact cards, the inputs and outputs, and
/// the raw transaction behind a disclosure. Same facts as before, read
/// in the order a person asks for them.
class TxDetailScreen extends ConsumerWidget {
  const TxDetailScreen({
    super.key,
    required this.walletId,
    required this.txid,
    required this.network,
  });

  final String walletId;
  final String txid;
  final Network network;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final detail = ref.watch(
      txDetailProvider((walletId: walletId, txid: txid)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: SafeArea(
        child: switch (detail) {
          AsyncData(:final value) => _Detail(detail: value, network: network),
          AsyncError() => Center(
            child: Text(
              'This transaction could not be loaded.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
          _ => Center(
            child: Text(
              'Loading…',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        },
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.detail, required this.network});

  final TxDetail detail;
  final Network network;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final summary = detail.summary;
    final extras = detail.extras;
    final explorer = explorerTxUrl(network, summary.txid);
    final coinbase = extras?.isCoinbase ?? false;
    // A coinbase input spends nothing: what it creates is the sum of the
    // outputs, which is the figure worth showing on that row.
    final outputTotal = detail.outputs.fold<int>(
      0,
      (sum, io) => sum + (io.valueSats ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      children: [
        _Hero(detail: detail, tokens: tokens),
        const SizedBox(height: GerfautSpacing.lg),
        FlowSummary(
          inputCount: detail.inputs.length,
          outputCount: detail.outputs.length,
          // A coinbase input spends nothing: what it creates is the
          // reward.
          inTotal: coinbase ? _sum(detail.outputs) : _sum(detail.inputs),
          outTotal: _sum(detail.outputs),
          feeSats: summary.feeSats,
          feeRate: detail.feeRateSatVb,
          inTitle: coinbase ? 'Coinbase' : null,
          inSubtitle: coinbase
              ? (extras?.coinbasePool != null
                    ? 'Newly minted · ${extras!.coinbasePool}'
                    : 'Newly minted coins')
              : null,
          inIcon: coinbase ? LucideIcons.pickaxe : null,
          tokens: tokens,
        ),
        const SizedBox(height: GerfautSpacing.lg),
        FactsCard(
          title: 'Details',
          tokens: tokens,
          rows: [
            FactRow(
              label: 'Transaction ID',
              tokens: tokens,
              child: AddressChip(value: summary.txid, head: 8, tail: 8),
            ),
            FactRow(
              label: 'Date',
              tokens: tokens,
              child:
                  summary.status.confirmed && summary.status.timestamp != null
                  ? FactValue(
                      formatTimestamp(summary.status.timestamp!),
                      tokens,
                    )
                  : FactValue('not yet mined', tokens, muted: true),
            ),
            FactRow(
              label: 'Block',
              tokens: tokens,
              child: summary.status.confirmed
                  ? FactValue(
                      groupThousands('${summary.status.height}'),
                      tokens,
                    )
                  : FactValue('—', tokens, muted: true),
            ),
            FactRow(
              label: 'Confirmations',
              tokens: tokens,
              child: FactValue(
                groupThousands('${summary.confirmations}'),
                tokens,
              ),
            ),
            FactRow(
              label: 'Fee',
              tokens: tokens,
              child: summary.feeSats != null
                  ? _FeeValue(sats: summary.feeSats!)
                  : FactValue('n/a', tokens, muted: true),
            ),
            FactRow(
              label: 'Fee rate',
              tokens: tokens,
              child: FactValue(
                detail.feeRateSatVb != null
                    ? '${detail.feeRateSatVb!.toStringAsFixed(1)} sat/vB'
                    : 'n/a',
                tokens,
                muted: detail.feeRateSatVb == null,
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.gutter),
        FactsCard(
          title: 'Technical',
          tokens: tokens,
          rows: extras != null
              ? [
                  FactRow(
                    label: 'Size',
                    tokens: tokens,
                    child: FactValue(
                      '${groupThousands('${extras.sizeBytes}')} B',
                      tokens,
                    ),
                  ),
                  FactRow(
                    label: 'Virtual size',
                    tokens: tokens,
                    child: FactValue(
                      '${groupThousands('${extras.vsize}')} vB',
                      tokens,
                    ),
                  ),
                  FactRow(
                    label: 'Weight',
                    tokens: tokens,
                    child: FactValue(
                      '${groupThousands('${extras.weightWu}')} WU',
                      tokens,
                    ),
                  ),
                  FactRow(
                    label: 'Version',
                    tokens: tokens,
                    child: FactValue('${extras.version}', tokens),
                  ),
                  FactRow(
                    label: 'Locktime',
                    tokens: tokens,
                    child: extras.locktime > 0
                        ? FactValue(
                            groupThousands('${extras.locktime}'),
                            tokens,
                          )
                        : FactValue('none', tokens, muted: true),
                  ),
                  FactRow(
                    label: 'Sigops',
                    tokens: tokens,
                    child: FactValue(
                      groupThousands('${extras.sigops}'),
                      tokens,
                    ),
                  ),
                  FactRow(
                    label: 'Flags',
                    tokens: tokens,
                    child: _Flags(
                      extras: extras,
                      outputs: detail.outputs,
                      tokens: tokens,
                    ),
                  ),
                ]
              : [
                  FactRow(
                    label: 'Virtual size',
                    tokens: tokens,
                    child: FactValue(
                      '${groupThousands('${detail.vsize}')} vB',
                      tokens,
                    ),
                  ),
                ],
        ),
        const SizedBox(height: GerfautSpacing.lg),
        _IoList(
          title: 'Inputs',
          ios: detail.inputs,
          side: _IoSide.input,
          extras: extras,
          coinbaseValue: outputTotal,
          tokens: tokens,
        ),
        const SizedBox(height: GerfautSpacing.lg),
        _IoList(
          title: 'Outputs',
          ios: detail.outputs,
          side: _IoSide.output,
          extras: extras,
          coinbaseValue: null,
          tokens: tokens,
        ),
        const SizedBox(height: GerfautSpacing.lg),
        Divider(
          height: 1,
          thickness: 1,
          color: tokens.border.withValues(alpha: 0.6),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        if (extras != null && extras.rawHex.isNotEmpty)
          _RawTransaction(hex: extras.rawHex, tokens: tokens),
        if (explorer != null) ExplorerLink(url: explorer),
      ],
    );
  }
}

/// What happened, in one glance: direction, amount, status.
class _Hero extends ConsumerWidget {
  const _Hero({required this.detail, required this.tokens});

  final TxDetail detail;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final summary = detail.summary;
    final sats = summary.netSats;
    // The subline carries only the fiat value, when that display is on.
    final fiat = fiatValueOf(ref, sats);
    final coinbase = detail.extras?.isCoinbase ?? false;
    final direction = coinbase
        ? 'Block reward'
        : sats >= 0
        ? 'Received'
        : 'Sent';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(direction, tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        // A long amount scales down rather than overflowing: a figure
        // is never allowed to clip.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            masked ? maskedValue : formatAmountSigned(sats, unit),
            style: tokens.amount,
            maxLines: 1,
          ),
        ),
        if (fiat != null) ...[
          const SizedBox(height: GerfautSpacing.xs),
          Text(fiat, style: tokens.figureOf(color: tokens.textMuted)),
        ],
        const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
        Row(
          children: [
            StatusPill(
              status: summary.status,
              confirmations: summary.confirmations,
            ),
            if (summary.status.confirmed) ...[
              const SizedBox(width: GerfautSpacing.sm),
              Text(
                'block ${groupThousands('${summary.status.height}')}',
                style: tokens.figureOf(size: 12, color: tokens.textMuted),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Sum of the values, or null as soon as one of them is unknown: a
/// partial total would read as a fact.
int? _sum(List<TxIo> ios) {
  var total = 0;
  for (final io in ios) {
    final value = io.valueSats;
    if (value == null) return null;
    total += value;
  }
  return total;
}

/// Fee in the chosen unit, no fiat: the facts stay scannable.
class _FeeValue extends ConsumerWidget {
  const _FeeValue({required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    return FactValue(masked ? maskedValue : formatAmount(sats, unit), tokens);
  }
}

enum _BadgeTone { neutral, pending, confirmed, accent }

/// One feature chip: icon, label, and a tone that carries the meaning.
/// Every tone shares the same bordered anatomy. The explanation rides
/// a long-press tooltip, which also serves as the accessibility label.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.tone,
    required this.label,
    required this.tokens,
    required this.hint,
    this.icon,
  });

  final _BadgeTone tone;
  final String label;
  final GerfautTokens tokens;

  /// What the badge means, in one line.
  final String hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink, Color outline) = switch (tone) {
      _BadgeTone.pending => (
        tokens.pendingSurface,
        tokens.pending,
        tokens.pending.withValues(alpha: 0.25),
      ),
      _BadgeTone.confirmed => (
        tokens.confirmedSurface,
        tokens.confirmed,
        tokens.confirmed.withValues(alpha: 0.25),
      ),
      _BadgeTone.accent => (
        tokens.primary.withValues(alpha: 0.08),
        tokens.primary,
        tokens.primary.withValues(alpha: 0.25),
      ),
      _BadgeTone.neutral => (
        tokens.surfaceSunken,
        tokens.textMuted,
        tokens.border,
      ),
    };
    return Tooltip(
      message: hint,
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
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
              style: tokens.figureOf(
                size: 11,
                weight: FontWeight.w500,
                color: ink,
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// The transaction's options as a tidy row of chips inside the facts.
/// The locktime value lives on its own line, so its chip stays bare.
class _Flags extends StatelessWidget {
  const _Flags({
    required this.extras,
    required this.outputs,
    required this.tokens,
  });

  final TxExtras extras;
  final List<TxIo> outputs;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final hasOpReturn = outputs.any((io) => io.opReturn != null);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: GerfautSpacing.sm - 2,
      runSpacing: GerfautSpacing.sm - 2,
      children: [
        if (extras.isCoinbase)
          _Badge(
            tone: _BadgeTone.confirmed,
            icon: LucideIcons.pickaxe,
            label:
                'Coinbase'
                '${extras.coinbasePool != null ? ' · ${extras.coinbasePool}' : ''}',
            hint: 'Coinbase: the block reward, coins minted by the miner',
            tokens: tokens,
          )
        else if (extras.rbfSignaled)
          _Badge(
            tone: _BadgeTone.pending,
            icon: LucideIcons.repeat2,
            label: 'Replaceable',
            hint: 'Replaceable: the sender can bump the fee (BIP-125)',
            tokens: tokens,
          )
        else
          _Badge(
            tone: _BadgeTone.neutral,
            icon: LucideIcons.lock,
            label: 'Final',
            hint: 'Final: no input signals replace-by-fee',
            tokens: tokens,
          ),
        if (extras.segwit)
          _Badge(
            tone: _BadgeTone.accent,
            icon: LucideIcons.layers,
            label: 'SegWit',
            hint: 'At least one input carries witness data',
            tokens: tokens,
          ),
        if (extras.taproot)
          _Badge(
            tone: _BadgeTone.accent,
            icon: LucideIcons.sprout,
            label: 'Taproot',
            hint: 'At least one input spends a Taproot output',
            tokens: tokens,
          ),
        if (extras.locktime > 0)
          _Badge(
            tone: _BadgeTone.neutral,
            icon: LucideIcons.clock,
            label: 'Locktime',
            hint: 'Earliest block this transaction could be mined in',
            tokens: tokens,
          ),
        if (hasOpReturn)
          _Badge(
            tone: _BadgeTone.pending,
            icon: LucideIcons.scrollText,
            label: 'OP_RETURN',
            hint: 'An output carries data instead of spendable coins',
            tokens: tokens,
          ),
      ],
    );
  }
}

/// The raw serialized transaction, collapsed by default behind a
/// disclosure row; the revealed hex scrolls and copies in one tap.
class _RawTransaction extends StatefulWidget {
  const _RawTransaction({required this.hex, required this.tokens});

  final String hex;
  final GerfautTokens tokens;

  @override
  State<_RawTransaction> createState() => _RawTransactionState();
}

class _RawTransactionState extends State<_RawTransaction> {
  bool _open = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.hex));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            // 44px tap target around a one-line disclosure.
            padding: const EdgeInsets.symmetric(
              vertical: GerfautSpacing.sm + GerfautSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14,
                  color: tokens.textMuted,
                ),
                const SizedBox(width: GerfautSpacing.xs),
                FieldLabel('Raw transaction', tokens: tokens),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: GerfautSpacing.xs),
          Stack(
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(GerfautRadius.md),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    GerfautSpacing.md,
                    GerfautSpacing.md,
                    GerfautSpacing.xxl,
                    GerfautSpacing.md,
                  ),
                  child: Text(
                    widget.hex,
                    style: tokens.data.copyWith(
                      fontSize: 11,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: GerfautSpacing.xs,
                right: GerfautSpacing.xs,
                child: IconButton(
                  onPressed: _copy,
                  tooltip: 'Copy raw transaction',
                  iconSize: 16,
                  icon: Icon(
                    _copied ? LucideIcons.check : LucideIcons.copy,
                    color: _copied ? tokens.confirmed : tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GerfautSpacing.sm),
        ],
      ],
    );
  }
}

enum _IoSide { input, output }

/// Inputs or outputs as airy rows: a role chip, the address, the
/// amount. Wallet rows carry a Glacier edge and an emphasized chip.
class _IoList extends StatelessWidget {
  const _IoList({
    required this.title,
    required this.ios,
    required this.side,
    required this.extras,
    required this.coinbaseValue,
    required this.tokens,
  });

  final String title;
  final List<TxIo> ios;
  final _IoSide side;
  final TxExtras? extras;

  /// Sum of the outputs: what a coinbase input actually creates.
  final int? coinbaseValue;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final coinbase = side == _IoSide.input && (extras?.isCoinbase ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.xs),
          child: FieldLabel('$title (${ios.length})', tokens: tokens),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        for (final (index, io) in ios.indexed) ...[
          if (index > 0) const SizedBox(height: GerfautSpacing.sm - 2),
          _IoRow(
            io: io,
            side: side,
            coinbase: coinbase,
            extras: extras,
            coinbaseValue: coinbaseValue,
            tokens: tokens,
          ),
        ],
      ],
    );
  }
}

/// One input or output: role chip, identity, amount.
class _IoRow extends StatelessWidget {
  const _IoRow({
    required this.io,
    required this.side,
    required this.coinbase,
    required this.extras,
    required this.coinbaseValue,
    required this.tokens,
  });

  final TxIo io;
  final _IoSide side;
  final bool coinbase;
  final TxExtras? extras;
  final int? coinbaseValue;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final mine = io.isMine;
    final value = io.valueSats ?? (coinbase ? coinbaseValue : null);
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
          _RoleChip(io: io, side: side, coinbase: coinbase, tokens: tokens),
          const SizedBox(width: GerfautSpacing.sm + 2),
          Expanded(
            child: _IoIdentity(
              io: io,
              side: side,
              coinbase: coinbase,
              extras: extras,
              tokens: tokens,
            ),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          if (value != null)
            StackedAmount(sats: value)
          else
            Text(
              'n/a',
              style: tokens.figureOf(color: tokens.textMuted),
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}

/// What the row is about: the address with its wallet role, the
/// coinbase attribution, or the OP_RETURN payload preview.
class _IoIdentity extends StatelessWidget {
  const _IoIdentity({
    required this.io,
    required this.side,
    required this.coinbase,
    required this.extras,
    required this.tokens,
  });

  final TxIo io;
  final _IoSide side;
  final bool coinbase;
  final TxExtras? extras;
  final GerfautTokens tokens;

  /// "block 148 589 · Foundry USA": a coinbase input spends nothing,
  /// so the row states where the coins come from instead.
  String get _coinbaseLine {
    final height = extras?.coinbaseHeight;
    final pool = extras?.coinbasePool;
    final origin = height != null
        ? 'block ${groupThousands('$height')}'
        : 'newly minted';
    return '$origin${pool != null ? ' · $pool' : ''}';
  }

  Widget _subline(String text, {TextStyle? style}) {
    return Text(
      text,
      style:
          style ??
          tokens.bodySmall.copyWith(fontSize: 11, color: tokens.textMuted),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final opReturn = io.opReturn;
    final main = tokens.bodySmall.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    final List<Widget> lines;
    if (opReturn != null) {
      lines = [
        Text(
          'OP_RETURN',
          style: main.copyWith(color: tokens.pending),
          maxLines: 1,
          softWrap: false,
        ),
        Tooltip(
          message: opReturn.text ?? opReturn.hex,
          triggerMode: TooltipTriggerMode.longPress,
          child: _subline(
            opReturnPreview(opReturn),
            style: tokens.data.copyWith(fontSize: 11, color: tokens.textMuted),
          ),
        ),
      ];
    } else if (coinbase) {
      lines = [
        Text('Coinbase', style: main, maxLines: 1, softWrap: false),
        Tooltip(
          message: extras?.coinbaseTag ?? _coinbaseLine,
          triggerMode: TooltipTriggerMode.longPress,
          child: _subline(_coinbaseLine),
        ),
      ];
    } else if (io.address != null) {
      lines = [
        Align(
          alignment: Alignment.centerLeft,
          child: AddressChip(
            value: io.address!,
            head: 10,
            tail: 8,
            emphasis: io.isMine,
          ),
        ),
        if (io.isMine)
          _subline(switch (side) {
            _IoSide.input => 'Spent from this wallet',
            _IoSide.output when io.change => 'Change back to this wallet',
            _IoSide.output => 'Received by this wallet',
          }),
      ];
    } else {
      lines = [
        Text(
          side == _IoSide.input ? 'Unknown input' : 'Script output',
          style: tokens.bodySmall.copyWith(
            fontSize: 13,
            color: tokens.textMuted,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, line) in lines.indexed) ...[
          if (index > 0) const SizedBox(height: 2),
          line,
        ],
      ],
    );
  }
}

/// Role chip: a 32px square that says what this row does for the
/// watched wallet, in one icon. The hint rides a long-press tooltip.
class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.io,
    required this.side,
    required this.coinbase,
    required this.tokens,
  });

  final TxIo io;
  final _IoSide side;
  final bool coinbase;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color ink, Color fill, String hint) = switch (io) {
      _ when coinbase => (
        LucideIcons.pickaxe,
        tokens.textMuted,
        tokens.surfaceSunken,
        'Newly minted coins',
      ),
      _ when io.opReturn != null => (
        LucideIcons.scrollText,
        tokens.pending,
        tokens.pendingSurface,
        'Data output',
      ),
      _ when !io.isMine => (
        LucideIcons.arrowUpRight,
        tokens.textMuted,
        tokens.surfaceSunken,
        side == _IoSide.input ? 'External input' : 'External output',
      ),
      _ when side == _IoSide.input => (
        LucideIcons.wallet,
        tokens.primary,
        tokens.primary.withValues(alpha: 0.10),
        'Spent from this wallet',
      ),
      _ when io.change => (
        LucideIcons.undo2,
        tokens.primary,
        tokens.primary.withValues(alpha: 0.10),
        'Change back to this wallet',
      ),
      _ => (
        LucideIcons.arrowDownLeft,
        tokens.primary,
        tokens.primary.withValues(alpha: 0.10),
        'Received by this wallet',
      ),
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
