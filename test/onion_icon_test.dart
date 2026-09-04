import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/onion_icon.dart';
import 'package:gerfaut/widgets/section_card.dart';

Widget framed(Widget child) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('the onion is stroked like every Lucide glyph, at any size', (
    tester,
  ) async {
    const ink = Color(0xFF0E7490);
    for (final side in [16.0, 20.0, 24.0]) {
      await tester.pumpWidget(framed(OnionIcon(size: side, color: ink)));

      expect(tester.getSize(find.byType(OnionIcon)), Size.square(side));
      // Stroke only, 1.5 wide, round ends, in the colour it was handed:
      // the rules the whole set is drawn to. The canvas is scaled, not
      // the coordinates, so the stroke thins with the glyph instead of
      // staying 1.5 device pixels at 16px.
      expect(
        tester.renderObject(find.byType(OnionIcon)),
        paints..path(color: ink, strokeWidth: 1.5, style: PaintingStyle.stroke),
      );
    }
  });

  testWidgets('it takes the size and the colour of the row it sits in', (
    tester,
  ) async {
    await tester.pumpWidget(
      framed(
        const SectionCard.glyph(
          glyph: OnionIcon(),
          title: 'Tor',
          children: [SizedBox(height: 8)],
        ),
      ),
    );

    // The card says 18px in the muted ink, exactly as it does for the
    // Lucide icon of every other section: the caller repeats neither.
    expect(tester.getSize(find.byType(OnionIcon)), const Size.square(18));
    expect(
      tester.renderObject(find.byType(OnionIcon)),
      paints..path(color: GerfautTokens.light.textMuted),
    );
    // Beside a title that says the word, the glyph stays silent.
    expect(find.bySemanticsLabel('Tor'), findsOneWidget);
  });

  testWidgets('it says what it is when it stands alone', (tester) async {
    await tester.pumpWidget(framed(const OnionIcon(semanticLabel: 'Tor')));
    expect(find.bySemanticsLabel('Tor'), findsOneWidget);
  });
}
