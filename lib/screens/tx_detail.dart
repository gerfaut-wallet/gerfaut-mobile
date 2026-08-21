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
    final masked = ref.watch(maskedProvider);
    final detail = ref.watch(
      txDetailProvider((walletId: walletId, txid: txid)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: SafeArea(
        child: switch (detail) {
          AsyncData(:final value) => _Detail(
            detail: value,
            network: network,
            masked: masked,
            tokens: tokens,
          ),
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

class _Detail extends StatelessWidget {
  const _Detail({
    required this.detail,
    required this.network,
    required this.masked,
    required this.tokens,
  });

  final TxDetail detail;
  final Network network;
  final bool masked;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final explorer = explorerTxUrl(network, summary.txid);

    return ListView(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      children: [
        Text.rich(
          TextSpan(
            text: masked ? maskedValue : formatBtcSigned(summary.netSats),
            style: tokens.amount,
            children: [
              TextSpan(
                text: ' BTC',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
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
        _FieldLabel('Transaction id', tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AddressChip(value: summary.txid, head: 10, tail: 10),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Fact(
                label: 'Fee',
                value: summary.feeSats != null
                    ? formatSats(summary.feeSats!)
                    : 'unknown',
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Fact(
                label: 'Fee rate',
                value: detail.feeRateSatVb != null
                    ? '${detail.feeRateSatVb!.toStringAsFixed(1)} sat/vB'
                    : 'unknown',
                tokens: tokens,
              ),
            ),
            Expanded(
              child: _Fact(
                label: 'Size',
                value: '${detail.vsize} vB',
                tokens: tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.lg),
        _IoSection(
          title: 'Inputs (${detail.inputs.length})',
          ios: detail.inputs,
          masked: masked,
          tokens: tokens,
        ),
        const SizedBox(height: GerfautSpacing.md),
        _IoSection(
          title: 'Outputs (${detail.outputs.length})',
          ios: detail.outputs,
          masked: masked,
          tokens: tokens,
        ),
        if (explorer != null) ...[
          const SizedBox(height: GerfautSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(GerfautRadius.sm),
              onTap: () => launchUrl(
                Uri.parse(explorer),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GerfautSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View on explorer',
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.tokens});

  final String label;
  final String value;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        Text(value, style: tokens.data),
      ],
    );
  }
}

class _IoSection extends StatelessWidget {
  const _IoSection({
    required this.title,
    required this.ios,
    required this.masked,
    required this.tokens,
  });

  final String title;
  final List<TxIo> ios;
  final bool masked;
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
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (io.address != null)
                        Flexible(child: AddressChip(value: io.address!))
                      else
                        Text(
                          'unknown',
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
                Text(
                  io.valueSats != null
                      ? (masked ? maskedValue : formatSats(io.valueSats!))
                      : '—',
                  style: tokens.data,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
