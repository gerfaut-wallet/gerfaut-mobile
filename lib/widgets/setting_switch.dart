import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A setting that is a switch: its name, what it does under the name,
/// and the switch at the end of the row.
///
/// One node for a screen reader. Left to themselves, the name and the
/// switch are two stops, and the switch is read alone: three of them
/// in a card become "off, switch" three times over, with no word of
/// which locks the app and which disguises it. Merged, the switch is
/// read with its name and its line.
///
/// A switch that cannot be moved is greyed and the name keeps its ink:
/// the line under it says why, as a disabled control does everywhere
/// else in Gerfaut.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    this.semanticLabel,
    this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;

  /// Read in place of the title, for a name that does not say on its
  /// own what the switch does: a wallet's name in a list of them.
  final String? semanticLabel;

  /// What the setting does, or why it cannot be changed, in a muted
  /// line under the name. Null for a name that says it all.
  final String? hint;
  final bool value;

  /// Null greys the switch out.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final name = Text(
      title,
      semanticsLabel: semanticLabel,
      style: tokens.bodySmall.copyWith(
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
      ),
    );
    final hint = this.hint;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                if (hint != null)
                  Text(
                    hint,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          // The colours above are the switch's own, kept when it cannot
          // move: on its own a greyed switch still wears the Glacier
          // track of one that is on, and reads as on. At the opacity
          // of every disabled control, it reads as out of reach.
          Opacity(
            opacity: onChanged == null ? 0.45 : 1,
            child: Switch(
              value: value,
              activeThumbColor: tokens.onPrimary,
              activeTrackColor: tokens.primary,
              inactiveThumbColor: tokens.textMuted,
              inactiveTrackColor: tokens.surfaceSunken,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
