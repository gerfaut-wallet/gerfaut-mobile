// Live watch: a connection to the user's server kept open by an Android
// foreground service, so a transaction is told within seconds.
//
// Who owns what. The core owns the watch: one wallet manager per
// process, one watch in it, one consumer of its events, in Rust. The
// Android service owns its lifetime: the Dart entry point it hosts
// ([runLiveService]) is the only caller of `liveRun` and `liveStop`,
// and the only one that turns a live event into a notification. The
// screens never start, stop or announce: they ask the platform for the
// service ([LivePlatform]) and listen to the same events to refresh what
// they show. So the app in front, behind, or swiped away is the same
// arrangement, and nothing is handed over between them.
//
// A sync the app runs on its own (pull to refresh, the periodic task)
// still notifies, through the core's record of what was announced: a
// transaction is said once per stage, whoever saw it first.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background.dart';
import 'bridge.dart';
import 'disguise.dart';
import 'format.dart';
import 'models.dart';
import 'notifications.dart';
import 'state.dart';
import 'vault_key.dart';

// --- the platform side, as the screens see it --------------------------

/// What Android does for Live watch. Behind an interface so no test ever
/// reaches the activity.
abstract class LivePlatform {
  /// Records that Live is wanted on this phone and starts the service.
  /// False when Android would not start it.
  Future<bool> start();

  /// Records that Live is no longer wanted and stops the service.
  Future<void> stop();

  Future<bool> isRunning();

  /// Whether Live is recorded as wanted on this phone. Kept by the
  /// platform, outside the vault: "Stop" on the notification clears it
  /// even when nothing else of the app runs, and a vault restored on
  /// another phone does not carry it.
  Future<bool> isWanted();

  Future<bool> isBatteryExempt();

  /// Puts Android's own question to the user and answers whether the
  /// app is exempt once they are back.
  Future<bool> requestBatteryExemption();

  /// `Build.MANUFACTURER`, as the phone spells it.
  Future<String> manufacturer();

  /// Opens Gerfaut's own page in the system settings, where every maker
  /// keeps its per-app battery switches. False when it did not open.
  Future<bool> openAppSettings();
}

/// The real thing: a method channel the Android activity answers.
class SystemLivePlatform implements LivePlatform {
  const SystemLivePlatform();

  static const MethodChannel _channel = MethodChannel('gerfaut/live');

