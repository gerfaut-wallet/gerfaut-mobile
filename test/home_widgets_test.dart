import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';

import 'fakes.dart';

const int _syncedAt = 1755000000;

/// Two hours after the most recent sync of the fixtures.
final DateTime _now = DateTime.fromMillisecondsSinceEpoch(
  (_syncedAt + 7200) * 1000,
);

SyncStamp _stamp(int at, {int tipHeight = 912345}) =>
    SyncStamp(at: at, tipHeight: tipHeight, backend: 'mempool.space');

const PriceQuote _quote = PriceQuote(
  rate: 50000,
  currency: FiatCurrency.eur,
  source: PriceSource.coingecko,
  at: _syncedAt,
);

/// A vault opened before, on mainnet, with two synced wallets.
FakeBridge _bridge({List<WalletMeta>? wallets}) {
  return FakeBridge(
    wallets:
        wallets ??
        [
          makeMeta(
            id: 'a',
            name: 'Cold storage',
            totalSats: 100000000,
            lastSync: _stamp(_syncedAt - 60),
          ),
          makeMeta(
            id: 'b',
            name: 'Spending',
            totalSats: 50000,
            lastSync: _stamp(_syncedAt),
          ),
        ],
    settings: const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
}

/// A container with the feed running against fakes, its providers
/// settled, so a test reads the board rather than a race.
Future<({ProviderContainer container, WidgetFeed feed})> _running(
  FakeBridge bridge,
  FakeWidgetBoard board,
) async {
  final container = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      widgetBoardProvider.overrideWithValue(board),
    ],
  );
  addTearDown(container.dispose);
  final feed = container.read(widgetFeedProvider);
  await container.read(walletsProvider.future);
  await container.read(widgetPriceProvider.future);
  await container.read(widgetFeesProvider.future);
  await feed.publish();
  return (container: container, feed: feed);
}

