import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'focus_ring.dart';
import 'tap_target.dart';

/// Tallest the anchored menu grows before it scrolls.
const double _menuMaxHeight = 320;

/// Narrowest the anchored menu gets, whatever the field's width.
const double _menuMinWidth = 220;

/// Share of the screen a bottom sheet may take.
const double _sheetShare = 0.7;

/// One option of a [GerfautSelect].
class GerfautSelectItem<T> {
  const GerfautSelectItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.enabled = true,
    this.mono = false,
  });

  final T value;
  final String title;

  /// A second, quieter line: what the option means, what it speaks.
  final String? subtitle;
  final IconData? icon;

  /// An option that cannot apply here: muted, and out of reach.
  final bool enabled;

  /// The title is an identifier (a host, a code): set in mono so it
  /// verifies character by character.
  final bool mono;
}

/// A titled run of options; the label is optional for a lone group.
class GerfautSelectGroup<T> {
  const GerfautSelectGroup({required this.items, this.label});

  final List<GerfautSelectItem<T>> items;

  /// Uppercase header above the group.
  final String? label;
}

/// The one way to pick from a list in Gerfaut: a field that reads as an
/// input at rest, opening a Gerfaut menu anchored under it on a wide
/// screen and a bottom sheet on a phone. Two-line rows, group headers,
/// disabled options, the current one checked.
class GerfautSelect<T> extends StatefulWidget {
  const GerfautSelect({
    super.key,
    required this.label,
    required this.value,
    required this.groups,
    required this.onChanged,
  });

  /// A lone group without a header.
  GerfautSelect.items({
    super.key,
    required this.label,
    required this.value,
    required List<GerfautSelectItem<T>> items,
    required this.onChanged,
  }) : groups = [GerfautSelectGroup<T>(items: items)];

  /// What the field selects, for assistive technology.
  final String label;
  final T value;
  final List<GerfautSelectGroup<T>> groups;

  /// Called with the option picked, even when it is the current one.
  /// Null greys the field out: it shows its value and opens nothing,
  /// and the line under it says why.
  final ValueChanged<T>? onChanged;

  /// Every option, groups flattened.
  List<GerfautSelectItem<T>> get items => [
    for (final group in groups) ...group.items,
  ];

  /// The option matching [value], or null when the list has none.
  GerfautSelectItem<T>? get selected {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  @override
  State<GerfautSelect<T>> createState() => _GerfautSelectState<T>();
}

class _GerfautSelectState<T> extends State<GerfautSelect<T>> {
  bool _focused = false;

