// Local notifications: what Gerfaut says when a sync finds a
// transaction it had not seen. Composed here, posted by the platform,
// and sent nowhere: the only traffic is the sync itself.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'format.dart';
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

/// Composes and posts what a batch of sync reports amounts to.
class NewTxAnnouncer {
  const NewTxAnnouncer(this.service);

  final NotificationService service;

  /// What the reports amount to: one notice per transaction up to
  /// [noticesPerWallet] a wallet, then one line counting the rest.
  /// Pure: the same reports, names, unit and mask always say the same.
  static List<TxNotice> compose(
    List<SyncReport> reports, {
    required Map<String, String> walletNames,
    required AmountUnit unit,
    required bool masked,
  }) {
    final notices = <TxNotice>[];
    for (final report in reports) {
      final title = walletNames[report.walletId] ?? report.walletId;
      final txs = report.newTxs;
      if (txs.isEmpty) {
        // A core that counts without listing still gets its line.
        if (report.newTxCount > 0) {
          notices.add(
            TxNotice(
              id: noticeId('count:${report.walletId}'),
              title: title,
              body: _plural(report.newTxCount, 'new transaction'),
            ),
          );
        }
        continue;
      }
      for (final tx in txs.take(noticesPerWallet)) {
        notices.add(
          TxNotice(
            id: noticeId(tx.txid),
            title: title,
            body: _describe(tx, unit: unit, masked: masked),
          ),
        );
      }
      final rest = txs.length - noticesPerWallet;
      if (rest > 0) {
        notices.add(
          TxNotice(
            id: noticeId('more:${report.walletId}'),
            title: title,
            body: _plural(rest, 'more new transaction'),
          ),
        );
      }
    }
    return notices;
  }

  /// Posts what [compose] says about the reports.
  Future<void> announce(
    List<SyncReport> reports, {
    required Map<String, String> walletNames,
    required AmountUnit unit,
    required bool masked,
  }) async {
    final notices = compose(
      reports,
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
String _describe(NewTx tx, {required AmountUnit unit, required bool masked}) {
  final sats = tx.netSats;
  final what = switch ((masked, sats)) {
    (_, 0) => 'New transaction',
    (true, > 0) => 'New transaction',
    (true, _) => 'New outgoing transaction',
    (false, > 0) => 'Received ${formatAmount(sats, unit)}',
    (false, _) => '${formatAmount(-sats, unit)} left this wallet',
  };
  return tx.confirmed ? what : '$what · pending';
}

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

final newTxAnnouncerProvider = Provider<NewTxAnnouncer>(
  (ref) => NewTxAnnouncer(ref.watch(notificationServiceProvider)),
);

/// The open app's side of it: nothing unless the preference is on, then
/// the names, unit and mask the screen shows go with the reports.
class SyncAnnouncer {
  const SyncAnnouncer(this._ref);

  final Ref _ref;

  Future<void> announce(List<SyncReport> reports) async {
    if (!_ref.read(notifyNewTxProvider)) return;
    if (reports.every((r) => r.newTxs.isEmpty && r.newTxCount == 0)) return;
    try {
      final wallets =
          _ref.read(walletsProvider).valueOrNull ??
          await _ref.read(bridgeProvider).listWallets();
      await _ref
          .read(newTxAnnouncerProvider)
          .announce(
            reports,
            walletNames: {for (final w in wallets) w.id: w.name},
            unit: _ref.read(unitProvider),
            masked: _ref.read(maskedProvider),
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
    await rescheduleBackgroundCheck(
      ref,
      notifying: on,
      seconds: ref.read(backgroundCheckProvider).seconds,
    );
  }
}

/// The new-transaction notice, off by default, persisted as
/// "notify.new_tx".
final notifyNewTxProvider = NotifierProvider<NotifyNewTxNotifier, bool>(
  NotifyNewTxNotifier.new,
);

/// The system refused notifications the last time the toggle asked.
final notificationsRefusedProvider = StateProvider<bool>((ref) => false);

/// How often the background check runs; the seconds are what the
/// preference stores.
enum BackgroundCheck {
  off(0, 'Off'),
  quarterHour(900, 'Every 15 min'),
  hour(3600, 'Every hour'),
  sixHours(21600, 'Every 6 hours');

  const BackgroundCheck(this.seconds, this.label);

  final int seconds;
  final String label;

  static BackgroundCheck? fromSeconds(String? stored) {
    final seconds = int.tryParse(stored ?? '');
    for (final check in BackgroundCheck.values) {
      if (check.seconds == seconds) return check;
    }
    return null;
  }
}

class BackgroundCheckNotifier extends Notifier<BackgroundCheck> {
  @override
  BackgroundCheck build() => BackgroundCheck.off;

  void hydrate(String? stored) {
    final check = BackgroundCheck.fromSeconds(stored);
    if (check != null) state = check;
  }

  Future<void> set(BackgroundCheck check) async {
    state = check;
    ref
        .read(bridgeProvider)
        .setAppPref('notify.background', '${check.seconds}')
        .catchError((_) {});
    await rescheduleBackgroundCheck(
      ref,
      notifying: ref.read(notifyNewTxProvider),
      seconds: check.seconds,
    );
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