void main() {
  group('the price widget', () {
    test('states one bitcoin in the currency and the clock time', () {
      final payload = PricePayload.of(_quote);
      expect(payload.figure, formatFiat(satsPerBtc, 50000, FiatCurrency.eur));
      expect(payload.asOf, 'as of ${formatClock(_syncedAt)}');
      // The core carries no daily change yet: the line stays hidden.
      expect(payload.toData()[WidgetKeys.priceChange], isNull);
      expect(payload.toData().keys, PricePayload.keys);
    });

    test('the clock is the reader\'s, on 24 hours', () {
      final local = DateTime.fromMillisecondsSinceEpoch(_syncedAt * 1000)
          .toLocal();
      final expected =
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
      expect(formatClock(_syncedAt), expected);
      expect(formatClock(_syncedAt), matches(RegExp(r'^\d\d:\d\d$')));
    });

    test('the source and currency follow the preferences, with the '
        'same fallback the screens apply', () {
      expect(priceChoice(const {}), (
        currency: FiatCurrency.eur,
        source: PriceSource.coingecko,
      ));
      expect(
        priceChoice(const {
          'display.fiat_currency': 'usd',
          'display.fiat_source': 'kraken',
        }),
        (currency: FiatCurrency.usd, source: PriceSource.kraken),
      );
      // Kraken does not quote the rupee: CoinGecko answers instead.
      expect(
        priceChoice(const {
          'display.fiat_currency': 'inr',
          'display.fiat_source': 'kraken',
        }),
        (currency: FiatCurrency.inr, source: PriceSource.coingecko),
      );
    });
  });

  group('the balance widget', () {
    final wallets = [
      makeMeta(id: 'a', name: 'Cold storage', totalSats: 100000000),
      makeMeta(
        id: 'b',
        name: 'Spending',
        totalSats: 50000,
        lastSync: _stamp(_syncedAt),
      ),
    ];

    test('totals the wallets in the display unit', () {
      final btc = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: false,
        now: _now,
      );
      expect(btc.total, '1.00050000 BTC');
      expect(btc.rows, [
        (name: 'Cold storage', figure: '1.00000000 BTC'),
        (name: 'Spending', figure: '0.00050000 BTC'),
      ]);

      final sats = BalancePayload.of(
        wallets,
        unit: AmountUnit.sats,
        masked: false,
        now: _now,
      );
      expect(sats.total, formatSats(100050000));
      expect(sats.rows.first.figure, formatSats(100000000));
    });

    test('masked, the names stay and every figure goes', () {
      final payload = BalancePayload.of(
        wallets,
        unit: AmountUnit.btc,
        masked: true,
        now: _now,
      );
      expect(payload.total, maskedValue);
      expect(payload.rows.map((row) => row.name), ['Cold storage', 'Spending']);
      expect(payload.rows.every((row) => row.figure == maskedValue), isTrue);
    });

    test('lists four wallets at most; the total counts them all', () {
      final many = [
        for (var i = 0; i < 6; i++)
          makeMeta(id: 'w$i', name: 'Wallet $i', totalSats: 1000),
      ];
      final payload = BalancePayload.of(
        many,
        unit: AmountUnit.sats,
        masked: false,
      );
      expect(payload.rows, hasLength(BalancePayload.maxRows));
      expect(payload.rows.last.name, 'Wallet 3');
      expect(payload.total, formatSats(6000));
      // Every row key is written, the unused ones as absent.
      final data = payload.toData();
      expect(data.keys, BalancePayload.keys);
      expect(data[WidgetKeys.balanceRowName(4)], 'Wallet 3');
      final two = BalancePayload.of(
        wallets,
        unit: AmountUnit.sats,
        masked: false,
      ).toData();
      expect(two[WidgetKeys.balanceRowName(3)], isNull);
      expect(two[WidgetKeys.balanceRowFigure(4)], isNull);
    });

    test('says how old the figures are, from the most recent sync', () {
      expect(syncedLine(wallets, now: _now), 'Synced 2 h ago');
      expect(
        syncedLine([makeMeta(id: 'a', name: 'New')], now: _now),
        'Not synced yet',
      );
      expect(syncedLine(const [], now: _now), 'No wallets yet');
    });
  });

  group('the network widget', () {
    const fees = FeeEstimates(
      fastest: 12,
      halfHour: 8.5,
      hour: 4,
      economy: 2,
      minimum: 1,
      at: _syncedAt,
    );

    test('takes the height the latest sync saw, and the fees as given', () {
      final wallets = [
        // Synced later but from a shorter chain view: the later stamp
        // wins, whatever its height.
        makeMeta(
          id: 'a',
          name: 'A',
          lastSync: _stamp(_syncedAt - 3600, tipHeight: 912400),
        ),
        makeMeta(id: 'b', name: 'B', lastSync: _stamp(_syncedAt)),
      ];
      final payload = NetworkPayload.of(
        wallets,
        fees: fees,
        network: Network.mainnet,
        now: _now,
      );
      expect(payload.height, groupThousands('912345'));
      expect(payload.nextBlock, '12 sat/vB');
      expect(payload.hour, '4 sat/vB');
      expect(payload.footer, 'Synced 2 h ago');
      expect(payload.toData().keys, NetworkPayload.keys);
    });

    test('drops the fee lines when there are none, and names a network '
        'that is not the chain', () {
      final payload = NetworkPayload.of(
        [makeMeta(id: 'a', name: 'A', network: Network.signet)],
        network: Network.signet,
        now: _now,
      );
      expect(payload.height, '—');
      expect(payload.nextBlock, isNull);
      expect(payload.hour, isNull);
      expect(payload.footer, 'Signet · not synced yet');
      final data = payload.toData();
      expect(data[WidgetKeys.networkNextBlock], isNull);
      expect(data[WidgetKeys.networkHour], isNull);
    });

    test('a fee rate is whole when it is whole, else one decimal', () {
      expect(formatFeeRate(12), '12 sat/vB');
      expect(formatFeeRate(8.5), '8.5 sat/vB');
      expect(formatFeeRate(1.02), '1.0 sat/vB');
    });
  });

  group('the feed', () {
    test('writes every placed widget and asks it to redraw', () async {
      final board = FakeWidgetBoard(
        installed: {
          HomeWidgets.price,
          HomeWidgets.balance,
          HomeWidgets.network,
        },
      );
      await _running(_bridge(), board);

      // Fiat display is off in the app: the widget fetched its own quote
      // in the preferred currency all the same.
      expect(
        board.data[WidgetKeys.priceFigure],
        formatFiat(satsPerBtc, 50000, FiatCurrency.eur),
      );
      expect(board.data[WidgetKeys.priceAsOf], startsWith('as of '));
      expect(board.data.containsKey(WidgetKeys.priceChange), isFalse);
      // Masked until the widget preference says otherwise.
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);
      expect(board.data[WidgetKeys.balanceRowName(1)], 'Cold storage');
      expect(board.data[WidgetKeys.balanceRowFigure(1)], maskedValue);
      expect(board.data[WidgetKeys.balanceSynced], startsWith('Synced '));
      expect(board.data[WidgetKeys.networkHeight], groupThousands('912345'));
      expect(board.data[WidgetKeys.networkNextBlock], '12 sat/vB');
      expect(board.data[WidgetKeys.networkHour], '4 sat/vB');
      expect(board.updates.toSet(), {
        HomeWidgets.price,
        HomeWidgets.balance,
        HomeWidgets.network,
      });
    });

    test('shows the balances once the preference is on, and hides them '
        'again while the app hides amounts', () async {
      final bridge = _bridge();
      final board = FakeWidgetBoard(installed: {HomeWidgets.balance});
      final (:container, :feed) = await _running(bridge, board);

      container.read(widgetBalancesProvider.notifier).set(true);
      await feed.publish();
      expect(bridge.appPrefs['widgets.balances'], '1');
      expect(board.data[WidgetKeys.balanceTotal], '1.00050000 BTC');
      expect(board.data[WidgetKeys.balanceRowFigure(2)], '0.00050000 BTC');

      container.read(maskedProvider.notifier).toggle();
      await feed.publish();
      expect(board.data[WidgetKeys.balanceTotal], maskedValue);

      container.read(maskedProvider.notifier).toggle();
      container.read(unitProvider.notifier).set(AmountUnit.sats);
      await feed.publish();
      expect(board.data[WidgetKeys.balanceTotal], formatSats(100050000));
    });

    test(
      'a widget nobody placed gets nothing, and its keys are cleared',
      () async {
        final board = FakeWidgetBoard(installed: {HomeWidgets.price});
        board.data[WidgetKeys.balanceTotal] = 'stale';
        final bridge = _bridge();
        await _running(bridge, board);

        expect(board.data.containsKey(WidgetKeys.balanceTotal), isFalse);
        expect(board.data.containsKey(WidgetKeys.networkHeight), isFalse);
        expect(board.updates, everyElement(HomeWidgets.price));
        // No network widget, no fee request.
        expect(bridge.feeCalls, isEmpty);
      },
    );

    test(
      'a quote that could not be fetched leaves the last one standing',
      () async {
        final bridge = _bridge();
        final board = FakeWidgetBoard(installed: {HomeWidgets.price});
        final (:container, :feed) = await _running(bridge, board);
        final before = board.data[WidgetKeys.priceFigure];
        expect(before, isNotNull);

        bridge.onFetchPrice = (_, _) =>
            throw const BridgeException('sync', 'no answer');
        container.invalidate(widgetPriceProvider);
        await expectLater(
          container.read(widgetPriceProvider.future),
          throwsA(isA<BridgeException>()),
        );
        await feed.publish();
        expect(board.data[WidgetKeys.priceFigure], before);
      },
    );

    test('a return to the foreground reads the placed widgets again', () async {
      final board = FakeWidgetBoard(installed: {HomeWidgets.price});
      final (:container, :feed) = await _running(_bridge(), board);
      expect(board.data.containsKey(WidgetKeys.networkHeight), isFalse);

      board.installed.add(HomeWidgets.network);
      feed.resume();
      await container.read(installedWidgetsProvider.future);
      await container.read(widgetFeesProvider.future);
      await feed.publish();
      expect(board.installedAsks, 2);
      expect(board.data[WidgetKeys.networkNextBlock], '12 sat/vB');
      expect(board.updates, contains(HomeWidgets.network));
    });

    test('fees are left off a network with no fee market', () async {
      final bridge = FakeBridge(
        wallets: [
          makeMeta(
            id: 'r',
            name: 'Local',
            network: Network.regtest,
            lastSync: _stamp(_syncedAt, tipHeight: 120),
          ),
        ],
        settings: const Settings(
          activeNetwork: Network.regtest,
          backends: {},
          appPrefs: {},
        ),
      );
      final board = FakeWidgetBoard(installed: {HomeWidgets.network});
      await _running(bridge, board);

      expect(bridge.feeCalls, [Network.regtest]);
      expect(board.data[WidgetKeys.networkHeight], '120');
      expect(board.data.containsKey(WidgetKeys.networkNextBlock), isFalse);
      expect(board.data[WidgetKeys.networkFooter], startsWith('Regtest · '));
    });
  });
}
