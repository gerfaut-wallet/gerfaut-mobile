// The background check: a sync Android runs while Gerfaut is closed, so
// a transaction that lands overnight is told in the morning.
//
// It talks to the backend already configured for the workspace network
// and to nothing else. There is no Gerfaut server in this path, and the
// isolate posts what it finds locally.

import 'package:workmanager/workmanager.dart';

import 'bridge.dart';
import 'format.dart';
import 'home_widgets.dart';
import 'notifications.dart';
import 'vault_key.dart';

/// The one task Gerfaut registers. A stable name: registering again
/// with the same one replaces the schedule instead of adding a second.
const String backgroundTaskName = 'gerfaut.check';

/// Registers the periodic check at `seconds`, or cancels it at zero.
///
/// Android never runs a periodic task more often than every fifteen
/// minutes and delays it further to save battery; the settings say so
/// rather than promising a cadence the system does not honour.
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

/// The entry point Android calls in a fresh isolate. Top level and
/// annotated, or the tree shaker drops it from a release build.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask(
    (task, _) =>
        task == widgetsTaskName ? refreshWidgets() : runBackgroundCheck(),
  );
}

/// Opens the vault, syncs every wallet of the workspace network, and
/// posts what the sync found. Returns false only when the check could
/// not run at all, which asks Android to try again later.
Future<bool> runBackgroundCheck({
  GerfautBridge bridge = const RustBridge(),
  NotificationService? service,
  Future<void> Function() bootstrap = bootstrapGerfaut,
}) async {
  try {
    await bootstrap();
    final settings = await bridge.getSettings();
    final prefs = settings.appPrefs;
    // The isolate reads the same preferences the screens write: a check
    // that the user turned off must not notify, and must not sync.
    if (prefs['notify.new_tx'] != '1') return true;

    final report = await bridge.syncAll(settings.activeNetwork);
    final reports = report.reports;
    if (reports.every((r) => r.newTxs.isEmpty && r.newTxCount == 0)) {
      return true;
    }
    final wallets = await bridge.listWallets(settings.activeNetwork);
    final announcer = NewTxAnnouncer(service ?? LocalNotificationService());
    await announcer.announce(
      reports,
      walletNames: {for (final wallet in wallets) wallet.id: wallet.name},
      unit: AmountUnit.fromId(prefs['display.unit']) ?? AmountUnit.btc,
      masked: prefs['mobile.masked'] == '1',
    );
    return true;
  } catch (_) {
    // A backend that did not answer is not a reason to retry in a
    // tight loop: the next scheduled check is soon enough.
    return true;
  }
}

/// Starts the scheduler. Called once from `main`, never from a test.
Future<void> initBackgroundChecks() =>
    Workmanager().initialize(callbackDispatcher);
