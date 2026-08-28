import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Width from which the options open in a menu anchored to the field;
/// narrower, they rise as a bottom sheet the thumb reaches.
const double _anchoredFrom = 600;

/// Tallest the anchored menu grows before it scrolls.
const double _menuMaxHeight = 360;

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
  final ValueChanged<T> onChanged;

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
    final wide = MediaQuery.sizeOf(context).width >= _anchoredFrom;
    final T? picked = wide
        ? await _showAnchored<T>(context, widget)
        : await _showSheet<T>(context, widget);
    if (picked != null && mounted) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final selected = widget.selected;
    final title = selected?.title ?? '';
    final subtitle = selected?.subtitle;
    final titleStyle = selected?.mono ?? false
        ? tokens.data.copyWith(fontSize: tokens.body.fontSize)
        : tokens.body;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      value: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          onTap: _open,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
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
                Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  Text(
                    ' · ',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: GerfautSpacing.sm),
                Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The options under the field, on a floating card. Pops with the
/// value picked, or null.
Future<T?> _showAnchored<T>(BuildContext context, GerfautSelect<T> select) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final field = origin & box.size;
  return Navigator.of(context).push<T>(
    _AnchoredMenuRoute<T>(
      select: select,
      field: field,
      overlaySize: overlay.size,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// The options as a sheet from the bottom of a phone screen.
Future<T?> _showSheet<T>(BuildContext context, GerfautSelect<T> select) {
  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  final maxHeight = MediaQuery.sizeOf(context).height * _sheetShare;
  return showModalBottomSheet<T>(
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
              GerfautSpacing.sm + 2,
              0,
              GerfautSpacing.sm + 2,
              GerfautSpacing.md,
            ),
            onPick: (value) => Navigator.of(sheetContext).pop(value),
          ),
        ),
      ],
    ),
  );
}

/// A menu that sits right under (or, short of room, above) its field,
/// with a transparent barrier: the page stays in view.
class _AnchoredMenuRoute<T> extends PopupRoute<T> {
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
  Duration get transitionDuration => const Duration(milliseconds: 150);

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
    final width = max(field.width, 240.0);
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
                    padding: const EdgeInsets.all(GerfautSpacing.xs + 2),
                    onPick: (value) => Navigator.of(context).pop(value),
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
              GerfautSpacing.sm + 2,
              GerfautSpacing.sm,
              GerfautSpacing.sm + 2,
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
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        autofocus: selected,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.sm + 2,
            vertical: GerfautSpacing.sm - 2,
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
                    Text(
                      item.title,
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: tokens.label.copyWith(
                          fontSize: 11,
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
    );
  }
}
