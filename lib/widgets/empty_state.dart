import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'brand.dart';

/// What, why, and exactly one action — never a blank area.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.hint,
    this.action,
    this.art,
  });

  final String title;
  final String hint;
  final Widget? action;

  /// Above the title. The falcon as a faint watermark by default, the
  /// only decoration the system allows; a screen that greets someone
  /// for the first time passes the full logo instead.
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            art ??
                GerfautMark(
                  color: tokens.text.withValues(alpha: 0.08),
                  height: 48,
                ),
            const SizedBox(height: GerfautSpacing.lg),
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
