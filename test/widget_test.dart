import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
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
  });

  testWidgets('a faked bootstrap resolves into the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakeBridge(), bootstrap: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('No wallets yet'), findsOneWidget);
    expect(find.text('Add a wallet'), findsOneWidget);
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
