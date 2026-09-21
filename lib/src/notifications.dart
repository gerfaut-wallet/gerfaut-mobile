// Local notifications: what Gerfaut says when a sync finds a
// transaction it had not seen. Composed here, posted by the platform,
// and sent nowhere: the only traffic is the sync itself.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'bridge.dart';
import 'disguise.dart';
import 'format.dart';
import 'live.dart';
import 'models.dart';
import 'state.dart';

/// Posts notifications on this device. Widget tests substitute a
/// recording fake so no test ever reaches the platform.
abstract class NotificationService {
  Future<void> init();

  /// Asks the system for leave to notify. Android 13 and later put the
  /// question to the user; earlier versions answer for them.
  Future<bool> requestPermission();

  /// Posts a notification, replacing the one already up under [id].
  Future<void> show(int id, String title, String body);
}

/// The one channel Gerfaut posts on; the user tunes or silences it
/// from the system settings.
const String transactionsChannelId = 'transactions';
const String _transactionsChannelName = 'Transactions';

/// The service of the real app, on flutter_local_notifications.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        transactionsChannelId,
        _transactionsChannelName,
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _android;
    if (android == null) return true;
    // Before Android 13 there is no question to put: the answer is
    // whatever the user set for the app, on unless they turned it off.
    return await android.requestNotificationsPermission() ??
        await android.areNotificationsEnabled() ??
        true;
  }

  @override
  Future<void> show(int id, String title, String body) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          transactionsChannelId,
          _transactionsChannelName,
          importance: Importance.defaultImportance,
          // The phone's own lock screen shows the title, never the
          // amount: an app that hides balances behind a PIN cannot
          // print them where anyone walking past can read them.
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);

// --- what is said ------------------------------------------------------

