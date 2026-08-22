import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/explorer.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/buttons.dart';
import '../widgets/flow_diagram.dart';
import '../widgets/status_pill.dart';

/// Full-screen transaction detail: net amount, status, identifiers,
/// fees, and both sides of the transaction with "mine" markers.
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
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final summary = detail.summary;
    final explorer = explorerTxUrl(network, summary.txid);
    final fiat = fiatValueOf(ref, summary.netSats);
    // The other unit rides the subline, with the fiat value when on.
    final secondary = formatAmount(
      summary.netSats,
      unit == AmountUnit.btc ? AmountUnit.sats : AmountUnit.btc,
    );

    return ListView(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            masked ? maskedValue : formatAmountSigned(summary.netSats, unit),
            style: tokens.amount.copyWith(fontSize: 26, letterSpacing: -0.26),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: GerfautSpacing.xs),
        Text(
          masked
              ? maskedValue
              : (fiat != null ? '$secondary · $fiat' : secondary),
          style: tokens.data.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.sm),
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
                style: tokens.data.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: GerfautSpacing.lg),
        // The transaction's vitals as one quiet panel: label left,
        // value right, so long values never overflow.
        Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            children: [
              _MetaRow(
                label: 'Transaction id',
                tokens: tokens,
                child: AddressChip(value: summary.txid, head: 8, tail: 8),
              ),
              const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
              _MetaRow(
                label: 'Fee',
                tokens: tokens,
                child: summary.feeSats != null
                    ? _FeeValue(sats: summary.feeSats!)
                    : Text(
                        'n/a',
                        style: tokens.data.copyWith(color: tokens.textMuted),
                      ),
              ),
              const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
              _MetaRow(
                label: 'Fee rate',
                tokens: tokens,
                child: Text(
                  detail.feeRateSatVb != null
                      ? '${detail.feeRateSatVb!.toStringAsFixed(1)} sat/vB'
                      : 'n/a',
                  style: tokens.data,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              const SizedBox(height: GerfautSpacing.sm + GerfautSpacing.xs),
              _MetaRow(
                label: 'Size',
                tokens: tokens,
                child: Text(
                  '${detail.vsize} vB',
                  style: tokens.data,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.lg),
        FlowDiagram(
          inputs: detail.inputs,
          outputs: detail.outputs,
          feeSats: summary.feeSats,
          feeRate: detail.feeRateSatVb,
        ),
        const SizedBox(height: GerfautSpacing.lg),
        _IoSection(
          title: 'Inputs (${detail.inputs.length})',
          ios: detail.inputs,
          side: _IoSide.input,
          tokens: tokens,
        ),
        const SizedBox(height: GerfautSpacing.md),
        _IoSection(
          title: 'Outputs (${detail.outputs.length})',
          ios: detail.outputs,
          side: _IoSide.output,
          tokens: tokens,
        ),
        if (explorer != null) ...[
          const SizedBox(height: GerfautSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(GerfautRadius.sm),
              onTap: () => _openExplorer(context, ref, explorer),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GerfautSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View on mempool.space',
                      style: tokens.bodySmall.copyWith(color: tokens.primary),
                    ),
                    const SizedBox(width: GerfautSpacing.xs),
                    Icon(
                      LucideIcons.externalLink,
                      size: 14,
                      color: tokens.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The explorer link sits behind a privacy warning: a third party can
/// link the transaction to the viewer's IP address. Once acknowledged
/// for good, the dialog steps aside.
void _openExplorer(BuildContext context, WidgetRef ref, String url) {
  void launch() {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  if (ref.read(explorerAckProvider)) {
    launch();
    return;
  }

  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  var skipNextTime = false;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            backgroundColor: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GerfautRadius.lg),
            ),
            title: Text('Open an external explorer', style: tokens.h2),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
                    decoration: BoxDecoration(
                      color: tokens.alertSurface,
                      borderRadius: BorderRadius.circular(GerfautRadius.md),
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
                          child: Text(
                            'This opens the transaction on mempool.space, a '
                            'third-party website. Its operator can link this '
                            'transaction to your IP address.',
                            style: tokens.bodySmall.copyWith(
                              color: tokens.alert,
                              fontWeight: FontWeight.w500,
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Consider a VPN or Tor if that link matters to you.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  InkWell(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    onTap: () => setState(() => skipNextTime = !skipNextTime),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: GerfautSpacing.sm + 2,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: skipNextTime,
                              activeColor: tokens.primary,
                              checkColor: tokens.onPrimary,
                              side: BorderSide(
                                color: tokens.textMuted,
                                width: 1.5,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) => setState(
                                () => skipNextTime = value ?? false,
                              ),
                            ),
                          ),
                          const SizedBox(width: GerfautSpacing.sm),
                          Expanded(
                            child: Text(
                              'Do not show this warning again',
                              style: tokens.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              PrimaryButton(
                label: 'Open explorer',
                onPressed: () {
                  if (skipNextTime) {
                    ref.read(explorerAckProvider.notifier).set(true);
                  }
                  Navigator.of(dialogContext).pop();
                  launch();
                },
              ),
            ],
          );
        },
      );
    },
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.tokens});

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

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.child,
    required this.tokens,
  });

  final String label;
  final Widget child;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FieldLabel(label, tokens: tokens),
        const SizedBox(width: GerfautSpacing.sm),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    );
  }
}

/// Fee in the chosen unit, no fiat: the meta panel stays scannable.
class _FeeValue extends ConsumerWidget {
  const _FeeValue({required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    return Text(
      masked ? maskedValue : formatAmount(sats, unit),
      style: tokens.data,
      maxLines: 1,
      softWrap: false,
    );
  }
}

enum _IoSide { input, output }

class _IoSection extends StatelessWidget {
  const _IoSection({
    required this.title,
    required this.ios,
    required this.side,
    required this.tokens,
  });

  final String title;
  final List<TxIo> ios;
  final _IoSide side;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(title, tokens: tokens),
        const SizedBox(height: GerfautSpacing.sm),
        for (final io in ios)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (io.address != null)
                        Flexible(child: AddressChip(value: io.address!))
                      else
                        Text(
                          side == _IoSide.input ? 'coinbase' : 'script output',
                          style: tokens.data.copyWith(color: tokens.textMuted),
                        ),
                      if (io.isMine) ...[
                        const SizedBox(width: GerfautSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: GerfautSpacing.xs,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceSunken,
                            borderRadius: BorderRadius.circular(
                              GerfautRadius.full,
                            ),
                          ),
                          child: Text(
                            'MINE',
                            style: tokens.label.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                if (io.valueSats != null)
                  StackedAmount(sats: io.valueSats!)
                else
                  Text(
                    'n/a',
                    style: tokens.data.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
