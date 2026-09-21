// App state. Server state lives in providers fed by the bridge; the
// notifiers below hold only what the interface itself decides:
// preferences and sync progress.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'format.dart';
import 'models.dart';
import 'notifications.dart';

/// The bridge to the core. Widget tests override this with a fake.
final bridgeProvider = Provider<GerfautBridge>((ref) => const RustBridge());

/// Vault settings. Invalidated after any mutation that touches them.
final settingsProvider = FutureProvider<Settings>((ref) {
  return ref.watch(bridgeProvider).getSettings();
});

/// Public servers offered for a network, in the order the settings list
/// them. A fixed catalogue: it only changes with the app.
final publicServersProvider =
    FutureProvider.family<List<PublicServer>, Network>((ref, network) {
      return ref.watch(bridgeProvider).publicServers(network);
    });

/// Wallets of the active workspace network.
final walletsProvider = FutureProvider<List<WalletMeta>>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  return ref.watch(bridgeProvider).listWallets(settings.activeNetwork);
});

/// Full view of one wallet.
final snapshotProvider = FutureProvider.family<WalletSnapshot, String>((
  ref,
  id,
) {
  return ref.watch(bridgeProvider).walletSnapshot(id);
});

/// The spending policy of one wallet, read against the chain tip and
/// the coins of the last sync.
final policyProvider = FutureProvider.family<PolicySnapshot, String>((ref, id) {
  return ref.watch(bridgeProvider).walletPolicy(id);
});

/// Unspent outputs of one wallet.
final utxosProvider = FutureProvider.family<List<UtxoInfo>, String>((ref, id) {
  return ref.watch(bridgeProvider).utxos(id);
});

/// Detail of one transaction, keyed by wallet and txid.
final txDetailProvider =
    FutureProvider.family<TxDetail, ({String walletId, String txid})>((
      ref,
      key,
    ) {
      return ref.watch(bridgeProvider).txDetail(key.walletId, key.txid);
    });

/// Revealed addresses of one wallet, by keychain, capped by the core.
final addressListProvider = FutureProvider.family<AddressList, String>((
  ref,
  id,
) {
  return ref.watch(bridgeProvider).addressList(id);
});

/// The next unused receive address of one wallet, plus `lookahead`
/// addresses peeked past it. The entry at index `lookahead` is the one
/// on display; peeking retires nothing.
final receiveProvider =
    FutureProvider.family<
      List<AddressEntry>,
      ({String walletId, int lookahead})
    >((ref, key) {
      return ref
          .watch(bridgeProvider)
          .receiveAddresses(key.walletId, key.lookahead);
    });

// --- preferences -------------------------------------------------------

/// Theme preference. Light is the default; dark and system are options.
enum ThemePref {
  light('light', 'Light'),
  dark('dark', 'Dark'),
  system('system', 'System');

  const ThemePref(this.id, this.label);

  final String id;
  final String label;

  static ThemePref? fromId(String? id) {
    for (final pref in ThemePref.values) {
      if (pref.id == id) return pref;
    }
    return null;
  }
}

class ThemeNotifier extends Notifier<ThemePref> {
  @override
  ThemePref build() => ThemePref.light;

  void hydrate(String? stored) {
    final pref = ThemePref.fromId(stored);
    if (pref != null) state = pref;
  }

  void set(ThemePref pref) {
    state = pref;
    // Persisted in the encrypted vault; a write failure only loses the
    // preference, never the UI change.
    ref
        .read(bridgeProvider)
        .setAppPref('mobile.theme', pref.id)
        .catchError((_) {});
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemePref>(
  ThemeNotifier.new,
);

class MaskedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    if (stored != null) state = stored == '1';
  }

  void toggle() {
    state = !state;
    ref
        .read(bridgeProvider)
        .setAppPref('mobile.masked', state ? '1' : '0')
        .catchError((_) {});
  }
}

/// Masked balances: the eye toggle, persisted as "mobile.masked".
final maskedProvider = NotifierProvider<MaskedNotifier, bool>(
  MaskedNotifier.new,
);

class UnitNotifier extends Notifier<AmountUnit> {
  @override
  AmountUnit build() => AmountUnit.btc;

  void hydrate(String? stored) {
    final unit = AmountUnit.fromId(stored);
    if (unit != null) state = unit;
  }

  void set(AmountUnit unit) {
    state = unit;
    ref
        .read(bridgeProvider)
        .setAppPref('display.unit', unit.id)
        .catchError((_) {});
  }
}

/// Display unit for every amount, persisted as "display.unit".
final unitProvider = NotifierProvider<UnitNotifier, AmountUnit>(
  UnitNotifier.new,
);

class FiatEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    // Only an explicit "1" turns the display on: fiat is opt-in.
    state = stored == '1';
  }

  void set(bool enabled) {
    state = enabled;
    ref
        .read(bridgeProvider)
        .setAppPref('display.fiat', enabled ? '1' : '0')
        .catchError((_) {});
  }
}