/// One notification, ready to post.
class TxNotice {
  const TxNotice({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;
}

/// Transactions said one by one for a wallet in one sync; the rest are
/// counted in a single line.
const int noticesPerWallet = 3;

/// FNV-1a over the text, kept to 31 bits. The same transaction gets the
/// same id from any isolate on any run, so a repeat replaces the
/// notification instead of stacking another.
int noticeId(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Composes and posts what a batch of announcements amounts to.
///
/// What it is handed are [LiveTx]: transactions the core gave out once,
/// at one stage, to whoever asked first. The live watch hands them as
/// events; a sync of the app's own gets them from
/// [GerfautBridge.claimAnnouncements]. Either way nothing is said twice.
class NewTxAnnouncer {
  const NewTxAnnouncer(this.service);

  final NotificationService service;

  /// One notice per transaction up to [noticesPerWallet] a wallet, then
  /// one line counting the rest. A payment that is no longer coming is
  /// always said on its own, never folded into the count: it takes back
  /// what an earlier notice promised. Pure: the same transactions,
  /// names, unit and mask always say the same.
  ///
  /// Every notice about one transaction carries its id, so the
  /// confirmation, or the news that it is not coming, takes the place
  /// of the arrival instead of stacking under it.
  static List<TxNotice> compose(
    List<LiveTx> txs, {
    required Map<String, String> walletNames,
    required AmountUnit unit,
    required bool masked,
  }) {
    final byWallet = <String, List<LiveTx>>{};
    for (final tx in txs) {
      byWallet.putIfAbsent(tx.walletId, () => []).add(tx);
    }
    final notices = <TxNotice>[];
    for (final MapEntry(key: walletId, value: mine) in byWallet.entries) {
      final title = walletNames[walletId] ?? walletId;
      TxNotice notice(LiveTx tx) => TxNotice(
        id: noticeId(tx.txid),
        title: title,
        body: _describe(tx, unit: unit, masked: masked),
      );
      final moved = [
        for (final tx in mine)
          if (tx.stage != TxStage.dropped) tx,
      ];
      notices.addAll(moved.take(noticesPerWallet).map(notice));
      final rest = moved.length - noticesPerWallet;
      if (rest > 0) {
        notices.add(
          TxNotice(
            id: noticeId('more:$walletId'),
            title: title,
            body: _plural(rest, 'more new transaction'),
          ),
        );
      }
      notices.addAll([
        for (final tx in mine)
          if (tx.stage == TxStage.dropped) notice(tx),
      ]);
    }
    return notices;
  }

  /// Posts what [compose] says about the transactions.
  Future<void> announce(
    List<LiveTx> txs, {
    required Map<String, String> walletNames,
    required AmountUnit unit,
    required bool masked,
  }) async {
    final notices = compose(
      txs,
      walletNames: walletNames,
      unit: unit,
      masked: masked,
    );
    for (final notice in notices) {
      await service.show(notice.id, notice.title, notice.body);
    }
  }
}

/// A balance change is stated, never celebrated: an amount, a
/// direction, and whether the chain has it yet.
String _describe(LiveTx tx, {required AmountUnit unit, required bool masked}) {
  final sats = tx.netSats;
  if (tx.stage == TxStage.dropped) {
    return masked
        ? 'A pending payment is no longer coming'
        : 'A pending payment of ${formatAmount(sats.abs(), unit)} is no '
              'longer coming';
  }
  final what = switch ((masked, sats)) {
    (_, 0) => 'New transaction',
    (true, > 0) => 'New transaction',
    (true, _) => 'New outgoing transaction',
    (false, > 0) => 'Received ${formatAmount(sats, unit)}',
    (false, _) => '${formatAmount(-sats, unit)} left this wallet',
  };
  return tx.stage == TxStage.confirmed
      ? '$what · confirmed'
      : '$what · pending';
}

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

/// Whether a notification may carry an amount: never while balances are
/// masked, and never while an app lock exists. A notification is read
/// from outside the lock, by whoever holds the phone.
bool amountsHidden(Settings settings) =>
    settings.appPrefs['mobile.masked'] == '1' || settings.appLock != null;

/// What the syncs behind these reports found that nobody has announced
/// yet, in order, taken off the core's record. Every wallet is asked,
/// the reports that list nothing included: a sync that ran for another
/// caller at the same moment may have left its news under this one.
/// Whoever calls this announces what it returns, or drops it on
/// purpose; nothing returned here is ever returned again.
Future<List<LiveTx>> claimAll(
  GerfautBridge bridge,
  Iterable<SyncReport> reports,
) async {
  final claimed = <LiveTx>[];
  final asked = <String>{};
  for (final report in reports) {
    if (!asked.add(report.walletId)) continue;
    claimed.addAll(await bridge.claimAnnouncements(report.walletId));
  }
  return claimed;
}

final newTxAnnouncerProvider = Provider<NewTxAnnouncer>(
  (ref) => NewTxAnnouncer(ref.watch(notificationServiceProvider)),
);

/// The open app's side of it. Every sync the screens run is claimed,
/// then said with the names, unit and mask the screen shows, or
/// dropped when nothing may be said: the notice is off, or the app is
/// disguised.
///
/// A wallet's first sync says nothing: the core records none of an
/// import's history as news, so there is nothing to leave out here.
class SyncAnnouncer {
  const SyncAnnouncer(this._ref);

  final Ref _ref;

  Future<void> announce(List<SyncReport> reports) async {
    if (reports.isEmpty) return;
    final List<LiveTx> claimed;
    try {
      claimed = await claimAll(_ref.read(bridgeProvider), reports);
    } catch (_) {
      // A claim that failed took nothing: the next one gets it.
      return;
    }
    if (claimed.isEmpty) return;
    if (!_ref.read(notifyNewTxProvider)) return;
    // Nothing is posted while disguised: a notification's header carries
    // the app's name, and a "Gerfaut" line over a calculator would tell
    // everything the disguise hides.
    if (_ref.read(disguiseProvider).disguised) return;
    try {
      final wallets =
          _ref.read(walletsProvider).valueOrNull ??
          await _ref.read(bridgeProvider).listWallets();
      final lock = _ref.read(settingsProvider).valueOrNull?.appLock;
      await _ref
          .read(newTxAnnouncerProvider)
          .announce(
            claimed,
            walletNames: {for (final w in wallets) w.id: w.name},
            unit: _ref.read(unitProvider),
            masked: _ref.read(maskedProvider) || lock != null,
          );
    } catch (_) {
      // A notification that cannot be posted is not a failed sync.
    }
  }
}

final syncAnnouncerProvider = Provider<SyncAnnouncer>(
  (ref) => SyncAnnouncer(ref),
);

// --- preferences -------------------------------------------------------

class NotifyNewTxNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    // Only an explicit "1" turns it on: notifications are opt-in.
    state = stored == '1';
  }

  /// Turning it on asks the system first; a refusal leaves it off and
  /// is said on screen rather than pretended away.
  Future<void> set(bool on) async {
    if (on) {
      final granted = await ref
          .read(notificationServiceProvider)
          .requestPermission();
      ref.read(notificationsRefusedProvider.notifier).state = !granted;
      if (!granted) return;
    }
    state = on;
    ref
        .read(bridgeProvider)
        .setAppPref('notify.new_tx', on ? '1' : '0')
        .catchError((_) {});
    final cadence = ref.read(backgroundCheckProvider);
    await rescheduleBackgroundCheck(
      ref,
      notifying: on,
      seconds: cadence.seconds,
    );
    // With nothing to say there is nothing to watch for: Live follows
    // the notice off, and back on.
    await ref
        .read(liveProvider.notifier)
        .apply(wanted: on && cadence == BackgroundCheck.live);
  }
}

/// The new-transaction notice, off by default, persisted as
/// "notify.new_tx".
final notifyNewTxProvider = NotifierProvider<NotifyNewTxNotifier, bool>(
  NotifyNewTxNotifier.new,
);

/// The system refused notifications the last time the toggle asked.
final notificationsRefusedProvider = StateProvider<bool>((ref) => false);

/// How Gerfaut looks for transactions while it is off screen. What the
/// preference stores is [stored]: the seconds of a periodic check, or
/// `live`.
enum BackgroundCheck {
  off('0', 0, 'Off'),