  Future<T> _ask<T>(String method, T fallback) async {
    try {
      return await _channel.invokeMethod<T>(method) ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  @override
  Future<bool> start() => _ask('start', false);

  @override
  Future<void> stop() => _ask<Object?>('stop', null);

  @override
  Future<bool> isRunning() => _ask('isRunning', false);

  @override
  Future<bool> isWanted() => _ask('isWanted', false);

  @override
  Future<bool> isBatteryExempt() => _ask('isBatteryExempt', false);

  @override
  Future<bool> requestBatteryExemption() =>
      _ask('requestBatteryExemption', false);

  @override
  Future<String> manufacturer() => _ask('manufacturer', '');

  @override
  Future<bool> openAppSettings() => _ask('openAppSettings', false);
}

final livePlatformProvider = Provider<LivePlatform>(
  (ref) => const SystemLivePlatform(),
);

/// One change to make in a maker's own settings.
@immutable
class MakerStep {
  const MakerStep(this.text, {this.exemption = false});

  final String text;

  /// The step is the maker's own door to Android's battery exemption.
  /// Once the exemption is granted it is already done, and saying it
  /// again would send the user to a switch that is on.
  final bool exemption;
}

/// Phones whose own battery managers stop background apps whatever
/// Android says, with what to change on each. Short on purpose: the
/// menus move between versions, and dontkillmyapp.com keeps up with
/// them better than an app can. Every menu name here comes from there,
/// or from the phone itself: none is guessed.
///
/// None of these switches can be flipped by an app. The most Gerfaut
/// can do is open its own page in the system settings, where the
/// per-app ones live.
enum PhoneMaker {
  xiaomi([
    MakerStep('Settings › Apps › Gerfaut › Autostart: on.'),
    MakerStep('Settings › Apps › Gerfaut › Battery saver: No restrictions.'),
    MakerStep('In the recent apps, hold Gerfaut and tap the padlock.'),
  ]),
  huawei([
    MakerStep(
      'Settings › Battery › App launch › Gerfaut: Manage manually, and '
      'leave every switch on.',
    ),
    MakerStep(
      'In Settings, search for Battery optimisation, then set Gerfaut '
      'to Don’t allow.',
      exemption: true,
    ),
  ]),
  samsung([
    MakerStep(
      'Settings › Apps › Gerfaut › Battery: Unrestricted.',
      exemption: true,
    ),
    MakerStep(
      'Settings › Battery › Background usage limits › Never sleeping '
      'apps: add Gerfaut.',
    ),
  ]),
  onePlus([
    MakerStep(
      'Settings › Apps › Gerfaut › Battery usage: turn on Allow '
      'background activity.',
    ),
    MakerStep(
      'On the same page, turn on Allow auto launch, so Live can start '
      'again after Android stops it or after a restart.',
    ),
    MakerStep(
      'Settings › Battery › Battery optimisation › Gerfaut: Don’t optimise.',
      exemption: true,
    ),
    MakerStep('In the recent apps, open the menu of Gerfaut and tap Lock.'),
  ]);

  const PhoneMaker(this.steps);

  final List<MakerStep> steps;

  /// What is left to do. With the exemption granted, the step that
  /// only grants it again goes.
  List<String> stepsFor({required bool exempt}) => [
    for (final step in steps)
      if (!(exempt && step.exemption)) step.text,
  ];

  /// Reads `Build.MANUFACTURER`. The sister brands share a system with
  /// their parent, and its battery manager with it.
  static PhoneMaker? of(String manufacturer) =>
      PhoneBrand.of(manufacturer)?.maker;
}

/// The brand a phone wears, which is what its owner calls it, and the
/// maker whose battery manager it runs.
@immutable
class PhoneBrand {
  const PhoneBrand._(this.label, this.maker, this.slug, {this.an = false});

  final String label;

  /// The name is said with a vowel first, "an Oppo", "an Honor": the
  /// spelling alone would get "a OnePlus" wrong.
  final bool an;

  /// The card's title.
  String get heading => 'On ${an ? 'an' : 'a'} $label phone';
  final PhoneMaker maker;

  /// Its page on dontkillmyapp.com: a sister brand without one of its
  /// own reads its parent's.
  final String slug;

  String get helpUrl => 'https://dontkillmyapp.com/$slug';

  static PhoneBrand? of(String manufacturer) {
    return switch (manufacturer.trim().toLowerCase()) {
      'xiaomi' => const PhoneBrand._('Xiaomi', PhoneMaker.xiaomi, 'xiaomi'),
      'redmi' => const PhoneBrand._('Redmi', PhoneMaker.xiaomi, 'xiaomi'),
      'poco' => const PhoneBrand._('POCO', PhoneMaker.xiaomi, 'xiaomi'),
      'huawei' => const PhoneBrand._('Huawei', PhoneMaker.huawei, 'huawei'),
      'honor' => const PhoneBrand._(
        'Honor',
        PhoneMaker.huawei,
        'huawei',
        an: true,
      ),
      'samsung' => const PhoneBrand._('Samsung', PhoneMaker.samsung, 'samsung'),
      'oneplus' => const PhoneBrand._('OnePlus', PhoneMaker.onePlus, 'oneplus'),
      'oppo' => const PhoneBrand._(
        'Oppo',
        PhoneMaker.onePlus,
        'oppo',
        an: true,
      ),
      'realme' => const PhoneBrand._('realme', PhoneMaker.onePlus, 'realme'),
      _ => null,
    };
  }
}

// --- what the screens know ---------------------------------------------

/// Where Live watch stands, as the settings show it.
@immutable
class LiveState {
  const LiveState({
    this.serviceRunning = false,
    this.status = const LiveWatchStatus(),
    this.batteryExempt = true,
    this.checked = false,
  });

  /// The Android service is up.
  final bool serviceRunning;

  /// What the core says of its connection.
  final LiveWatchStatus status;
  final bool batteryExempt;

  /// The platform has answered at least once: before that the status
  /// line says nothing rather than "stopped".
  final bool checked;

  LiveState copyWith({
    bool? serviceRunning,
    LiveWatchStatus? status,
    bool? batteryExempt,
    bool? checked,
  }) {
    return LiveState(
      serviceRunning: serviceRunning ?? this.serviceRunning,
      status: status ?? this.status,
      batteryExempt: batteryExempt ?? this.batteryExempt,
      checked: checked ?? this.checked,
    );
  }
}

/// The one line under the setting. Null while there is nothing to say.
String? liveStatusLine(LiveState live) {
  if (!live.checked) return null;
  if (!live.serviceRunning) return 'Stopped by Android. Tap to restart.';
  final status = live.status;
  switch (status.state) {
    case WatchState.connected:
      return [
        'Connected',
        if (status.transport != null) status.transport!.label,
        if (status.server != null) status.server!,
      ].join(' · ');
    case WatchState.polling:
      return 'Polling every minute';
    case WatchState.reconnecting:
      return 'Reconnecting';
    case WatchState.connecting:
    case WatchState.off:
      return 'Connecting';
  }
}

/// The same, for the permanent notification: no host, ever, and no
/// count either. That Live leaves addresses to the syncs is said in a
/// few words; how many, and what to do about it, is for the settings.
String liveNotificationText(LiveWatchStatus status) {
  final state = switch (status.state) {
    WatchState.connected => 'Connected to your server',
    WatchState.polling => 'Checking every minute',
    WatchState.reconnecting => 'Reconnecting',
    WatchState.connecting || WatchState.off => 'Connecting',
  };
  return status.leavesSomeOut
      ? '$state · some addresses wait for syncs'
      : state;
}

/// The most addresses Live follows, as the core caps them: on a public
/// server, in all and per wallet, then on a node the user says is
/// theirs. Grouped the way every figure in the app is.
final String liveLimit = groupThousands('2000');
final String livePerWalletLimit = groupThousands('200');
final String ownNodeLiveLimit = groupThousands('20000');

/// What the settings say under the status line when Live cannot follow
/// every address: how many wait for a sync instead, and what lifts the
/// limit. Null while every address is followed. On a node already
/// declared the user's own, the limit is all there is to say: nothing
/// in the app lifts it further.
({String fact, String? remedy})? liveCoverageNote(
  LiveWatchStatus status, {
  required bool ownNode,
}) {
  if (!status.leavesSomeOut) return null;
  final addresses = _counted(status.leftOutScripts, 'address', 'addresses');
  final wallets = _counted(status.leftOutWallets, 'wallet', 'wallets');
  final verb = status.leftOutScripts == 1 ? 'waits' : 'wait';
  final waiting = '$addresses of $wallets $verb for the next sync instead.';
  if (ownNode) {
    return (
      fact:
          'Live follows up to $ownNodeLiveLimit addresses on your node. '
          '$waiting',
      remedy: null,
    );
  }
  return (
    fact:
        'Live follows up to $liveLimit addresses, $livePerWalletLimit per '
        'wallet. $waiting',
    remedy:
        'Connect your own node and turn on "This is my node" in Network '
        'to follow up to $ownNodeLiveLimit.',
  );
}

String _counted(int count, String one, String many) =>
    '${groupThousands('$count')} ${count == 1 ? one : many}';

class LiveController extends Notifier<LiveState> {
  StreamSubscription<LiveEvent>? _events;

  @override
  LiveState build() {
    ref.onDispose(() => _events?.cancel());
    return const LiveState();
  }

  bool get _chosen =>
      ref.read(notifyNewTxProvider) &&
      ref.read(backgroundCheckProvider) == BackgroundCheck.live;

  /// Called once the preferences are in, and each time the app comes
  /// back on screen. Listens to the core, and brings the service in line
  /// with the setting: started when it should run and does not, and the
  /// setting taken back to a periodic check when Live was stopped from
  /// its notification while no Dart code could write that down.
  Future<void> resume() async {
    _events ??= ref
        .read(bridgeProvider)
        .liveEvents()
        .listen(_onEvent, onError: (_) {});
    if (!_chosen) return;
    final platform = ref.read(livePlatformProvider);
    if (ref.read(disguiseProvider).disguised) {
      await _fallBack();
      return;
    }
    if (!await platform.isWanted()) {
      await _fallBack();
      return;
    }
    if (!await platform.isRunning()) await platform.start();
    await refresh();
  }

  /// Reads the platform and the core again.
  Future<void> refresh() async {
    final platform = ref.read(livePlatformProvider);
    final running = await platform.isRunning();
    final exempt = await platform.isBatteryExempt();
    var status = const LiveWatchStatus();
    if (running) {
      try {
        status = await ref.read(bridgeProvider).liveStatus();
      } catch (_) {
        // The line says "Connecting" until the core answers.
      }
    }
    state = LiveState(
      serviceRunning: running,
      status: status,
      batteryExempt: exempt,
      checked: true,
    );
  }

  /// Starts or stops the service to match the setting.
  Future<void> apply({required bool wanted}) async {
    final platform = ref.read(livePlatformProvider);
    if (wanted && !ref.read(disguiseProvider).disguised) {
      await platform.start();
    } else {
      await platform.stop();
    }
    await refresh();
  }

  /// "Tap to restart" on the status line.
  Future<void> restart() async {
    if (!_chosen) return;
    await ref.read(livePlatformProvider).start();
    // The service answers a moment after it was asked for.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refresh();
  }

  Future<bool> requestBatteryExemption() async {
    final exempt = await ref
        .read(livePlatformProvider)
        .requestBatteryExemption();
    state = state.copyWith(batteryExempt: exempt);
    return exempt;
  }

  Future<void> _fallBack() async {
    await ref
        .read(backgroundCheckProvider.notifier)
        .set(BackgroundCheck.quarterHour);
  }

  void _onEvent(LiveEvent event) {
    switch (event) {
      case LiveWalletSynced(:final report):
        ref.read(syncErrorsProvider.notifier).clear(report.walletId);
        ref.read(syncProvider.notifier).refreshed(report.walletId);
      case LiveSyncFailed(:final walletId, :final message):
        ref.read(syncErrorsProvider.notifier).set(walletId, message);
      case LiveStatusChanged(:final status):
        state = state.copyWith(
          status: status,
          serviceRunning: true,
          checked: true,
        );
      case LiveStopped():
        unawaited(_stopped());
      case LiveTransaction():
      case LiveNewBlock():
        // Said by the service; a block alone changes nothing on screen
        // that the sync following it will not.
        break;
    }
  }

  /// The watch ended. If that was "Stop" on the notification, the vault
  /// already says so: the setting on screen follows it.
  Future<void> _stopped() async {
    try {
      final settings = await ref.read(bridgeProvider).getSettings();
      final stored = BackgroundCheck.fromStored(
        settings.appPrefs['notify.background'],
      );
      if (stored != null && stored != ref.read(backgroundCheckProvider)) {
        ref.read(backgroundCheckProvider.notifier).hydrate(stored.stored);
      }
    } catch (_) {
      // The next resume reads it again.
    }
    await refresh();
  }
}

final liveProvider = NotifierProvider<LiveController, LiveState>(
  LiveController.new,
);

// --- the service side ---------------------------------------------------

/// How long a burst of announcements waits for the sync report that
/// closes it, before being said anyway.
const Duration _flushAfter = Duration(seconds: 3);

/// How long a stop waits for the watch to say it has ended.
const Duration _endWait = Duration(seconds: 3);

/// How long a watch that ended on its own is left before it starts again.
const Duration _restartAfter = Duration(seconds: 2);

/// How long the phone stays awake after the last word from a watch at
/// work: a ping answered, a wallet synced, a status said.
const Duration _quietAfter = Duration(seconds: 5);

/// How long it stays awake for a watch that is still connecting, which
/// may say nothing until the server answers. The service lets go after
/// this much whatever happens.
const Duration _connectingFor = Duration(seconds: 30);

/// What runs inside the engine the Android service hosts: opens the
/// vault, starts the watch, says what it finds, and answers the
/// service's heartbeat.
class LiveRunner {
  LiveRunner({
    required this.bridge,
    required this.notifications,
    required this.channel,
    this.bootstrap = bootstrapGerfaut,
    this.isDisguised = isDisguisedFromDisk,
    this.schedule = registerBackgroundCheck,
    this.flushAfter = _flushAfter,
    this.restartAfter = _restartAfter,
    this.quietAfter = _quietAfter,
    this.connectingFor = _connectingFor,
  });

  final GerfautBridge bridge;
  final NotificationService notifications;
  final MethodChannel channel;
  final Future<void> Function() bootstrap;
  final Future<bool> Function() isDisguised;
  final BackgroundScheduler schedule;
  final Duration flushAfter;
  final Duration restartAfter;
  final Duration quietAfter;
  final Duration connectingFor;

  StreamSubscription<LiveEvent>? _events;

  /// When the phone may sleep again, if nothing more is said.
  Timer? _letGo;

  /// Announcements being said: the phone stays awake until they are.
  int _flushing = 0;

  /// The state the watch last said it was in.
  WatchState? _lastState;
  bool _started = false;

  /// The start under way: the heartbeat and a change of network may ask
  /// for one while the first is still opening the vault.
  Future<bool>? _starting;

  /// Which run the subscription belongs to: the end of an older one
  /// must not be taken for the end of the current.
  int _run = 0;
  bool _stopping = false;
  Completer<void>? _ended;
  final Map<String, List<LiveTx>> _pending = {};
  final Map<String, Timer> _timers = {};

  /// Answers the service from now on, and makes a first attempt.
  Future<void> run() async {
    channel.setMethodCallHandler(_onCall);
    await _ensureStarted();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'tick':
        // The core only hears the ask here: the ping, and whatever its
        // answer sets off, happen after, and the phone stays up for it.
        _stayAwake(quietAfter);
        // A start that failed (the keystore not ready, the vault not
        // to be opened yet) is tried again at each heartbeat.
        if (await _ensureStarted()) {
          try {
            await bridge.liveTick();
          } catch (_) {
            // The next heartbeat asks again.
          }
        }
        return null;
      case 'stop':
        await stop(revert: call.arguments == true);
        return null;
    }
    throw MissingPluginException();
  }

  /// True once the watch runs. Stands the service down when the
  /// settings do not ask for Live, or the app is disguised. One start at
  /// a time: a caller that comes during one waits for its answer.
  Future<bool> _ensureStarted() {
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<bool> _start() async {
    if (_started) return true;
    if (_stopping) return false;
    try {
      await bootstrap();
      final settings = await bridge.getSettings();
      final prefs = settings.appPrefs;
      final wanted =
          prefs['notify.new_tx'] == '1' &&
          prefs['notify.background'] == BackgroundCheck.live.stored;
      if (!wanted || await isDisguised()) {
        await _tell('standDown');
        return false;
      }
      // Said before the run begins, so what the run says comes after.
      await _tell('status', liveNotificationText(const LiveWatchStatus()));
      final run = ++_run;
      _started = true;
      _events = bridge.liveRun().listen(
        _onEvent,
        // A run that could not start ends right after: see onDone.
        onError: (Object _) {},
        onDone: () => _runEnded(run),
      );
      return true;
    } on VaultInUseException {
      // Another opener holds the vault: nothing is wrong, and the next
      // heartbeat tries again. The notification keeps what it says.
      return false;
    } catch (_) {
      await _tell('status', 'Waiting to start');
      return false;
    }
  }

  /// Stops the watch. With [revert], the user pressed "Stop" on the
  /// notification: the setting goes back to a check every 15 minutes,
  /// written where the screens will read it.
  ///
  /// The watch stops while this isolate still listens: what the core
  /// had already handed out reaches it before the end is said, and is
  /// announced here. Nothing handed out is ever handed out again.
  Future<void> stop({required bool revert}) async {
    _stopping = true;
    _stayAwake(connectingFor);
    final running = _started;
    final ended = _ended = Completer<void>();
    try {
      await bridge.liveStop();
    } catch (_) {
      // Nothing left to stop.
    }
    if (running) {
      await ended.future.timeout(_endWait, onTimeout: () {});
    }
    _ended = null;
    await _flushAll();
    await _events?.cancel();
    _events = null;
    _started = false;
    _letGo?.cancel();
    _letGo = null;
    await _tell('release');
    try {
      if (revert) {
        await bridge.setAppPref(
          'notify.background',
          BackgroundCheck.quarterHour.stored,
        );
        await schedule(BackgroundCheck.quarterHour.seconds);
      }
    } catch (_) {
      // The platform flag is cleared already; the app reads it at its
      // next start and writes the setting then.
    }
  }

  void _onEvent(LiveEvent event) {
    // A push from the server wakes the phone for an instant; the sync it
    // sets off and the announcement after it need it awake for longer.
    // A status that only recounts what is followed sets nothing off: the
    // watch says one at every round of its own, and holding the phone
    // up for each would cost more than the watch itself.
    _stayAwake(switch (event) {
      LiveStatusChanged(:final status) when status.state == _lastState =>
        Duration.zero,
      LiveStatusChanged(
        status: LiveWatchStatus(
          state: WatchState.connecting || WatchState.reconnecting,
        ),
      ) =>
        connectingFor,
      _ => quietAfter,
    });
    if (event is LiveStatusChanged) _lastState = event.status.state;
    switch (event) {
      case LiveTransaction(:final tx):
        _pending.putIfAbsent(tx.walletId, () => []).add(tx);
        _timers[tx.walletId] ??= Timer(
          flushAfter,
          () => unawaited(_flush(tx.walletId)),
        );
      case LiveWalletSynced(:final report):
        // The core hands out the transactions of one sync, then its
        // report: the report closes the batch.
        unawaited(_flush(report.walletId));
      case LiveStatusChanged(:final status):
        unawaited(_tell('status', liveNotificationText(status)));
      case LiveStopped():
        // The run ends right after: see [_runEnded].
        break;
      case LiveSyncFailed():
      case LiveNewBlock():
        break;
    }
  }

  /// The run is over: the watch stopped, on purpose or not, or it could
  /// not start. Not asked for here, it is started again, and catches up
  /// on what it missed.
  void _runEnded(int run) {
    if (run != _run) return;
    _started = false;
    _events = null;
    final ended = _ended;
    if (ended != null && !ended.isCompleted) ended.complete();
    if (!_stopping) {
      Timer(restartAfter, () => unawaited(_ensureStarted()));
    }
  }

  Future<void> _flushAll() async {
    for (final walletId in _pending.keys.toList()) {
      await _flush(walletId);
    }
  }

  /// Says what one sync found for one wallet, under the rules every
  /// other announcement follows, read fresh each time: the notice may
  /// have been turned off, the unit changed, a lock set.
  Future<void> _flush(String walletId) async {
    _timers.remove(walletId)?.cancel();
    final txs = _pending.remove(walletId);
    if (txs == null || txs.isEmpty) return;
    _flushing++;
    try {
      final settings = await bridge.getSettings();
      final prefs = settings.appPrefs;
      if (prefs['notify.new_tx'] != '1' || await isDisguised()) return;
      final wallets = await bridge.listWallets();
      await NewTxAnnouncer(notifications).announce(
        txs,
        walletNames: {for (final wallet in wallets) wallet.id: wallet.name},
        unit: AmountUnit.fromId(prefs['display.unit']) ?? AmountUnit.btc,
        masked: notifiesMasked(settings),
        locked: notifiesLocked(settings),
      );
    } catch (_) {
      // A notification that cannot be posted ends nothing: the
      // transaction is in the wallet for the next look at the app.
    } finally {
      _flushing--;
    }
  }

  /// Keeps the phone awake for [window] more, from now. Each call asks
  /// the service again, which moves its own timeout; the last one to
  /// run out lets the phone sleep, unless announcements are still on
  /// their way, which keep it up until they are said.
  void _stayAwake(Duration window) {
    if (window <= Duration.zero) return;
    _letGo?.cancel();
    _letGo = Timer(window, _rest);
    unawaited(_tell('hold'));
  }

  void _rest() {
    _letGo = null;
    if (_pending.isNotEmpty || _flushing > 0) {
      _stayAwake(quietAfter);
      return;
    }
    unawaited(_tell('release'));
  }

  Future<void> _tell(String method, [Object? argument]) async {
    try {
      await channel.invokeMethod<void>(method, argument);
    } catch (_) {
      // The service is gone, or going.
    }
  }
}

/// The Dart entry point of the Android service. `liveMain` in main.dart
/// is what the service names; it comes straight here.
Future<void> runLiveService() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The engine has no activity: the plugins the bootstrap needs are
  // registered by hand, as they are for the periodic task.
  DartPluginRegistrant.ensureInitialized();
  await LiveRunner(
    bridge: const RustBridge(),
    notifications: LocalNotificationService(),
    channel: const MethodChannel('gerfaut/live_service'),
  ).run();
}
