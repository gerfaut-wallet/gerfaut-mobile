import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/readable_width.dart';

import 'fakes.dart';

/// Sets the window to [width] by [height] logical pixels for one test.
void window(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('ReadableWidth', () {
    Widget frame() => const Directionality(
      textDirection: TextDirection.ltr,
      child: ReadableWidth(child: SizedBox.expand(key: Key('content'))),
    );

    testWidgets('leaves a phone-wide window as it is', (tester) async {
      window(tester, 390, 844);
      await tester.pumpWidget(frame());
      expect(
        tester.getRect(find.byKey(const Key('content'))),
        const Rect.fromLTWH(0, 0, 390, 844),
      );
    });

    testWidgets('leaves a window exactly as wide as the limit as it is', (
      tester,
    ) async {
      window(tester, GerfautLayout.readableWidth, 800);
      await tester.pumpWidget(frame());
      expect(
        tester.getSize(find.byKey(const Key('content'))).width,
        GerfautLayout.readableWidth,
      );
    });

    testWidgets('centres the content at the limit in a wider window', (
      tester,
    ) async {
      window(tester, 1000, 800);
      await tester.pumpWidget(frame());
      expect(
        tester.getRect(find.byKey(const Key('content'))),
        Rect.fromLTWH((1000 - GerfautLayout.readableWidth) / 2, 0, 640, 800),
      );
    });
  });

  testWidgets('keeps the state of the screen when the window crosses the '
      'limit', (tester) async {
    // A foldable opened, or a phone turned sideways: same screen, new
    // width. Typed text stands for any state a screen holds.
    window(tester, 390, 844);
    final typed = TextEditingController();
    addTearDown(typed.dispose);
    Widget frame() => MaterialApp(
      home: Scaffold(
        body: ReadableWidth(child: _Field(controller: typed)),
      ),
    );
    await tester.pumpWidget(frame());
    await tester.enterText(find.byType(TextField), 'kept');
    final before = tester.state(find.byType(_Field));

    window(tester, 1000, 800);
    await tester.pumpWidget(frame());
    expect(tester.state(find.byType(_Field)), same(before));

    window(tester, 390, 844);
    await tester.pumpWidget(frame());
    expect(tester.state(find.byType(_Field)), same(before));
    expect(find.text('kept'), findsOneWidget);
  });

  group('the home screen in a wide window', () {
    final meta = makeMeta();
    Widget app() => ProviderScope(
      retry: noRetry,
      overrides: [
        bridgeProvider.overrideWithValue(
          FakeBridge(
            wallets: [meta],
            snapshots: {'w1': makeSnapshot(meta: meta)},
            settings: const Settings(
              preferences: kPreferences,
              activeNetwork: Network.mainnet,
              backends: {},
              appPrefs: {'onboarding.seen': '1'},
            ),
          ),
        ),
        disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      ],
      child: const GerfautApp(),
    );

    testWidgets('keeps the wallet card readable and the app bar whole', (
      tester,
    ) async {
      window(tester, 1000, 800);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byKey(const ValueKey('w1')));
      expect(card.width, lessThanOrEqualTo(GerfautLayout.readableWidth));
      expect(card.center.dx, closeTo(500, 0.5));
      expect(tester.getSize(find.byType(AppBar)).width, 1000);
    });

    testWidgets('lays a phone out as before', (tester) async {
      window(tester, 390, 844);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byKey(const ValueKey('w1')));
      // Only the screen's own margins around it, as on every phone.
      expect(card.width, greaterThan(390 - 2 * GerfautSpacing.lg));
    });
  });
}

/// A field that holds state of its own, to see whether it survives.
class _Field extends StatefulWidget {
  const _Field({required this.controller});

  final TextEditingController controller;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  @override
  Widget build(BuildContext context) =>
      TextField(controller: widget.controller);
}
