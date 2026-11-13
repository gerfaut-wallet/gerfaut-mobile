// The background check: a sync the system runs while Gerfaut is closed,
// so a transaction that lands overnight is told in the morning. Android
// runs it at the cadence it is given. iOS runs it when it sees fit, a
// quarter of an hour apart at the soonest and never once the app is
// swiped away; the check keeps the cadence there itself.
//
// It talks to the backend already configured for the workspace network
// and to nothing else. There is no Gerfaut server in this path, and the
// isolate posts what it finds locally.

import 'package:workmanager/workmanager.dart';

import 'bridge.dart';
import 'disguise.dart';
import 'home_widgets.dart';
import 'models.dart';
import 'notifications.dart';
import 'platform_features.dart';
import 'quiet_errors.dart';
import 'vault_key.dart';
import 'prefs.dart';

/// The one task Gerfaut registers. A stable name: registering again
/// with the same one replaces the schedule instead of adding a second.
const String backgroundTaskName = 'gerfaut.check';

/// Registers the periodic check at `seconds`, or cancels it at zero.
///
/// Android never runs a periodic task more often than every fifteen
/// minutes and delays it further to save battery; iOS takes no cadence
/// at all (see [isCheckDue]). The settings say so rather than promise
/// what the system does not honour.
Future<void> registerBackgroundCheck(int seconds) async {
  final manager = Workmanager();
  if (seconds <= 0) {
    await manager.cancelByUniqueName(backgroundTaskName);
    return;
  }
  await manager.registerPeriodicTask(
    backgroundTaskName,
    backgroundTaskName,
    frequency: Duration(seconds: seconds),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    // The cadence the user just chose is the one that must run.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

/// The companion task that repaints the home-screen widgets while the
/// app is closed. Registered only while at least one widget is placed.
const String widgetsTaskName = 'gerfaut.widgets';

/// Registers the periodic widget refresh, or cancels it when nothing is
/// left to refresh. Fifteen minutes is the floor Android grants a
/// periodic task, and it delays further to save battery.
Future<void> registerWidgetRefresh(bool wanted) async {
  final manager = Workmanager();
  if (!wanted) {
    await manager.cancelByUniqueName(widgetsTaskName);
    return;
  }
  await manager.registerPeriodicTask(
    widgetsTaskName,
    widgetsTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    // Update, not replace: registering again at every app start must
    // not push the next run another period away.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// The entry point the system calls in a fresh isolate. Top level and
/// annotated, or the tree shaker drops it from a release build.
@pragma('vm:entry-point')
void callbackDispatcher() {
  quietErrorsInRelease();
  Workmanager().executeTask(
    (task, _) =>
        task == widgetsTaskName ? refreshWidgets() : runBackgroundCheck(),
  );
}

/// Opens the vault, syncs every wallet of the workspace network, and
/// posts what the sync found. Returns false only when the check could
/// not run at all, which asks the system to try again later.
Future<bool> runBackgroundCheck({
  GerfautBridge bridge = const RustBridge(),
  NotificationService? service,
  Future<void> Function() bootstrap = bootstrapGerfaut,
  Future<bool> Function() isDisguised = isDisguisedFromDisk,
  PlatformFeatures? features,
  DateTime? now,
}) async {
  final system = features ?? PlatformFeatures.current;
  try {
    await bootstrap();
    final settings = await bridge.getSettings();
    final prefs = settings.appPrefs;
    // The isolate reads the same preferences the screens write: a check
    // that the user turned off must not notify, and must not sync.
    if (!settings.preferences.notifyNewTx) return true;
    // Nothing is posted while disguised. The isolate has no channel to
    // the activity, so it reads the marker the activity keeps on disk.
    if (await isDisguised()) return true;
    final cadence = AppPrefs(prefs).background.on(system);
    // Under Live this task is the safety net, for when Android stopped
    // the service. While the watch runs it has everything covered, and
    // a full sync every quarter hour would only cost data and battery.
    // The watch lives in this same process, so the core can say.
    if (cadence == BackgroundCheck.live &&
        (await bridge.liveStatus()).state != WatchState.off) {
      return true;
    }
    if (!system.checksKeepCadence &&
        !await isCheckDue(bridge, settings.activeNetwork, cadence, now: now)) {
      return true;
    }

    // Past the system's budget, the turn is given up rather than taken
    // from the app: what the sync found by then is in the vault, and
    // said at the next turn or the next opening.
    final sync = bridge.syncAll(settings.activeNetwork);
    final budget = system.backgroundBudget;
    final report = budget == null ? await sync : await sync.timeout(budget);
    // Only what nobody has said yet. A wallet's first sync is an
    // import, and the core keeps none of it as news.
    final claimed = await claimAll(bridge, report.reports);
    await announceFromVault(
      bridge,
      service ?? LocalNotificationService(),
      claimed,
      isDisguised: isDisguised,
    );
    return true;
  } on VaultInUseException {
    // Another opener holds the vault. It is healthy, and whoever holds
    // it watches the same wallets: this turn is skipped, quietly.
    return true;
  } catch (_) {
    // A backend that did not answer is not a reason to retry in a
    // tight loop: the next scheduled check is soon enough.
    return true;
  }
}

/// How much sooner than its cadence a turn still counts as due: a sync
/// takes a moment, and the system's turn never lands on the second.
const int _dueMargin = 60;

/// Whether a turn the system chose on its own is due at [cadence]: a
/// wallet of [network] last synced longer ago than that, or never did.
/// The open app's syncs count, so a turn just after it is skipped. With
/// no cadence, none is.
Future<bool> isCheckDue(
  GerfautBridge bridge,
  Network network,
  BackgroundCheck cadence, {
  DateTime? now,
}) async {
  if (cadence.seconds <= 0) return false;
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  for (final wallet in await bridge.listWallets(network)) {
    final stamp = wallet.lastSync;
    if (stamp == null || at - stamp.at >= cadence.seconds - _dueMargin) {
      return true;
    }
  }
  return false;
}

/// Starts the scheduler. Called once from `main`, never from a test.
Future<void> initBackgroundChecks() =>
    Workmanager().initialize(callbackDispatcher);