/// Fiat display, off by default, persisted as "display.fiat".
final fiatEnabledProvider = NotifierProvider<FiatEnabledNotifier, bool>(
  FiatEnabledNotifier.new,
);

class FiatCurrencyNotifier extends Notifier<FiatCurrency> {
  @override
  FiatCurrency build() => FiatCurrency.eur;

  void hydrate(String? stored) {
    final currency = FiatCurrency.fromId(stored);
    if (currency != null) state = currency;
  }

  void set(FiatCurrency currency) {
    state = currency;
    ref
        .read(bridgeProvider)
        .setAppPref('display.fiat_currency', currency.id)
        .catchError((_) {});
  }
}

/// Fiat currency, persisted as "display.fiat_currency".
final fiatCurrencyProvider =
    NotifierProvider<FiatCurrencyNotifier, FiatCurrency>(
      FiatCurrencyNotifier.new,
    );

class FiatSourceNotifier extends Notifier<PriceSource> {
  @override
  PriceSource build() => PriceSource.coingecko;

  void hydrate(String? stored) {
    final source = PriceSource.fromId(stored);
    // A stored pair no source can honour — a currency only CoinGecko
    // quotes, kept next to Kraken — falls back to CoinGecko rather than
    // to a quote that never arrives. The currency hydrates first.
    if (source != null &&
        source.supportsCurrency(ref.read(fiatCurrencyProvider))) {
      state = source;
    }
  }

  void set(PriceSource source) {
    state = source;
    ref
        .read(bridgeProvider)
        .setAppPref('display.fiat_source', source.id)
        .catchError((_) {});
  }
}

/// Price source, persisted as "display.fiat_source".
final fiatSourceProvider = NotifierProvider<FiatSourceNotifier, PriceSource>(
  FiatSourceNotifier.new,
);

class ExplorerAckNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    // Only an explicit "1" skips the warning, same rule as the desktop.
    state = stored == '1';
  }

  void set(bool acknowledged) {
    state = acknowledged;
    ref
        .read(bridgeProvider)
        .setAppPref('privacy.explorer_ack', acknowledged ? '1' : '0')
        .catchError((_) {});
  }
}

/// External explorer warning acknowledged: the dialog is skipped when
/// set. Persisted as "privacy.explorer_ack", shared with the desktop.
final explorerAckProvider = NotifierProvider<ExplorerAckNotifier, bool>(
  ExplorerAckNotifier.new,
);

/// Current BTC price, refreshed every minute while fiat display is on.
/// Failures surface as an error state: amounts degrade to no fiat and
/// the settings screen shows a quiet hint.
class PriceNotifier extends AsyncNotifier<PriceQuote?> {
  Timer? _timer;

  @override
  Future<PriceQuote?> build() async {
    _timer?.cancel();
    final enabled = ref.watch(fiatEnabledProvider);
    final currency = ref.watch(fiatCurrencyProvider);
    final source = ref.watch(fiatSourceProvider);
    if (!enabled) return null;
    ref.onDispose(() => _timer?.cancel());
    // Scheduled before the fetch so failures retry on the same cadence.
    _timer = Timer(const Duration(seconds: 60), () => ref.invalidateSelf());
    return ref.read(bridgeProvider).fetchPrice(source, currency);
  }
}

final priceProvider = AsyncNotifierProvider<PriceNotifier, PriceQuote?>(
  PriceNotifier.new,
);

/// Most broadcasts kept for a later status check.
const int recentBroadcastsCap = 10;

/// The transactions this app sent, newest first, so the broadcast
/// screen can check on them again after a restart. Persisted as JSON
/// under "broadcast.recent", capped at [recentBroadcastsCap].
class RecentBroadcastsNotifier extends Notifier<List<RecentBroadcast>> {
  @override
  List<RecentBroadcast> build() => const [];

  void hydrate(String? stored) {
    if (stored == null || stored.isEmpty) return;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return;
      state = [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) RecentBroadcast.fromJson(entry),
      ];
    } on FormatException {
      // A preference this build cannot read is left alone: the next
      // broadcast rewrites it.
    }
  }

  /// Records a broadcast, replacing an earlier entry with the same txid.
  void add(RecentBroadcast broadcast) {
    state = [
      broadcast,
      ...state.where((b) => b.txid != broadcast.txid),
    ].take(recentBroadcastsCap).toList();
    _persist();
  }

  /// Drops the record of a broadcast, with no way back. Only this app's
  /// own note of it goes: the transaction is on the network, where
  /// Gerfaut has never had any say.
  void forget(String txid) {
    state = state.where((b) => b.txid != txid).toList();
    _persist();
  }

  void _persist() {
    ref
        .read(bridgeProvider)
        .setAppPref(
          'broadcast.recent',
          jsonEncode([for (final b in state) b.toJson()]),
        )
        .catchError((_) {});
  }
}

