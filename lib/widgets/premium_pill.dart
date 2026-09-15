import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// The Bruyère badge: premium is announced, never pushed.
///
/// One colour and one glyph, reserved for this: the `gem` at 12px and
/// the word in 10px uppercase semibold on the premium surface, with the
/// 25% border every pill of the system wears. Bruyère marks the premium
/// service and nothing else in the app, so the badge is found at a
/// glance and never mistaken for a chain state.
class PremiumPill extends StatelessWidget {
  const PremiumPill({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.premiumSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: tokens.premium.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.gem, size: 12, color: tokens.premium),
          const SizedBox(width: GerfautSpacing.xs),
          Text(
            'PREMIUM',
            style: TextStyle(
              fontFamily: GerfautFonts.ui,
              fontSize: 10,
              height: 1.4,
              letterSpacing: 0.5,
              color: tokens.premium,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Watched" pill of a wallet the server watches: the same Bruyère
/// and the same `gem`, with the state as its word. A wallet still being
/// scanned is not yet watched, and says so elsewhere on its row.
class WatchedPill extends StatelessWidget {
  const WatchedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      padding: const EdgeInsets.only(
        left: GerfautSpacing.sm,
        right: GerfautSpacing.sm + 2,
        top: 2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.premiumSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: tokens.premium.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.gem, size: 12, color: tokens.premium),
          const SizedBox(width: GerfautSpacing.xs + 2),
          Text('Watched', style: tokens.label.copyWith(color: tokens.premium)),
        ],
      ),
    );
  }
}
