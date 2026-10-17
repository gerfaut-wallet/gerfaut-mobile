import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/choice_group.dart';
import 'package:gerfaut/widgets/tap_target.dart';

/// One group of three, the middle one out of reach.
Widget _app({
  required String value,
  required ValueChanged<String> onChanged,
  bool middleEnabled = false,
}) {
  return MaterialApp(
    theme: themeFrom(GerfautTokens.light, Brightness.light),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(GerfautSpacing.md),
        child: ChoiceGroup<String>(
          label: 'Theme',
          value: value,
          options: [
            const ChoiceOption(value: 'first', label: 'Light'),
            ChoiceOption(
              value: 'second',
              label: 'Dark',
              enabled: middleEnabled,
            ),
            const ChoiceOption(value: 'third', label: 'System'),
          ],
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

Rect _option(WidgetTester tester, String label) =>
    tester.getRect(find.widgetWithText(InkWell, label));

/// The area that answers the finger for the option [label].
Rect _target(WidgetTester tester, String label) => tester.getRect(
  find.ancestor(of: find.text(label), matching: find.byType(TapTarget)).first,
);

void main() {
  testWidgets('two options never touch', (tester) async {
    await tester.pumpWidget(_app(value: 'first', onChanged: (_) {}));

    // The failure this guards: options laid out with no gap read as one
    // block of colour, and adjacent touch targets need room of their own
    // to be aimed at.
    final first = _option(tester, 'Light');
    final second = _option(tester, 'Dark');
    final third = _option(tester, 'System');
    expect(second.top - first.bottom, GerfautSpacing.sm);
    expect(third.top - second.bottom, GerfautSpacing.sm);
    // Each one is drawn a control's height and answers the finger over
    // a full target, and the targets stand apart.
    expect(first.height, GerfautTouch.control);
    expect(second.height, GerfautTouch.control);
    final firstTarget = _target(tester, 'Light');
    final secondTarget = _target(tester, 'Dark');
    expect(firstTarget.height, GerfautTouch.target);
    expect(secondTarget.height, GerfautTouch.target);
    expect(secondTarget.top, greaterThan(firstTarget.bottom));
  });

  testWidgets('picking an option reports it once', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(picked, ['third']);
  });

  testWidgets('an option that cannot apply takes no tap', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);

    // Quiet rather than absent: the option still says it exists.
    final tokens = GerfautTokens.light;
    final label = tester.widget<Text>(find.text('Dark'));
    expect(label.style?.color, tokens.textMuted);
  });

  testWidgets('the selected option is the only filled one', (tester) async {
    await tester.pumpWidget(
      _app(value: 'third', onChanged: (_) {}, middleEnabled: true),
    );

    final tokens = GerfautTokens.light;
    Color fill(String label) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        )
        .color!;
    expect(fill('System'), tokens.primary);
    expect(fill('Light'), tokens.surfaceSunken);
    expect(fill('Dark'), tokens.surfaceSunken);
  });
}
