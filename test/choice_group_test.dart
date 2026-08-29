import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/choice_group.dart';

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
          label: 'Price source',
          value: value,
          options: [
            const ChoiceOption(value: 'first', label: 'CoinGecko'),
            ChoiceOption(
              value: 'second',
              label: 'Kraken',
              enabled: middleEnabled,
            ),
            const ChoiceOption(value: 'third', label: 'mempool.space'),
          ],
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

Rect _option(WidgetTester tester, String label) =>
    tester.getRect(find.widgetWithText(InkWell, label));

void main() {
  testWidgets('two options never touch', (tester) async {
    await tester.pumpWidget(_app(value: 'first', onChanged: (_) {}));

    // The failure this guards: options laid out with no gap read as one
    // block of colour, and adjacent touch targets need room of their own
    // to be aimed at.
    final first = _option(tester, 'CoinGecko');
    final second = _option(tester, 'Kraken');
    final third = _option(tester, 'mempool.space');
    expect(second.top - first.bottom, GerfautSpacing.sm);
    expect(third.top - second.bottom, GerfautSpacing.sm);
    // And each one is a full 44px target.
    expect(first.height, 44);
    expect(second.height, 44);
  });

  testWidgets('picking an option reports it once', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

    await tester.tap(find.text('mempool.space'));
    await tester.pumpAndSettle();
    expect(picked, ['third']);
  });

  testWidgets('an option that cannot apply takes no tap', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_app(value: 'first', onChanged: picked.add));

    await tester.tap(find.text('Kraken'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);

    // Quiet rather than absent: the option still says it exists.
    final tokens = GerfautTokens.light;
    final label = tester.widget<Text>(find.text('Kraken'));
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
    expect(fill('mempool.space'), tokens.primary);
    expect(fill('CoinGecko'), tokens.surfaceSunken);
    expect(fill('Kraken'), tokens.surfaceSunken);
  });
}
