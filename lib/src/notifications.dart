// Local notifications: what Gerfaut says when a sync finds a
// transaction it had not seen. Composed by the core, posted by the
// platform, and sent nowhere: the only traffic is the sync itself.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'bridge.dart';
import 'disguise.dart';
import 'live.dart';
import 'models.dart';
import 'state.dart';
import 'prefs.dart';

/// Posts notifications on this device. Widget tests substitute a
/// recording fake so no test ever reaches the platform.
abstract class NotificationService {
  Future<void> init();

  /// Asks the system for leave to notify. Android 13 and later put the
  /// question to the user; earlier versions answer for them.
  Future<bool> requestPermission();

  /// Posts a notification, replacing the one already up under [id].
  Future<void> show(int id, String title, String body);

  /// Whether what is posted reaches the user right now: the app's
  /// notifications allowed, and its transactions channel not silenced.
  /// Both are changed in the system settings, behind the app's back.
  Future<bool> deliverable();

  /// Takes every notification the app has posted off the screen.
  Future<void> cancelAll();
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
  Future<bool> deliverable() async {
    await init();
    final android = _android;
    if (android == null) return true;
    if (await android.areNotificationsEnabled() == false) return false;
    final channels = await android.getNotificationChannels() ?? const [];
    for (final channel in channels) {
      if (channel.id == transactionsChannelId) {
        return channel.importance != Importance.none;
      }
    }
    return true;
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
          // Private: on a phone set to hide sensitive content on its
          // lock screen, only the app's name shows there. On one set to
          // show everything, the text shows as written, which is why
          // it names no wallet and no amount once the user says so,
          // and carries no amount while balances are hidden.
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }

  /// Every notification of the app, whichever isolate posted it. Not
  /// the one of a foreground service still running: Android keeps it
  /// until the service stops.
  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);

// --- what is said ------------------------------------------------------

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

/// The id Android posts [notice] under. Every notice about one payment
/// shares one, the wallet included, so the confirmation, a fee bump's
/// included, or the news that it is not coming takes the place of the
/// arrival; a payment between two watched wallets is said in each. The
/// line that counts the rest of a wallet's sync takes the place of the
/// last one, and so does the line that says more is waiting.
int postedId(TxNotice notice) {
  final payment = notice.payment;
  if (payment != null) {
    return noticeId('${payment.walletId}:${payment.txid}');
  }
  final walletId = notice.walletId;
  if (walletId == null) return noticeId('waiting:${notice.kind.id}');
  return noticeId(
    notice.kind == NoticeKind.dropped ? 'gone:$walletId' : 'more:$walletId',
  );
}

/// The title of a notice said without the core: the app's name.
const String fallbackTitle = 'Gerfaut';

/// What is said of the transactions of a batch the core could not put
/// into words. The core's own line for "more is waiting", word for
/// word: no wallet, no amount, only that there is something to open
/// the app for. test/fixtures/fallback_notices.json holds the core's
/// words, and the bridge's tests check them against the core.
const String fallbackTransactions =
    'More transactions are coming in. Open Gerfaut to see them.';

/// [fallbackTransactions] for the payments no longer coming.
const String fallbackDropped =
    'More pending payments are no longer coming. Open Gerfaut to see them.';

/// What is posted when the core cannot say what [txs] amount to: the
/// vault closed under a background isolate, an answer that does not
/// read, a panic. The batch is claimed already, and nothing claimed is
/// handed out twice: left unsaid here, its payments would never be
/// said. One notice for the transactions and one for the payments no
/// longer coming, as the core's budget says them, posted under the id
/// of the core's own line, so a second failure takes the place of the
/// first rather than piling up.
List<TxNotice> fallbackNotices(List<LiveTx> txs) => [
  if (txs.any((tx) => tx.stage != TxStage.dropped))
    const TxNotice(
      title: fallbackTitle,
      body: fallbackTransactions,
      kind: NoticeKind.transaction,
    ),
  if (txs.any((tx) => tx.stage == TxStage.dropped))
    const TxNotice(
      title: fallbackTitle,
      body: fallbackDropped,
      kind: NoticeKind.dropped,
    ),
];

/// Posts what a batch of announcements amounts to.
///
/// What it is handed are [LiveTx]: transactions the core gave out once,
/// at one stage, to whoever asked first. The live watch hands them as
/// events; a sync of the app's own gets them from
/// [GerfautBridge.claimAnnouncements]. Either way nothing is said twice.
///
/// The words are the core's, the same as the desktop app's
/// ([GerfautBridge.liveNotices]): what is said here is what the context
/// lets it say. While balances are masked, no amount. Without details,
/// no amount and no wallet name either. The user chooses, and the app
/// lock has no say: a notification is read on the lock screen by
/// whoever holds the phone, whether the app is locked or not.
class NewTxAnnouncer {
  const NewTxAnnouncer(this.service, this.bridge);

  final NotificationService service;
  final GerfautBridge bridge;

