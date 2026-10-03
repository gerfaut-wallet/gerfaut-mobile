import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/bridge.dart';
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

  testWidgets('a hidden amount is said as one, not dot by dot', (tester) async {
    final handle = tester.ensureSemantics();
    final bridge = FakeBridge(
      wallets: [makeMeta(totalSats: 123456)],
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'mobile.masked': '1', 'onboarding.seen': '1'},
      ),
    );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();

    // On screen the dots; read out, the words.
    final balance = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText(includeSemanticsLabels: false))
        .where((text) => text.contains(maskedValue));
    expect(balance, isNotEmpty);
    expect(find.bySemanticsLabel(RegExp(maskedSpoken)), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('•')), findsNothing);
    handle.dispose();
  });

  test('the mask is said in words, anything else as it is', () {
    expect(
      spokenIfMasked('It pays a fee of $maskedValue'),
      'It pays a fee of Hidden amount',
    );
    expect(spokenIfMasked('0.001 BTC'), isNull);
  });

  testWidgets('out of sight the price is not asked, and is asked on return', (
    tester,
  ) async {
    var asked = 0;
    final bridge = FakeBridge()
      ..onFetchPrice = (source, currency) {
        asked++;
        return PriceQuote(
          rate: 50000,
          currency: currency,
          source: source,
          at: 1755000000,
        );
      };
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    container.read(fiatEnabledProvider.notifier).hydrate('1');
    container.listen(priceProvider, (_, _) {});
    await tester.pump();
    expect(asked, 1);

    await tester.pump(const Duration(seconds: 61));
    expect(asked, 2);

    // Behind the launcher: the quote in hand stays, nothing is asked.
    container.read(appInFrontProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 10));
    expect(asked, 2);
    expect(container.read(priceProvider).valueOrNull?.rate, 50000);

    container.read(appInFrontProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 1));
    expect(asked, 3);
    container.dispose();
  });

  testWidgets('a source that stops answering takes the fiat away with it', (
    tester,
  ) async {
    var answering = true;
    final bridge =
        FakeBridge(
            wallets: [makeMeta(totalSats: 123456)],
            settings: const Settings(
              activeNetwork: Network.mainnet,
              backends: {},
              appPrefs: {'display.fiat': '1', 'onboarding.seen': '1'},
            ),
          )
          ..onFetchPrice = (source, currency) {
            if (!answering) {
              throw const BridgeException('sync', 'price: http 503');
            }
            return PriceQuote(
              rate: 50000,
              currency: currency,
              source: source,
              at: 1755000000,
            );
          };
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();
    expect(find.textContaining('€'), findsWidgets);

    answering = false;
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.textContaining('€'), findsNothing);
  });

  testWidgets('a quote in another currency is not shown as the new one', (
    tester,
  ) async {
    final bridge =
        FakeBridge(
            wallets: [makeMeta(totalSats: 123456)],
            settings: const Settings(
              activeNetwork: Network.mainnet,
              backends: {},
              appPrefs: {'display.fiat': '1', 'onboarding.seen': '1'},
            ),
          )
          ..onFetchPrice = (source, currency) => PriceQuote(
            rate: 50000,
            currency: currency,
            source: source,
            at: 1755000000,
          );
    await tester.pumpWidget(app(bridge));
    await tester.pumpAndSettle();
    expect(find.textContaining('€'), findsWidgets);

    // The euro quote is in hand when dollars are chosen: until the dollar
    // quote lands, no figure claims to be in dollars.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GerfautApp)),
    );
    container.read(fiatCurrencyProvider.notifier).set(FiatCurrency.usd);
    await tester.pump();
    expect(find.textContaining('€'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining(r'$'), findsWidgets);
  });
}
