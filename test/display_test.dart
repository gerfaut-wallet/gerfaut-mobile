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

  testWidgets('a failure out of sight stays a failure', (tester) async {
    var answering = true;
    final bridge = FakeBridge()
      ..onFetchPrice = (source, currency) {
        if (!answering) {
          throw const BridgeException('backend', 'the source is down');
        }
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
    answering = false;
    await tester.pump(const Duration(seconds: 61));
    expect(container.read(priceProvider).hasError, isTrue);

    // Behind the launcher, the old quote does not come back as fresh.
    container.read(appInFrontProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 10));
    expect(container.read(priceProvider).hasError, isTrue);
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

  group('fiat off mainnet', () {
    /// A wallet of 123 456 sats on [network] with one transaction each
    /// way and one coin, fiat on, the fake's price at 50 000 a coin.
    FakeBridge testCoins(Network network) {
      final meta = makeMeta(network: network, totalSats: 123456);
      return FakeBridge(
        wallets: [meta],
        settings: Settings(
          activeNetwork: network,
          backends: const {},
          appPrefs: const {'display.fiat': '1', 'onboarding.seen': '1'},
        ),
        snapshots: {
          'w1': makeSnapshot(
            meta: meta,
            totalSats: 123456,
            txs: [
              TxSummary(
                txid: 'a' * 64,
                netSats: 125456,
                feeSats: 141,
                status: TxStatus.confirmed(height: 100, timestamp: 1755000000),
                confirmations: 10,
              ),
              TxSummary(
                txid: 'b' * 64,
                netSats: -2000,
                feeSats: 141,
                status: TxStatus.pending(),
                confirmations: 0,
              ),
            ],
          ),
        },
        utxos: {
          'w1': const [
            UtxoInfo(
              txid: 'c1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
              vout: 1,
              address: 'tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl',
              valueSats: 123456,
              status: TxStatus.confirmed(height: 100),
              keychain: 'external',
              derivationIndex: 0,
            ),
          ],
        },
      );
    }

    test('zero takes the currency\'s own decimals', () {
      expect(formatFiat(0, 50000, FiatCurrency.eur), '€0.00');
      expect(formatFiat(0, 50000, FiatCurrency.usd), r'$0.00');
      expect(formatFiat(0, 7654321, FiatCurrency.jpy), '¥0');
    });

    for (final network in [Network.signet, Network.testnet4]) {
      testWidgets('a ${network.label} coin is worth zero in the currency', (
        tester,
      ) async {
        await tester.pumpWidget(app(testCoins(network)));
        await tester.pumpAndSettle();

        // The list: the card says zero, in euros, as a real value would.
        expect(find.text('€0.00'), findsOneWidget);
        expect(find.text('€61.73'), findsNothing);

        // The wallet: its balance and both rows.
        await tester.tap(find.text('Cold storage'));
        await tester.pumpAndSettle();
        expect(find.text('€0.00'), findsNWidgets(3));
        expect(find.textContaining('€'), findsNWidgets(3));

        // The coin.
        await tester.tap(find.text('UTXOs'));
        await tester.pumpAndSettle();
        expect(find.text('€0.00'), findsWidgets);
        expect(find.text('€61.73'), findsNothing);
      });
    }

    testWidgets('a mainnet coin keeps its value at the price', (tester) async {
      await tester.pumpWidget(app(testCoins(Network.mainnet)));
      await tester.pumpAndSettle();

      expect(find.text('€61.73'), findsOneWidget);
      expect(find.text('€0.00'), findsNothing);

      await tester.tap(find.text('Cold storage'));
      await tester.pumpAndSettle();
      expect(find.text('€61.73'), findsOneWidget);
      expect(find.text('€62.73'), findsOneWidget);
      expect(find.text('-€1.00'), findsOneWidget);
    });

    testWidgets('hidden amounts stay hidden off mainnet', (tester) async {
      final bridge = testCoins(Network.signet);
      bridge.appPrefs['mobile.masked'] = '1';
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      expect(find.textContaining('€'), findsNothing);
      expect(findMasked(), findsWidgets);
    });
  });

  testWidgets('the "ago" clock ticks on screen, and rests behind it', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(FakeBridge())],
    );
    addTearDown(container.dispose);
    var ticks = 0;
    container.listen(relativeClockProvider, (_, _) => ticks++);
    await tester.pump(const Duration(seconds: 61));
    expect(ticks, 2);

    container.read(appInFrontProvider.notifier).state = false;
    await tester.pump(const Duration(milliseconds: 1));
    final away = ticks;
    await tester.pump(const Duration(minutes: 10));
    expect(ticks, away);

    // Back on screen, the lines are drawn again at once.
    container.read(appInFrontProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, away + 1);
    container.dispose();
  });
}
