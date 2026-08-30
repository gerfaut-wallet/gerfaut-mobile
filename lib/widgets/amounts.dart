import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/format.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import 'facts.dart';

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

/// Large balance figure: UI face, tabular, masked-aware, never
/// animated. The primary line follows the unit setting; the second line
/// carries only the fiat value, when that display is on.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A long balance scales down rather than overflowing: a figure
        // is never allowed to clip.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
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
            maxLines: 1,
          ),
        ),
        if (fiat != null) ...[
          const SizedBox(height: GerfautSpacing.xs),
          Text(fiat, style: tokens.figureOf(color: tokens.textMuted)),
        ],
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
          style: tokens.figureOf(weight: FontWeight.w500, color: color),
          textAlign: TextAlign.right,
        ),
        if (fiat != null)
          Text(
            fiat,
            style: tokens.figureOf(size: 11, color: tokens.textMuted),
            textAlign: TextAlign.right,
          ),
      ],
    );
  }
}

/// Unsigned amount stacked over its fiat value, for dense rows: the
/// amount never wraps, the fiat line carries the small print.
class StackedAmount extends ConsumerWidget {
  const StackedAmount({super.key, required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final fiat = fiatValueOf(ref, sats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          masked ? maskedValue : formatAmount(sats, unit),
          style: tokens.figureOf(weight: FontWeight.w500),
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
        ),
        if (fiat != null)
          Text(
            fiat,
            style: tokens.figureOf(size: 11, color: tokens.textMuted),
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
          ),
      ],
    );
  }
}

/// The heading of an input or output list: how many, and what the side
/// carries in all.
///
/// The totals used to live on the two-card flow summary the diagram
/// replaced, and went with it. They answer what no row answers on its
/// own — how much went in against how much came out, the gap between
/// them being the fee. **One value nobody knows makes the whole sum a
/// guess**, so the side reads `n/a` rather than a figure that is
/// quietly short. The count keeps the label face; the total is a
/// figure, tabular like every other.
class IoListHeading extends ConsumerWidget {
  const IoListHeading({
    super.key,
    required this.title,
    required this.count,
    required this.totalSats,
  });

  final String title;
  final int count;

  /// What the side carries, null as soon as one value on it is unknown.
  final int? totalSats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final total = totalSats == null
        ? 'n/a'
        : masked
        ? maskedValue
        : formatAmount(totalSats!, unit);
    return Row(
      children: [
        FieldLabel('$title ($count)', tokens: tokens),
        Text(' · ', style: tokens.label.copyWith(color: tokens.textMuted)),
        Flexible(
          child: Text(
            total,
            style: tokens.figureOf(
              size: 12,
              weight: FontWeight.w500,
              color: tokens.textMuted,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
          ),
        ),
      ],
    );
  }
}

/// The sum of a side, or null the moment one value on it is unknown: a
/// total short by an input nobody could price is worse than no total.
int? sideTotal(Iterable<int?> values) {
  var total = 0;
  for (final value in values) {
    if (value == null) return null;
    total += value;
  }
  return total;
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
      return Text(maskedValue, style: tokens.figure);
    }
    final fiat = fiatValueOf(ref, sats);
    return Text.rich(
      TextSpan(
        text: formatAmount(sats, unit),
        style: tokens.figure,
        children: [
          if (fiat != null)
            TextSpan(
              text: ' · $fiat',
              style: tokens.figureOf(color: tokens.textMuted),
            ),
        ],
      ),
    );
  }
}
