// App state. Server state lives in providers fed by the bridge; the
// notifiers below hold only what the interface itself decides:
// preferences and sync progress.

import 'dart:async';

import 'package:flutter/foundation.dart' show protected;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'format.dart';
import 'models.dart';
import 'notifications.dart';
import 'prefs.dart';

/// The bridge to the core. Widget tests override this with a fake.
final bridgeProvider = Provider<GerfautBridge>((ref) => const RustBridge());

/// No provider asks again by itself after a failure: each one says it
/// failed, at once, and is asked again by a person or by its own clock.
/// Riverpod's own retries would reach a server again behind the
/// screen's back, and hold a failure as "loading" for half a minute.
Duration? noRetry(int retryCount, Object error) => null;

/// A plain value the app sets from outside its provider: a flag, a
/// note. Listeners hear of a new value only when it differs.
class Slot<T> extends Notifier<T> {
  Slot(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void put(T value) => state = value;
}

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
  // Watched before the wait: once the settings change, this build is
  // over and its ref may no longer be used.
  final bridge = ref.watch(bridgeProvider);
  final settings = await ref.watch(settingsProvider.future);
  return bridge.listWallets(settings.activeNetwork);
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

class ThemeNotifier extends VaultPrefNotifier<ThemePref> {
  @override
  VaultPref<ThemePref> get pref => AppPref.theme;
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
  priceSource: PriceSource.mempoolSpace,
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

/// The preference writes of the screens, the ones both apps keep and
/// the ones of this app alone: one after the other, in the order they
/// were asked, so that each answer is the vault after the change before
/// it. The one way a change shown on screen settles. What the app
/// writes on its own, never shown as a choice (the biometric lack), goes
/// around it.
class VaultWrites {
  Future<void> _written = Future.value();
  Future<void> _followed = Future.value();

  /// How many changes were asked, and the number of the last one asked
  /// of each preference, by its name.
  int _changes = 0;
  final Map<String, int> _lastAsked = {};

  /// Runs [write] after the writes already on their way.
  Future<R> queue<R>(Future<R> Function() write) {
    final next = _written.then((_) => write());
    _written = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Runs what follows a settled change, the periodic task and Live,
  /// after what followed the changes settled before it: each step
  /// awaits the platform, and two of them side by side could land a
  /// start after the stop that came later.
  Future<void> follow(Future<void> Function() step) {
    final next = _followed.then((_) => step());
    _followed = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Writes a change of the preferences [names] after the writes on
  /// their way, a second time when the vault refuses the first, and
  /// says what became of it.
  ///
  /// A change a newer one of the same preference overtook is never
  /// asked again: written after the newer one, it would undo it in the
  /// vault while the screen shows the newer.
  Future<Shown> persist(
    List<String> names,
    Future<void> Function() write,
  ) async {
    final number = ++_changes;
    for (final name in names) {
      _lastAsked[name] = number;
    }
    bool overtaken() => names.any((name) => _lastAsked[name] != number);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0 && overtaken()) return Shown.overtaken;
      try {
        await queue(write);
        return overtaken() ? Shown.overtaken : Shown.kept;
      } catch (_) {
        // Asked once more; the second refusal is the caller's to say.
      }
    }
    return overtaken() ? Shown.overtaken : Shown.refused;
  }
}

final vaultWritesProvider = Provider<VaultWrites>((ref) => VaultWrites());

/// The preferences both apps keep, as the screens show them. The core
/// holds them, with their defaults and their rules; this holds what is
/// on screen, and writes each change through, after the ones before it.
class PreferencesNotifier extends Notifier<Preferences> {
  /// What the vault last said it holds: at start, then at each write
  /// it took. A change it refused is put back at this.
  Preferences _stored = _untilTheVaultAnswers;

  @override
  Preferences build() => _untilTheVaultAnswers;

  void hydrate(Preferences stored) => state = _stored = stored;

  /// Writes [change] after the writes already on their way, and answers
  /// what the vault holds then.
  Future<Preferences> write(PreferencesChange change) {
    final write = _writer(change);
    return ref.read(vaultWritesProvider).queue(write);
  }

