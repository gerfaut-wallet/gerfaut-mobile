// Home-screen widgets: Gerfaut on the launcher without being opened.
// The text is composed here and handed to the platform as flat strings;
// the Kotlin providers only lay it out. Nothing private leaves the
// vault for a widget — a wallet name, a formatted balance, a price, a
// height — never an address, a descriptor or a transaction id.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'format.dart';
import 'models.dart';
import 'state.dart';

/// The three providers, by the class name Android knows them under.
abstract final class HomeWidgets {
  static const String price = 'PriceWidgetProvider';
  static const String balance = 'BalanceWidgetProvider';
  static const String network = 'NetworkWidgetProvider';

  /// The Kotlin package the providers live in.
  static const String package = 'com.gerfautwallet.gerfaut';
}

/// Every key a widget reads, in one place. The Kotlin providers read
/// them back under these exact names; a key that is absent hides its
/// line.
abstract final class WidgetKeys {
  static const String priceFigure = 'price.figure';
  static const String priceChange = 'price.change';
  static const String priceAsOf = 'price.asOf';
  static const String balanceTotal = 'balance.total';
  static const String balanceSynced = 'balance.synced';
  static const String networkHeight = 'network.height';
  static const String networkNextBlock = 'network.nextBlock';
  static const String networkHour = 'network.hour';
  static const String networkFooter = 'network.footer';

  /// The name of the wallet on row [n], counted from one.
  static String balanceRowName(int n) => 'balance.row$n.name';

  /// The balance of the wallet on row [n], counted from one.
  static String balanceRowFigure(int n) => 'balance.row$n.figure';
}

// --- payloads ----------------------------------------------------------

/// What the price widget shows.
class PricePayload {
  const PricePayload({required this.figure, this.change, required this.asOf});

  /// The quote as the widget states it: the price of one bitcoin in the
  /// quote's currency, and the clock time it was fetched at.
  factory PricePayload.of(PriceQuote quote) {
    return PricePayload(
      figure: formatFiat(satsPerBtc, quote.rate, quote.currency),
      asOf: 'as of ${formatClock(quote.at)}',
    );
  }

  static const List<String> keys = [
    WidgetKeys.priceFigure,
    WidgetKeys.priceChange,
    WidgetKeys.priceAsOf,
  ];

  final String figure;

  /// The signed change over 24 hours, when the source gives one. The
  /// quotes the core serves carry none yet, so the line stays hidden.
  final String? change;

  final String asOf;

  Map<String, String?> toData() => {
    WidgetKeys.priceFigure: figure,
    WidgetKeys.priceChange: change,
    WidgetKeys.priceAsOf: asOf,
  };
}

/// One wallet on the balance widget.
typedef BalanceRow = ({String name, String figure});

/// What the balance widget shows: the total of the network's wallets,
/// then up to [maxRows] of them by name.
class BalancePayload {
  const BalancePayload({
    required this.total,
    required this.rows,
    required this.synced,
  });

  /// The wallets as the widget states them, in the order the home
  /// screen lists them. Masked, the figures go and the names stay: a
  /// name is allowed off the vault, an amount only when asked for.
  factory BalancePayload.of(
    List<WalletMeta> wallets, {
    required AmountUnit unit,
    required bool masked,
    DateTime? now,
  }) {
    String figure(int sats) => masked ? maskedValue : formatAmount(sats, unit);
    var sum = 0;
    for (final wallet in wallets) {
      sum += wallet.cachedBalance.total;
    }
    return BalancePayload(
      total: figure(sum),
      rows: [
        for (final wallet in wallets.take(maxRows))
          (name: wallet.name, figure: figure(wallet.cachedBalance.total)),
      ],
      synced: syncedLine(wallets, now: now),
    );
  }

  /// Wallets listed by name; the total covers them all regardless.
  static const int maxRows = 4;

  static final List<String> keys = [
    WidgetKeys.balanceTotal,
    for (var n = 1; n <= maxRows; n++) ...[
      WidgetKeys.balanceRowName(n),
      WidgetKeys.balanceRowFigure(n),
    ],
    WidgetKeys.balanceSynced,
  ];

  final String total;
  final List<BalanceRow> rows;
  final String synced;

