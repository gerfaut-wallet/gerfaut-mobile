// Home-screen widgets: Gerfaut on the launcher without being opened.
// The text is composed here and handed to the platform as flat strings;
// the Kotlin providers only lay it out. Nothing private leaves the
// vault for a widget — a wallet name, a formatted balance, a price, a
// height — never an address, a descriptor or a transaction id.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'background.dart';
import 'bridge.dart';
import 'format.dart';
import 'models.dart';
import 'state.dart';
import 'vault_key.dart';
import 'prefs.dart';

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

  /// The as-of line for an instance too narrow for [priceAsOf]; absent
  /// when that line is already as short as it can be and stay true.
  static const String priceAsOfNarrow = 'price.asOfNarrow';

  /// When the quote was fetched, in unix seconds. No widget shows it:
  /// the as-of lines are written again from it while no new quote comes.
  static const String priceAt = 'price.at';

  /// The credit the source of the price asks for under it ("Powered by
  /// CoinGecko"); absent when it asks for none.
  static const String priceCredit = 'price.credit';

  /// Which source the price comes from, by the core's identifier. No
  /// widget shows it: the credit is written again from it while the
  /// same price stands.
  static const String priceSource = 'price.source';
  static const String balanceTotal = 'balance.total';
  static const String balanceSynced = 'balance.synced';
  static const String networkHeight = 'network.height';
  static const String networkFooter = 'network.footer';

  /// The name of the wallet on row [n], counted from one.
  static String balanceRowName(int n) => 'balance.row$n.name';

  /// The balance of the wallet on row [n], counted from one.
  static String balanceRowFigure(int n) => 'balance.row$n.figure';
}

// --- payloads ----------------------------------------------------------

/// What the price widget shows.
class PricePayload {
  const PricePayload({
    required this.figure,
    this.change,
    required this.at,
    required this.asOf,
    this.asOfNarrow,
    required this.source,
    this.credit,
  });

  /// The quote as the widget states it: the price of one bitcoin in the
  /// quote's currency, in the same figures the app's own price line
  /// uses, when it was fetched, as [priceAsOf] says it [now], and the
  /// credit its source asks for in the core's [table].
  factory PricePayload.of(PriceQuote quote, PriceTable table, {DateTime? now}) {
    final asOf = priceAsOf(quote.at, now: now);
    return PricePayload(
      figure: formatFiatPrice(quote.rate, quote.currency),
      at: quote.at,
      asOf: asOf.full,
      asOfNarrow: asOf.narrow,
      source: quote.source.id,
      credit: table.creditOf(quote.source)?.text,
    );
  }

  static const List<String> keys = [
    WidgetKeys.priceFigure,
    WidgetKeys.priceChange,
    WidgetKeys.priceAsOf,
    WidgetKeys.priceAsOfNarrow,
    WidgetKeys.priceAt,
    WidgetKeys.priceCredit,
    WidgetKeys.priceSource,
  ];

  final String figure;

  /// The signed change over 24 hours, when the source gives one. The
  /// quotes the core serves carry none yet, so the line stays hidden.
  final String? change;

  /// When the quote was fetched, in unix seconds.
  final int at;

  final String asOf;
  final String? asOfNarrow;

  /// The source of the quote, by the core's identifier.
  final String source;

  /// What the source of the quote asks to be shown with it, word for
  /// word, as the core's table gives it; null when it asks for nothing.
  final String? credit;

  Map<String, String?> toData() => {
    WidgetKeys.priceFigure: figure,
    WidgetKeys.priceChange: change,
    WidgetKeys.priceAsOf: asOf,
    WidgetKeys.priceAsOfNarrow: asOfNarrow,
    WidgetKeys.priceAt: '$at',
    WidgetKeys.priceCredit: credit,
    WidgetKeys.priceSource: source,
  };
}

