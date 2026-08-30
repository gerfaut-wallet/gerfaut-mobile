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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tokens.textMuted),
              const SizedBox(width: GerfautSpacing.sm),
              // Flexible, because a Row hands an inflexible child
              // unbounded width: at a doubled text scale on a narrow
              // frame a one-word title ran off the card rather than
              // wrapping onto a second line.
              Flexible(child: Text(title, style: tokens.h2)),
            ],
          ),
          const SizedBox(height: GerfautSpacing.md),
          ...children,
        ],
      ),
    );
  }
}
