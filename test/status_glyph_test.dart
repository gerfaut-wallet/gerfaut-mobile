import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _mined = TxStatus.confirmed(height: 100, timestamp: 1755000000);

Future<Icon> _glyph(
  WidgetTester tester,
  StatusGlyph glyph, {
  Brightness brightness = Brightness.light,
}) async {
  final tokens = brightness == Brightness.dark
      ? GerfautTokens.dark
      : GerfautTokens.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: themeFrom(tokens, brightness),
      home: Scaffold(body: Center(child: glyph)),
    ),
  );
  return tester.widget<Icon>(find.byType(Icon));
}

void main() {
  for (final brightness in Brightness.values) {
    final tokens = brightness == Brightness.dark
        ? GerfautTokens.dark
        : GerfautTokens.light;

    group('colour is kept for what still moves, ${brightness.name}', () {
      testWidgets('a clock in amber while it waits', (tester) async {
        final icon = await _glyph(
          tester,
          brightness: brightness,
          const StatusGlyph(status: TxStatus.pending(), confirmations: 0),
        );
        expect(icon.icon, LucideIcons.clock);
        expect(icon.color, tokens.pending);
        expect(icon.semanticLabel, 'Pending');
      });

      testWidgets('a green check while it settles', (tester) async {
        for (var count = 1; count < settledConfirmations; count++) {
          final icon = await _glyph(
            tester,
            brightness: brightness,
            StatusGlyph(status: _mined, confirmations: count),
          );
          expect(icon.icon, LucideIcons.check, reason: '$count');
          expect(icon.color, tokens.confirmed, reason: '$count');
          expect(icon.semanticLabel, '$count conf');
        }
      });

      testWidgets('a muted check once settled', (tester) async {
        for (final count in [settledConfirmations, 120]) {
          final icon = await _glyph(
            tester,
            brightness: brightness,
            StatusGlyph(status: _mined, confirmations: count),
          );
          expect(icon.icon, LucideIcons.check, reason: '$count');
          expect(icon.color, tokens.textMuted, reason: '$count');
          expect(icon.semanticLabel, 'Confirmed');
        }
      });

      testWidgets('a muted check when the count is not known', (tester) async {
        final icon = await _glyph(
          tester,
          brightness: brightness,
          const StatusGlyph(status: _mined),
        );
        expect(icon.icon, LucideIcons.check);
        expect(icon.color, tokens.textMuted);
        expect(icon.semanticLabel, 'Confirmed');
      });
    });
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
}
