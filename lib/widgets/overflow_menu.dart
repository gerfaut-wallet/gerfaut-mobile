import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// Widest the menu grows, whatever its labels: past that it stops
/// reading as a menu and starts reading as a panel.
const double _menuWidth = 280;

/// One entry of an [OverflowMenu].
@immutable
class OverflowMenuItem {
  const OverflowMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.detail,
  });

  /// A Lucide glyph, as everywhere else.
  final IconData icon;

  /// What the entry does, in the words the header button used.
  final String label;

  /// A second, quieter line: what the page behind it already knows —
  /// the policy digest, say — so moving an action into the menu does
  /// not cost the reader the answer the row used to show. Read out
  /// after the label.
  final String? detail;

  /// Runs once the menu has closed, so what it opens is not fighting a
  /// surface still on its way out.
  final VoidCallback onSelected;
}

/// The overflow of a page header: what the bar cannot hold, under one
/// button.
///
/// A phone header has room for a title and about two glyphs. Gerfaut's
/// two list headers had four each, which left the wallet's name half a
/// screen and made every action look equally worth doing. What stays in
/// the bar is what is used on the way past — the sync — and the rest
/// comes here, named in words rather than guessed from a glyph.
///
/// The surface is the one DESIGN.md gives every floating thing: card
/// colour, hairline, 12px radius, the single overlay shadow, and a fade
/// with 8px of travel to place it. A device asking for less motion
/// keeps the fade and loses the travel.
class OverflowMenu extends StatefulWidget {
  const OverflowMenu({super.key, required this.items});

  final List<OverflowMenuItem> items;

  @override
  State<OverflowMenu> createState() => _OverflowMenuState();
}

class _OverflowMenuState extends State<OverflowMenu> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      // The tooltip is the spoken label too: a Semantics label on top
      // would only say the same word a second time.
      tooltip: 'More',
      onPressed: widget.items.isEmpty ? null : _open,
      icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
    );
  }

  Future<void> _open() async {
    final navigator = Navigator.of(context);
    final button = context.findRenderObject()! as RenderBox;
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await navigator.push(
      _OverflowMenuRoute(
        items: widget.items,
        button: origin & button.size,
        overlaySize: overlay.size,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
      ),
    );
    // The entries act on the page this menu belongs to: a page that
    // left while the menu was open has nothing left to act on.
    if (mounted) picked?.onSelected();
  }
}

/// The menu itself, hung under the button that opened it, over a
/// transparent barrier: the page it belongs to stays in view.
class _OverflowMenuRoute extends PopupRoute<OverflowMenuItem> {
  _OverflowMenuRoute({
    required this.items,
    required this.button,
    required this.overlaySize,
    required this.barrierLabel,
  });

  final List<OverflowMenuItem> items;

  /// The button, in the overlay's coordinates.
  final Rect button;

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
    // A fade only, at the speed of the other floating list in the app.
    // A panel anchored under its own button already says where it came
    // from; travel would only be the second answer to a settled question.
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
    final top = button.bottom + gap;
    final width = min(_menuWidth, overlaySize.width - GerfautSpacing.md * 2);
    // Flush with the button's own edge, so the menu hangs off the
    // glyph that opened it rather than off the screen.
    final right = max(overlaySize.width - button.right, GerfautSpacing.sm);
    final maxHeight = max(overlaySize.height - top - GerfautSpacing.md, 96.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Stack(
        children: [
          Positioned(
            top: top,
            right: right,
            width: width,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              label: MaterialLocalizations.of(context).popupMenuLabel,
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
                  child: FocusTraversalGroup(
                    // A list, not a column: at a doubled text scale on
                    // a short screen the entries scroll rather than
                    // running off the bottom.
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(GerfautSpacing.xs + 2),
                      children: [
                        for (final item in items)
                          _MenuRow(
                            item: item,
                            onTap: () => Navigator.of(context).pop(item),
                          ),
                      ],
                    ),
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

/// One entry: the glyph, the label, and the quiet line under it. Same
/// row as the select's options — 44px, radius 8 — so the two floating
/// lists of the app read as one.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onTap});

  final OverflowMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final detail = item.detail;
    return Semantics(
      container: true,
      button: true,
      label: detail == null ? item.label : '${item.label}: $detail',
      // Excluding the child's semantics drops the ink well's tap with
      // them: the node has to carry its own, or a screen reader's
      // double-tap lands on nothing.
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.sm + 2,
            vertical: GerfautSpacing.sm - 2,
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 16, color: tokens.text),
              const SizedBox(width: GerfautSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null)
                      Text(
                        detail,
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
            ],
          ),
        ),
      ),
    );
  }
}
