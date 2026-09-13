import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

/// What of a balance is still moving: the signed sum of the
/// transactions not yet in a block, behind a clock. The total above it
/// already counts this; the line says how much of it the chain has not
/// taken yet, and which way it is going. Amber is the colour of
/// waiting, and the sign and the glyph say it without the colour.
class PendingAmount extends ConsumerWidget {
  const PendingAmount({super.key, required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final figure = masked ? maskedValue : formatAmountSigned(sats, unit);
    return Semantics(
      label: '$figure pending',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 13, color: tokens.pending),
          const SizedBox(width: GerfautSpacing.xs + 2),
          Text(
            figure,
            style: tokens.figureOf(
              weight: FontWeight.w500,
              color: tokens.pending,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

/// What a row carries, in the chosen unit and nothing else.
///
/// A fiat figure beside an input reads as the value on the day of the
/// transaction to one person and as the value now to the next, and
/// nothing on the row settles it. A figure nobody can interpret is
/// worse than no figure, so this one stays in bitcoin.
class UnitAmount extends ConsumerWidget {
  const UnitAmount({super.key, required this.sats, required this.tokens});

  /// What the row is worth, null when no one could price it.
  final int? sats;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = sats;
    if (value == null) {
      return Text(
        'n/a',
        style: tokens.figureOf(color: tokens.textMuted),
        maxLines: 1,
        softWrap: false,
      );
    }
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    // A long figure scales down rather than overflowing, as the hero
    // does: a figure is never allowed to clip.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        masked ? maskedValue : formatAmount(value, unit),
        style: tokens.figureOf(weight: FontWeight.w500),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.right,
      ),
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
    this.note,
  });

  final String title;
  final int count;

  /// What the side carries, null as soon as one value on it is unknown.
  final int? totalSats;

  /// A line under the heading when the total is not the chain's word —
  /// the broadcast preview marks a sum the PSBT states and no backend
  /// confirmed. Nothing when null.
  final String? note;

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
    final heading = Row(
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
    final note = this.note;
    if (note == null) return heading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        Text(
          note,
          style: tokens.label.copyWith(
            letterSpacing: 0,
            color: tokens.textMuted,
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