  Future<Preferences> Function() _writer(PreferencesChange change) {
    final bridge = ref.read(bridgeProvider);
    return () async => _stored = await bridge.setPreferences(change);
  }

  /// Shows [change] at once and writes it through, a second time when
  /// the vault refuses the first. A refusal leaves the change on
  /// screen, which the mask needs: amounts never shown again under the
  /// eye. Every other preference goes through [offer]. Completes
  /// with what became of it, for a caller that has to say the vault did
  /// not take it.
  ///
  /// Every change shown names one preference; one that named more would
  /// be overtaken by a newer change of any of them.
  Future<Shown> show(PreferencesChange change) {
    state = change.applyTo(state);
    final names = change.toJson().keys.toList();
    return ref.read(vaultWritesProvider).persist(names, _writer(change));
  }

  /// What the vault last said it holds.
  Preferences get stored => _stored;

  /// Shows [change] and writes it, and puts it back at what the vault
  /// holds when the vault refuses it twice: the background notices read
  /// the vault, and a choice it does not hold would be on screen only.
  /// Every preference but the mask, which stays on ([show]).
  Future<Shown> offer(PreferencesChange change) async {
    final shown = await show(change);
    if (shown == Shown.refused && ref.mounted) {
      state = change.heldIn(_stored).applyTo(state);
    }
    return shown;
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

/// A preference of this app alone, as the screens show it. Each change
/// is shown at once and written through; one the vault refuses twice
/// goes back to what the vault holds. The periodic task, Live and the
/// widgets read the vault, not the screen: a switch the vault does not
/// hold would promise what none of them does.
abstract class VaultPrefNotifier<T> extends Notifier<T> {
  VaultPref<T> get pref;

  /// What the vault last said it holds: at start, then at each write it
  /// took.
  late T _stored;

  T get stored => _stored;

  @override
  T build() => _stored = decode(null);

  void hydrate(String? stored) => state = _stored = decode(stored);

  /// What [stored] reads as on this phone: the rule of [pref], unless
  /// a value the vault may hold stands for something this system does
  /// not offer. A vault travels between phones in a backup.
  @protected
  T decode(String? stored) => pref.decode(stored);

  /// Shows [value] and writes it, and answers what became of it: a
  /// refusal puts the screen back at what the vault holds.
  Future<Shown> set(T value) async {
    final shown = await persist(value);
    if (shown == Shown.refused && ref.mounted) state = _stored;
    return shown;
  }

  /// Shows [value] and writes it, and leaves it on screen whatever the
  /// vault answers.
  Future<Shown> persist(T value) {
    state = value;
    final bridge = ref.read(bridgeProvider);
    return ref.read(vaultWritesProvider).persist([pref.key], () async {
      await bridge.setAppPref(pref.key, pref.encode(value));
      _stored = value;
    });
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
      .offer(PreferencesChange(unit: unit));
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
      .offer(PreferencesChange(fiat: enabled));
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
      .offer(PreferencesChange(explorerAck: acknowledged));
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
final appInFrontProvider = NotifierProvider<Slot<bool>, bool>(() => Slot(true));

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
  int _builds = 0;

  @override
  Future<PriceQuote?> build() async {
    _timer?.cancel();
    final build = ++_builds;
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
      return kept.value;
    }
    ref.onDispose(() => _timer?.cancel());
    final every = (await ref.read(priceTableProvider.future)).refresh;
    // A newer build began during the wait: its clock is the one that
    // runs, and what this one returns is dropped.
    if (build != _builds) return state.value;
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
class RecentBroadcastsNotifier extends AsyncNotifier<List<RecentBroadcast>> {
  RecentBroadcastsNotifier(this.network);

  final Network network;

  @override
  Future<List<RecentBroadcast>> build() =>
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
final prefsHydratedProvider = NotifierProvider<Slot<bool>, bool>(
  () => Slot(false),
);
final autoSyncedProvider = NotifierProvider<Slot<bool>, bool>(
  () => Slot(false),
);

// --- sync --------------------------------------------------------------

/// Where the sync of one wallet stands, as the screens show it.
sealed class WalletSyncState {
  const WalletSyncState();
}

/// No sync of the wallet runs, and the last one did not fail.
final class WalletSyncIdle extends WalletSyncState {
  const WalletSyncIdle();
}

/// A sync of the wallet runs.
final class WalletSyncing extends WalletSyncState {
  const WalletSyncing({this.ticket, this.previousFailure});

  /// The ticket this app gave the sync it started, which its answer
  /// must still match to be heard; null for a sync the core said runs,
  /// which only the core settles.
  final int? ticket;

  /// The failure the wallet showed before this sync: until it ends, the
  /// figure on screen is still the one that failure left.
  final String? previousFailure;
}

/// No sync of the wallet runs, and the last one failed, in these words.
final class WalletSyncFailed extends WalletSyncState {
  const WalletSyncFailed(this.message);

  final String message;
}

/// Where the sync of every wallet stands, and the sync of every wallet
/// this app runs, when one runs.
class WalletSyncs {
  const WalletSyncs({this.wallets = const {}, this.syncingAll});

  /// By wallet id; a wallet not in it is idle.
  final Map<String, WalletSyncState> wallets;

  /// The ticket of the sync of every wallet this app runs, or null.
  final int? syncingAll;

  WalletSyncState of(String walletId) =>
      wallets[walletId] ?? const WalletSyncIdle();

  /// Whether a sync covers the wallet: one of its own, from any source,
  /// or a sync of every wallet.
  bool isSyncing(String walletId) =>
      syncingAll != null || of(walletId) is WalletSyncing;

  /// Whether a sync covers any of `walletIds`, the wallets on screen:
  /// the core also says the syncs of other networks' wallets.
  bool syncingAnyOf(Iterable<String> walletIds) =>
      syncingAll != null || walletIds.any(isSyncing);

  /// The failure the wallet shows: its last sync's, still shown while a
  /// new one runs. Null when the last one did not fail.
  String? failureOf(String walletId) => switch (of(walletId)) {
    WalletSyncFailed(:final message) => message,
    WalletSyncing(:final previousFailure) => previousFailure,
    WalletSyncIdle() => null,
  };

  WalletSyncs _with(
    Map<String, WalletSyncState> changed, {
    int? Function()? syncingAll,
  }) => WalletSyncs(
    wallets: {...wallets, ...changed},
    syncingAll: syncingAll == null ? this.syncingAll : syncingAll(),
  );
}

/// What moves the sync of a wallet: a sync this app starts or ends, and
/// what the core tells of every sync, whoever started it.
sealed class SyncChange {
  const SyncChange();
}

/// This app starts a sync of one wallet, under [ticket].
final class SyncStarted extends SyncChange {
  const SyncStarted(this.walletId, this.ticket);

  final String walletId;
  final int ticket;
}

/// The answer of the sync this app started under [ticket]: [failure]
/// in the screens' words, or null when it succeeded.
final class SyncEnded extends SyncChange {
  const SyncEnded(this.walletId, this.ticket, this.failure);

  final String walletId;
  final int ticket;
  final String? failure;
}

/// This app starts a sync of every wallet of a network, under [ticket].
final class SyncAllStarted extends SyncChange {
  const SyncAllStarted(this.ticket);

  final int ticket;
}

/// The answer of the sync of every wallet started under [ticket]: for
/// each wallet it synced, its failure in the screens' words, or null.
final class SyncAllEnded extends SyncChange {
  const SyncAllEnded(this.ticket, this.outcomes);

  final int ticket;
  final Map<String, String?> outcomes;
}

/// The core says a sync of the wallet runs.
final class CoreSyncStarted extends SyncChange {
  const CoreSyncStarted(this.walletId);

  final String walletId;
}

/// The live watch says how a sync it ran ended: [failure] in the
/// screens' words, or null for a good one. It comes apart from the
/// core's own changes, in no set order with them, and never says
/// whether a sync runs: heard only while none of the wallet does.
final class LiveSyncHeard extends SyncChange {
  const LiveSyncHeard(this.walletId, this.failure);

  final String walletId;
  final String? failure;
}

/// The core's changes stopped coming: a wallet only the core said
/// syncs goes back to where it stood before, since nothing would say
/// where that sync ended; the next listener reads them all again.
final class CoreSyncLost extends SyncChange {
  const CoreSyncLost();
}

/// The core says where the wallet stands once no sync of it runs:
/// [failure] in the screens' words, or null when the last one did not
/// fail.
final class CoreSyncSettled extends SyncChange {
  const CoreSyncSettled(this.walletId, this.failure);

  final String walletId;
  final String? failure;
}

/// The one way the sync of a wallet moves.
///
/// The core sees every sync, the app's own included, so what it tells
/// wins: a sync it says runs takes the place of the app's ticket, and
/// where it says a wallet stands settles it. The answer of a sync this
/// app started is heard only while its ticket is still the wallet's;
/// once replaced, it is stale and changes nothing. The answer of a
/// sync of every wallet leaves alone a wallet whose own sync runs: that
/// one says where it ends.
WalletSyncs nextSyncs(WalletSyncs syncs, SyncChange change) {
  WalletSyncState settled(String? failure) =>
      failure == null ? const WalletSyncIdle() : WalletSyncFailed(failure);
  switch (change) {
    case SyncStarted(:final walletId, :final ticket):
      if (syncs.of(walletId) case WalletSyncing(ticket: _?)) return syncs;
      return syncs._with({
        walletId: WalletSyncing(
          ticket: ticket,
          previousFailure: syncs.failureOf(walletId),
        ),
      });
    case SyncEnded(:final walletId, :final ticket, :final failure):
      final current = syncs.of(walletId);
      if (current is! WalletSyncing || current.ticket != ticket) return syncs;
      return syncs._with({walletId: settled(failure)});
    case SyncAllStarted(:final ticket):
      if (syncs.syncingAll != null) return syncs;
      return syncs._with(const {}, syncingAll: () => ticket);
    case SyncAllEnded(:final ticket, :final outcomes):
      if (syncs.syncingAll != ticket) return syncs;
      return syncs._with({
        for (final MapEntry(key: id, value: failure) in outcomes.entries)
          if (syncs.of(id) is! WalletSyncing) id: settled(failure),
      }, syncingAll: () => null);
    case CoreSyncStarted(:final walletId):
      return syncs._with({
        walletId: WalletSyncing(previousFailure: syncs.failureOf(walletId)),
      });
    case CoreSyncSettled(:final walletId, :final failure):
      return syncs._with({walletId: settled(failure)});
    case CoreSyncLost():
      return syncs._with({
        for (final MapEntry(key: id, value: state) in syncs.wallets.entries)
          if (state case WalletSyncing(ticket: null, :final previousFailure))
            id: settled(previousFailure),
      });
    case LiveSyncHeard(:final walletId, :final failure):
      if (syncs.of(walletId) is WalletSyncing) return syncs;
      return syncs._with({walletId: settled(failure)});
  }
}

/// The change a word of the core makes, its failure in the screens'
/// words.
SyncChange _toldBy(WalletSync told) => switch (told.state) {
  CoreSyncRunning() => CoreSyncStarted(told.walletId),
  CoreSyncIdle() => CoreSyncSettled(told.walletId, null),
  CoreSyncFailed(:final kind, :final message) => CoreSyncSettled(
    told.walletId,
    reportedFailure(kind, message),
  ),
};

/// Where the sync of each wallet stands, and the syncs this app runs;
/// invalidates what a sync changes.
class SyncController extends Notifier<WalletSyncs> {
  StreamSubscription<WalletSync>? _changes;

  /// The ticket of the last sync this app started.
  int _tickets = 0;

  @override
  WalletSyncs build() {
    ref.onDispose(() {
      _changes?.cancel();
      _changes = null;
    });
    return const WalletSyncs();
  }

  /// The only writer of the state.
  void _apply(SyncChange change) {
    state = nextSyncs(state, change);
  }

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

  /// Listens to where the core says each wallet's sync stands: every
  /// wallet first, a failure the vault kept from before a restart among
  /// them, then each change, whoever runs the sync. Called when the
  /// screens start listening to the core, and each time the app comes
  /// back on screen; nothing more while it already listens.
  void listen() {
    if (_changes != null) return;
    void lost() {
      _changes = null;
      _apply(const CoreSyncLost());
    }

    _changes = ref
        .read(bridgeProvider)
        .syncChanges()
        .listen(
          (told) => _apply(_toldBy(told)),
          onError: (_) {},
          // The core's side never ends but on a failure: the next time
          // the app comes on screen listens anew.
          onDone: lost,
        );
  }

  /// A sync that did not start here changed this wallet: the live
  /// watch saw it move and synced it in the core.
  void refreshed(String walletId) => _invalidateWallet(walletId);

  /// A sync that did not start here ended: the live watch saw the
  /// wallet move and synced it in the core. [failure] is its failure in
  /// the screens' words, or null when it succeeded.
  void syncedElsewhere(String walletId, {String? failure}) =>
      _apply(LiveSyncHeard(walletId, failure));

  /// Runs one wallet operation with the sync bookkeeping: the wallet is
  /// marked in flight under a ticket of its own, the answer settles it
  /// if that ticket is still the wallet's, and what the operation
  /// changed is refreshed. Null when [refused] says a sync running now
  /// stands in for it.
  Future<SyncReport?> _run(
    String id,
    Future<SyncReport> Function(GerfautBridge bridge) operation, {
    required bool Function(WalletSyncs syncs) refused,
  }) async {
    if (refused(state)) return null;
    final ticket = ++_tickets;
    _apply(SyncStarted(id, ticket));
    String? failure;
    try {
      final report = await operation(ref.read(bridgeProvider));
      // Said after the fact, never in place of it: a notification that
      // cannot be posted must not look like a failed sync.
      await ref.read(syncAnnouncerProvider).announce([report]);
      return report;
    } catch (error) {
      failure = syncFailure(error);
      rethrow;
    } finally {
      _apply(SyncEnded(id, ticket, failure));
      _invalidateWallet(id);
    }
  }

  /// Syncs one wallet. Rethrows the core error after cleanup so the
  /// caller can show it; the failure also lands in [syncErrorsProvider].
  Future<SyncReport?> syncWallet(String id) => _run(
    id,
    (bridge) => bridge.syncWallet(id),
    // Any sync of the wallet, or of every wallet, reads what this
    // one would.
    refused: (syncs) => syncs.isSyncing(id),
  );

  /// Scans one wallet again from its first address, with the same
  /// bookkeeping as [syncWallet].
  Future<SyncReport?> rescanWallet(String id) => _run(
    id,
    (bridge) => bridge.rescanWallet(id),
    // A rescan reads from the first address, which no routine sync
    // does: only a sync or rescan this app already runs of the
    // wallet stands in for it.
    refused: (syncs) => switch (syncs.of(id)) {
      WalletSyncing(ticket: _?) => true,
      _ => false,
    },
  );

  /// Syncs every wallet of a network. Failures are reported per wallet
  /// inside the returned report, never thrown. Null while one already
  /// runs.
  Future<SyncAllReport?> syncAll(Network network) async {
    if (state.syncingAll != null) return null;
    final ticket = ++_tickets;
    _apply(SyncAllStarted(ticket));
    var outcomes = const <String, String?>{};
    try {
      final report = await ref.read(bridgeProvider).syncAll(network);
      outcomes = {
        for (final sync in report.reports) sync.walletId: null,
        for (final failure in report.failures)
          failure.walletId: reportedFailure(failure.kind, failure.message),
      };
      await ref.read(syncAnnouncerProvider).announce(report.reports);
      return report;
    } finally {
      _apply(SyncAllEnded(ticket, outcomes));
      _invalidateWallet(null);
    }
  }
}

final syncProvider = NotifierProvider<SyncController, WalletSyncs>(
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

/// Last sync failure per wallet id, cleared on the next success, and
/// still there while a new sync runs. A failed sync is stated with its
/// reason: silence would look like health. Read from [syncProvider],
/// which alone writes it.
final syncErrorsProvider = Provider<Map<String, String>>((ref) {
  final syncs = ref.watch(syncProvider);
  return {for (final id in syncs.wallets.keys) id: ?syncs.failureOf(id)};
});