/// The line under a price fetched at [at], as the widget says it [now]:
/// the clock time alone on the day of the quote, `as of 09:41`; the day
/// and the time on any later day, `as of Oct 03, 09:41`; the day and the
/// year once the year has turned, `as of Dec 31, 2025`. A price kept up
/// for days must not pass for this morning's.
///
/// [narrow] is the line for an instance too narrow for the time,
/// `as of Oct 03`; null when [full] is already as short as it can be
/// and stay true. The year is never the part dropped: a day without it
/// would read as this year's.
({String full, String? narrow}) priceAsOf(int at, {DateTime? now}) {
  final then = DateTime.fromMillisecondsSinceEpoch(at * 1000);
  final today = (now ?? DateTime.now()).toLocal();
  if (then.year != today.year) {
    return (full: 'as of ${formatDate(at)}', narrow: null);
  }
  if (then.month == today.month && then.day == today.day) {
    return (full: 'as of ${formatClock(at)}', narrow: null);
  }
  final day = formatDayMonth(at);
  return (full: 'as of $day, ${formatClock(at)}', narrow: 'as of $day');
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
  ///
  /// [locked], an app lock is set, and neither goes: the widget sits on
  /// the home screen of a phone whose app is locked, for whoever holds
  /// it, and says nothing of the wallets. Notifications follow a switch
  /// of their own; the widget follows the lock. The total stays, masked,
  /// so the widget still shows when it was last brought up to date.
  factory BalancePayload.of(
    List<WalletMeta> wallets, {
    required AmountUnit unit,
    required bool masked,
    bool locked = false,
    DateTime? now,
  }) {
    String figure(int sats) =>
        masked || locked ? maskedValue : formatAmount(sats, unit);
    var sum = 0;
    for (final wallet in wallets) {
      sum += wallet.cachedBalance.total;
    }
    return BalancePayload(
      total: figure(sum),
      rows: [
        if (!locked)
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
/// and how old that reading is.
class NetworkPayload {
  const NetworkPayload({required this.height, required this.footer});

  /// The height is the one the most recent sync saw. A network other
  /// than mainnet is named in the footer, so a signet height is never
  /// read as the chain's.
  factory NetworkPayload.of(
    List<WalletMeta> wallets, {
    required Network network,
    DateTime? now,
  }) {
    final stamp = latestSync(wallets);
    final synced = syncedLine(wallets, now: now);
    return NetworkPayload(
      height: stamp == null ? '—' : groupThousands('${stamp.tipHeight}'),
      footer: network == Network.mainnet
          ? synced
          : '${network.label} · ${synced[0].toLowerCase()}${synced.substring(1)}',
    );
  }

  static const List<String> keys = [
    WidgetKeys.networkHeight,
    WidgetKeys.networkFooter,
  ];

  final String height;
  final String footer;

  Map<String, String?> toData() => {
    WidgetKeys.networkHeight: height,
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

// --- the platform side -------------------------------------------------

/// The platform's side of the widgets: the store the providers read,
/// the request to redraw, and which of them are on a home screen.
/// Tests substitute a recording fake so no test reaches the platform.
abstract class WidgetBoard {
  /// Stores one string under [key]; null removes it.
  Future<void> saveWidgetData(String key, String? value);

  /// The string stored under [key], null when there is none.
  Future<String?> readWidgetData(String key);

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
  Future<String?> readWidgetData(String key) =>
      _quietly(() => HomeWidget.getWidgetData<String>(key));

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
        .setAppPref(Pref.widgetBalances, on ? '1' : '0')
        .catchError((_) {});
  }
}

/// Balances shown on the widgets, off by default, persisted as
/// "widgets.balances".
final widgetBalancesProvider = NotifierProvider<WidgetBalancesNotifier, bool>(
  WidgetBalancesNotifier.new,
);

/// Registers the periodic widget refresh, or cancels it.
typedef WidgetScheduler = Future<void> Function(bool wanted);

/// The real app schedules with the system; tests record the calls.
final widgetSchedulerProvider = Provider<WidgetScheduler>(
  (ref) => registerWidgetRefresh,
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
    // Asked again when the pair changes: the core prices by it.
    ref.watch(fiatCurrencyProvider);
    ref.watch(fiatSourceProvider);
    final inFront = ref.watch(appInFrontProvider);
    final installed = await ref.watch(installedWidgetsProvider.future);
    if (!installed.contains(HomeWidgets.price)) return null;
    if (fiatOn) return appQuote.value;
    // Out of sight the widget is the periodic task's to refresh: no
    // minute clock runs behind the launcher.
    if (!inFront) return state.value;
    ref.onDispose(() => _timer?.cancel());
    final every = (await ref.read(priceTableProvider.future)).refresh;
    // Scheduled before the fetch so failures retry on the same cadence
    // as the app's own quote.
    _timer = Timer(every, () => ref.invalidateSelf());
    return ref.read(bridgeProvider).fetchPrice();
  }
}

final widgetPriceProvider =
    AsyncNotifierProvider<WidgetPriceNotifier, PriceQuote?>(
      WidgetPriceNotifier.new,
    );

/// Composes what the widgets say and hands it to the board.
///
/// Created once the preferences are hydrated, it follows everything a
/// widget shows — wallets and their syncs, the quote, the unit, the
/// mask, the widget preference, the set of placed widgets —
/// and republishes on each change. Publishing coalesces: a burst of
/// changes is written once, after the last of them.
class WidgetFeed {
  WidgetFeed(this._ref) {
    void republish(Object? _, Object? _) => publish();
    // A provider refreshing still shows what it had: only a settled
    // state is worth a write.
    _ref.listen(walletsProvider, (_, next) {
      if (next.hasValue && !next.isLoading) publish();
    });
    _ref.listen(widgetPriceProvider, (_, next) {
      if (next.hasValue && !next.isLoading) publish();
    });
    _ref.listen(unitProvider, republish);
    _ref.listen(maskedProvider, republish);
    _ref.listen(widgetBalancesProvider, republish);
    // A lock set or taken off changes what the balance widget may say.
    _ref.listen(settingsProvider, (previous, next) {
      final before = previous?.value?.appLock != null;
      final now = next.value?.appLock != null;
      if (next.hasValue && before != now) publish();
    });
    _ref.listen(installedWidgetsProvider, (_, next) {
      if (next.isLoading) return;
      final installed = next.value;
      if (installed == null) return;
      // The background refresh runs only while something is there to
      // refresh; an empty home screen costs nothing.
      _ref
          .read(widgetSchedulerProvider)(installed.isNotEmpty)
          .catchError((_) {});
      publish();
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
      } while (_again && _ref.mounted);
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
    final settings = _ref.read(settingsProvider).value;
    if (settings == null) return;
    Set<String> installed;
    try {
      installed = await _ref.read(installedWidgetsProvider.future);
    } catch (_) {
      return;
    }
    // Each wait is a chance for the app to have closed meanwhile.
    if (!_ref.mounted) return;
    final wallets = _ref.read(walletsProvider).value ?? const [];
    final quote = _ref.read(widgetPriceProvider).value;
    final table = await _ref.read(priceTableProvider.future);
    if (!_ref.mounted) return;
    await write(
      _ref.read(widgetBoardProvider),
      installed: installed,
      price: quote == null ? null : PricePayload.of(quote, table),
      table: table,
      balance: BalancePayload.of(
        wallets,
        unit: _ref.read(unitProvider),
        masked: _ref.read(maskedProvider) || !_ref.read(widgetBalancesProvider),
        locked: settings.appLock != null,
      ),
      network: NetworkPayload.of(wallets, network: settings.activeNetwork),
    );
  }

  /// Writes each placed widget's data and asks it to redraw. The keys
  /// of a widget nobody placed are cleared, so the store holds only
  /// what is on a home screen. A missing [price] leaves the last quote
  /// standing: it carries its own time, and a dash would say less; its
  /// source's credit stands with it, written again from [table].
  static Future<void> write(
    WidgetBoard board, {
    required Set<String> installed,
    PricePayload? price,
    PriceTable? table,
    required BalancePayload balance,
    required NetworkPayload network,
    DateTime? now,
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
    } else {
      // The last quote stands, but its time is said again from when it
      // was fetched: written once, "as of 23:50" would still say so the
      // next day. A store from before the key holds no time to say.
      final at = int.tryParse(
        await board.readWidgetData(WidgetKeys.priceAt) ?? '',
      );
      final source = PriceSource.fromId(
        await board.readWidgetData(WidgetKeys.priceSource),
      );
      if (at != null && source == null) {
        // A price from a build that kept no source: CoinGecko may have
        // priced it, and it would stand without the credit its terms
        // ask for. It goes, until a fresh one comes.
        await clear(PricePayload.keys);
        await board.updateWidget(HomeWidgets.price);
      } else if (at != null) {
        final asOf = priceAsOf(at, now: now);
        await put(HomeWidgets.price, {
          WidgetKeys.priceAsOf: asOf.full,
          WidgetKeys.priceAsOfNarrow: asOf.narrow,
          if (table != null)
            WidgetKeys.priceCredit: table.creditOf(source!)?.text,
        });
      }
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

// --- the background refresh --------------------------------------------

/// Whether the background refresh may ask for the price without Tor
/// being started for it.
///
/// With a .onion node the core sends the price through Tor, and nothing
/// at all while Tor cannot be had. Asked from here, that route would
/// start the built-in client every quarter hour for one figure: a
/// bootstrap of up to a minute and a half, on battery, behind the
/// launcher. So the price follows only a Tor that already runs: the
/// built-in client once something else in this process brought it up
/// (a sync, the live watch, the open app), or the Tor app chosen as
/// System, which the core only knocks on and never starts. Otherwise
/// nothing is asked, and the widget keeps the last price with the time
/// it carries. Nothing goes out in the clear either way: the core sees
/// to that whatever this says.
Future<bool> priceWithoutStartingTor(GerfautBridge bridge) async {
  if (!await bridge.usesTor()) return true;
  final tor = await bridge.torStatus();
  return tor.mode == TorMode.system || tor.bootstrapped;
}

/// What Android runs every quarter hour while widgets are placed and
/// Gerfaut is closed: open the vault, read what the placed widgets
/// show, fetch the price if one of them needs it, publish. It never
/// syncs the chain — balances and heights stay as of the last sync, and
/// the line under them says so. Always answers true: the next run is
/// soon enough for whatever did not work this time.
Future<bool> refreshWidgets({
  GerfautBridge bridge = const RustBridge(),
  WidgetBoard board = const HomeWidgetBoard(),
  Future<void> Function() bootstrap = bootstrapGerfaut,
  DateTime? now,
}) async {
  try {
    final installed = await board.installedWidgets();
    if (installed.isEmpty) return true;
    await bootstrap();
    final settings = await bridge.getSettings();
    final prefs = settings.appPrefs;
    final shared = settings.preferences;
    final network = settings.activeNetwork;
    final wallets = await bridge.listWallets(network);
    PriceQuote? quote;
    final table = await bridge.priceTable();
    if (installed.contains(HomeWidgets.price)) {
      try {
        if (await priceWithoutStartingTor(bridge)) {
          quote = await bridge.fetchPrice();
        }
      } catch (_) {
        // The last quote stays up, with the time it carries.
      }
    }
    await WidgetFeed.write(
      board,
      installed: installed,
      price: quote == null ? null : PricePayload.of(quote, table, now: now),
      table: table,
      balance: BalancePayload.of(
        wallets,
        unit: shared.unit,
        masked: shared.masked || prefs[Pref.widgetBalances] != '1',
        locked: settings.appLock != null,
        now: now,
      ),
      network: NetworkPayload.of(wallets, network: network, now: now),
      now: now,
    );
    return true;
  } on VaultInUseException {
    // Another opener holds the vault, which is fine: the widgets keep
    // what they show until the next run.
    return true;
  } catch (_) {
    // A vault that would not open is not a reason to retry in a tight
    // loop: the next scheduled run is soon enough.
    return true;
  }
}