  /// Posts what the core says about [txs], in its order, or, when the
  /// core cannot say it, [fallbackNotices].
  Future<void> announce(List<LiveTx> txs, NoticeContext context) async {
    if (txs.isEmpty) return;
    List<TxNotice> notices;
    try {
      notices = await bridge.liveNotices(txs, context);
    } catch (_) {
      notices = fallbackNotices(txs);
    }
    for (final notice in notices) {
      await service.show(postedId(notice), notice.title, notice.body);
    }
  }
}

/// Says what a background isolate claimed, the way the open app would
/// say it: the names, the unit, the mask and the choice of details read
/// from the vault, since these isolates have no screen to ask, and
/// nothing at all while the notice is off or the app is disguised. The
/// periodic task and Live both come through here, so a rule of silence
/// added once holds for both.
Future<void> announceFromVault(
  GerfautBridge bridge,
  NotificationService service,
  List<LiveTx> claimed, {
  required Future<bool> Function() isDisguised,
}) async {
  if (claimed.isEmpty) return;
  final settings = await bridge.getSettings();
  final shared = settings.preferences;
  if (!shared.notifyNewTx || await isDisguised()) return;
  final wallets = await bridge.listWallets();
  await NewTxAnnouncer(service, bridge).announce(
    claimed,
    NoticeContext(
      names: {for (final wallet in wallets) wallet.id: wallet.name},
      unit: shared.unit,
      masked: shared.masked,
      details: AppPrefs(settings.appPrefs).notifyDetails,
    ),
  );
}

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
  (ref) => NewTxAnnouncer(
    ref.watch(notificationServiceProvider),
    ref.watch(bridgeProvider),
  ),
);

/// The open app's side of it. Every sync the screens run is claimed,
/// then said with the names, unit, mask and choice of details the
/// screens hold, or dropped when nothing may be said: the notice is
/// off, or the app is disguised.
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
      // The choice of details is read from the vault in the same pass
      // as the notice itself: a notice on means it is in.
      await _ref
          .read(newTxAnnouncerProvider)
          .announce(
            claimed,
            NoticeContext(
              names: {for (final w in wallets) w.id: w.name},
              unit: _ref.read(unitProvider),
              masked: _ref.read(maskedProvider),
              details: _ref.read(notifyDetailsProvider),
            ),
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
  bool build() => ref.watch(preferencesProvider.select((p) => p.notifyNewTx));

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
    // Read before the change: it rebuilds this notifier, whose ref
    // answers nothing until then.
    final cadence = ref.read(backgroundCheckProvider);
    final scheduler = ref.read(backgroundSchedulerProvider);
    final live = ref.read(liveProvider.notifier);
    ref
        .read(preferencesProvider.notifier)
        .show(PreferencesChange(notifyNewTx: on));
    await rescheduleBackgroundCheck(
      scheduler,
      notifying: on,
      seconds: cadence.seconds,
    );
    // With nothing to say there is nothing to watch for: Live follows
    // the notice off, and back on.
    await live.apply(wanted: on && cadence == BackgroundCheck.live);
  }

  /// Reads again whether Android lets the notices through, each time the
  /// app comes back: a long press on a notice silences its channel, and
  /// the permission is taken back in the system settings, both without
  /// a word to the app. Said under the setting when they no longer get
  /// through; Live, which would keep a connection open for nothing,
  /// waits for them (see [LiveController.resume]).
  Future<void> checkSystem() async {
    final refused = ref.read(notificationsRefusedProvider.notifier);
    if (!state) {
      refused.state = false;
      return;
    }
    final bool deliverable;
    try {
      deliverable = await ref.read(notificationServiceProvider).deliverable();
    } catch (_) {
      // Unanswered: what was last known stands.
      return;
    }
    refused.state = !deliverable;
  }
}

/// The new-transaction notice, one of the preferences both apps keep.
final notifyNewTxProvider = NotifierProvider<NotifyNewTxNotifier, bool>(
  NotifyNewTxNotifier.new,
);

class NotifyDetailsNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void hydrate(String? stored) {
    // On unless turned off: nothing stored, an install from before the
    // switch included, names the wallet and says the amount.
    state = stored != '0';
  }

  /// Read fresh by every isolate at its next notice: nothing to start,
  /// stop or reschedule.
  void set(bool on) {
    state = on;
    ref
        .read(bridgeProvider)
        .setAppPref(Pref.notifyDetails, on ? '1' : '0')
        .catchError((_) {});
  }
}

/// The wallet's name and the amount in a notification, app lock or
/// not. On by default, persisted as "notify.details".
final notifyDetailsProvider = NotifierProvider<NotifyDetailsNotifier, bool>(
  NotifyDetailsNotifier.new,
);

/// The system refused notifications the last time it was asked, when
/// the toggle went on or when the app last came back on screen.
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
        .setAppPref(Pref.background, check.stored)
        .catchError((_) {});
    final notifying = ref.read(notifyNewTxProvider);
    await rescheduleBackgroundCheck(
      ref.read(backgroundSchedulerProvider),
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
/// nothing. Both values are passed in, and the scheduler with them — a
/// notifier that read them back through its own provider would be
/// reading itself.
Future<void> rescheduleBackgroundCheck(
  BackgroundScheduler scheduler, {
  required bool notifying,
  required int seconds,
}) {
  final wanted = notifying ? seconds : 0;
  return scheduler(wanted).catchError((_) {});
}
