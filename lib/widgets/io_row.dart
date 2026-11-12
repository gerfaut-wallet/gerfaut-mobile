import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The bordered row of one input or output: role chip, identity, amount.
/// A row on a watched wallet carries a Glacier edge.
///
/// The transaction detail and the preview before a broadcast show the
/// same list, and draw it here so the two cannot drift.
class IoRow extends StatelessWidget {
  const IoRow({
    super.key,
    required this.mine,
    required this.chip,
    required this.identity,
    required this.amount,
  });

  final bool mine;
  final Widget chip;
  final Widget identity;
  final Widget amount;

  /// Under this width, at the reader's text size, the amount goes under
  /// the identity instead of beside it. Side by side, the row needs the
  /// chip (32), an address at six and four characters with its copy
  /// icon (135), the amount of a bitcoin figure (83) and the two gaps
  /// (16): 266. Narrower than that and the address is cut below what is
  /// worth comparing, then faded — a different address on screen.
  static const double stackUnder = 290;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm),
      decoration: BoxDecoration(
        color: mine ? tokens.primary.withValues(alpha: 0.04) : tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(
          color: mine ? tokens.primary.withValues(alpha: 0.4) : tokens.border,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < stackUnder * scale) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                chip,
                const SizedBox(width: GerfautSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      identity,
                      const SizedBox(height: GerfautSpacing.xs),
                      amount,
                    ],
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              chip,
              const SizedBox(width: GerfautSpacing.sm),
              Expanded(child: identity),
              const SizedBox(width: GerfautSpacing.sm),
              // At a large text size the figure alone is wider than the
              // row. Half of it is the most it may claim; past that it
              // scales down, and the address keeps a place to live.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: amount,
              ),
            ],
          );
        },
      ),
    );
  }
}
