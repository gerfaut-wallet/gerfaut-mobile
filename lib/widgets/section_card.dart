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
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

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
    return Container(
      margin: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: frame(tokens),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: icon, title: title),
          ...children,
        ],
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
                child: _SectionTitle(icon: icon, title: title),
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
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.textMuted),
          const SizedBox(width: GerfautSpacing.sm),
          // Flexible, because a Row hands an inflexible child unbounded
          // width: at a doubled text scale on a narrow frame a one-word
          // title ran off the card rather than wrapping onto a second
          // line.
          Flexible(child: Text(title, style: tokens.h2)),
        ],
      ),
    );
  }
}
