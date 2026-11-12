import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/count_badge.dart';

Widget framed(Widget child, {double textScale = 1}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('a badge is a circle or a pill, never taller than wide', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      for (final count in [1, 7, 49, 334]) {
        await tester.pumpWidget(
          framed(CountBadge(count: count), textScale: scale),
        );
        final size = tester.getSize(find.byType(CountBadge));
        expect(
          size.width,
          greaterThanOrEqualTo(size.height),
          reason: '$count at a text scale of $scale: $size',
        );
      }
    }
  });
}
