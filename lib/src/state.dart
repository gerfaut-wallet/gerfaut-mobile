// App state. Server state lives in providers fed by the bridge; the
// notifiers below hold only what the interface itself decides:
// preferences and sync progress.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'format.dart';
import 'models.dart';
import 'notifications.dart';
import 'prefs.dart';

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

/// The next unused receive address of one wallet, plus up to
/// `lookahead` unused addresses past it, 200 at most: the core skips
/// one a payment already reached, and a descriptor without a wildcard
/// gives its one address alone. Peeking retires nothing.
///
/// Read afresh each time Receive opens, and again after every sync of
/// any wallet: an address a payment just reached is never offered to
/// the next payer.
final receiveProvider = FutureProvider.autoDispose
    .family<List<AddressEntry>, ({String walletId, int lookahead})>((ref, key) {
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
    ref.read(bridgeProvider).setAppPref(Pref.theme, pref.id).catchError((_) {});
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemePref>(
  ThemeNotifier.new,
);

/// What the screens hold before the vault answers. Never a default
/// anyone sees: the screens wait for the vault, which always answers
/// every preference, the ones it never stored at the core's defaults.
const _untilTheVaultAnswers = Preferences(
  unit: AmountUnit.btc,
  masked: false,
  fiat: false,
  fiatCurrency: FiatCurrency('eur'),
  priceSource: PriceSource.coingecko,
  notifyNewTx: false,
  explorerAck: false,
);

/// What became of a change shown on screen ([PreferencesNotifier.show]).
enum Shown {
  /// The vault took it.
  kept,

  /// The vault refused it twice.
  refused,

  /// A newer change of the same preference was asked before this one
  /// settled. That one says what the vault holds; this one has nothing
  /// left to say.
  overtaken,
}

/// The preferences both apps keep, as the screens show them. The core
/// holds them, with their defaults and their rules; this holds what is
/// on screen, and writes each change through, after the ones before it.
class PreferencesNotifier extends Notifier<Preferences> {
  /// The writes in flight, one after the other in the order they were
  /// made, so that each answer is the vault after the change before it.
  Future<void> _written = Future.value();

  /// How many changes were shown, and the number of the last one asked
  /// of each preference, by its name on the bridge.
  int _changes = 0;
  final Map<String, int> _lastAsked = {};

  @override
  Preferences build() => _untilTheVaultAnswers;

  void hydrate(Preferences stored) => state = stored;

  /// Writes [change] after the writes already on their way, and answers
  /// what the vault holds then.
  Future<Preferences> write(PreferencesChange change) {
    final bridge = ref.read(bridgeProvider);
    final next = _written.then((_) => bridge.setPreferences(change));
    _written = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Shows [change] at once and writes it through, a second time when
  /// the vault refuses the first. A refusal only loses the preference,
  /// never the change on screen: putting it back would undo what was
  /// asked, amounts shown again under the eye. Completes with what
  /// became of it, for a caller that has to say the vault did not take
  /// it.
  ///
  /// A change a newer one of the same preference overtook is never
  /// asked again: written after the newer one, it would undo it in the
  /// vault while the screen shows the newer. Every change shown names
  /// one preference; one that named more would be overtaken by a newer
  /// change of any of them.
  Future<Shown> show(PreferencesChange change) async {
    state = change.applyTo(state);
    final number = ++_changes;
    final names = change.toJson().keys;
    for (final name in names) {
      _lastAsked[name] = number;
    }
    bool overtaken() => names.any((name) => _lastAsked[name] != number);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0 && overtaken()) return Shown.overtaken;
      try {
        await write(change);
        return overtaken() ? Shown.overtaken : Shown.kept;
      } catch (_) {
        // Asked once more; the second refusal is the caller's to say.
      }
    }
    return overtaken() ? Shown.overtaken : Shown.refused;
  }

  /// Changes what the price is asked by, the currency or the source, and
  /// shows the pair once the vault answered with it. The core asks the
  /// price by what it stored, and stores a currency with a source that
  /// quotes it: shown before, a currency would sit for a moment beside
  /// a source the core has already moved, and the price be asked by a
  /// pair the core never had. A refusal leaves the screen as it was,
  /// which is what the vault still holds.
  Future<void> setPair(PreferencesChange change) async {
    final Preferences stored;
    try {
      stored = await write(change);
    } catch (_) {
      return;
    }
    state = state.copyWith(
      fiatCurrency: stored.fiatCurrency,
      priceSource: stored.priceSource,
    );
  }
}

final preferencesProvider = NotifierProvider<PreferencesNotifier, Preferences>(
  PreferencesNotifier.new,
);

class MaskedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(preferencesProvider.select((p) => p.masked));

  void toggle() => _save(!state);

  /// Writes the mask on screen again, after the vault refused it.
  void retry() => _save(state);

  /// Shows [masked] and writes it. The home screen widget and the
  /// notifications posted in the background read the mask from the
  /// vault: balances hidden in the app that the vault refused to keep
  /// hidden are hidden in the app only, and the screens say so until a
  /// write goes through. Only the last change asked says it: an older
  /// one that settles after it would say what the vault no longer
  /// holds.
  Future<void> _save(bool masked) async {
    // Read before the change: shown, it rebuilds this notifier, whose
    // ref then waits for the rebuild.
    final unsaved = ref.read(maskUnsavedProvider.notifier);
    final preferences = ref.read(preferencesProvider.notifier);
    final shown = await preferences.show(PreferencesChange(masked: masked));
    if (shown == Shown.overtaken) return;
    unsaved.set(masked && shown == Shown.refused);
  }
}

