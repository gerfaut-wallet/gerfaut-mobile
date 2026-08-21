import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/format.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

/// Fiat value of an amount, when the display is enabled and a quote is
/// available. Degrades to null, never to an error.
String? fiatValueOf(WidgetRef ref, int sats) {
  if (!ref.watch(fiatEnabledProvider) || ref.watch(maskedProvider)) {
    return null;
  }
  final quote = ref.watch(priceProvider).valueOrNull;
  if (quote == null) return null;
  return formatFiat(sats, quote.rate, quote.currency);
}

/// Large balance figure: mono, tabular, masked-aware, never animated.
/// The primary line follows the unit setting; the second line carries
/// the other unit and the fiat value.
class BalanceAmount extends ConsumerWidget {
  const BalanceAmount({super.key, required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final fiat = fiatValueOf(ref, sats);
    final primary = unit == AmountUnit.btc ? formatBtc(sats) : formatSats(sats);
    final secondary = unit == AmountUnit.btc
        ? formatSats(sats)
        : '${formatBtc(sats)} BTC';
    final secondLine = masked
        ? maskedValue
        : (fiat != null ? '$secondary · $fiat' : secondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: masked ? maskedValue : primary,
            style: tokens.amount,
            children: [
              if (unit == AmountUnit.btc)
                TextSpan(
                  text: ' BTC',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.xs),
        Text(secondLine, style: tokens.data.copyWith(color: tokens.textMuted)),
      ],
    );
  }
}

/// Signed list amount with an optional fiat subline. Direction is also
/// carried by icon and sign elsewhere in the row.
class ListAmount extends ConsumerWidget {
  const ListAmount({super.key, required this.sats, this.pending = false});

  final int sats;
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final fiat = fiatValueOf(ref, sats);
    final color = sats > 0 && !pending ? tokens.confirmed : tokens.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          masked ? maskedValue : formatAmountSigned(sats, unit),
          style: tokens.data.copyWith(color: color),
          textAlign: TextAlign.right,
        ),
        if (fiat != null)
          Text(
            fiat,
            style: tokens.data.copyWith(
              fontSize: tokens.label.fontSize,
              color: tokens.textMuted,
            ),
            textAlign: TextAlign.right,
          ),
      ],
    );
  }
}

/// Inline amount for detail views: primary unit plus fiat.
class InlineAmount extends ConsumerWidget {
  const InlineAmount({super.key, required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    if (masked) {
      return Text(maskedValue, style: tokens.data);
    }
    final fiat = fiatValueOf(ref, sats);
    return Text.rich(
      TextSpan(
        text: formatAmount(sats, unit),
        style: tokens.data,
        children: [
          if (fiat != null)
            TextSpan(
              text: ' · $fiat',
              style: tokens.data.copyWith(color: tokens.textMuted),
            ),
        ],
      ),
    );
  }
}
