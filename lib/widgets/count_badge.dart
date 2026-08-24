import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small sunken pill carrying a count: tab labels, list headers. The
/// figure is tabular so a growing count never shifts what sits beside it.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.xs + 2),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
      ),
      child: Text(
        '$count',
        style: tokens.figureOf(
          size: 11,
          weight: FontWeight.w500,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}
