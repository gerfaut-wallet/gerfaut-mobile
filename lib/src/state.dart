// App state. Server state lives in providers fed by the bridge; the
// notifiers below hold only what the interface itself decides:
// preferences and sync progress.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
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
