// App state. Server state lives in providers fed by the bridge; the
// notifiers below hold only what the interface itself decides:
// preferences and sync progress.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'format.dart';
import 'models.dart';

/// The bridge to the core. Widget tests override this with a fake.
final bridgeProvider = Provider<GerfautBridge>((ref) => const RustBridge());

/// Vault settings. Invalidated after any mutation that touches them.
final settingsProvider = FutureProvider<Settings>((ref) {
  return ref.watch(bridgeProvider).getSettings();
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

/// Unspent outputs of one wallet.
final utxosProvider = FutureProvider.family<List<UtxoInfo>, String>((ref, id) {
  return ref.watch(bridgeProvider).utxos(id);
});

/// Detail of one transaction, keyed by wallet and txid.
final txDetailProvider = FutureProvider
    .family<TxDetail, ({String walletId, String txid})>((ref, key) {
      return ref.watch(bridgeProvider).txDetail(key.walletId, key.txid);
    });

/// The next unused receive address of one wallet.
final receiveProvider = FutureProvider.family<List<AddressEntry>, String>((
  ref,
  id,
) {
  return ref.watch(bridgeProvider).receiveAddresses(id, 0);
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
  bool build() => true;

  void hydrate(String? stored) {
    if (stored != null) state = stored != '0';
  }

  void set(bool enabled) {
    state = enabled;
    ref
        .read(bridgeProvider)
        .setAppPref('display.fiat', enabled ? '1' : '0')
        .catchError((_) {});
  }
}

/// Fiat display, on by default, persisted as "display.fiat".
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
    if (source != null) state = source;
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
      ref.invalidate(utxosProvider(id));
    } else {
      ref.invalidate(snapshotProvider);
      ref.invalidate(utxosProvider);
    }
    ref.invalidate(txDetailProvider);
  }

  /// Syncs one wallet. Rethrows the core error after cleanup so the
  /// caller can show it.
  Future<SyncReport?> syncWallet(String id) async {
    if (state.contains(id)) return null;
    state = {...state, id};
    try {
      return await ref.read(bridgeProvider).syncWallet(id);
    } finally {
      state = {...state}..remove(id);
      _invalidateWallet(id);
    }
  }

  /// Syncs every wallet of a network. Failures are reported per wallet
  /// inside the returned report, never thrown.
  Future<SyncAllReport?> syncAll(Network network) async {
    if (state.contains(syncAllId)) return null;
    state = {...state, syncAllId};
    try {
      return await ref.read(bridgeProvider).syncAll(network);
    } finally {
      state = {...state}..remove(syncAllId);
      _invalidateWallet(null);
    }
  }
}

final syncProvider = NotifierProvider<SyncController, Set<String>>(
  SyncController.new,
);