/// Masked balances: the eye toggle.
final maskedProvider = NotifierProvider<MaskedNotifier, bool>(
  MaskedNotifier.new,
);

class MaskUnsavedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool unsaved) => state = unsaved;
}

/// Balances are hidden in the app and the vault refused, twice, to keep
/// them hidden: see [MaskedNotifier].
final maskUnsavedProvider = NotifierProvider<MaskUnsavedNotifier, bool>(
  MaskUnsavedNotifier.new,
);

class UnitNotifier extends Notifier<AmountUnit> {
  @override
  AmountUnit build() => ref.watch(preferencesProvider.select((p) => p.unit));

  void set(AmountUnit unit) => ref
      .read(preferencesProvider.notifier)
      .show(PreferencesChange(unit: unit));
}

/// Display unit for every amount.
final unitProvider = NotifierProvider<UnitNotifier, AmountUnit>(
  UnitNotifier.new,
);

class FiatEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(preferencesProvider.select((p) => p.fiat));

  void set(bool enabled) => ref
      .read(preferencesProvider.notifier)
      .show(PreferencesChange(fiat: enabled));
}

/// Fiat display.
final fiatEnabledProvider = NotifierProvider<FiatEnabledNotifier, bool>(
  FiatEnabledNotifier.new,
);

class FiatCurrencyNotifier extends Notifier<FiatCurrency> {
  @override
  FiatCurrency build() =>
      ref.watch(preferencesProvider.select((p) => p.fiatCurrency));

  /// Shown once the vault stored it, with the source it kept beside it.
  Future<void> set(FiatCurrency currency) => ref
      .read(preferencesProvider.notifier)
      .setPair(PreferencesChange(fiatCurrency: currency));
}

/// Fiat currency.
final fiatCurrencyProvider =
    NotifierProvider<FiatCurrencyNotifier, FiatCurrency>(
      FiatCurrencyNotifier.new,
    );

class FiatSourceNotifier extends Notifier<PriceSource> {
  @override
  PriceSource build() =>
      ref.watch(preferencesProvider.select((p) => p.priceSource));

  /// Shown once the vault stored it: always one that quotes the
  /// currency.
  Future<void> set(PriceSource source) => ref
      .read(preferencesProvider.notifier)
      .setPair(PreferencesChange(priceSource: source));
}

/// Price source.
final fiatSourceProvider = NotifierProvider<FiatSourceNotifier, PriceSource>(
  FiatSourceNotifier.new,
);

class ExplorerAckNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(preferencesProvider.select((p) => p.explorerAck));

  void set(bool acknowledged) => ref
      .read(preferencesProvider.notifier)
      .show(PreferencesChange(explorerAck: acknowledged));
}

/// External explorer warning acknowledged: the dialog is skipped when
/// set. Shared with the desktop.
final explorerAckProvider = NotifierProvider<ExplorerAckNotifier, bool>(
  ExplorerAckNotifier.new,
);

