import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/add_wallet.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

Widget screen(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const AddWalletScreen(),
    ),
  );
}

void main() {
  testWidgets('pasting material reaches the confirmation step', (
    tester,
  ) async {
    final bridge = FakeBridge(onParse: (_) => makeParsedInput());
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'wpkh([9a6a2580/84h/1h/0h]tpub.../0/*)',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Confirmation step: recognized card, name field, network candidates.
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('Signet'), findsOneWidget);
    expect(find.text('Testnet 4'), findsOneWidget);
    expect(find.text('Add wallet'), findsOneWidget);
  });

  testWidgets('private material rejection shows the core message', (
    tester,
  ) async {
    const message = 'input contains private key material and was rejected';
    final bridge = FakeBridge(
      onParse: (_) => throw const BridgeException('private_material', message),
    );
    await tester.pumpWidget(screen(bridge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xprv9s21ZrQH...');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    // Still on the input step.
    expect(find.text('NAME'), findsNothing);
  });
}