  Map<String, String?> toData() => {
    WidgetKeys.balanceTotal: total,
    for (var n = 1; n <= maxRows; n++) ...{
      WidgetKeys.balanceRowName(n): n <= rows.length ? rows[n - 1].name : null,
      WidgetKeys.balanceRowFigure(n): n <= rows.length
          ? rows[n - 1].figure
          : null,
    },
    WidgetKeys.balanceSynced: synced,
  };
}

/// What the network widget shows: the chain height as of the last sync,
/// and the fee rates the backend recommends right now.
class NetworkPayload {
  const NetworkPayload({
    required this.height,
    this.nextBlock,
    this.hour,
    required this.footer,
  });

  /// The height is the one the most recent sync saw; the fees are
  /// omitted when there are none, whether the network has no fee
  /// market or the source did not answer. A network other than
  /// mainnet is named in the footer, so a signet height is never read
  /// as the chain's.
  factory NetworkPayload.of(
    List<WalletMeta> wallets, {
    FeeEstimates? fees,
    required Network network,
    DateTime? now,
  }) {
    final stamp = latestSync(wallets);
    final synced = syncedLine(wallets, now: now);
    return NetworkPayload(
      height: stamp == null ? '—' : groupThousands('${stamp.tipHeight}'),
      nextBlock: fees == null ? null : formatFeeRate(fees.fastest),
      hour: fees == null ? null : formatFeeRate(fees.hour),
      footer: network == Network.mainnet
          ? synced
          : '${network.label} · ${synced[0].toLowerCase()}${synced.substring(1)}',
    );
  }

  static const List<String> keys = [
    WidgetKeys.networkHeight,
    WidgetKeys.networkNextBlock,
    WidgetKeys.networkHour,
    WidgetKeys.networkFooter,
  ];

  final String height;
  final String? nextBlock;
  final String? hour;
  final String footer;

  Map<String, String?> toData() => {
    WidgetKeys.networkHeight: height,
    WidgetKeys.networkNextBlock: nextBlock,
    WidgetKeys.networkHour: hour,
    WidgetKeys.networkFooter: footer,
  };
}

/// The most recent sync stamp across the wallets, null when none has
/// synced yet.
SyncStamp? latestSync(List<WalletMeta> wallets) {
  SyncStamp? latest;
  for (final wallet in wallets) {
    final stamp = wallet.lastSync;
    if (stamp != null && (latest == null || stamp.at > latest.at)) {
      latest = stamp;
    }
  }
  return latest;
}

/// The freshness line under a figure read off the last sync. A widget
/// never syncs on its own, so the line says how old what it shows is.
String syncedLine(List<WalletMeta> wallets, {DateTime? now}) {
  if (wallets.isEmpty) return 'No wallets yet';
  final stamp = latestSync(wallets);
  if (stamp == null) return 'Not synced yet';
  return 'Synced ${relativeTime(stamp.at, now: now)}';
}

/// The currency and source the preferences name, with the fallback the
/// screens apply when they hydrate: a source that does not quote the
/// currency yields to CoinGecko.
({FiatCurrency currency, PriceSource source}) priceChoice(
  Map<String, String> prefs,
) {
  final currency =
      FiatCurrency.fromId(prefs['display.fiat_currency']) ?? FiatCurrency.eur;
  final stored = PriceSource.fromId(prefs['display.fiat_source']);
  final source = stored != null && stored.supportsCurrency(currency)
      ? stored
      : PriceSource.coingecko;
  return (currency: currency, source: source);
}

// --- the platform side -------------------------------------------------

/// The platform's side of the widgets: the store the providers read,
/// the request to redraw, and which of them are on a home screen.
/// Tests substitute a recording fake so no test reaches the platform.
abstract class WidgetBoard {
  /// Stores one string under [key]; null removes it.
  Future<void> saveWidgetData(String key, String? value);

  /// Asks every instance of the provider [name] to redraw.
  Future<void> updateWidget(String name);

  /// The provider names with at least one instance on a home screen.
  Future<Set<String>> installedWidgets();
}

/// The board of the real app, on home_widget. A widget that cannot be
/// drawn is not an app failure: platform refusals are swallowed here,
/// and a host with no widgets at all reports none.
class HomeWidgetBoard implements WidgetBoard {
  const HomeWidgetBoard();

