import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/confirmation_pie.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'contrast.dart';

const _mined = TxStatus.confirmed(height: 100, timestamp: 1755000000);

GerfautTokens _tokensOf(Brightness brightness) =>
    brightness == Brightness.dark ? GerfautTokens.dark : GerfautTokens.light;

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: themeFrom(_tokensOf(brightness), brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    final tokens = _tokensOf(brightness);

    group('the list glyph, ${brightness.name}', () {
      testWidgets('a clock in amber while it waits, and no pie', (
        tester,
      ) async {
        await _show(
          tester,
          brightness: brightness,
          const StatusGlyph(status: TxStatus.pending(), confirmations: 0),
        );
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, LucideIcons.clock);
        expect(icon.color, tokens.pending);
        expect(icon.semanticLabel, 'Pending');
        expect(find.byType(ConfirmationPie), findsNothing);
      });

      testWidgets('a green pie, one part per confirmation, while it settles', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        for (var count = 1; count < settledConfirmations; count++) {
          await _show(
            tester,
            brightness: brightness,
            StatusGlyph(status: _mined, confirmations: count),
          );
          expect(find.byType(Icon), findsNothing, reason: '$count');
          final pie = tester.widget<ConfirmationPie>(
            find.byType(ConfirmationPie),
          );
          expect(pie.filled, count);
          expect(pie.size, 14);
          expect(pie.color, tokens.confirmed);
          expect(
            find.bySemanticsLabel('$count of 6 confirmations'),
            findsOneWidget,
          );
        }
        semantics.dispose();
      });

      testWidgets('a muted check once settled', (tester) async {
        for (final count in [settledConfirmations, 120]) {
          await _show(
            tester,
            brightness: brightness,
            StatusGlyph(status: _mined, confirmations: count),
          );
          final icon = tester.widget<Icon>(find.byType(Icon));
          expect(icon.icon, LucideIcons.check, reason: '$count');
          expect(icon.color, tokens.textMuted, reason: '$count');
          expect(icon.semanticLabel, 'Confirmed');
          expect(find.byType(ConfirmationPie), findsNothing);
        }
      });
    });

    group('the detail pill, ${brightness.name}', () {
      testWidgets('pending: the clock and its word', (tester) async {
        final semantics = tester.ensureSemantics();
        await _show(
          tester,
          brightness: brightness,
          StatusPill(status: const TxStatus.pending(), confirmations: 0),
        );
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, LucideIcons.clock);
        expect(icon.color, tokens.pending);
        expect(find.byType(ConfirmationPie), findsNothing);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.bySemanticsLabel('Pending'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('settling: the pie, "N conf" written, the count heard', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _show(
          tester,
          brightness: brightness,
          StatusPill(status: _mined, confirmations: 3),
        );
        expect(find.byType(Icon), findsNothing);
        final pie = tester.widget<ConfirmationPie>(
          find.byType(ConfirmationPie),
        );
        expect(pie.filled, 3);
        expect(pie.size, 12);
        expect(pie.color, tokens.confirmed);
        expect(find.text('3 conf'), findsOneWidget);
        // Heard once, in full: the written short form is not read too.
        expect(find.bySemanticsLabel('3 of 6 confirmations'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('conf\$')), findsNothing);
        semantics.dispose();
      });

      testWidgets('settled: the check and its word', (tester) async {
        final semantics = tester.ensureSemantics();
        await _show(
          tester,
          brightness: brightness,
          StatusPill(status: _mined, confirmations: settledConfirmations),
        );
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, LucideIcons.check);
        expect(icon.color, tokens.confirmed);
        expect(find.byType(ConfirmationPie), findsNothing);
        expect(find.text('Confirmed'), findsOneWidget);
        expect(find.bySemanticsLabel('Confirmed'), findsOneWidget);
        semantics.dispose();
      });
    });

    // The pie is drawn in the confirmed tone at 12 to 14 pixels, on every
    // ground it sits on: a non-text graphic, held to 3:1.
    test(
      'the confirmed tone stands out on its grounds, ${brightness.name}',
      () {
        for (final (name, ground) in [
          ('surface', tokens.surface),
          ('background', tokens.background),
          ('surfaceSunken', tokens.surfaceSunken),
          ('confirmedSurface', tokens.confirmedSurface),
        ]) {
          expect(
            contrastRatio(tokens.confirmed, ground),
            greaterThanOrEqualTo(3),
            reason: name,
          );
        }
      },
    );
  }

  test('the glyph and the label settle at the same depth', () {
    expect(
      labelOfStatus(_mined, confirmations: settledConfirmations - 1),
      '${settledConfirmations - 1} conf',
    );
    expect(
      labelOfStatus(_mined, confirmations: settledConfirmations),
      'Confirmed',
    );
  });

  test('the spoken state counts against the settled depth', () {
    expect(spokenStatus(const TxStatus.pending(), confirmations: 0), 'Pending');
    expect(spokenStatus(_mined, confirmations: 1), '1 of 6 confirmations');
    expect(
      spokenStatus(_mined, confirmations: settledConfirmations - 1),
      '${settledConfirmations - 1} of $settledConfirmations confirmations',
    );
    expect(
      spokenStatus(_mined, confirmations: settledConfirmations),
      'Confirmed',
    );
  });
}
