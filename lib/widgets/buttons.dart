import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The single primary action of a screen: Glacier surface, 44px tall.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Fills the available width: the thumb-reachable bottom action.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      background: tokens.primary,
      foreground: tokens.onPrimary,
    );
  }
}

/// The primary action of a premium screen: the same button in Bruyère,
/// so what the paid service does reads as its own at a glance —
/// activating a key, handing a wallet to the server, adding a channel.
/// Never a destructive step, which stays a [DangerButton] whatever the
/// screen.
class PremiumButton extends StatelessWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Fills the available width: the thumb-reachable bottom action.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      background: tokens.premium,
      foreground: tokens.onPremium,
    );
  }
}

/// The filled 44px button behind [PrimaryButton] and [PremiumButton]:
/// one shape, one type style, one disabled state, only the ink differs.
class _FilledAction extends StatelessWidget {
  const _FilledAction({
    required this.label,
    required this.onPressed,
    required this.icon,
    required this.expand,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: 44,
      width: expand ? double.infinity : null,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: tokens.surfaceSunken,
          disabledForegroundColor: tokens.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          textStyle: tokens.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        onPressed: onPressed,
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: GerfautSpacing.sm),
                  // The height is fixed, so a label wider than the
                  // phone at a large text size gives ground at its end
                  // rather than running past the button.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Second-rank action: Givre surface, no border.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: 44,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.surfaceSunken,
          foregroundColor: tokens.text,
          disabledBackgroundColor: tokens.surfaceSunken,
          disabledForegroundColor: tokens.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          textStyle: tokens.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        onPressed: onPressed,
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: GerfautSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tertiary action: transparent, muted text. A deletion is this plus an
/// explicit confirmation — never a red button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          textStyle: tokens.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        onPressed: onPressed,
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: GerfautSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Destructive confirmations only, never a lone delete button: filled
/// with the alert color inside an explicit confirmation banner.
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 44,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.alert,
          // Light: white text on the deep red. Dark: near-black text on
          // the bright red, mirroring the desktop danger variant.
          foregroundColor: dark ? tokens.background : tokens.surface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          textStyle: tokens.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// The two buttons that close a confirmation: the way out and the deed,
/// in that order, the deed at the end where the thumb expects the last
/// word.
///
/// A Wrap and not a Row: at a large text size two labels do not share
/// a line on a phone, and the deed then goes to a line of its own under
/// the way out rather than past the edge of the panel. Aligned to the
/// end whichever column it sits in.
class ConfirmActions extends StatelessWidget {
  const ConfirmActions({
    super.key,
    required this.cancel,
    required this.confirm,
  });

  final Widget cancel;
  final Widget confirm;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: GerfautSpacing.sm,
        runSpacing: GerfautSpacing.sm,
        children: [cancel, confirm],
      ),
    );
  }
}
