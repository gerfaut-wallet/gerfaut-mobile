import 'package:flutter/material.dart';

/// The square, rounded chip that opens a row: which way a transaction
/// went, what an input or an output is to the wallet. One size, one
/// corner and one glyph size, whatever the row.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.icon,
    required this.ink,
    required this.fill,
    this.semanticLabel,
  });

  /// The side of the square.
  static const double side = 32;

  final IconData icon;

  /// The colour of the glyph.
  final Color ink;

  /// The colour of the square under it.
  final Color fill;

  /// What the glyph says out loud, when no text beside it says it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: ink, semanticLabel: semanticLabel),
    );
  }
}
