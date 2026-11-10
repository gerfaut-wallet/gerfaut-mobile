import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The keyboard focus ring of every control Gerfaut draws itself: 2px of
/// the primary colour, drawn while a control under [child] holds the
/// focus, and only when that focus came from a keyboard. A touch never
/// shows it.
///
/// It is painted over the child and outside its box, so it never moves
/// the layout. A control that sits alone takes the default [gap], 2px
/// clear of its edge; a row in a list, whose neighbours touch it, takes
/// a gap of 0 and gets the ring just inside its own edge instead.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = GerfautRadius.md,
    this.gap = FocusRingPainter.defaultGap,
  });

  final Widget child;

  /// The corner radius of the control the ring goes around.
  final double radius;

  /// How far out of the control's edge the ring stands; 0 draws it
  /// inside the edge.
  final double gap;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode mode) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // A listener in the focus tree, not a stop of its own: Tab goes
    // straight to the control inside.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: CustomPaint(
        foregroundPainter: ring
            ? FocusRingPainter(
                color: tokens.primary,
                radius: widget.radius,
                gap: widget.gap,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

/// Paints the focus ring around a box of the size it is given.
class FocusRingPainter extends CustomPainter {
  const FocusRingPainter({
    required this.color,
    required this.radius,
    this.gap = defaultGap,
  });

  final Color color;
  final double radius;
  final double gap;

  /// The design system's ring: 2px wide, 2px clear of the control.
  static const double width = 2;
  static const double defaultGap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // The middle of the stroke: outside the edge by the gap, or just
    // inside it when there is none.
    final out = gap > 0 ? gap + width / 2 : -width / 2;
    final rect = (Offset.zero & size).inflate(out);
    final corner = radius + out < 0 ? 0.0 : radius + out;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(corner)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.color != color || old.radius != radius || old.gap != gap;
}
