import 'package:flutter/material.dart';

import 'brand_art.dart';

/// The falcon head alone, sized by its height and painted in one
/// colour. The identity of the app, never a functional icon: nothing in
/// the interface may use it to mean an action.
class GerfautMark extends StatelessWidget {
  const GerfautMark({
    super.key,
    required this.color,
    this.height = 28,
    this.semanticLabel,
  });

  final Color color;

  /// Height in logical pixels. The brand kit sets 24 as the floor: a
  /// smaller falcon turns into a smudge.
  final double height;

  /// What assistive technology reads. Left null, the shape is silent,
  /// which is what a watermark wants.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _Art(
      outlines: GerfautArt.mark,
      art: GerfautArt.markSize,
      color: color,
      width: height * GerfautArt.markSize.width / GerfautArt.markSize.height,
      semanticLabel: semanticLabel,
    );
  }
}

/// The full logo: the falcon over GERFAUT, sized by its width. The
/// wordmark is outlined in the brand kit, so it needs no font.
class GerfautLockup extends StatelessWidget {
  const GerfautLockup({
    super.key,
    required this.color,
    this.width = 132,
    this.semanticLabel,
  });

  final Color color;
  final double width;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _Art(
      outlines: GerfautArt.lockup,
      art: GerfautArt.lockupSize,
      color: color,
      width: width,
      semanticLabel: semanticLabel,
    );
  }
}

/// One brand outline, scaled to [width] and filled with [color].
class _Art extends StatelessWidget {
  const _Art({
    required this.outlines,
    required this.art,
    required this.color,
    required this.width,
    required this.semanticLabel,
  });

  final List<Path> outlines;

  /// The box the outlines were drawn in, which fixes their proportions.
  final Size art;
  final Color color;
  final double width;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final shape = SizedBox(
      width: width,
      height: width * art.height / art.width,
      child: CustomPaint(
        painter: _ArtPainter(outlines: outlines, art: art, color: color),
      ),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: shape)
        : Semantics(image: true, label: label, child: shape);
  }
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter({
    required this.outlines,
    required this.art,
    required this.color,
  });

  final List<Path> outlines;
  final Size art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    canvas.save();
    canvas.scale(size.width / art.width);
    // One at a time, each with its own fill rule: merged into a single
    // path, the overlapping contours of a letter would cancel out.
    for (final outline in outlines) {
      canvas.drawPath(outline, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.color != color || old.outlines != outlines;
}
