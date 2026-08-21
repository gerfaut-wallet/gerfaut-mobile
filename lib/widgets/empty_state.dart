import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// What, why, and exactly one action — never a blank area.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.hint, this.action});

  final String title;
  final String hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: tokens.body, textAlign: TextAlign.center),
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              hint,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: GerfautSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