/// The currencies and price sources the settings offer, and how often
/// the price is asked. The core's table: it only changes with the app.
final priceTableProvider = FutureProvider<PriceTable>((ref) {
  return ref.watch(bridgeProvider).priceTable();
});

/// Whether the app is on screen. Dart timers go on firing behind the
/// launcher for as long as Live keeps the process, so what runs on a
/// clock for the screen's sake watches this and stops while it is
/// false. Kept by the gate, from the app's lifecycle.
final appInFrontProvider = StateProvider<bool>((ref) => true);

/// Ticks every 30 seconds while the app is on screen. The lines that
/// say how long ago something was, "Synced 5 min ago", are worked out
/// when they are drawn: watching this draws them again, so a page left
/// open does not say "just now" three hours later. Back on screen it
/// ticks at once.
class RelativeClock extends Notifier<int> {
  Timer? _timer;

  /// A count, not the time: every build and every tick must change the
  /// value, or the lines that watch it are not drawn again. Two builds
  /// within one millisecond would read the same time.
  int _beats = 0;

  @override
  int build() {
    _timer?.cancel();
    final inFront = ref.watch(appInFrontProvider);
    ref.onDispose(() => _timer?.cancel());
    if (inFront) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => state = ++_beats,
      );
    }
    return ++_beats;
  }
}

final relativeClockProvider = NotifierProvider<RelativeClock, int>(
  RelativeClock.new,
);

/// Current BTC price, in the currency and from the source of the
/// preferences, asked again at the core's cadence while fiat display is
/// on and the app is on screen. Failures surface as an error state:
/// amounts degrade to no fiat and the settings screen shows a quiet
/// hint.
class PriceNotifier extends AsyncNotifier<PriceQuote?> {
  Timer? _timer;

  @override
  Future<PriceQuote?> build() async {
    _timer?.cancel();
    final enabled = ref.watch(fiatEnabledProvider);
    // Asked again when the pair changes, which the screens only take
    // once the vault stored it: the core prices by what it stored.
    ref.watch(fiatCurrencyProvider);
    ref.watch(fiatSourceProvider);
    final inFront = ref.watch(appInFrontProvider);
    if (!enabled) return null;
    // Out of sight nothing is asked, and no clock runs: the quote in
    // hand stays, and a fresh one is asked the moment the app is back.
    // A failure stands too: returned as a value, the quote it had
    // hidden would come back on every amount as if it were fresh.
    if (!inFront) {
      final kept = state;
      if (kept.hasError) {
        Error.throwWithStackTrace(
          kept.error!,
          kept.stackTrace ?? StackTrace.current,
        );
      }
      return kept.valueOrNull;
    }
    ref.onDispose(() => _timer?.cancel());
    final every = (await ref.read(priceTableProvider.future)).refresh;
    // Scheduled before the fetch so failures retry on the same cadence.
    _timer = Timer(every, () => ref.invalidateSelf());
    return ref.read(bridgeProvider).fetchPrice();
  }
}

final priceProvider = AsyncNotifierProvider<PriceNotifier, PriceQuote?>(
  PriceNotifier.new,
);

/// The transactions this app sent on a network, newest first, as the
/// vault keeps them, so the broadcast screen can check on them again
/// after a restart.
class RecentBroadcastsNotifier
    extends FamilyAsyncNotifier<List<RecentBroadcast>, Network> {
  @override
  Future<List<RecentBroadcast>> build(Network network) =>
      ref.watch(bridgeProvider).recentBroadcasts(network);

  /// Reads the list again, once the vault has kept a transaction sent.
  void reload() => ref.invalidateSelf();

  /// Drops the record of a broadcast, with no way back. Only this app's
  /// own note of it goes: the transaction is on the network, where
  /// Gerfaut has never had any say. A vault that cannot write keeps it,
  /// and the list read again says so.
  Future<void> forget(String txid) async {
    try {
      await ref.read(bridgeProvider).forgetBroadcast(txid);
    } on BridgeException {
      // Said by the list itself, which still holds it.
    }
    ref.invalidateSelf();
  }
}

final recentBroadcastsProvider =
    AsyncNotifierProvider.family<
      RecentBroadcastsNotifier,
      List<RecentBroadcast>,
      Network
    >(RecentBroadcastsNotifier.new);

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
    // Keyed by wallet and lookahead: every address on offer is read
    // again, since the one shown may be the one just paid.
    ref.invalidate(receiveProvider);
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