  /// A connection kept open by a foreground service. The periodic check
  /// stays scheduled under it, at the shortest cadence Android grants:
  /// whenever Live cannot run, that is what is left.
  live('live', 900, 'Live'),
  quarterHour('900', 900, 'Every 15 min'),
  hour('3600', 3600, 'Every hour'),
  sixHours('21600', 21600, 'Every 6 hours');

  const BackgroundCheck(this.stored, this.seconds, this.label);

  final String stored;

  /// The cadence of the periodic task, zero for none.
  final int seconds;
  final String label;

  static BackgroundCheck? fromStored(String? stored) {
    for (final check in BackgroundCheck.values) {
      if (check.stored == stored) return check;
    }
    return null;
  }
}

class BackgroundCheckNotifier extends Notifier<BackgroundCheck> {
  @override
  BackgroundCheck build() => BackgroundCheck.off;

  void hydrate(String? stored) {
    final check = BackgroundCheck.fromStored(stored);
    if (check != null) state = check;
  }

  /// Persists the choice, brings the periodic task in line, and starts
  /// or stops the Live service to match. Choosing Live from the settings
  /// goes through the explanation sheet first; this is what the sheet
  /// calls once the user has said yes.
  Future<void> set(BackgroundCheck check) async {
    state = check;
    ref
        .read(bridgeProvider)
        .setAppPref('notify.background', check.stored)
        .catchError((_) {});
    final notifying = ref.read(notifyNewTxProvider);
    await rescheduleBackgroundCheck(
      ref,
      notifying: notifying,
      seconds: check.seconds,
    );
    await ref
        .read(liveProvider.notifier)
        .apply(wanted: notifying && check == BackgroundCheck.live);
  }
}

/// The background cadence, off by default, persisted as
/// "notify.background".
final backgroundCheckProvider =
    NotifierProvider<BackgroundCheckNotifier, BackgroundCheck>(
      BackgroundCheckNotifier.new,
    );

/// Registers the periodic task at a cadence, or cancels it at zero.
typedef BackgroundScheduler = Future<void> Function(int seconds);

/// The real app schedules with the system; tests record the calls.
final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => registerBackgroundCheck,
);

/// Brings the task in line with both preferences: it runs at the chosen
/// cadence only while the notice is on, so nothing is fetched for
/// nothing. Both values are passed in — a notifier that read them back
/// through its own provider would be reading itself.
Future<void> rescheduleBackgroundCheck(
  Ref ref, {
  required bool notifying,
  required int seconds,
}) {
  final wanted = notifying ? seconds : 0;
  return ref.read(backgroundSchedulerProvider)(wanted).catchError((_) {});
}
