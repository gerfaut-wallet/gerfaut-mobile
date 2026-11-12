import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';

/// The tracking a [Text] really paints with, once the ambient default
/// style of a Material page has been merged under [style].
double? paintedTracking(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  return paragraph.text.style?.letterSpacing;
}

void main() {
  // Material's default body style is tracked (+0.25), and a style that
  // leaves its own tracking unset takes that one on a page. Whatever
  // measures a string in the bare style then lands under what is
  // painted: an address fitted to its chip lost its last glyph to the
  // fade.
  testWidgets('a style without tracking of its own paints with none', (
    tester,
  ) async {
    final tokens = GerfautTokens.light;
    final styles = {
      'h2': tokens.h2,
      'body': tokens.body,
      'bodySmall': tokens.bodySmall,
      'data': tokens.data,
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFrom(tokens, Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              for (final entry in styles.entries)
                Text(entry.key, style: entry.value),
            ],
          ),
        ),
      ),
    );
    for (final name in styles.keys) {
      expect(paintedTracking(tester, name), 0, reason: name);
    }
  });
}