final recentBroadcastsProvider =
    NotifierProvider<RecentBroadcastsNotifier, List<RecentBroadcast>>(
      RecentBroadcastsNotifier.new,
    );

/// One-shot guards: prefs hydration and the startup auto-sync.
final prefsHydratedProvider = StateProvider<bool>((ref) => false);
final autoSyncedProvider = StateProvider<bool>((ref) => false);

// --- sync --------------------------------------------------------------

/// Sentinel id marking a sync-all in progress.
const String syncAllId = '*';

/// Tracks which wallets are syncing and invalidates what a sync changes.
class SyncController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isSyncing(String walletId) =>
      state.contains(walletId) || state.contains(syncAllId);

  bool get syncingAny => state.isNotEmpty;

  void _invalidateWallet(String? id) {
    ref.invalidate(walletsProvider);
    if (id != null) {
      ref.invalidate(snapshotProvider(id));
      ref.invalidate(policyProvider(id));
      ref.invalidate(utxosProvider(id));
      ref.invalidate(addressListProvider(id));
    } else {
      ref.invalidate(snapshotProvider);
      ref.invalidate(policyProvider);
      ref.invalidate(utxosProvider);
      ref.invalidate(addressListProvider);
    }
    ref.invalidate(txDetailProvider);
  }

  /// A sync that did not start here changed this wallet: the live
  /// watch saw it move and synced it in the core.
  void refreshed(String walletId) => _invalidateWallet(walletId);

  /// Runs one wallet operation with the sync bookkeeping: the wallet is
  /// marked in flight, its last failure is recorded or cleared, and
  /// what the operation changed is refreshed. Null when one is already
  /// running for that wallet.
  Future<SyncReport?> _run(
    String id,
    Future<SyncReport> Function(GerfautBridge bridge) operation,
  ) async {
    if (state.contains(id)) return null;
    state = {...state, id};
    try {
      final report = await operation(ref.read(bridgeProvider));
      ref.read(syncErrorsProvider.notifier).clear(id);
      // Said after the fact, never in place of it: a notification that
      // cannot be posted must not look like a failed sync.
      await ref.read(syncAnnouncerProvider).announce([report]);
      return report;
    } catch (error) {
      ref.read(syncErrorsProvider.notifier).set(id, '$error');
      rethrow;
    } finally {
      state = {...state}..remove(id);
      _invalidateWallet(id);
    }
  }

  /// Syncs one wallet. Rethrows the core error after cleanup so the
  /// caller can show it; the failure also lands in [syncErrorsProvider].
  Future<SyncReport?> syncWallet(String id) =>
      _run(id, (bridge) => bridge.syncWallet(id));

  /// Scans one wallet again from its first address, with the same
  /// bookkeeping as [syncWallet].
  Future<SyncReport?> rescanWallet(String id) =>
      _run(id, (bridge) => bridge.rescanWallet(id));

  /// Syncs every wallet of a network. Failures are reported per wallet
  /// inside the returned report, never thrown.
  Future<SyncAllReport?> syncAll(Network network) async {
    if (state.contains(syncAllId)) return null;
    state = {...state, syncAllId};
    try {
      final report = await ref.read(bridgeProvider).syncAll(network);
      final errors = ref.read(syncErrorsProvider.notifier);
      for (final sync in report.reports) {
        errors.clear(sync.walletId);
      }
      for (final failure in report.failures) {
        errors.set(failure.walletId, failure.message);
      }
      await ref.read(syncAnnouncerProvider).announce(report.reports);
      return report;
    } finally {
      state = {...state}..remove(syncAllId);
      _invalidateWallet(null);
    }
  }
}

final syncProvider = NotifierProvider<SyncController, Set<String>>(
  SyncController.new,
);

/// Loads older history for a watched address, one round at a time. The
/// balance already covers the whole chain, so only the list grows.
class HistoryController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isLoading(String walletId) => state.contains(walletId);

  /// Returns how many transactions were added, or null when a round is
  /// already in flight. Rethrows the core error after refreshing the
  /// snapshot, so the caller can state what went wrong.
  Future<int?> loadMore(String walletId) async {
    if (state.contains(walletId)) return null;
    state = {...state, walletId};
    try {
      return await ref.read(bridgeProvider).loadMoreHistory(walletId);
    } finally {
      state = {...state}..remove(walletId);
      ref.invalidate(snapshotProvider(walletId));
    }
  }
}

final historyProvider = NotifierProvider<HistoryController, Set<String>>(
  HistoryController.new,
);

/// Last sync failure per wallet id, cleared on the next success.
/// A failed sync is stated with its reason: silence would look like
/// health.
class SyncErrorsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void set(String walletId, String message) {
    state = {...state, walletId: message};
  }

  void clear(String walletId) {
    if (!state.containsKey(walletId)) return;
    state = {...state}..remove(walletId);
  }
}

final syncErrorsProvider =
    NotifierProvider<SyncErrorsNotifier, Map<String, String>>(
      SyncErrorsNotifier.new,
    );
