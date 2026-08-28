import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/widgets/brand.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

Widget app(FakeBridge bridge, {Future<void> Function()? bootstrap}) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: GerfautApp(bootstrap: bootstrap),
  );
}

void main() {
  testWidgets('empty state shows the guidance and its single action', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakeBridge()));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
    // The first screen anyone sees carries the whole logo, wordmark
    // included: it is the one place the app introduces itself.
    expect(find.byType(GerfautLockup), findsOneWidget);
  });

  testWidgets('the header wears the falcon, not the word', (tester) async {
    await tester.pumpWidget(app(FakeBridge()));
    await tester.pumpAndSettle();

    // Whoever opened the app knows its name; the mark says it in the
    // room of a glyph and leaves the bar to the actions.
    expect(find.byType(GerfautMark), findsWidgets);
    expect(find.text('Gerfaut'), findsNothing);
    expect(find.bySemanticsLabel('Gerfaut'), findsWidgets);
  });

  testWidgets('a faked bootstrap resolves into the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakeBridge(), bootstrap: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
  });

  testWidgets('nothing asks the core before the vault is open', (
    tester,
  ) async {
    final bridge = _ClosedUntilOpen();
    await tester.pumpWidget(
      app(
        bridge,
        bootstrap: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          bridge.open = true;
        },
      ),
    );
    await tester.pump();
    expect(find.text('Opening the vault\u2026'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('No wallets yet'), findsOneWidget);
  });

  testWidgets('every wallet card carries the same generic icon', (
    tester,
  ) async {
    final bridge = FakeBridge(
      wallets: [
        makeMeta(id: 'w1', name: 'Cold storage'),
        makeMeta(
          id: 'w2',
          name: 'Donation address',
          kind: const SingleAddressKind(address: 'bc1qwatched'),
        ),
      ],
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // The wallet kind is stated in words where it matters, never as a
    // different icon on the card.
    expect(find.byIcon(LucideIcons.wallet), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.mapPin), findsNothing);
  });

  testWidgets('the wallet list masks its balances from its own eye', (
    tester,
  ) async {
    final bridge = FakeBridge(wallets: [makeMeta(totalSats: 123456)]);
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Hide balances'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.00123456', findRichText: true), findsNothing);
    expect(find.textContaining('•••••', findRichText: true), findsWidgets);
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
    expect(bridge.appPrefs['mobile.masked'], '1');

    await tester.tap(find.byTooltip('Show balances'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
    expect(bridge.appPrefs['mobile.masked'], '0');
  });

  testWidgets('a failed bootstrap shows the startup error screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeBridge(),
        bootstrap: () async => throw StateError('vault init failed'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerfaut could not start'), findsOneWidget);
    expect(find.text('No wallets yet'), findsNothing);
  });
}

/// A bridge that refuses every call until the vault is open, the way the
/// real one does before the Rust bridge has been initialized.
class _ClosedUntilOpen extends FakeBridge {
  bool open = false;

  @override
  Future<Settings> getSettings() => open
      ? super.getSettings()
      : Future.error(StateError('the core was called too early'));
}
