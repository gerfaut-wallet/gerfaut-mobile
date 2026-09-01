import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/section_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The card on the narrowest frame Gerfaut supports, at the text scale
/// someone who needs it actually sets.
Widget cramped(Widget card, {double width = 340, double scale = 2}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: SingleChildScrollView(child: card),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a title wraps rather than running off the card', (tester) async {
    await tester.pumpWidget(
      cramped(
        const SectionCard(
          icon: LucideIcons.lock,
          title: 'Security',
          children: [SizedBox(height: 8)],
        ),
      ),
    );

    // An overflow paints a black and yellow bar and records an
    // exception: at a doubled scale the title used to run 42px past
    // the card it names.
    expect(tester.takeException(), isNull);
    final title = tester.getSize(find.text('Security'));
    final card = tester.getSize(find.byType(SectionCard));
    expect(title.width, lessThanOrEqualTo(card.width));
  });

  testWidgets('a long title still fits, on two lines if it must', (
    tester,
  ) async {
    await tester.pumpWidget(
      cramped(
        const SectionCard(
          icon: LucideIcons.bell,
          title: 'Notifications and alerts',
          children: [SizedBox(height: 8)],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('Notifications and alerts')).width,
      lessThanOrEqualTo(tester.getSize(find.byType(SectionCard)).width),
    );
  });
}
