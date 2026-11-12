import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fitted_text.dart';

/// A small sunken pill carrying a count: tab labels, list headers. The
/// figure is tabular so a growing count never shifts what sits beside it.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final style = tokens.figureOf(
      size: 11,
      weight: FontWeight.w500,
      color: tokens.textMuted,
    );
    return Container(
      // As wide as it is tall at least: one digit at a large text size
      // would otherwise stand taller than its padding makes it wide.
      constraints: BoxConstraints(
        minWidth: lineHeight(style, MediaQuery.textScalerOf(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.xs),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
      ),
      child: Text('$count', style: style, textAlign: TextAlign.center),
    );
  }
}
