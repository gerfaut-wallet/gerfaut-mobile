import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The confirmation count from which a transaction is settled: its
/// count is no longer written, its glyph no longer takes a colour,
/// and a broadcast stops being watched. The pie has one part for
/// each block on the way.
const int settledConfirmations = 6;

/// The angle, in degrees, that [filled] confirmations sweep from noon:
/// one part of the circle per confirmation, the whole circle once
/// settled. Out of range counts are held to the circle.
double confirmationSweepDegrees(int filled) =>
    filled.clamp(0, settledConfirmations) * 360 / settledConfirmations;

/// How far a transaction has come towards settled, as a pie that fills
/// clockwise from noon: a ring, and a solid sector of the same colour.
///
/// Drawn on the 24 unit grid of the icon set, with its stroke, so it
/// sits in the same box and at the same weight as the clock and the
/// check it stands beside. No dividers between the parts: at list size
/// they would merge into a smudge, and the sector edge already reads.
///
/// It says nothing to assistive technology: the caller names the state
/// in words.
class ConfirmationPie extends StatelessWidget {
  const ConfirmationPie({
    super.key,
    required this.filled,
    required this.size,
    required this.color,
  });

  /// The confirmations drawn, held between 0 and [settledConfirmations].
  final int filled;

  /// The side of the square box, as for an icon.
  final double size;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: ConfirmationPiePainter(
          filled: filled.clamp(0, settledConfirmations),
          color: color,
        ),
      ),
    );
  }
}

/// Paints [ConfirmationPie]: a circle of radius 10 stroked 2 wide, and
/// the sector out to that radius, scaled from a 24 unit grid.
class ConfirmationPiePainter extends CustomPainter {
  const ConfirmationPiePainter({required this.filled, required this.color});

  final int filled;
  final Color color;

  static const double _grid = 24;
  static const double _radius = 10;
  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _grid;
    final center = size.center(Offset.zero);
    final radius = _radius * scale;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * scale
        ..isAntiAlias = true,
    );

    final sweep = confirmationSweepDegrees(filled) * math.pi / 180;
    if (sweep <= 0) return;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (sweep >= 2 * math.pi) {
      // A full turn is a disc: drawn as one, rather than as an arc
      // whose two ends meet on the same edge.
      canvas.drawCircle(center, radius, fill);
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      true,
      fill,
    );
  }

  @override
  bool shouldRepaint(ConfirmationPiePainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.color != color;
}