  @override
  Future<void> saveWidgetData(String key, String? value) =>
      _quietly(() => HomeWidget.saveWidgetData<String>(key, value));

  @override
  Future<void> updateWidget(String name) => _quietly(
    () => HomeWidget.updateWidget(
      qualifiedAndroidName: '${HomeWidgets.package}.$name',
    ),
  );

  @override
  Future<Set<String>> installedWidgets() async {
    final placed = await _quietly(HomeWidget.getInstalledWidgets);
    return {
      for (final widget in placed ?? const <HomeWidgetInfo>[])
        // Android names the provider relative to the package, with a
        // leading dot; the simple class name is what the app goes by.
        if (widget.androidClassName != null)
          widget.androidClassName!.split('.').last,
    };
  }

  static Future<T?> _quietly<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

final widgetBoardProvider = Provider<WidgetBoard>(
  (ref) => const HomeWidgetBoard(),
);

/// Which widgets are on a home screen, by provider name. Read at start
/// and again on every return to the foreground, since the launcher had
/// the screen in between. Nothing is fetched for a widget nobody placed.
final installedWidgetsProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(widgetBoardProvider).installedWidgets(),
);

// --- preferences -------------------------------------------------------

class WidgetBalancesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    // Only an explicit "1" shows them: a widget is read over the
    // shoulder, so the amounts stay masked until asked for.
    state = stored == '1';
  }

  void set(bool on) {
    state = on;
    ref
        .read(bridgeProvider)
        .setAppPref('widgets.balances', on ? '1' : '0')
        .catchError((_) {});
  }
}

/// Balances shown on the widgets, off by default, persisted as
/// "widgets.balances".
final widgetBalancesProvider = NotifierProvider<WidgetBalancesNotifier, bool>(
  WidgetBalancesNotifier.new,
);

// --- what the open app feeds -------------------------------------------

/// The price the widget shows: the app's own quote while fiat display
/// is on, otherwise one fetched for the widget alone, in the currency
/// and from the source the settings name. Placing the widget is the
/// opt-in; nothing is fetched while none is placed.
class WidgetPriceNotifier extends AsyncNotifier<PriceQuote?> {
  Timer? _timer;

  @override
  Future<PriceQuote?> build() async {
    _timer?.cancel();
    final fiatOn = ref.watch(fiatEnabledProvider);
    final appQuote = ref.watch(priceProvider);
    final currency = ref.watch(fiatCurrencyProvider);
    final source = ref.watch(fiatSourceProvider);
    final installed = await ref.watch(installedWidgetsProvider.future);
    if (!installed.contains(HomeWidgets.price)) return null;
    if (fiatOn) return appQuote.valueOrNull;
    ref.onDispose(() => _timer?.cancel());
    // Scheduled before the fetch so failures retry on the same cadence
    // as the app's own quote.
    _timer = Timer(const Duration(seconds: 60), () => ref.invalidateSelf());
    return ref.read(bridgeProvider).fetchPrice(source, currency);
  }
}

final widgetPriceProvider =
    AsyncNotifierProvider<WidgetPriceNotifier, PriceQuote?>(
      WidgetPriceNotifier.new,
    );

/// How often the open app asks for fee estimates while a network widget
/// is placed: blocks come about that often.
const Duration widgetFeesCadence = Duration(minutes: 10);

/// Fee estimates for the network widget, refreshed on [widgetFeesCadence]
/// while one is placed. Null when none is, and on a network with no
/// fee market.
class WidgetFeesNotifier extends AsyncNotifier<FeeEstimates?> {
  Timer? _timer;

  @override
  Future<FeeEstimates?> build() async {
    _timer?.cancel();
    final settings = ref.watch(settingsProvider).valueOrNull;
    final installed = await ref.watch(installedWidgetsProvider.future);
    if (settings == null || !installed.contains(HomeWidgets.network)) {
      return null;
    }
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer(widgetFeesCadence, () => ref.invalidateSelf());
    return ref.read(bridgeProvider).fetchFees(settings.activeNetwork);
  }
}

final widgetFeesProvider =
    AsyncNotifierProvider<WidgetFeesNotifier, FeeEstimates?>(
      WidgetFeesNotifier.new,
    );

