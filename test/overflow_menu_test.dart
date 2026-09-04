import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/app_bar.dart';
import 'package:gerfaut/widgets/overflow_menu.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'menu.dart';

/// The smallest phone Gerfaut supports, in its own pixels.
void usePixel2(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1080 / 411;
  addTearDown(tester.view.reset);
}

/// A page whose header holds nothing but the menu.
Widget page(
  List<OverflowMenuItem> items, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) {
  final tokens = brightness == Brightness.dark
      ? GerfautTokens.dark
      : GerfautTokens.light;
  return MaterialApp(
    theme: themeFrom(tokens, brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          appBar: GerfautAppBar.text(
            'Cold storage',
            actions: [
              OverflowMenu(items: items),
              const SizedBox(width: GerfautSpacing.sm),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// Three entries, one of them with a line under it.
List<OverflowMenuItem> sample({List<String> picked = const []}) => [
  OverflowMenuItem(
    icon: LucideIcons.route,
    label: 'Policy',
    detail: '2 of 3 keys',
    onSelected: () => picked.add('Policy'),
  ),
  OverflowMenuItem(
    icon: LucideIcons.eyeOff,
    label: 'Hide balances',
    onSelected: () => picked.add('Hide balances'),
  ),
  OverflowMenuItem(
    icon: LucideIcons.radio,
    label: 'Broadcast',
    onSelected: () => picked.add('Broadcast'),
  ),
];

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the menu wears the floating surface (${brightness.name})', (
      tester,
    ) async {
      final tokens = brightness == Brightness.dark
          ? GerfautTokens.dark
          : GerfautTokens.light;
      await tester.pumpWidget(page(sample(), brightness: brightness));
      await openMenu(tester);

      // Card colour, hairline, 12px, and the one shadow of the system:
      // the surface DESIGN.md gives every floating thing.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration ==
                  BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(GerfautRadius.lg),
                    border: Border.all(color: tokens.border),
                    boxShadow: [tokens.shadowOverlay],
                  ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('it hangs under the button that opened it', (tester) async {
    usePixel2(tester);
    await tester.pumpWidget(page(sample()));
    final button = tester.getRect(find.byTooltip('More'));
    await openMenu(tester);

    final panel = tester.getRect(find.text('Policy'));
    expect(panel.top, greaterThan(button.bottom));
    expect(panel.right, lessThanOrEqualTo(button.right));
    // And never off the side of the phone it opened on.
    expect(panel.left, greaterThan(0));
  });

  testWidgets('every entry is a 44px target, label and line and all', (
    tester,
  ) async {
    final picked = <String>[];
    await tester.pumpWidget(page(sample(picked: picked)));
    await openMenu(tester);

    for (final label in ['Policy', 'Hide balances', 'Broadcast']) {
      expect(menuRowHeight(tester, label), greaterThanOrEqualTo(44));
    }
    // The second line is the digest the page would have shown.
    expect(find.text('2 of 3 keys'), findsOneWidget);

    await tester.tap(find.text('Policy'));
    await tester.pumpAndSettle();
    // The menu is gone before the entry acts, so what it opens is not
    // fighting a surface on its way out.
    expect(find.text('Hide balances'), findsNothing);
    expect(picked, ['Policy']);
  });

  testWidgets('a screen reader hears the label and the line under it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final picked = <String>[];
    await tester.pumpWidget(page(sample(picked: picked)));
    await openMenu(tester);

    final entry = find.semantics.byLabel('Policy: 2 of 3 keys');
    expect(
      entry,
      isSemantics(
        label: 'Policy: 2 of 3 keys',
        isButton: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(entry);
    await tester.pumpAndSettle();
    expect(picked, ['Policy']);
    handle.dispose();
  });

  testWidgets('escape closes it and picks nothing', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(page(sample(picked: picked)));
    await openMenu(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Broadcast'), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('it drops into place, and a fade alone when asked to', (
    tester,
  ) async {
    await tester.pumpWidget(page(sample()));
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final flying = tester.getTopLeft(find.text('Policy')).dy;
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.text('Policy')).dy;
    expect(flying, lessThan(settled));
    expect(settled - flying, lessThanOrEqualTo(8));

    // A device asking for less motion keeps the fade and loses the
    // travel: nothing slides, and nothing jumps either.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: page(sample()),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final still = tester.getTopLeft(find.text('Policy')).dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Policy')).dy, still);
  });

  testWidgets('a small screen at a doubled text scale scrolls, not spills', (
    tester,
  ) async {
    usePixel2(tester);
    final items = [
      for (var i = 0; i < 8; i++)
        OverflowMenuItem(
          icon: LucideIcons.route,
          label: 'A wallet action with a long enough name $i',
          detail: 'and a second line under it, longer still',
          onSelected: () {},
        ),
    ];
    await tester.pumpWidget(page(items, scale: 2));
    await openMenu(tester);

    // No overflow, and the panel stays inside the phone: the entries
    // scroll instead of running off the bottom.
    expect(tester.takeException(), isNull);
    final first = tester.getRect(
      find.text('A wallet action with a long enough name 0'),
    );
    expect(first.right, lessThanOrEqualTo(411));
    expect(first.left, greaterThanOrEqualTo(0));
    await tester.drag(
      find.text('and a second line under it, longer still').first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
