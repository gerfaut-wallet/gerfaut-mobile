import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

/// Width from which the flow summary sits side by side instead of
/// stacked: a phone in landscape or a tablet.
const double _wideFlow = 560;

/// A transaction in one glance: what went in, what came out, and the
/// fee between the two. Counts and totals only; the input and output
/// lists carry the detail. Stacked on a phone, side by side once the
/// width allows it.
class FlowSummary extends ConsumerWidget {
  const FlowSummary({
    super.key,
    required this.inputCount,
    required this.outputCount,
    required this.inTotal,
    required this.outTotal,
    required this.feeSats,
    required this.feeRate,
    required this.tokens,
    this.inTitle,
    this.inSubtitle,
    this.inIcon,
  });

  final int inputCount;
  final int outputCount;

  /// Sum of the inputs, or null when one of them is unknown: a partial
  /// total would read as a fact.
  final int? inTotal;
  final int? outTotal;
  final int? feeSats;
  final double? feeRate;
  final GerfautTokens tokens;

  /// Overrides for the input side, when it is not a plain count: a
  /// coinbase spends nothing and says so instead.
  final String? inTitle;
  final String? inSubtitle;
  final IconData? inIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    String amount(int? sats) => sats == null
        ? 'n/a'
        : masked
        ? maskedValue
        : formatAmount(sats, unit);

    final inSide = _FlowSide(
      title: inTitle ?? '$inputCount input${inputCount == 1 ? '' : 's'}',
      subtitle: inSubtitle ?? 'spent',
      amount: amount(inTotal),
      unknown: inTotal == null,
      icon: inIcon,
      tokens: tokens,
    );
    final outSide = _FlowSide(
      title: '$outputCount output${outputCount == 1 ? '' : 's'}',
      subtitle: 'created',
      amount: amount(outTotal),
      unknown: outTotal == null,
      tokens: tokens,
    );
    final showFee = feeSats != null && feeSats! > 0;
    final feePill = showFee
        ? FeePill(feeSats: feeSats!, feeRate: feeRate, tokens: tokens)
        : null;

    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideFlow) {
            // Both cards share the taller one's height, the way two
            // halves of one statement should.
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: inSide),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GerfautSpacing.sm + GerfautSpacing.xs,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.arrowRight,
                          size: 20,
                          color: tokens.textMuted,
                        ),
                        if (feePill != null) ...[
                          const SizedBox(height: GerfautSpacing.xs),
                          feePill,
                        ],
                      ],
                    ),
                  ),
                  Expanded(child: outSide),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              inSide,
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GerfautSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.arrowDown,
                      size: 20,
                      color: tokens.textMuted,
                    ),
                    if (feePill != null) ...[
                      const SizedBox(width: GerfautSpacing.sm),
                      Flexible(child: feePill),
                    ],
                  ],
                ),
              ),
              outSide,
            ],
          );
        },
      ),
    );
  }
}

/// One side of the flow: a count, what it means, and the total.
class _FlowSide extends StatelessWidget {
  const _FlowSide({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.unknown,
    required this.tokens,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String amount;

  /// The total could not be computed: shown muted, never as a figure.
  final bool unknown;
  final GerfautTokens tokens;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm + GerfautSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: tokens.textMuted),
                const SizedBox(width: GerfautSpacing.xs + 2),
              ],
              Text(
                title,
                style: tokens.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                ),
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: GerfautSpacing.xs + 2),
              Flexible(
                child: Text(
                  subtitle,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GerfautSpacing.xs),
          Text(
            amount,
            style: unknown
                ? tokens.figureOf(size: 15, color: tokens.textMuted)
                : tokens.figureOf(size: 15, weight: FontWeight.w600),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

/// Fee as a pending-tinted pill: amount in the chosen unit, rate as
/// small print. Never an alert.
class FeePill extends ConsumerWidget {
  const FeePill({
    super.key,
    required this.feeSats,
    required this.feeRate,
    required this.tokens,
  });

  final int feeSats;
  final double? feeRate;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.pendingSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: tokens.pending.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('FEE', style: tokens.label.copyWith(color: tokens.pending)),
          const SizedBox(width: GerfautSpacing.xs + 2),
          // The figures give way before the pill ever overflows.
          Flexible(
            child: Text(
              masked ? maskedValue : formatAmount(feeSats, unit),
              style: tokens.figureOf(
                size: 11,
                weight: FontWeight.w500,
                color: tokens.pending,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
          if (feeRate != null) ...[
            const SizedBox(width: GerfautSpacing.xs + 2),
            Flexible(
              child: Text(
                '${feeRate!.toStringAsFixed(1)} sat/vB',
                style: tokens.figureOf(size: 11, color: tokens.textMuted),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
