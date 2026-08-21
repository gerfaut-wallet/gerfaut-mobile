import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/state.dart';

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
