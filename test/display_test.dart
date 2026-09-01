import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/disguise.dart';

import 'fakes.dart';

Widget app(FakeBridge bridge) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
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

  testWidgets(
    'a stored currency and source that disagree land on one that answers',
    (tester) async {
      final bridge = FakeBridge(
        wallets: [makeMeta(totalSats: 123456)],
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {
            'display.fiat': '1',
            'display.fiat_currency': 'ngn',
            'display.fiat_source': 'kraken',
          },
        ),
      );
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GerfautApp)),
      );
      expect(container.read(fiatCurrencyProvider), FiatCurrency.ngn);
      // Kraken does not quote the naira: CoinGecko answers rather than
      // no one at all.
      expect(container.read(fiatSourceProvider), PriceSource.coingecko);
    },
  );

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
