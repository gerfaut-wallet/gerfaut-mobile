import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/widgets/confirmation_pie.dart';

const _green = Color(0xFF1B7F4B);

/// How opaque the pixel at ([x], [y]) is in a 48px pie of [filled]
/// parts: centre at 24, the ring between 18 and 22 from it.
Future<int> _alphaAt(WidgetTester tester, int filled, int x, int y) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: ConfirmationPie(filled: filled, size: 48, color: _green),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image.width, bytes!);
  });
  final (width, bytes) = data!;
  return bytes.getUint8((y * width + x) * 4 + 3);
}

void main() {
  testWidgets('the sector starts at noon and turns clockwise', (tester) async {
    // One part: filled just right of noon, not yet at three o'clock.
    expect(await _alphaAt(tester, 1, 29, 15), greaterThan(200));
    expect(await _alphaAt(tester, 1, 34, 24), 0);
    expect(await _alphaAt(tester, 1, 19, 15), 0);
    // Three parts: the right half, and nothing on the left.
    expect(await _alphaAt(tester, 3, 34, 24), greaterThan(200));
    expect(await _alphaAt(tester, 3, 14, 24), 0);
    // Five parts: all but the last sixth, left of noon.
    expect(await _alphaAt(tester, 5, 14, 24), greaterThan(200));
    expect(await _alphaAt(tester, 5, 19, 15), 0);
    // No part: the bare ring.
    expect(await _alphaAt(tester, 0, 29, 15), 0);
    expect(await _alphaAt(tester, 0, 44, 24), greaterThan(200));
  });

  testWidgets('the pie paints what it is given, in a square box', (
    tester,
  ) async {
    for (final filled in [1, 3, 5]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ConfirmationPie(filled: filled, size: 14, color: _green),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(ConfirmationPie),
          matching: find.byType(CustomPaint),
        ),
      );
      final painter = paint.painter! as ConfirmationPiePainter;
      expect(painter.filled, filled);
      expect(painter.color, _green);
      expect(tester.getSize(find.byType(ConfirmationPie)), const Size(14, 14));
    }
  });

  testWidgets('a count past the circle is held to it', (tester) async {
    for (final (given, drawn) in [(-1, 0), (9, settledConfirmations)]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ConfirmationPie(filled: given, size: 14, color: _green),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(ConfirmationPie),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((paint.painter! as ConfirmationPiePainter).filled, drawn);
    }
  });

  testWidgets('the pie says nothing of its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ConfirmationPie(filled: 3, size: 14, color: _green),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });

  test('each confirmation sweeps a sixth of the circle from noon', () {
    expect(confirmationSweepDegrees(0), 0);
    expect(confirmationSweepDegrees(1), 60);
    expect(confirmationSweepDegrees(3), 180);
    expect(confirmationSweepDegrees(5), 300);
    expect(confirmationSweepDegrees(settledConfirmations), 360);
    expect(confirmationSweepDegrees(-2), 0);
    expect(confirmationSweepDegrees(40), 360);
  });

  test('it repaints when the count or the colour moves, and only then', () {
    const painter = ConfirmationPiePainter(filled: 3, color: _green);
    expect(
      painter.shouldRepaint(
        const ConfirmationPiePainter(filled: 3, color: _green),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const ConfirmationPiePainter(filled: 2, color: _green),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const ConfirmationPiePainter(filled: 3, color: Color(0xFF000000)),
      ),
      isTrue,
    );
  });
}
