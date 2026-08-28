import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One option of a [ChoiceGroup].
class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// A glyph before the label, decorative: the label carries the sense.
  final IconData? icon;

  /// An option that cannot apply here: quiet, and out of reach.
  final bool enabled;
}

/// The one way to pick between a handful of options in Gerfaut: one
/// full-width row per option, stacked, 44px tall, with a real gap
/// between them.
///
/// The gap is the point. Rows that touch read as one block of colour
/// instead of as separate buttons, and adjacent touch targets need
/// space of their own to be aimed at. Every choice in the app goes
/// through here so none of them can drift back.
class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  /// What the group selects, announced around the options.
  final String label;
  final T value;
  final List<ChoiceOption<T>> options;

  /// Called with the option picked, even when it is the current one.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(height: GerfautSpacing.sm),
            _ChoiceRow<T>(
              option: option,
              selected: option.value == value,
              onTap: option.enabled ? () => onChanged(option.value) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final color = switch ((selected, option.enabled)) {
      (true, _) => tokens.onPrimary,
      (false, false) => tokens.textMuted,
      (false, true) => tokens.text,
    };
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      enabled: option.enabled,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? tokens.primary : tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon != null) ...[
                  Icon(option.icon, size: 15, color: color),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    style: tokens.bodySmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
