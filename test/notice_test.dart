import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A panel narrow enough that anything of length wraps.
Widget host(
  Widget notice, {
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final tokens = brightness == Brightness.dark
      ? GerfautTokens.dark
      : GerfautTokens.light;
  return MaterialApp(
    theme: themeFrom(tokens, brightness),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Center(child: SizedBox(width: 240, child: notice)),
        ),
      ),
    ),
  );
}

/// The panel's own decoration, not the frame it was dropped into.
BoxDecoration decorationOf(WidgetTester tester) {
  return tester
          .widget<Container>(
            find
                .descendant(
                  of: find.byType(GerfautNotice),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration!
      as BoxDecoration;
}

void main() {
  const short = 'One line.';
  const long =
      'This key carries no script type: check the one selected below, and '
      'compare the first address with your wallet.';

  testWidgets('the alert tone is red, with the triangle', (tester) async {
    final tokens = GerfautTokens.light;
    await tester.pumpWidget(
      host(const GerfautNotice(tone: NoticeTone.alert, message: short)),
    );

    expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    expect(find.byIcon(LucideIcons.info), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.triangleAlert)).color,
      tokens.alert,
    );
    expect(tester.widget<Text>(find.text(short)).style?.color, tokens.alert);

    final decoration = decorationOf(tester);
    expect(decoration.color, tokens.alertSurface);
    expect(decoration.border!.top.color, tokens.alert.withValues(alpha: 0.25));
    expect(decoration.border!.top.width, 1);
    expect(decoration.borderRadius, BorderRadius.circular(GerfautRadius.md));
  });

  testWidgets('the info tone is amber, with the info glyph', (tester) async {
    final tokens = GerfautTokens.light;
    await tester.pumpWidget(
      host(const GerfautNotice(tone: NoticeTone.info, message: short)),
    );

    expect(find.byIcon(LucideIcons.info), findsOneWidget);
    expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.info)).color,
      tokens.pending,
    );
    expect(tester.widget<Text>(find.text(short)).style?.color, tokens.pending);

    final decoration = decorationOf(tester);
    expect(decoration.color, tokens.pendingSurface);
    expect(
      decoration.border!.top.color,
      tokens.pending.withValues(alpha: 0.25),
    );
  });

  testWidgets('the dark theme keeps the colored text without the tint', (
    tester,
  ) async {
    final tokens = GerfautTokens.dark;
    await tester.pumpWidget(
      host(
        const GerfautNotice(tone: NoticeTone.info, message: short),
        brightness: Brightness.dark,
      ),
    );

    expect(decorationOf(tester).color, tokens.surface);
    expect(tester.widget<Text>(find.text(short)).style?.color, tokens.pending);
  });

  group('the icon sits on the first line', () {
    /// Where the first line of [style] puts its optical centre, counted
    /// from the top of the paragraph.
    double halfLine(TextStyle style, TextScaler scaler) =>
        scaler.scale(style.fontSize!) * style.height! / 2;

    testWidgets('of a message that wraps', (tester) async {
      final style = GerfautTokens.light.bodySmall;
      await tester.pumpWidget(
        host(const GerfautNotice(tone: NoticeTone.info, message: long)),
      );

      final text = tester.getRect(find.text(long));
      final icon = tester.getRect(find.byIcon(LucideIcons.info));
      // Several lines, so centring on the block would be visibly wrong.
      expect(text.height, greaterThan(style.fontSize! * style.height! * 2));
      expect(
        icon.center.dy,
        closeTo(text.top + halfLine(style, TextScaler.noScaling), 0.5),
      );
      // And well above the middle of the block.
      expect(icon.center.dy, lessThan(text.center.dy));
    });

    testWidgets('at a larger text scale, with nothing to correct', (
      tester,
    ) async {
      const scaler = TextScaler.linear(2);
      final style = GerfautTokens.light.bodySmall;
      await tester.pumpWidget(
        host(
          const GerfautNotice(tone: NoticeTone.alert, message: long),
          textScaler: scaler,
        ),
      );

      final text = tester.getRect(find.text(long));
      final icon = tester.getRect(find.byIcon(LucideIcons.triangleAlert));
      expect(icon.center.dy, closeTo(text.top + halfLine(style, scaler), 0.5));
    });

    testWidgets('and on a single line stays centred on it', (tester) async {
      final style = GerfautTokens.light.bodySmall;
      await tester.pumpWidget(
        host(const GerfautNotice(tone: NoticeTone.info, message: short)),
      );

      final text = tester.getRect(find.text(short));
      final icon = tester.getRect(find.byIcon(LucideIcons.info));
      expect(text.height, closeTo(style.fontSize! * style.height!, 0.5));
      expect(icon.center.dy, closeTo(text.center.dy, 0.5));
    });
  });

  group('a style with pieces missing', () {
    testWidgets('does not take the screen down with it', (tester) async {
      // A TextStyle that only names a colour is an ordinary thing to
      // hand a public widget, and most Material styles leave `height`
      // null. Neither is a caller's mistake.
      await tester.pumpWidget(
        host(
          const Row(
            children: [
              FirstLine(
                style: TextStyle(color: Color(0xFF000000)),
                child: Icon(LucideIcons.info, size: 16),
              ),
              Expanded(child: Text('Bare style.')),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
      // The fallback measures a body-small line, so the icon still has
      // a box to be centred in.
      expect(tester.getSize(find.byType(FirstLine)).height, 14 * 1.5);
    });

    testWidgets('still scales the fallback with the text', (tester) async {
      await tester.pumpWidget(
        host(
          const FirstLine(
            style: TextStyle(color: Color(0xFF000000)),
            child: Icon(LucideIcons.info, size: 16),
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );

      expect(tester.getSize(find.byType(FirstLine)).height, 28 * 1.5);
    });
  });

  testWidgets('a live region is opt-in', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const GerfautNotice(tone: NoticeTone.info, message: short)),
    );
    // A note that was on the page all along announces nothing: a region
    // that speaks on every rebuild is noise.
    expect(
      tester
          .getSemantics(find.byType(GerfautNotice))
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );

    await tester.pumpWidget(
      host(
        const GerfautNotice(
          tone: NoticeTone.info,
          message: short,
          liveRegion: true,
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(GerfautNotice))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets("another system's words stay mono and selectable", (
    tester,
  ) async {
    const refusal = 'min relay fee not met, 1 < 141';
    await tester.pumpWidget(
      host(
        const GerfautNotice(
          tone: NoticeTone.info,
          message: 'The network refused this transaction.',
          detail: refusal,
        ),
      ),
    );

    // It is a string to compare and to quote, not prose of ours.
    final detail = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(detail.data, refusal);
    expect(detail.style?.fontFamily, GerfautTokens.light.data.fontFamily);
  });

  testWidgets('a trailing action rides along', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      host(
        GerfautNotice(
          tone: NoticeTone.info,
          message: short,
          action: TextButton(
            onPressed: () => tapped++,
            child: const Text('Fix'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fix'));
    expect(tapped, 1);
    // Beside the words, on the same row.
    final text = tester.getRect(find.text(short));
    final button = tester.getRect(find.text('Fix'));
    expect(button.left, greaterThan(text.right));
    expect(button.center.dy, closeTo(text.center.dy, 12));
  });

  testWidgets('actions below give the sentence the whole width', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        GerfautNotice(
          tone: NoticeTone.info,
          message: long,
          actionsBelow: true,
          action: Row(
            key: const Key('actions'),
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () {}, child: const Text('Keep')),
              TextButton(onPressed: () {}, child: const Text('Go')),
            ],
          ),
        ),
      ),
    );

    final panel = tester.getRect(find.byType(GerfautNotice));
    final text = tester.getRect(find.text(long));
    final keep = tester.getRect(find.text('Keep'));
    final go = tester.getRect(find.text('Go'));
    // The words run to the panel's right padding, not to a button.
    expect(text.right, closeTo(panel.right - 12, 1));
    // The buttons sit under the words, on one row, flush right.
    expect(keep.top, greaterThan(text.bottom));
    expect(go.top, greaterThan(text.bottom));
    expect(keep.center.dy, closeTo(go.center.dy, 1));
    expect(keep.left, lessThan(go.left));
    final row = tester.getRect(find.byKey(const Key('actions')));
    expect(row.right, closeTo(panel.right - 12, 1));
  });
}
