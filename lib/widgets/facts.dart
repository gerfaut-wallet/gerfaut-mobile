import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Section title: uppercase label, muted.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, required this.tokens});

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

/// A calm card of facts: a title, then label / value lines separated
/// by hairlines, with room to breathe.
class FactsCard extends StatelessWidget {
  const FactsCard({
    super.key,
    required this.title,
    required this.rows,
    required this.tokens,
  });

  final String title;
  final List<Widget> rows;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm + GerfautSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(title, tokens: tokens),
          const SizedBox(height: GerfautSpacing.xs),
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.border.withValues(alpha: 0.5),
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// One label / value line; values keep their own typography.
class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.child,
    required this.tokens,
  });

  final String label;
  final Widget child;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // Two thirds is all a name may claim, so a long one folds
            // at a large text size instead of pushing its value off
            // the card. Every name is well under that at normal size,
            // where the row keeps the width it always had.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 2 / 3,
              ),
              child: Text(
                label,
                style: tokens.bodySmall.copyWith(
                  fontSize: 13,
                  color: tokens.textMuted,
                ),
              ),
            ),
            const SizedBox(width: GerfautSpacing.md),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// A plain fact value: UI face, tabular, one line, right-aligned.
class FactValue extends StatelessWidget {
  const FactValue(this.text, this.tokens, {super.key, this.muted = false});

  final String text;
  final GerfautTokens tokens;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: tokens.figureOf(
        weight: FontWeight.w500,
        color: muted ? tokens.textMuted : null,
      ),
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.right,
    );
  }
}
