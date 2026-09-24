import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One card of the settings screen: an icon, a title in the display
/// face, and the controls below. Every section, whatever it holds,
/// shares this frame so the screen reads as one list.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.iconColor,
    this.trailing,
  }) : glyph = null;

  /// The same card with a glyph of our own — an [OnionIcon] — for the
  /// one section Lucide has no icon for. The card hands it the size and
  /// the colour every other section icon gets, through the icon theme,
  /// so a caller never restates them and the row cannot drift.
  const SectionCard.glyph({
    super.key,
    required Widget this.glyph,
    required this.title,
    required this.children,
    this.iconColor,
    this.trailing,
  }) : icon = null;

  /// The Lucide glyph of the section; null when [glyph] draws it.
  final IconData? icon;

  /// Drawn in place of the Lucide icon; null on every other section.
  final Widget? glyph;

  final String title;
  final List<Widget> children;

  /// The ink of the icon; the muted text colour when null. The premium
  /// cards set Bruyère here, so the section reads as the paid service's
  /// from its glyph on.
  final Color? iconColor;

  /// One quiet action at the end of the title, for the card itself
  /// rather than for anything in it: "Hide".
  final Widget? trailing;

  /// The frame every section card wears: card surface, hairline, the
  /// large radius.
  static BoxDecoration frame(GerfautTokens tokens) {
    return BoxDecoration(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(GerfautRadius.lg),
      border: Border.all(color: tokens.border),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // One stop for a screen reader, its title first. Without it, the
    // words of every card on the page fold into a single node, and a
    // field among them takes that node over: the whole page read as
    // the hint of one text field, and a note under a card read only
    // after every card below it. The margin stays outside, so the
    // focus drawn around the card is its frame.
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: frame(tokens),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                glyph: glyph ?? Icon(icon),
                title: title,
                color: iconColor,
                trailing: trailing,
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The same card around slivers: for a section whose rows are a list
/// that reorders by drag. Such a list has to scroll the page to reach a
/// row out of sight, and only a sliver of the page's own scroll view
/// can; boxed in a card, it could not. The frame is painted along the
/// slivers' whole extent, so the card reads as one card however far it
/// runs, and the [slivers] sit under the title in the same padding.
class SliverSectionCard extends StatelessWidget {
  const SliverSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.slivers,
  });

  final IconData icon;
  final String title;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      sliver: DecoratedSliver(
        decoration: SectionCard.frame(tokens),
        sliver: SliverPadding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: _SectionTitle(glyph: Icon(icon), title: title),
              ),
              ...slivers,
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon, a title in the display face, and the gap before the
/// controls.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.glyph,
    required this.title,
    this.color,
    this.trailing,
  });

  /// A Lucide [Icon] or a glyph of ours; either way it is the card
  /// that says how big and what colour, never the caller.
  final Widget glyph;

  final String title;

  /// The icon's ink when a card has one of its own.
  final Color? color;

  /// An action at the end of the row, when the card has one.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.md),
      child: Row(
        children: [
          IconTheme.merge(
            data: IconThemeData(size: 18, color: color ?? tokens.textMuted),
            child: glyph,
          ),
          const SizedBox(width: GerfautSpacing.sm),
          // Flexible, because a Row hands an inflexible child unbounded
          // width: at a doubled text scale on a narrow frame a one-word
          // title ran off the card rather than wrapping onto a second
          // line. With an action at the end, the title takes the rest.
          if (trailing == null)
            Flexible(child: Text(title, style: tokens.h2))
          else ...[
            Expanded(child: Text(title, style: tokens.h2)),
            const SizedBox(width: GerfautSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
