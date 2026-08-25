import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';

import 'fakes.dart';

Widget app(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: const GerfautApp(),
  );
}

void main() {
  testWidgets('fiat is off by default', (tester) async {
    final meta = makeMeta(totalSats: 123456);
    final bridge = FakeBridge(wallets: [meta]);
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // One unit only, and no fiat line while the display is off.
    expect(
      find.textContaining('0.00123456', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(formatSats(123456)), findsNothing);
    expect(find.textContaining('€'), findsNothing);
  });

  testWidgets('a stored "1" turns the fiat display on', (tester) async {
    final meta = makeMeta(totalSats: 123456);
    final bridge = FakeBridge(
      wallets: [meta],
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'display.fiat': '1'},
      ),
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    expect(find.textContaining('€'), findsWidgets);
  });

  testWidgets('any other stored value keeps fiat off', (tester) async {
    final meta = makeMeta(totalSats: 123456);
    final bridge = FakeBridge(
      wallets: [meta],
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'display.fiat': 'true'},
      ),
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    expect(find.textContaining('€'), findsNothing);
  });
}
