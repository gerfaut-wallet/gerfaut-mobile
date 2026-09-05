import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'notice.dart';

/// The one red banner of the app: a monitoring anomaly, and nothing
/// else. An unexpected outflow, or the watch gone offline.
///
/// Alert surface, alert text, the 1px border, radius 8; the glyph on the
/// first line of the message, the stamp under it, and the one action —
/// acknowledging — on a row of its own. It stays until acknowledged or
/// until the anomaly ends: never a toast, because a toast disappears and
/// an outflow must not be missable. In the dark theme the text carries
/// the colour on the card surface, as every other note does.
class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.message,
    this.stamp,
    required this.actionLabel,
    required this.onAction,
  });

  /// What is wrong, in one sentence that says what is at stake.
  final String message;

  /// When it started, or the last time it was checked, under the message.
  final String? stamp;

  /// The acknowledgement, in words: "Acknowledge", "Dismiss".
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = tokens.bodySmall.copyWith(
      color: tokens.alert,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          GerfautSpacing.sm + 4,
          GerfautSpacing.sm + 4,
          GerfautSpacing.sm + 4,
          GerfautSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: dark ? tokens.surface : tokens.alertSurface,
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          border: Border.all(color: tokens.alert.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FirstLine(
                  style: style,
                  child: Icon(
                    LucideIcons.triangleAlert,
                    size: 16,
                    color: tokens.alert,
                    semanticLabel: 'Alert',
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message, style: style),
                      if (stamp != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          stamp!,
                          style: tokens.label.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 44,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.alert,
                    padding: const EdgeInsets.symmetric(
                      horizontal: GerfautSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GerfautRadius.md),
                    ),
                    textStyle: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
