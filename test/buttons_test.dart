import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _page(
  Widget body, {
  Brightness brightness = Brightness.light,
  bool stillMotion = false,
}) {
  final tokens = brightness == Brightness.dark
      ? GerfautTokens.dark
      : GerfautTokens.light;
  return MaterialApp(
    theme: themeFrom(tokens, brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: stillMotion),
        child: Scaffold(body: Center(child: body)),
      ),
    ),
  );
}

/// The fill a button is painted with right now.
Color _fill(WidgetTester tester, String label) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color!;
}

ShapeBorder _shape(WidgetTester tester, String label) {
  return tester
      .widget<Material>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text(label),
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
              matching: find.byType(Material),
            )
            .first,
      )
      .shape!;
}

/// WCAG 2 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final (hi, lo) = (luminance(a), luminance(b));
  return (math.max(hi, lo) + 0.05) / (math.min(hi, lo) + 0.05);
}

void main() {
  group('every labelled button has a fill', () {
    for (final brightness in Brightness.values) {
      final tokens = brightness == Brightness.dark
          ? GerfautTokens.dark
          : GerfautTokens.light;

      testWidgets('in the ${brightness.name} theme', (tester) async {
        await tester.pumpWidget(
          _page(
            brightness: brightness,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(label: 'Primary', onPressed: () {}),
                SecondaryButton(label: 'Secondary', onPressed: () {}),
                DangerButton(label: 'Danger', onPressed: () {}),
              ],
            ),
          ),
        );
        expect(_fill(tester, 'Primary'), tokens.primary);
        expect(_fill(tester, 'Secondary'), tokens.surfaceSunken);
        expect(_fill(tester, 'Danger'), tokens.alert);
      });

      testWidgets('darkens under the finger, ${brightness.name}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _page(
            brightness: brightness,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(label: 'Primary', onPressed: () {}),
                SecondaryButton(label: 'Secondary', onPressed: () {}),
                DangerButton(label: 'Danger', onPressed: () {}),
              ],
            ),
          ),
        );
        for (final (label, pressed) in [
          ('Primary', tokens.primaryPressed),
          (
            'Secondary',
            Color.alphaBlend(
              tokens.border.withValues(alpha: 0.6),
              tokens.surfaceSunken,
            ),
          ),
          ('Danger', tokens.alertPressed),
        ]) {
          final gesture = await tester.startGesture(
            tester.getCenter(find.text(label)),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(_fill(tester, label), pressed, reason: label);
          await gesture.up();
          await tester.pumpAndSettle();
        }
      });

      test('every label reads at AA, ${brightness.name}', () {
        final pairs = {
          'primary': (tokens.onPrimary, tokens.primary),
          'primary pressed': (tokens.onPrimary, tokens.primaryPressed),
          'secondary': (tokens.text, tokens.surfaceSunken),
          'secondary pressed': (
            tokens.text,
            Color.alphaBlend(
              tokens.border.withValues(alpha: 0.6),
              tokens.surfaceSunken,
            ),
          ),
          'secondary on a tint': (tokens.text, tokens.surface),
          'secondary on a tint, pressed': (tokens.text, tokens.background),
          'danger': (tokens.onAlert, tokens.alert),
          'danger pressed': (tokens.onAlert, tokens.alertPressed),
          'disclosure on a card': (tokens.textMuted, tokens.surface),
          'disclosure pressed': (tokens.textMuted, tokens.surfaceSunken),
        };
        for (final MapEntry(key: name, value: (ink, fill)) in pairs.entries) {
          expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5), reason: name);
        }
      });
    }
  });

  testWidgets('the disclosure has no fill and says whether it is open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var open = false;
    await tester.pumpWidget(
      _page(
        StatefulBuilder(
          builder: (context, setState) => DisclosureButton(
            label: 'Advanced',
            open: open,
            onPressed: () => setState(() => open = !open),
          ),
        ),
      ),
    );
    expect(_fill(tester, 'Advanced').a, 0);
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(DisclosureButton)),
      matchesSemantics(
        label: 'Advanced',
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(DisclosureButton)),
      matchesSemantics(
        label: 'Advanced',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  group('busy', () {
    testWidgets('keeps its colour, turns a spinner and ignores presses', (
      tester,
    ) async {
      var pressed = 0;
      await tester.pumpWidget(
        _page(
          PrimaryButton(
            label: 'Saving…',
            icon: LucideIcons.save,
            busy: true,
            onPressed: () => pressed++,
          ),
        ),
      );
      expect(_fill(tester, 'Saving…'), GerfautTokens.light.primary);
      expect(find.byType(Opacity), findsNothing);
      // The spinner takes the icon's place: one slot, the label stays.
      expect(find.byIcon(LucideIcons.loaderCircle), findsOneWidget);
      expect(find.byIcon(LucideIcons.save), findsNothing);
      final turns = tester
          .widget<RotationTransition>(
            find.ancestor(
              of: find.byIcon(LucideIcons.loaderCircle),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      final before = turns.value;
      await tester.pump(const Duration(milliseconds: 250));
      expect(turns.value, isNot(before));

      await tester.tap(find.text('Saving…'));
      await tester.pump();
      expect(pressed, 0);
    });

    testWidgets('busy wins over a null callback', (tester) async {
      await tester.pumpWidget(
        _page(
          const SecondaryButton(
            label: 'Rescanning…',
            busy: true,
            onPressed: null,
          ),
        ),
      );
      expect(_fill(tester, 'Rescanning…'), GerfautTokens.light.surfaceSunken);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('stands still when the phone asks for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _page(
          stillMotion: true,
          DangerButton(label: 'Removing…', busy: true, onPressed: () {}),
        ),
      );
      // Nothing left to animate, so the frame settles.
      await tester.pumpAndSettle();
      final turns = tester
          .widget<RotationTransition>(
            find.ancestor(
              of: find.byIcon(LucideIcons.loaderCircle),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      expect(turns.value, 0);
    });

    testWidgets('back to the icon once done', (tester) async {
      var busy = true;
      late StateSetter set;
      await tester.pumpWidget(
        _page(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return PrimaryButton(
                label: 'Check',
                icon: LucideIcons.refreshCw,
                busy: busy,
                onPressed: () {},
              );
            },
          ),
        ),
      );
      set(() => busy = false);
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.loaderCircle), findsNothing);
      expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
    });
  });

  testWidgets('off fades the whole button and keeps its fill', (tester) async {
    await tester.pumpWidget(
      _page(const PrimaryButton(label: 'Add wallet', onPressed: null)),
    );
    expect(_fill(tester, 'Add wallet'), GerfautTokens.light.primary);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.text('Add wallet'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0.5,
    );
  });

  group('a secondary on a notice', () {
    Widget notice(Brightness brightness) => _page(
      brightness: brightness,
      Padding(
        padding: const EdgeInsets.all(16),
        child: GerfautNotice(
          tone: NoticeTone.info,
          message: 'The new order could not be saved.',
          actionsBelow: true,
          action: SecondaryButton(label: 'Dismiss', onPressed: () {}),
        ),
      ),
    );

    testWidgets('takes white and a hairline in the light theme', (
      tester,
    ) async {
      await tester.pumpWidget(notice(Brightness.light));
      final tokens = GerfautTokens.light;
      expect(_fill(tester, 'Dismiss'), tokens.surface);
      final shape = _shape(tester, 'Dismiss') as RoundedRectangleBorder;
      expect(shape.side.color, tokens.border);
    });

    testWidgets('keeps its fill in the dark theme', (tester) async {
      await tester.pumpWidget(notice(Brightness.dark));
      final tokens = GerfautTokens.dark;
      expect(_fill(tester, 'Dismiss'), tokens.surfaceSunken);
      final shape = _shape(tester, 'Dismiss') as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);
    });
  });
}
