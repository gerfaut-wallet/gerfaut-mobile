import 'package:flutter/material.dart';

/// An onion, drawn in Lucide's grammar.
///
/// Tor's own mark is an onion, and Lucide has none: the closest it
/// offers is a carnival mask, which says "disguise" where the section
/// means "the onion router". So this one glyph is drawn by hand — and
/// drawn to the same rules as the set it stands in, so it cannot be
/// told from its neighbours: a 24 unit box, a 1.5 stroke, round caps
/// and joins, no fill, and the current colour. It is the only
/// hand-drawn icon of the app; anything Lucide has, Lucide draws.
///
/// Size and colour come from the surrounding [IconTheme], exactly as
/// they do for [Icon], so a caller that sets neither matches whatever
/// row it sits in.
class OnionIcon extends StatelessWidget {
  const OnionIcon({super.key, this.size, this.color, this.semanticLabel});

  /// Falls back to the ambient icon theme, then to Material's own 24.
  final double? size;

  /// Falls back to the ambient icon theme, then to the text colour.
  final Color? color;

  /// Said out loud when the glyph carries meaning of its own. Left
  /// unset beside a title that already names it: an icon that repeats
  /// the word next to it makes a screen reader say it twice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final tint =
        color ?? theme.color ?? DefaultTextStyle.of(context).style.color;
    final glyph = CustomPaint(
      size: Size.square(side),
      painter: _OnionPainter(tint ?? const Color(0xFF000000)),
    );
    if (semanticLabel == null) return glyph;
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

/// The four strokes of the onion, in a 24 unit box: the sprout, the
/// bulb, and the two skin layers that meet under it. The canvas is
/// scaled rather than the coordinates, so the 1.5 stroke thins with
/// the glyph the way a font would, instead of thickening at 16px.
class _OnionPainter extends CustomPainter {
  const _OnionPainter(this.color);

  final Color color;

  /// The box the paths were drawn in.
  static const double _box = 24;

  static Path _onion() {
    return Path()
      // The sprout, leaning off the top.
      ..moveTo(12, 5.5)
      ..relativeCubicTo(-0.6, -1.6, 0, -2.8, 1.6, -3.5)
      // The bulb: down the left flank, around the bottom, back up.
      ..moveTo(12, 5.5)
      ..cubicTo(8.5, 8.8, 5.5, 10.8, 5.5, 13.5)
      ..arcToPoint(
        const Offset(18.5, 13.5),
        radius: const Radius.circular(6.5),
        // SVG sweep-flag 0: the arc takes the long way round, under
        // the bulb, instead of cutting straight across it.
        clockwise: false,
      )
      ..relativeCubicTo(0, -2.7, -3, -4.7, -6.5, -8)
      ..close()
      // The two skins, meeting at the sprout and again at the base.
      ..moveTo(12, 5.5)
      ..relativeCubicTo(-2, 3.4, -3, 6.4, -3, 9.1)
      ..relativeCubicTo(0, 2.1, 0.9, 3.8, 3, 5.4)
      ..moveTo(12, 5.5)
      ..relativeCubicTo(2, 3.4, 3, 6.4, 3, 9.1)
      ..relativeCubicTo(0, 2.1, -0.9, 3.8, -3, 5.4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _box, size.height / _box);
    canvas.drawPath(
      _onion(),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OnionPainter old) => old.color != color;
}