  Future<void> _open() async {
    // A wide window opens the options in a menu anchored to the field;
    // a narrower one raises a bottom sheet the thumb reaches.
    final wide = MediaQuery.sizeOf(context).width >= GerfautLayout.wideFrom;
    final picked = wide
        ? await _showAnchored<T>(context, widget)
        : await _showSheet<T>(context, widget);
    if (picked != null && mounted) widget.onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final selected = widget.selected;
    final title = selected?.title ?? '';
    final subtitle = selected?.subtitle;
    final enabled = widget.onChanged != null;
    final baseStyle = selected?.mono ?? false
        ? tokens.data.copyWith(fontSize: tokens.body.fontSize)
        : tokens.body;
    // Greyed, the value is still read: it is what applies again once
    // the field can be changed.
    final titleStyle = enabled
        ? baseStyle
        : baseStyle.copyWith(color: tokens.textMuted);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      value: subtitle == null ? title : '$title, $subtitle',
      onTap: enabled ? _open : null,
      excludeSemantics: true,
      // Drawn at a field's height, answering the finger over a whole
      // touch target.
      child: TapTarget(
        child: Material(
          color: tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
            onTap: enabled ? _open : null,
            onFocusChange: (focused) => setState(() => _focused = focused),
            // A field's height at least, and taller when the system text
            // is large: a fixed height would cut the value in half at 200 %.
            child: Container(
              constraints: const BoxConstraints(
                minHeight: GerfautTouch.control,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: GerfautSpacing.md,
                vertical: GerfautSpacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GerfautRadius.sm),
                border: Border.all(
                  color: _focused ? tokens.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  if (selected?.icon != null) ...[
                    Icon(selected!.icon, size: 16, color: tokens.textMuted),
                    const SizedBox(width: GerfautSpacing.sm),
                  ],
                  // The value alone, as on the desktop: what a choice
                  // means is the second line of its row in the open
                  // list, and a field has no room to say it whole. The
                  // free width is the title's, so a long one ends in an
                  // ellipsis inside the field, never past it.
                  Expanded(
                    child: Text(
                      title,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: GerfautSpacing.sm),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a menu closes with: the option picked, wrapped. An option may
/// be null itself, as "Automatic" is among the public servers, and a
/// bare null could not tell that pick from a menu closed on nothing.
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

/// The options under the field, on a floating card. Pops with the
/// value picked, or null when closed without a pick.
Future<_Picked<T>?> _showAnchored<T>(
  BuildContext context,
  GerfautSelect<T> select,
) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final field = origin & box.size;
  return Navigator.of(context).push<_Picked<T>>(
    _AnchoredMenuRoute<T>(
      select: select,
      field: field,
      overlaySize: overlay.size,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// The options as a sheet from the bottom of a phone screen.
Future<_Picked<T>?> _showSheet<T>(
  BuildContext context,
  GerfautSelect<T> select,
) {
  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  final maxHeight = MediaQuery.sizeOf(context).height * _sheetShare;
  return showModalBottomSheet<_Picked<T>>(
    context: context,
    backgroundColor: tokens.surface,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    constraints: BoxConstraints(maxHeight: maxHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GerfautRadius.canvas),
      ),
    ),
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: GerfautSpacing.sm,
            bottom: GerfautSpacing.xs,
          ),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.border,
              borderRadius: BorderRadius.circular(GerfautRadius.full),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.md,
            GerfautSpacing.sm,
            GerfautSpacing.md,
            GerfautSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              select.label.toUpperCase(),
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          ),
        ),
        Flexible(
          child: _OptionList<T>(
            select: select,
            padding: const EdgeInsets.fromLTRB(
              GerfautPanel.padding,
              0,
              GerfautPanel.padding,
              GerfautSpacing.md,
            ),
            onPick: (value) => Navigator.of(sheetContext).pop(_Picked(value)),
          ),
        ),
      ],
    ),
  );
}

/// A menu that sits right under (or, short of room, above) its field,
/// with a transparent barrier: the page stays in view.
class _AnchoredMenuRoute<T> extends PopupRoute<_Picked<T>> {
  _AnchoredMenuRoute({
    required this.select,
    required this.field,
    required this.overlaySize,
    required this.barrierLabel,
  });

  final GerfautSelect<T> select;
  final Rect field;
  final Size overlaySize;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => GerfautMotion.fast;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // A fade only: nothing slides, nothing bounces.
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    const gap = GerfautSpacing.xs;
    final below = overlaySize.height - field.bottom - gap - GerfautSpacing.md;
    final above = field.top - gap - GerfautSpacing.md;
    final opensBelow = below >= min(_menuMaxHeight, 240) || below >= above;
    final maxHeight = min(
      _menuMaxHeight,
      max(opensBelow ? below : above, 96.0),
    );
    final width = max(field.width, _menuMinWidth);
    final left = min(field.left, overlaySize.width - width - GerfautSpacing.md);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Stack(
        children: [
          Positioned(
            left: max(left, GerfautSpacing.md),
            top: opensBelow ? field.bottom + gap : null,
            bottom: opensBelow ? null : overlaySize.height - field.top + gap,
            width: width,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              label: select.label,
              child: Container(
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(GerfautRadius.lg),
                  border: Border.all(color: tokens.border),
                  boxShadow: [tokens.shadowOverlay],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: _OptionList<T>(
                    select: select,
                    padding: const EdgeInsets.all(GerfautPanel.padding),
                    onPick: (value) =>
                        Navigator.of(context).pop(_Picked(value)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rows themselves, shared by the menu and the sheet: headers,
/// hairlines between groups, the current option checked.
class _OptionList<T> extends StatelessWidget {
  const _OptionList({
    required this.select,
    required this.padding,
    required this.onPick,
  });

  final GerfautSelect<T> select;
  final EdgeInsets padding;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final rows = <Widget>[];
    for (final (index, group) in select.groups.indexed) {
      if (index > 0) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.xs),
            child: Divider(height: 1, thickness: 1, color: tokens.border),
          ),
        );
      }
      if (group.label != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GerfautPanel.rowInset,
              GerfautSpacing.sm,
              GerfautPanel.rowInset,
              GerfautSpacing.xs,
            ),
            child: Text(
              group.label!.toUpperCase(),
              style: tokens.label.copyWith(
                fontSize: 11,
                color: tokens.textMuted,
              ),
            ),
          ),
        );
      }
      for (final item in group.items) {
        rows.add(
          _OptionRow<T>(
            item: item,
            selected: item.value == select.value,
            onTap: item.enabled ? () => onPick(item.value) : null,
          ),
        );
      }
    }
    return FocusTraversalGroup(
      child: ListView(shrinkWrap: true, padding: padding, children: rows),
    );
  }
}

/// One option: leading icon, title, subtitle, and the check when it is
/// the current one. Disabled rows are muted and take no tap.
class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GerfautSelectItem<T> item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final enabled = onTap != null;
    final ink = enabled ? tokens.text : tokens.textMuted;
    final titleStyle = item.mono
        ? tokens.data.copyWith(fontSize: 14, color: ink)
        : tokens.bodySmall.copyWith(
            color: ink,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: item.subtitle == null
          ? item.title
          : '${item.title}, ${item.subtitle}',
      excludeSemantics: true,
      // Rows touch each other: the ring is drawn inside the row's edge.
      child: FocusRing(
        gap: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          autofocus: selected,
          focusColor: Colors.transparent,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: GerfautTouch.target),
            padding: const EdgeInsets.symmetric(
              horizontal: GerfautPanel.rowInset,
              vertical: GerfautSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceSunken : null,
              borderRadius: BorderRadius.circular(GerfautRadius.md),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 16, color: ink),
                  const SizedBox(width: GerfautSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // An identifier wraps rather than lose its end: the
                      // end of a host is what tells two servers apart.
                      Text(
                        item.title,
                        style: titleStyle,
                        maxLines: item.mono ? null : 1,
                        overflow: item.mono ? null : TextOverflow.ellipsis,
                      ),
                      if (item.subtitle != null)
                        Text(
                          item.subtitle!,
                          // The label face at its size, without the
                          // tracking it keeps for uppercase: this line is
                          // a phrase, as in the overflow menu.
                          style: tokens.label.copyWith(
                            fontSize: 11,
                            letterSpacing: 0,
                            color: tokens.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: GerfautSpacing.sm),
                  Icon(LucideIcons.check, size: 16, color: tokens.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
