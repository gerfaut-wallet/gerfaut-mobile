import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../theme/tokens.dart';

/// The Lucide glyph behind a wallet icon. The names are the core's and
/// Lucide's at once, so the desktop draws the same seven.
IconData walletGlyph(WalletIcon icon) {
  return switch (icon) {
    WalletIcon.wallet => LucideIcons.wallet,
    WalletIcon.key => LucideIcons.key,
    WalletIcon.shield => LucideIcons.shield,
    WalletIcon.mapPin => LucideIcons.mapPin,
    WalletIcon.snowflake => LucideIcons.snowflake,
    WalletIcon.landmark => LucideIcons.landmark,
    WalletIcon.piggyBank => LucideIcons.piggyBank,
  };
}

/// Picks the glyph a wallet shows beside its name: the seven icons in a
/// grid, the current one outlined in the accent. Tapping one answers
/// and closes; tapping outside answers nothing.
class WalletIconPicker extends StatelessWidget {
  const WalletIconPicker({super.key, required this.current});

  /// Opens the picker over [context]. Null when it was dismissed.
  static Future<WalletIcon?> show(
    BuildContext context, {
    required WalletIcon current,
  }) {
    return showModalBottomSheet<WalletIcon>(
      context: context,
      builder: (_) => WalletIconPicker(current: current),
    );
  }

  /// A tile is a comfortable target, well past the 44px floor.
  static const double tileSize = 56;

  final WalletIcon current;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: GerfautSpacing.md,
        right: GerfautSpacing.md,
        top: GerfautSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wallet icon', style: tokens.h2),
          const SizedBox(height: GerfautSpacing.xs),
          Text(
            'Shown beside the name, here and on the wallet list.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: GerfautSpacing.md),
          Wrap(
            spacing: GerfautSpacing.sm,
            runSpacing: GerfautSpacing.sm,
            children: [
              for (final icon in WalletIcon.values)
                _IconTile(
                  icon: icon,
                  selected: icon == current,
                  onTap: () => Navigator.of(context).pop(icon),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One choice of the grid. The outline says which one is on, and so
/// does the announced state: an outline is not heard.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final WalletIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: icon.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: onTap,
        child: Container(
          width: WalletIconPicker.tileSize,
          height: WalletIconPicker.tileSize,
          decoration: BoxDecoration(
            color: selected ? tokens.surfaceSunken : tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.md),
            border: Border.all(
              color: selected ? tokens.primary : tokens.border,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            walletGlyph(icon),
            size: 24,
            color: selected ? tokens.primary : tokens.text,
          ),
        ),
      ),
    );
  }
}