/// Composes what the widgets say and hands it to the board.
///
/// Created once the preferences are hydrated, it follows everything a
/// widget shows — wallets and their syncs, the quote, the fees, the
/// unit, the mask, the widget preference, the set of placed widgets —
/// and republishes on each change. Publishing coalesces: a burst of
/// changes is written once, after the last of them.
class WidgetFeed {
  WidgetFeed(this._ref) {
    void republish(Object? _, Object? _) => publish();
    _ref.listen(walletsProvider, (_, next) {
      if (next.hasValue) publish();
    });
    _ref.listen(widgetPriceProvider, (_, next) {
      if (next.hasValue) publish();
    });
    _ref.listen(widgetFeesProvider, (_, next) {
      // An error hides the fee lines: a rate that could not be fetched
      // must not stand as current.
      if (!next.isLoading) publish();
    });
    _ref.listen(unitProvider, republish);
    _ref.listen(maskedProvider, republish);
    _ref.listen(widgetBalancesProvider, republish);
    _ref.listen(installedWidgetsProvider, (_, next) {
      if (next.hasValue) publish();
    });
    publish();
  }

  final Ref _ref;
  Future<void>? _inFlight;
  bool _again = false;

  /// Writes what the widgets show now. The future completes once the
  /// state at the time of the last call is on the board, so a caller
  /// that awaits it can read the board.
  Future<void> publish() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _run();
  }

  Future<void> _run() async {
    try {
      do {
        _again = false;
        await _publishOnce();
      } while (_again);
    } finally {
      _inFlight = null;
    }
  }

  /// The launcher had the screen: the set of placed widgets may have
  /// changed. Reading it again is what republishes.
  void resume() => _ref.invalidate(installedWidgetsProvider);

  Future<void> _publishOnce() async {
    // Nothing to say before the vault has answered: an empty wallet
    // list would read as "no wallets yet" for a second.
    final settings = _ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    Set<String> installed;
    try {
      installed = await _ref.read(installedWidgetsProvider.future);
    } catch (_) {
      return;
    }
    final wallets = _ref.read(walletsProvider).valueOrNull ?? const [];
    final quote = _ref.read(widgetPriceProvider).valueOrNull;
    final fees = _ref.read(widgetFeesProvider).valueOrNull;
    await write(
      _ref.read(widgetBoardProvider),
      installed: installed,
      price: quote == null ? null : PricePayload.of(quote),
      balance: BalancePayload.of(
        wallets,
        unit: _ref.read(unitProvider),
        masked: _ref.read(maskedProvider) || !_ref.read(widgetBalancesProvider),
      ),
      network: NetworkPayload.of(
        wallets,
        fees: fees,
        network: settings.activeNetwork,
      ),
    );
  }

  /// Writes each placed widget's data and asks it to redraw. The keys
  /// of a widget nobody placed are cleared, so the store holds only
  /// what is on a home screen. A missing [price] leaves the last quote
  /// standing: it carries its own time, and a dash would say less.
  static Future<void> write(
    WidgetBoard board, {
    required Set<String> installed,
    PricePayload? price,
    required BalancePayload balance,
    required NetworkPayload network,
  }) async {
    Future<void> put(String name, Map<String, String?> data) async {
      for (final entry in data.entries) {
        await board.saveWidgetData(entry.key, entry.value);
      }
      await board.updateWidget(name);
    }

    Future<void> clear(List<String> keys) async {
      for (final key in keys) {
        await board.saveWidgetData(key, null);
      }
    }

    if (!installed.contains(HomeWidgets.price)) {
      await clear(PricePayload.keys);
    } else if (price != null) {
      await put(HomeWidgets.price, price.toData());
    }
    if (installed.contains(HomeWidgets.balance)) {
      await put(HomeWidgets.balance, balance.toData());
    } else {
      await clear(BalancePayload.keys);
    }
    if (installed.contains(HomeWidgets.network)) {
      await put(HomeWidgets.network, network.toData());
    } else {
      await clear(NetworkPayload.keys);
    }
  }
}

/// The feed of the app. Reading it is what starts it, once the
/// preferences a widget depends on are hydrated.
final widgetFeedProvider = Provider<WidgetFeed>((ref) => WidgetFeed(ref));
