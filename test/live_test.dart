import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/background.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/vault_key.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:gerfaut/widgets/setting_switch.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'notifications_test.dart' show FakeNotifications;

const _serviceChannel = MethodChannel('gerfaut/live_service');

const Map<String, String> _livePrefs = {'notify.background': 'live'};

/// The notice on, which Live is there to say.
final _alertsOn = kPreferences.copyWith(notifyNewTx: true);

FakeBridge _bridge({
  Map<String, String> prefs = _livePrefs,
  Preferences? preferences,
  AppLock? lock,
  Network network = Network.signet,
  Map<Network, BackendConfig> backends = const {},
}) {
  return FakeBridge(
    // On the network in use: the one whose wallets Live watches.
    wallets: [makeMeta(network: network)],
    settings: Settings(
      preferences: preferences ?? _alertsOn,
      activeNetwork: network,
      backends: backends,
      appPrefs: {...prefs},
    ),
  )..lock = lock;
}

LiveTx _live(
  String txid,
  int sats, {
  TxStage stage = TxStage.mempool,
  String wallet = 'w1',
}) => LiveTx(walletId: wallet, txid: txid, netSats: sats, stage: stage);

SyncReport _report({
  List<NewTx> fresh = const [],
  List<NewTx> confirmed = const [],
  String id = 'w1',
}) => SyncReport(
  walletId: id,
  newTxCount: fresh.length,
  newTxs: fresh,
  confirmedTxs: confirmed,
  balance: makeBalance(0),
  tipHeight: 100,
  tookMs: 1,
  backend: 'electrum.example',
);

/// The service side under test: a runner over a fake bridge, with what
/// it tells the Android service recorded.
class _Service {
  _Service(
    this.bridge, {
    bool disguised = false,
    Future<void> Function()? bootstrap,
    Duration flushAfter = const Duration(seconds: 3),
    Duration restartAfter = const Duration(seconds: 2),
    Duration quietAfter = const Duration(seconds: 5),
    Duration connectingFor = const Duration(seconds: 30),
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_serviceChannel, (call) async {
          // The wake lock is kept apart from what the notification is
          // told, so each can be read on its own.
          if (call.method == 'hold' || call.method == 'release') {
            awake.add(call.method);
          } else {
            told.add((call.method, call.arguments));
          }
          return null;
        });
    runner = LiveRunner(
      bridge: bridge,
      notifications: notifications,
      channel: _serviceChannel,
      bootstrap: bootstrap ?? () async {},
      isDisguised: () async => disguised,
      schedule: (seconds) async => scheduled.add(seconds),
      flushAfter: flushAfter,
      restartAfter: restartAfter,
      quietAfter: quietAfter,
      connectingFor: connectingFor,
    );
  }

  final FakeBridge bridge;
  final FakeNotifications notifications = FakeNotifications();
  final List<(String, Object?)> told = [];

  /// Every hold and release of the wake lock, in order.
  final List<String> awake = [];

  /// Whether the service holds the work lock now.
  bool get holding => awake.isNotEmpty && awake.last == 'hold';
  final List<int> scheduled = [];
  late final LiveRunner runner;

  /// What the Android service sends down the channel.
  Future<void> send(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _serviceChannel.name,
          _serviceChannel.codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);
}

Widget _settings(
  FakeBridge bridge, {
  required FakeLivePlatform platform,
  FakeNotifications? notifications,
  FakeDisguise? disguise,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      notificationServiceProvider.overrideWithValue(
        notifications ?? FakeNotifications(),
      ),
      backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
      livePlatformProvider.overrideWithValue(platform),
      disguiseServiceProvider.overrideWithValue(disguise ?? FakeDisguise()),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const _HydratedSettings(),
    ),
  );
}

/// The notifications page, with the two preferences it reads hydrated
/// from the fake vault the way the app does at start.
class _HydratedSettings extends ConsumerStatefulWidget {
  const _HydratedSettings();

  @override
  ConsumerState<_HydratedSettings> createState() => _HydratedSettingsState();
}

class _HydratedSettingsState extends ConsumerState<_HydratedSettings> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final settings = await ref.read(settingsProvider.future);
      final prefs = settings.appPrefs;
      ref.read(preferencesProvider.notifier).hydrate(settings.preferences);
      ref.read(notifyDetailsProvider.notifier).hydrate(prefs['notify.details']);
      ref
          .read(backgroundCheckProvider.notifier)
          .hydrate(prefs['notify.background']);
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return const SettingsScreen(section: SettingsSection.notifications);
  }
}

Future<void> _open(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String option) async {
  await tester.tap(find.byType(GerfautSelect<BackgroundCheck>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the service announces', () {
    test('an arrival, then its confirmation in the same place', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      expect(service.bridge.liveStartCalls, 1);
      expect(service.told.last, ('status', 'Connecting…'));
      service.bridge.liveController.add(
        const LiveStatusChanged(LiveWatchStatus(state: WatchState.connected)),
      );
      await service.settle();
      expect(service.told.last, ('status', 'Connected to your server'));

      service.bridge.liveController
        ..add(LiveTransaction(_live('aa', 5000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      service.bridge.liveController
        ..add(LiveTransaction(_live('aa', 5000, stage: TxStage.confirmed)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();

      final posted = service.notifications.posted;
      expect(posted.map((p) => p.body), ['aa · pending', 'aa · confirmed']);
      expect(posted.map((p) => p.title).toSet(), {'Cold storage'});
      // The confirmation replaces the arrival instead of stacking.
      expect(posted[0].id, posted[1].id);
    });

    test('an exit reaches the core as it came', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('bb', -7000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.txs.single.netSats, -7000);
      expect(service.notifications.posted.single.body, 'bb · pending');
    });

    test('the transactions of one sync reach the core together', () async {
      // The core says the first three and counts the rest, per sync: it
      // has to be handed the sync whole.
      final service = _Service(_bridge());
      await service.runner.run();
      for (var i = 0; i < 5; i++) {
        service.bridge.liveController.add(LiveTransaction(_live('tx$i', 1000)));
      }
      service.bridge.liveController.add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.txs.map((tx) => tx.txid), [
        'tx0',
        'tx1',
        'tx2',
        'tx3',
        'tx4',
      ]);
      expect(service.notifications.posted, hasLength(5));
    });

    test('a batch whose report never comes is said all the same', () async {
      final service = _Service(
        _bridge(),
        flushAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      service.bridge.liveController.add(LiveTransaction(_live('cc', 1)));
      // However slowly a busy machine runs the clock: said within two
      // seconds, and once.
      for (var i = 0; i < 200 && service.notifications.posted.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.notifications.posted, hasLength(1));
    });

    test('no amount while balances are masked', () async {
      final service = _Service(
        _bridge(preferences: _alertsOn.copyWith(masked: true)),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('dd', 9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.context.masked, isTrue);
      expect(service.notifications.posted, hasLength(1));
    });

    test('the wallet and the amount, app lock or not', () async {
      final service = _Service(
        _bridge(lock: const AppLock(kind: LockKind.pin, biometric: false)),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('ee', -9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      final context = service.bridge.noticeAsks.single.context;
      expect(context.details, isTrue);
      expect(context.names, {'w1': 'Cold storage'});
      expect(service.notifications.posted.single.title, 'Cold storage');
    });

    test('no wallet and no amount once the details are off', () async {
      final service = _Service(
        _bridge(prefs: {..._livePrefs, 'notify.details': '0'}),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('ee', -9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.context.details, isFalse);
      expect(service.notifications.posted, hasLength(1));
    });

    test('the details turned off under it are off at the next', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.appPrefs['notify.details'] = '0';
      service.bridge.liveController
        ..add(LiveTransaction(_live('ee', 9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.context.details, isFalse);
    });

    test('the unit is the one on screen', () async {
      final service = _Service(
        _bridge(preferences: _alertsOn.copyWith(unit: AmountUnit.sats)),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('ff', 1234)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.bridge.noticeAsks.single.context.unit, AmountUnit.sats);
    });

    test('nothing once the notice was turned off under it', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.preferences = kPreferences;
      service.bridge.liveController
        ..add(LiveTransaction(_live('gg', 1)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.notifications.posted, isEmpty);
      expect(service.bridge.noticeAsks, isEmpty);
    });
  });

  group('the service starts, ticks and stops', () {
    // The wake-lock tests run on the test clock: the windows are seconds
    // long, as in the app, and no machine's load can stretch one past
    // the next check. Each ends a minute on, every window run out, so
    // no timer outlives it.
    Future<void> settled(WidgetTester tester) =>
        tester.pump(const Duration(minutes: 1));

    test('stands down when Live is not what the settings ask for', () async {
      final service = _Service(_bridge(prefs: {'notify.background': '900'}));
      await service.runner.run();
      expect(service.bridge.liveStartCalls, 0);
      expect(service.told.single.$1, 'standDown');
    });

    test('stands down while disguised, whatever the settings say', () async {
      final service = _Service(_bridge(), disguised: true);
      await service.runner.run();
      expect(service.bridge.liveStartCalls, 0);
      expect(service.told.single.$1, 'standDown');
    });

    test(
      'a vault that will not open yet is tried again at each tick',
      () async {
        var keystoreReady = false;
        final service = _Service(
          _bridge(),
          bootstrap: () async {
            if (!keystoreReady) throw StateError('the keystore is locked');
          },
        );
        await service.runner.run();
        expect(service.bridge.liveStartCalls, 0);
        expect(service.told.last, ('status', 'Waiting to start'));

        await service.send('tick');
        expect(service.bridge.liveStartCalls, 0);
        expect(service.bridge.liveTickCalls, 0);

        keystoreReady = true;
        await service.send('tick');
        expect(service.bridge.liveStartCalls, 1);
        expect(service.bridge.liveTickCalls, 1);
      },
    );

    test(
      'a vault held elsewhere is skipped quietly, then started at a tick',
      () async {
        var held = true;
        final service = _Service(
          _bridge(),
          bootstrap: () async {
            if (held) throw const VaultInUseException();
          },
        );
        await service.runner.run();
        expect(service.bridge.liveStartCalls, 0);
        // Nothing wrong is said: the vault is healthy.
        expect(service.told.where((t) => t.$1 == 'status'), isEmpty);

        held = false;
        await service.send('tick');
        expect(service.bridge.liveStartCalls, 1);
        expect(service.bridge.liveTickCalls, 1);
      },
    );

    test(
      'the heartbeat asks the core to check, and starts nothing twice',
      () async {
        final service = _Service(_bridge());
        await service.runner.run();
        await service.send('tick');
        await service.send('tick');
        expect(service.bridge.liveTickCalls, 2);
        expect(service.bridge.liveStartCalls, 1);
      },
    );

    test(
      'a change of status reaches the notification without a host',
      () async {
        final service = _Service(_bridge());
        await service.runner.run();
        service.bridge.liveController.add(
          const LiveStatusChanged(
            LiveWatchStatus(
              state: WatchState.reconnecting,
              server: 'secret.example',
              detail: 'connection reset',
            ),
          ),
        );
        await service.settle();
        expect(service.told.last, ('status', 'Reconnecting…'));
        expect(
          service.told.where((t) => '${t.$2}'.contains('secret.example')),
          isEmpty,
        );
      },
    );

    test('Stop on the notification takes the setting back to 15 min', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      await service.send('stop', true);
      expect(service.bridge.liveStopCalls, 1);
      expect(service.bridge.appPrefs['notify.background'], '900');
      expect(service.scheduled, [900]);
    });

    test('what the watch still held when stopped is said, once', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.drainedOnStop.addAll([
        LiveTransaction(_live('last', 3000)),
        LiveWalletSynced(_report()),
      ]);
      await service.send('stop', false);
      await service.settle();
      expect(service.notifications.posted.single.body, contains('pending'));
    });

    test('a watch that ended on its own starts again', () async {
      final service = _Service(
        _bridge(),
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      expect(service.bridge.liveStartCalls, 1);
      service.bridge.liveController.add(const LiveStopped());
      // However slowly a busy machine runs the clock: started again
      // within two seconds.
      for (var i = 0; i < 200 && service.bridge.liveStartCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.bridge.liveStartCalls, 2);
    });

    test('a run the core cut short is said, then started again', () async {
      final service = _Service(
        _bridge(),
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      expect(service.bridge.liveStartCalls, 1);
      service.bridge.breakRun();
      await service.settle();
      // Not "Connecting…" for good: the notification says what happened.
      expect(service.told.last, ('status', liveBrokeText));
      for (var i = 0; i < 200 && service.bridge.liveStartCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.bridge.liveStartCalls, 2);
      await service.runner.stop(revert: false);
    });

    test('a run that keeps breaking waits longer each time', () async {
      final service = _Service(
        _bridge(),
        restartAfter: const Duration(milliseconds: 40),
      );
      await service.runner.run();
      Future<Duration> restartTime(int calls) async {
        final clock = Stopwatch()..start();
        service.bridge.breakRun();
        for (var i = 0; i < 400 && service.bridge.liveStartCalls < calls; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(service.bridge.liveStartCalls, calls);
        return clock.elapsed;
      }

      final first = await restartTime(2);
      final third = await restartTime(3) + await restartTime(4);
      // 40 ms, then 80 and 160: a failure that comes back every time
      // does not keep the phone busy.
      expect(first, lessThan(const Duration(milliseconds: 160)));
      expect(third, greaterThanOrEqualTo(const Duration(milliseconds: 240)));

      // A run that reaches its server again starts the count over.
      service.bridge.liveController.add(
        const LiveStatusChanged(LiveWatchStatus(state: WatchState.connected)),
      );
      await service.settle();
      final again = await restartTime(5);
      expect(again, lessThan(const Duration(milliseconds: 160)));
      await service.runner.stop(revert: false);
    });

    test('a run refused for another reason is not said as broken', () async {
      final bridge = _bridge()
        ..runRefusal = const BridgeException('not_initialized', 'no vault');
      final service = _Service(
        bridge,
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      await service.settle();
      expect(service.told.map((t) => t.$2), isNot(contains(liveBrokeText)));
      bridge.runRefusal = null;
      for (var i = 0; i < 200 && bridge.liveStartCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await service.runner.stop(revert: false);
    });

    test('a watch started again is held up while it reconnects', () async {
      final service = _Service(
        _bridge(),
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      const reconnecting = LiveStatusChanged(
        LiveWatchStatus(state: WatchState.reconnecting),
      );
      service.bridge.liveController.add(reconnecting);
      await service.settle();
      service.bridge.liveController.add(const LiveStopped());
      for (var i = 0; i < 200 && service.bridge.liveStartCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.bridge.liveStartCalls, 2);
      final holds = service.awake.where((call) => call == 'hold').length;

      // The new run's first word is the same as the old run's last: it
      // is still news, and the phone stays up for it.
      service.bridge.liveController.add(reconnecting);
      await service.settle();
      await service.settle();
      expect(
        service.awake.where((call) => call == 'hold').length,
        greaterThan(holds),
      );
      await service.runner.stop(revert: false);
    });

    test('a run refused, the watch held elsewhere, is tried again', () async {
      final bridge = _bridge()
        ..runRefusal = const BridgeException(
          'live_running',
          'the live watch is held already',
        );
      final service = _Service(
        bridge,
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      // The first run was refused the moment it was listened to: the
      // watch is free from now, before the restart is due, however
      // slowly the clock of a busy machine runs.
      expect(bridge.liveStartCalls, 1);
      bridge.runRefusal = null;
      for (var i = 0; i < 200 && bridge.liveStartCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(bridge.liveStartCalls, 2);
      service.bridge.liveController.add(LiveTransaction(_live('after', 1)));
      service.bridge.liveController.add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.notifications.posted, hasLength(1));
    });

    test('a heartbeat during the start makes no second run', () async {
      final service = _Service(
        _bridge(),
        bootstrap: () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      final first = service.runner.run();
      await service.send('tick');
      await first;
      await service.settle();
      expect(service.bridge.liveStartCalls, 1);
      expect(service.told.where((t) => t.$1 == 'status'), hasLength(1));
    });

    testWidgets(
      'a tick keeps the phone up while the core checks, then lets go',
      (tester) async {
        final service = _Service(_bridge());
        await service.runner.run();
        await service.send('tick');
        expect(service.holding, isTrue);
        await tester.pump(const Duration(seconds: 4));
        expect(service.holding, isTrue);
        await tester.pump(const Duration(seconds: 2));
        expect(service.awake.last, 'release');
        await settled(tester);
      },
    );

    testWidgets('an arrival keeps the phone up until it is announced', (
      tester,
    ) async {
      final service = _Service(
        _bridge(),
        quietAfter: const Duration(seconds: 1),
        flushAfter: const Duration(seconds: 3),
      );
      await service.runner.run();
      service.bridge.liveController.add(LiveTransaction(_live('aa', 5000)));
      await tester.pump();
      expect(service.holding, isTrue);

      // Quiet for longer than the window, the announcement still to say.
      await tester.pump(const Duration(seconds: 2));
      expect(service.notifications.posted, isEmpty);
      expect(service.holding, isTrue);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(service.notifications.posted, hasLength(1));
      expect(service.awake.last, 'release');
      await settled(tester);
    });

    testWidgets('a reconnection keeps the phone up for longer', (tester) async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.liveController.add(
        const LiveStatusChanged(
          LiveWatchStatus(state: WatchState.reconnecting),
        ),
      );
      await tester.pump(const Duration(seconds: 20));
      expect(service.holding, isTrue);

      // Connected: a moment more for the catch-up, then sleep.
      service.bridge.liveController.add(
        const LiveStatusChanged(LiveWatchStatus(state: WatchState.connected)),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(service.awake.last, 'release');
      await settled(tester);
    });

    testWidgets('a status that changes nothing keeps nobody up', (
      tester,
    ) async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.liveController.add(
        const LiveStatusChanged(
          LiveWatchStatus(state: WatchState.connected, pushedScripts: 10),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      final holds = service.awake.where((call) => call == 'hold').length;
      expect(service.awake.last, 'release');

      // The next round recounts, in the same state: nothing to wait for.
      service.bridge.liveController.add(
        const LiveStatusChanged(
          LiveWatchStatus(state: WatchState.connected, pushedScripts: 20),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(service.awake.where((call) => call == 'hold'), hasLength(holds));
      await settled(tester);
    });

    test('a stop lets the phone sleep once it is over', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      await service.send('tick');
      await service.send('stop', false);
      expect(service.awake.last, 'release');
    });

    test('a watch stopped on purpose stays stopped', () async {
      final service = _Service(
        _bridge(),
        restartAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      await service.send('stop', false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(service.bridge.liveStartCalls, 1);
    });

    test('a stop asked by the app leaves the setting to the app', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      await service.send('stop', false);
      expect(service.bridge.liveStopCalls, 1);
      expect(service.bridge.appPrefs['notify.background'], isNull);
      expect(service.scheduled, isEmpty);
    });
  });

  group('the periodic task under Live', () {
    Future<bool> check(FakeBridge bridge) => runBackgroundCheck(
      bridge: bridge,
      service: FakeNotifications(),
      bootstrap: () async {},
      isDisguised: () async => false,
    );

    test('leaves a running watch alone', () async {
      final bridge = _bridge()
        ..watchStatus = const LiveWatchStatus(state: WatchState.connected);
      await check(bridge);
      expect(bridge.syncAllCalls, 0);
    });

    test('skips its turn quietly while the vault is held', () async {
      final bridge = _bridge();
      final notifications = FakeNotifications();
      final ran = await runBackgroundCheck(
        bridge: bridge,
        service: notifications,
        bootstrap: () async => throw const VaultInUseException(),
        isDisguised: () async => false,
      );
      expect(ran, isTrue);
      expect(bridge.syncAllCalls, 0);
      expect(notifications.posted, isEmpty);
    });

    test('syncs when the watch is not running', () async {
      final bridge = _bridge();
      await check(bridge);
      expect(bridge.syncAllCalls, 1);
    });

    test('says nothing of the wallet with the details off', () async {
      final bridge = _bridge(
        prefs: {'notify.background': '900', 'notify.details': '0'},
        lock: const AppLock(kind: LockKind.pin, biometric: false),
      )..syncedIds.add('w1');
      final pending = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      bridge.onSyncAll = (_) => SyncAllReport(reports: [pending], failures: []);
      final notifications = FakeNotifications();
      await runBackgroundCheck(
        bridge: bridge,
        service: notifications,
        bootstrap: () async {},
        isDisguised: () async => false,
      );
      expect(notifications.posted, hasLength(1));
      expect(bridge.noticeAsks.single.context.details, isFalse);
    });

    test('names the wallet under an app lock, details on', () async {
      final bridge = _bridge(
        prefs: {'notify.background': '900'},
        lock: const AppLock(kind: LockKind.pin, biometric: false),
      )..syncedIds.add('w1');
      final pending = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      bridge.onSyncAll = (_) => SyncAllReport(reports: [pending], failures: []);
      final notifications = FakeNotifications();
      await runBackgroundCheck(
        bridge: bridge,
        service: notifications,
        bootstrap: () async {},
        isDisguised: () async => false,
      );
      expect(notifications.posted.single.title, 'Cold storage');
      expect(bridge.noticeAsks.single.context.details, isTrue);
    });

    test('syncs as before at a periodic cadence', () async {
      final bridge = _bridge(prefs: {'notify.background': '900'})
        ..watchStatus = const LiveWatchStatus(state: WatchState.connected);
      await check(bridge);
      expect(bridge.syncAllCalls, 1);
    });
  });

  group('a transaction is said once', () {
    ProviderContainer screens(
      FakeBridge bridge,
      FakeNotifications notifications, {
      bool notify = true,
      bool disguised = false,
    }) {
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          notificationServiceProvider.overrideWithValue(notifications),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
          livePlatformProvider.overrideWithValue(FakeLivePlatform()),
          disguiseServiceProvider.overrideWithValue(
            FakeDisguise(disguised: disguised),
          ),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, PreferencesChange(notifyNewTx: notify));
      return container;
    }

    /// What the core does for its own watch: the sync records, the
    /// watch claims, and each claimed transaction goes out as an event.
    Future<void> watchSaw(FakeBridge bridge, SyncReport report) async {
      bridge.recordNews(report);
      for (final tx in await bridge.claimAnnouncements(report.walletId)) {
        bridge.liveController.add(LiveTransaction(tx));
      }
      bridge.liveController.add(LiveWalletSynced(report));
    }

    test('by the service, then not by the periodic task', () async {
      final bridge = _bridge()..syncedIds.add('w1');
      final service = _Service(bridge);
      await service.runner.run();
      final seen = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      await watchSaw(bridge, seen);
      await service.settle();
      expect(service.notifications.posted, hasLength(1));

      // The safety net syncs on its own and finds the same transaction.
      bridge.onSyncAll = (_) => SyncAllReport(reports: [seen], failures: []);
      final net = FakeNotifications();
      await runBackgroundCheck(
        bridge: bridge,
        service: net,
        bootstrap: () async {},
        isDisguised: () async => false,
      );
      expect(net.posted, isEmpty);
    });

    test('by the periodic task, then its confirmation once more', () async {
      final bridge = _bridge()..syncedIds.add('w1');
      final pending = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      final mined = _report(
        confirmed: [const NewTx(txid: 'aa', netSats: 5000, confirmed: true)],
      );
      final net = FakeNotifications();
      Future<void> check(SyncReport report) {
        bridge.onSyncAll = (_) =>
            SyncAllReport(reports: [report], failures: []);
        return runBackgroundCheck(
          bridge: bridge,
          service: net,
          bootstrap: () async {},
          isDisguised: () async => false,
        );
      }

      await check(pending);
      await check(pending);
      await check(mined);
      await check(mined);
      expect(net.posted.map((p) => p.body), ['aa · pending', 'aa · confirmed']);
    });

    test('by a pull to refresh, then not by the watch', () async {
      final bridge = _bridge()..syncedIds.add('w1');
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications);
      final seen = _report(
        fresh: [const NewTx(txid: 'zz', netSats: 800, confirmed: false)],
      );
      bridge.onSyncWallet = (_) => seen;
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(notifications.posted, hasLength(1));

      // The watch syncs the same wallet a moment later: the core has
      // nothing left to hand out for that transaction.
      bridge.recordNews(seen);
      expect(await bridge.claimAnnouncements('w1'), isEmpty);
    });

    test('a sync whose report lists nothing still claims', () async {
      // The watch's sync of the same wallet ran at the same moment and
      // left its news with the core; the screen's own report is empty.
      final bridge = _bridge()..syncedIds.add('w1');
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications);
      bridge.recordNews(
        _report(
          fresh: [const NewTx(txid: 'raced', netSats: 90, confirmed: false)],
        ),
      );
      bridge.onSyncWallet = (_) => _report();
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(bridge.claims, ['w1']);
      expect(notifications.posted.single.body, contains('pending'));
    });

    test('every wallet of a sync-all is claimed, once each', () async {
      final bridge = FakeBridge(
        wallets: [
          makeMeta(),
          makeMeta(id: 'w2', name: 'Spending'),
        ],
        settings: const Settings(
          preferences: kPreferences,
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {},
        ),
      );
      final container = screens(bridge, FakeNotifications());
      bridge.onSyncAll = (_) => SyncAllReport(
        reports: [
          _report(),
          _report(id: 'w2'),
          _report(),
        ],
        failures: [],
      );
      await container.read(syncProvider.notifier).syncAll(Network.mainnet);
      expect(bridge.claims, ['w1', 'w2']);
    });

    test('with the notice off, a sync claims and says nothing', () async {
      final bridge = _bridge()..syncedIds.add('w1');
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications, notify: false);
      bridge.onSyncWallet = (_) => _report(
        fresh: [const NewTx(txid: 'quiet', netSats: 5, confirmed: false)],
      );
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(bridge.claims, ['w1']);
      expect(notifications.posted, isEmpty);
      // Taken, so not said later when the notice comes back on.
      expect(bridge.news['w1'], isNull);
    });

    test('while disguised, a sync claims and says nothing', () async {
      final bridge = _bridge()..syncedIds.add('w1');
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications, disguised: true);
      await container.read(disguiseProvider.notifier).set(true);
      bridge.onSyncWallet = (_) => _report(
        fresh: [const NewTx(txid: 'hidden', netSats: 5, confirmed: false)],
      );
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(bridge.claims, ['w1']);
      expect(notifications.posted, isEmpty);
    });

    test('a first sync is an import: nothing to say, nothing kept', () async {
      final bridge = _bridge();
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications);
      bridge.onSyncWallet = (_) => _report(
        fresh: [const NewTx(txid: 'old', netSats: 1, confirmed: true)],
      );
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(notifications.posted, isEmpty);
      expect(await bridge.claimAnnouncements('w1'), isEmpty);
    });

    test('the first sync after a restart is news all the same', () async {
      // A wallet synced in an earlier run: what the screens find at
      // start is what arrived while nothing ran.
      final bridge = FakeBridge(
        wallets: [
          makeMeta(
            lastSync: const SyncStamp(
              at: 1755000000,
              tipHeight: 99,
              backend: 'electrum.example',
            ),
          ),
        ],
      );
      final notifications = FakeNotifications();
      final container = screens(bridge, notifications);
      bridge.onSyncAll = (_) => SyncAllReport(
        reports: [
          _report(
            fresh: [const NewTx(txid: 'night', netSats: 7, confirmed: true)],
          ),
        ],
        failures: [],
      );
      await container.read(syncProvider.notifier).syncAll(Network.mainnet);
      expect(notifications.posted.single.body, contains('confirmed'));
    });
  });

  group('a payment that is no longer coming', () {
    test('is posted in the place of the arrival it takes back', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('aa', 150000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      service.bridge.liveController
        ..add(LiveTransaction(_live('aa', 150000, stage: TxStage.dropped)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      final posted = service.notifications.posted;
      expect(posted.map((p) => p.body), [
        'aa · pending',
        'aa · no longer coming',
      ]);
      expect(posted[0].id, posted[1].id);
    });

    test(
      'the service says it with the details off, without the amount',
      () async {
        final service = _Service(
          _bridge(prefs: {..._livePrefs, 'notify.details': '0'}),
        );
        await service.runner.run();
        service.bridge.liveController
          ..add(LiveTransaction(_live('gone', 150000, stage: TxStage.dropped)))
          ..add(LiveWalletSynced(_report()));
        await service.settle();
        final asked = service.bridge.noticeAsks.single;
        expect(asked.txs.single.stage, TxStage.dropped);
        expect(asked.context.details, isFalse);
        expect(service.notifications.posted, hasLength(1));
      },
    );
  });

  group('the status line', () {
    test('says each state in a few words', () {
      LiveState running(LiveWatchStatus status) =>
          LiveState(serviceRunning: true, status: status, checked: true);
      expect(liveStatusLine(const LiveState()), isNull);
      expect(
        liveStatusLine(
          running(
            const LiveWatchStatus(
              state: WatchState.connected,
              transport: WatchTransport.electrum,
              server: 'electrum.example',
            ),
          ),
        ),
        'Connected · Electrum · electrum.example',
      );
      expect(
        liveStatusLine(
          running(const LiveWatchStatus(state: WatchState.polling)),
        ),
        'Polling every minute',
      );
      expect(
        liveStatusLine(
          running(const LiveWatchStatus(state: WatchState.reconnecting)),
        ),
        'Reconnecting…',
      );
      expect(
        liveStatusLine(
          running(const LiveWatchStatus(state: WatchState.connecting)),
        ),
        'Connecting…',
      );
      expect(
        liveStatusLine(const LiveState(checked: true)),
        'Stopped by Android. Tap to restart.',
      );
    });

    testWidgets('shows the connection, and follows the core', (tester) async {
      final bridge = _bridge()
        ..watchStatus = const LiveWatchStatus(
          state: WatchState.connected,
          transport: WatchTransport.electrum,
          server: 'electrum.example',
        );
      final platform = FakeLivePlatform(
        running: true,
        wanted: true,
        batteryExempt: true,
      );
      await _open(tester, _settings(bridge, platform: platform));
      expect(
        find.text('Connected · Electrum · electrum.example'),
        findsOneWidget,
      );
      expect(find.textContaining('Battery: restricted'), findsNothing);
    });

    testWidgets('a service Android stopped restarts on a tap', (tester) async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(wanted: true, batteryExempt: true);
      await _open(tester, _settings(bridge, platform: platform));
      expect(find.text('Stopped by Android. Tap to restart.'), findsOneWidget);

      await tester.tap(find.text('Stopped by Android. Tap to restart.'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(platform.calls, contains('start'));
      expect(find.text('Stopped by Android. Tap to restart.'), findsNothing);
    });

    testWidgets('a missing battery exemption is stated, with a way to fix it', (
      tester,
    ) async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      await _open(tester, _settings(bridge, platform: platform));
      expect(find.textContaining('Battery: restricted'), findsOneWidget);

      await tester.tap(find.text('Fix'));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('askBattery'));
      expect(find.textContaining('Battery: restricted'), findsNothing);
    });
  });

  group('what Live leaves to the syncs', () {
    const any = WatchLimits(perWallet: 200, total: 2000);
    const own = WatchLimits(perWallet: 20000, total: 20000);
    const capped = LiveLeftOut(
      reason: LeftOutReason.liveLimit,
      limits: any,
      remedy: OwnNodeRemedy(own),
    );
    const short = LiveWatchStatus(
      state: WatchState.connected,
      watchedScripts: 2000,
      pushedScripts: 2000,
      leftOutScripts: 1240,
      leftOutWallets: 2,
      leftOut: capped,
    );
    LiveWatchStatus judged(LiveLeftOut leftOut) => LiveWatchStatus(
      state: WatchState.connected,
      leftOutScripts: 1240,
      leftOutWallets: 2,
      leftOut: leftOut,
    );

    test('the limits of Live: how many wait, and what lifts them', () {
      final note = liveCoverageNote(short)!;
      expect(
        note.fact,
        'Live follows at most 200 addresses per wallet and 2 000 in all. '
        '1 240 addresses of 2 wallets are checked at the next sync instead.',
      );
      expect(
        note.remedy,
        'Connect your own node and turn on "This is my node" in Network to '
        'follow up to 20 000.',
      );
    });

    test('at the limits of a declared node: the limit alone', () {
      final note = liveCoverageNote(
        judged(
          const LiveLeftOut(
            reason: LeftOutReason.liveLimit,
            limits: own,
            ownNode: true,
          ),
        ),
      )!;
      expect(
        note.fact,
        'Live follows at most 20 000 addresses, even on your own node. '
        '1 240 addresses of 2 wallets are checked at the next sync instead.',
      );
      expect(note.remedy, isNull);
    });

    test('a server that refused some is blamed, not the limits', () {
      final public = liveCoverageNote(
        judged(
          const LiveLeftOut(
            reason: LeftOutReason.serverRefused,
            limits: any,
            remedy: OwnNodeRemedy(own),
          ),
        ),
      )!;
      expect(
        public.fact,
        'The server refuses some of the addresses Live asks it to follow. '
        '1 240 addresses of 2 wallets are checked at the next sync instead.',
      );
      expect(public.remedy, contains('"This is my node"'));
      final node = liveCoverageNote(
        judged(
          const LiveLeftOut(
            reason: LeftOutReason.serverRefused,
            limits: own,
            ownNode: true,
            remedy: RaiseServerLimit(
              server: ServerSoftware.fulcrum,
              settings: ['max_subs_per_ip'],
            ),
          ),
        ),
      )!;
      expect(node.fact, startsWith('Your node refuses some of the addresses'));
      expect(
        node.remedy,
        'Raise max_subs_per_ip in the Fulcrum configuration to follow them '
        'all.',
      );
    });

    test('the setting the core names, the way its software calls it', () {
      String raise(ServerSoftware? server, List<String> settings) =>
          liveRemedyWords(RaiseServerLimit(server: server, settings: settings));
      expect(
        raise(ServerSoftware.electrumx, ['COST_SOFT_LIMIT', 'COST_HARD_LIMIT']),
        'Raise COST_SOFT_LIMIT and COST_HARD_LIMIT in the ElectrumX settings '
        'to follow them all.',
      );
      expect(
        raise(ServerSoftware.electrsEsplora, ['--electrum-subscription-limit']),
        'Raise --electrum-subscription-limit on this electrs to follow them '
        'all.',
      );
      expect(
        raise(ServerSoftware.mempoolElectrs, ['--electrum-max-subscriptions']),
        'Raise --electrum-max-subscriptions on this electrs to follow them '
        'all.',
      );
      expect(
        raise(null, const []),
        'Raise the subscription limit of your server to follow them all.',
      );
    });

    test('one address of one wallet is said in the singular', () {
      final note = liveCoverageNote(
        const LiveWatchStatus(
          state: WatchState.polling,
          leftOutScripts: 1,
          leftOutWallets: 1,
          leftOut: capped,
        ),
      )!;
      expect(
        note.fact,
        endsWith('1 address of 1 wallet is checked at the next sync instead.'),
      );
    });

    test('nothing to say without a verdict of the core', () {
      expect(
        liveCoverageNote(const LiveWatchStatus(state: WatchState.connected)),
        isNull,
      );
      // Counts without a verdict are not believed either.
      expect(
        liveCoverageNote(
          const LiveWatchStatus(leftOutScripts: 10, leftOutWallets: 1),
        ),
        isNull,
      );
    });

    test('the permanent notification says it in a few words, no count', () {
      expect(
        liveNotificationText(short),
        'Connected to your server · some addresses wait for syncs',
      );
      expect(
        liveNotificationText(
          const LiveWatchStatus(state: WatchState.connected),
        ),
        'Connected to your server',
      );
    });

    testWidgets('the settings say it under the status, with the remedy', (
      tester,
    ) async {
      final bridge = _bridge()..watchStatus = short;
      final platform = FakeLivePlatform(
        running: true,
        wanted: true,
        batteryExempt: true,
      );
      await _open(tester, _settings(bridge, platform: platform));
      expect(
        find.textContaining('1 240 addresses of 2 wallets'),
        findsOneWidget,
      );
      expect(find.textContaining('"This is my node"'), findsOneWidget);
    });

    testWidgets('at the limits of a declared node, no remedy', (tester) async {
      final bridge = _bridge()
        ..watchStatus = judged(
          const LiveLeftOut(
            reason: LeftOutReason.liveLimit,
            limits: own,
            ownNode: true,
          ),
        );
      final platform = FakeLivePlatform(
        running: true,
        wanted: true,
        batteryExempt: true,
      );
      await _open(tester, _settings(bridge, platform: platform));
      expect(
        find.textContaining('20 000 addresses, even on your own node'),
        findsOneWidget,
      );
      expect(find.textContaining('"This is my node"'), findsNothing);
    });

    testWidgets('with room for every address, nothing is said', (tester) async {
      final bridge = _bridge()
        ..watchStatus = const LiveWatchStatus(
          state: WatchState.connected,
          watchedScripts: 120,
          pushedScripts: 120,
        );
      final platform = FakeLivePlatform(
        running: true,
        wanted: true,
        batteryExempt: true,
      );
      await _open(tester, _settings(bridge, platform: platform));
      expect(find.textContaining('for the next sync'), findsNothing);
    });
  });

  group('choosing Live', () {
    const onPrefs = {'notify.background': '900'};

    testWidgets('explains first, and "Not now" changes nothing', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform();
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');

      expect(find.text('Live watch'), findsOneWidget);
      expect(find.textContaining('small permanent notification'), findsOne);
      expect(
        find.textContaining('Your phone’s battery settings show how much.'),
        findsOne,
      );
      expect(find.textContaining('measured'), findsNothing);
      expect(find.textContaining('What a sync already tells it'), findsOne);
      expect(find.textContaining('Force-stopping Gerfaut ends Live'), findsOne);
      // Signet, no Tor: neither of the two conditional lines.
      expect(find.textContaining('Automatic backend'), findsNothing);
      expect(find.textContaining('goes through Tor'), findsNothing);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      // Nothing was written, nothing was started.
      expect(bridge.appPrefs['notify.background'], isNull);
      expect(platform.calls, isEmpty);
    });

    testWidgets('refused notifications keep Live off, and say why', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform();
      await _open(
        tester,
        _settings(
          bridge,
          platform: platform,
          notifications: FakeNotifications(granted: false),
        ),
      );
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();

      expect(find.text('Live needs notifications'), findsOneWidget);
      expect(bridge.appPrefs['notify.background'], isNull);
      expect(platform.calls, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Live needs notifications'), findsNothing);
    });

    testWidgets('notifications, the service, then the battery question', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform();
      final notifications = FakeNotifications();
      await _open(
        tester,
        _settings(bridge, platform: platform, notifications: notifications),
      );
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();

      expect(notifications.permissionAsks, 1);
      expect(bridge.appPrefs['notify.background'], 'live');
      expect(platform.calls, ['start']);
      expect(find.text('Let Gerfaut run in the background'), findsOneWidget);

      await tester.tap(find.text('Ask Android'));
      await tester.pumpAndSettle();
      expect(platform.calls, ['start', 'askBattery']);
      // A phone with no battery manager of its own: the sheet is done.
      expect(find.text('Let Gerfaut run in the background'), findsNothing);
      expect(find.textContaining('Battery: restricted'), findsNothing);
    });

    testWidgets('the battery question refused leaves Live on, and says so', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform(grantsExemption: false);
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask Android'));
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['notify.background'], 'live');
      expect(platform.running, isTrue);
      expect(find.textContaining('Battery: restricted'), findsOneWidget);
    });

    testWidgets('"Not now" to the battery question is an answer', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform();
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(platform.calls, ['start']);
      expect(bridge.appPrefs['notify.background'], 'live');
      expect(find.textContaining('Battery: restricted'), findsOneWidget);
    });

    testWidgets('an exempt phone is not asked again', (tester) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform(batteryExempt: true);
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();
      expect(find.text('Let Gerfaut run in the background'), findsNothing);
      expect(platform.calls, ['start']);
    });

    testWidgets('a Xiaomi gets its card, with the way to the full steps', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform(batteryExempt: true, maker: 'Xiaomi');
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();

      expect(find.text('On a Xiaomi phone'), findsOneWidget);
      expect(find.textContaining('Autostart: on'), findsOneWidget);
      await tester.tap(find.text('Open dontkillmyapp.com'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://dontkillmyapp.com/xiaomi']);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('On a Xiaomi phone'), findsNothing);
    });

    Future<void> reachMakerCard(
      WidgetTester tester,
      FakeLivePlatform platform,
    ) async {
      await _open(
        tester,
        _settings(_bridge(prefs: onPrefs), platform: platform),
      );
      await _pick(tester, 'Live');
      await tester.tap(find.text('Turn on Live'));
      await tester.pumpAndSettle();
      if (find.text('Ask Android').evaluate().isNotEmpty) {
        await tester.tap(find.text('Ask Android'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a OnePlus with the exemption: its own switches, and no '
        'step the exemption already took', (tester) async {
      final platform = FakeLivePlatform(batteryExempt: true, maker: 'OnePlus');
      await reachMakerCard(tester, platform);

      expect(find.text('On a OnePlus phone'), findsOneWidget);
      expect(find.textContaining('Allow background activity'), findsOne);
      expect(find.textContaining('Allow auto launch'), findsOne);
      expect(find.textContaining('tap Lock'), findsOne);
      expect(find.textContaining('Battery optimisation'), findsNothing);
      // Each step is one node for TalkBack, its place said first.
      expect(find.bySemanticsLabel(RegExp(r'^Step 3 of 3\.')), findsOneWidget);
    });

    testWidgets('a refused exemption keeps the step that grants it', (
      tester,
    ) async {
      final platform = FakeLivePlatform(
        maker: 'OnePlus',
        grantsExemption: false,
      );
      await reachMakerCard(tester, platform);

      expect(find.text('On a OnePlus phone'), findsOneWidget);
      expect(find.textContaining('Don’t optimise'), findsOne);
      expect(find.bySemanticsLabel(RegExp(r'^Step 4 of 4\.')), findsOne);
    });

    testWidgets('a sister brand is called by its own name and page', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final platform = FakeLivePlatform(batteryExempt: true, maker: 'OPPO');
      await reachMakerCard(tester, platform);

      expect(find.text('On an Oppo phone'), findsOneWidget);
      expect(find.textContaining('Allow auto launch'), findsOne);
      await tester.tap(find.text('Open dontkillmyapp.com'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://dontkillmyapp.com/oppo']);
    });

    testWidgets('Samsung and Huawei lose their exemption step once granted', (
      tester,
    ) async {
      await reachMakerCard(
        tester,
        FakeLivePlatform(batteryExempt: true, maker: 'samsung'),
      );
      expect(find.textContaining('Never sleeping apps'), findsOne);
      expect(find.textContaining('Unrestricted'), findsNothing);
      expect(
        PhoneMaker.huawei.stepsFor(exempt: true),
        isNot(contains(contains('Battery optimisation'))),
      );
      expect(
        PhoneMaker.huawei.stepsFor(exempt: false),
        contains(contains('Battery optimisation')),
      );
    });

    testWidgets('the card opens the app info page, as a trip that does '
        'not lock the app', (tester) async {
      final platform = FakeLivePlatform(batteryExempt: true, maker: 'OnePlus');
      await reachMakerCard(tester, platform);

      final container = ProviderScope.containerOf(
        tester.element(find.text('On a OnePlus phone')),
      );
      final lock = container.read(lockProvider.notifier)
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await tester.tap(find.text('Open Gerfaut’s app info'));
      await tester.pumpAndSettle();
      expect(platform.calls.last, 'appSettings');

      // Away in the system settings, and back.
      lock.noteHidden();
      lock.noteResumed();
      expect(container.read(lockProvider).locked, isFalse);
    });

    testWidgets('an app info page that does not open leaves the lock alone', (
      tester,
    ) async {
      final platform = FakeLivePlatform(
        batteryExempt: true,
        maker: 'OnePlus',
        opensAppSettings: false,
      );
      await reachMakerCard(tester, platform);
      final container = ProviderScope.containerOf(
        tester.element(find.text('On a OnePlus phone')),
      );
      final lock = container.read(lockProvider.notifier)
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await tester.tap(find.text('Open Gerfaut’s app info'));
      await tester.pumpAndSettle();
      lock.noteHidden();
      lock.noteResumed();
      expect(container.read(lockProvider).locked, isTrue);
    });

    test('only the four makers get a card, sister brands included', () {
      expect(PhoneMaker.of('Xiaomi'), PhoneMaker.xiaomi);
      expect(PhoneMaker.of('POCO'), PhoneMaker.xiaomi);
      expect(PhoneMaker.of('HONOR'), PhoneMaker.huawei);
      expect(PhoneMaker.of('samsung'), PhoneMaker.samsung);
      expect(PhoneMaker.of('realme'), PhoneMaker.onePlus);
      expect(PhoneMaker.of('Google'), isNull);
      expect(PhoneMaker.of(''), isNull);
      expect(PhoneBrand.of('HONOR')!.label, 'Honor');
      expect(PhoneBrand.of('HONOR')!.heading, 'On an Honor phone');
      expect(PhoneBrand.of('OnePlus')!.heading, 'On a OnePlus phone');
      expect(
        PhoneBrand.of('HONOR')!.helpUrl,
        'https://dontkillmyapp.com/huawei',
      );
      expect(
        PhoneBrand.of('realme')!.helpUrl,
        'https://dontkillmyapp.com/realme',
      );
    });

    test('no maker keeps a step the exemption covers once it is granted', () {
      for (final maker in PhoneMaker.values) {
        final covered = {
          for (final step in maker.steps)
            if (step.exemption) step.text,
        };
        final left = maker.stepsFor(exempt: true);
        expect(left.where(covered.contains), isEmpty, reason: '$maker');
        expect(left, isNotEmpty, reason: '$maker');
        expect(maker.stepsFor(exempt: false).length, maker.steps.length);
      }
    });

    testWidgets('over Tor, the sheet adds its caution', (tester) async {
      final bridge = _bridge(prefs: onPrefs)..usesTorValue = true;
      await _open(tester, _settings(bridge, platform: FakeLivePlatform()));
      await _pick(tester, 'Live');
      expect(find.textContaining('goes through Tor'), findsOneWidget);
      expect(find.text('Turn on Live'), findsOneWidget);
    });

    testWidgets('on mainnet with the Automatic backend, says where it goes', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs, network: Network.mainnet);
      await _open(tester, _settings(bridge, platform: FakeLivePlatform()));
      await _pick(tester, 'Live');
      expect(
        find.textContaining('an operator already in the rotation'),
        findsOneWidget,
      );
    });

    testWidgets('another cadence turns Live off at once', (tester) async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(
        running: true,
        wanted: true,
        batteryExempt: true,
      );
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Every hour');
      expect(bridge.appPrefs['notify.background'], '3600');
      expect(platform.calls, ['stop']);
      expect(find.textContaining('Stopped by Android'), findsNothing);
    });
  });

  group('the disguise', () {
    testWidgets('disguised, both settings are greyed and say why', (
      tester,
    ) async {
      final bridge = _bridge(
        prefs: {'notify.background': '900', 'notify.details': '0'},
      );
      final platform = FakeLivePlatform();
      await _open(
        tester,
        _settings(
          bridge,
          platform: platform,
          disguise: FakeDisguise(disguised: true),
        ),
      );
      // The switch reads off, as the notifications are, and neither
      // setting can be moved meanwhile.
      final notify = tester.widget<SettingSwitch>(
        find.widgetWithText(SettingSwitch, 'New transactions'),
      );
      expect(notify.value, isFalse);
      expect(notify.onChanged, isNull);
      expect(
        notify.hint,
        'Off while the app is disguised: a notification would show the '
        'name Gerfaut. Live stops, and background checks post nothing.',
      );
      final cadence = tester.widget<GerfautSelect<BackgroundCheck>>(
        find.byType(GerfautSelect<BackgroundCheck>),
      );
      expect(cadence.onChanged, isNull);
      expect(cadence.value, BackgroundCheck.quarterHour);
      // What a notification would say is out of reach too, drawn as
      // chosen.
      final details = tester.widget<SettingSwitch>(
        find.widgetWithText(SettingSwitch, 'Show wallet and amount'),
      );
      expect(details.value, isFalse);
      expect(details.onChanged, isNull);

      await tester.tap(find.byType(GerfautSelect<BackgroundCheck>));
      await tester.pumpAndSettle();
      expect(find.text('Every hour'), findsNothing);
      expect(find.text('Live watch'), findsNothing);
      expect(platform.calls, isEmpty);
      // Nothing written over the choice the user made.
      expect(bridge.appPrefs.containsKey('notify.background'), isFalse);
    });

    testWidgets('the switch reads off, and the choice is back after', (
      tester,
    ) async {
      final bridge = _bridge(prefs: {'notify.background': '900'});
      await _open(
        tester,
        _settings(
          bridge,
          platform: FakeLivePlatform(),
          disguise: FakeDisguise(disguised: true),
        ),
      );
      Switch drawn() => tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SettingSwitch, 'New transactions'),
          matching: find.byType(Switch),
        ),
      );
      expect(drawn().value, isFalse);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      // Only drawn off: the choice the user made is still the one held.
      expect(container.read(notifyNewTxProvider), isTrue);
      expect(bridge.preferencesChanges, isEmpty);

      await container.read(disguiseProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(drawn().value, isTrue);
      expect(drawn().onChanged, isNotNull);
      expect(find.textContaining('while the app is disguised'), findsNothing);
    });

    testWidgets('without the disguise, nothing says it', (tester) async {
      final bridge = _bridge(prefs: {'notify.background': '900'});
      await _open(tester, _settings(bridge, platform: FakeLivePlatform()));
      expect(find.textContaining('while the app is disguised'), findsNothing);
      final notify = tester.widget<SettingSwitch>(
        find.widgetWithText(SettingSwitch, 'New transactions'),
      );
      expect(notify.onChanged, isNotNull);
    });

    test('putting it on stops Live and goes back to 15 min', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final disguise = FakeDisguise();
      final scheduled = <int>[];
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          livePlatformProvider.overrideWithValue(platform),
          disguiseServiceProvider.overrideWithValue(disguise),
          backgroundSchedulerProvider.overrideWithValue(
            (seconds) async => scheduled.add(seconds),
          ),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));
      container.read(backgroundCheckProvider.notifier).hydrate('live');

      await container.read(disguiseProvider.notifier).set(true);
      expect(platform.calls, ['stop']);
      expect(platform.running, isFalse);
      expect(bridge.appPrefs['notify.background'], '900');
      expect(scheduled, [900]);
      expect(
        container.read(backgroundCheckProvider),
        BackgroundCheck.quarterHour,
      );
      // Live went before the launcher changed face.
      expect(disguise.calls.first, 'widgets:false');
    });
  });

  test('the battery question is a trip the lock lets back in', () async {
    final bridge = _bridge(
      lock: const AppLock(kind: LockKind.pin, biometric: false),
    )..lockSecret = '1234';
    final platform = FakeLivePlatform();
    final container = ProviderContainer(
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        livePlatformProvider.overrideWithValue(platform),
        disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      ],
    );
    addTearDown(container.dispose);
    final lock = container.read(lockProvider.notifier)
      ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));
    await lock.unlock('1234');
    expect(container.read(lockProvider).locked, isFalse);

    // The phone has no direct dialog: the list of apps opens, Gerfaut
    // goes out of sight behind it, and comes back unlocked.
    await container.read(liveProvider.notifier).requestBatteryExemption();
    lock
      ..noteHidden()
      ..noteResumed();
    expect(platform.calls, contains('askBattery'));
    expect(container.read(lockProvider).locked, isFalse);
  });

  test('a battery question that opens nothing excuses no absence', () async {
    final bridge = _bridge(
      lock: const AppLock(kind: LockKind.pin, biometric: false),
    )..lockSecret = '1234';
    final platform = FakeLivePlatform(opensBatteryQuestion: false);
    final container = ProviderContainer(
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        livePlatformProvider.overrideWithValue(platform),
        disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      ],
    );
    addTearDown(container.dispose);
    final lock = container.read(lockProvider.notifier)
      ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));
    await lock.unlock('1234');

    // Neither the question nor the list exists on this phone: nothing
    // came up, so the next time the app goes out of sight it locks.
    expect(
      await container.read(liveProvider.notifier).requestBatteryExemption(),
      isFalse,
    );
    expect(platform.calls, contains('askBattery'));
    expect(container.read(liveProvider).batteryExempt, isFalse);
    lock
      ..noteHidden()
      ..noteResumed();
    expect(container.read(lockProvider).locked, isTrue);
  });

  test('a battery question with nothing to ask excuses no absence', () async {
    final bridge = _bridge(
      lock: const AppLock(kind: LockKind.pin, biometric: false),
    )..lockSecret = '1234';
    final platform = FakeLivePlatform(batteryExempt: true);
    final container = ProviderContainer(
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        livePlatformProvider.overrideWithValue(platform),
        disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      ],
    );
    addTearDown(container.dispose);
    final lock = container.read(lockProvider.notifier)
      ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));
    await lock.unlock('1234');

    // Exempt already: no system screen opens, so the next time the app
    // goes out of sight is a real absence, and it locks.
    expect(
      await container.read(liveProvider.notifier).requestBatteryExemption(),
      isTrue,
    );
    expect(platform.calls, isNot(contains('askBattery')));
    lock
      ..noteHidden()
      ..noteResumed();
    expect(container.read(lockProvider).locked, isTrue);
  });

  group('notices the system no longer lets through', () {
    ProviderContainer withNotices(
      FakeBridge bridge,
      FakeLivePlatform platform,
      FakeNotifications notices,
    ) {
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          livePlatformProvider.overrideWithValue(platform),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          notificationServiceProvider.overrideWithValue(notices),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));
      container.read(backgroundCheckProvider.notifier).hydrate('live');
      return container;
    }

    /// What the app does each time it comes back on screen.
    Future<void> comeBack(ProviderContainer container) async {
      await container.read(notifyNewTxProvider.notifier).checkSystem();
      await container.read(liveProvider.notifier).resume();
    }

    test('are said, and Live waits for them, the choice kept', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final container = withNotices(bridge, platform, notices);

      await comeBack(container);

      expect(container.read(notificationsRefusedProvider), isTrue);
      expect(platform.calls, ['hold']);
      expect(platform.held, isTrue);
      expect(container.read(liveProvider).serviceRunning, isFalse);
      // Live is still the choice, in the vault and on screen.
      expect(bridge.appPrefs['notify.background'], isNot('900'));
      expect(container.read(backgroundCheckProvider), BackgroundCheck.live);
      // The notice itself stays on: it is the system that stops it.
      expect(container.read(notifyNewTxProvider), isTrue);
    });

    test('let through again, Live starts again by itself', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final container = withNotices(bridge, platform, notices);
      await comeBack(container);

      notices.deliverableNow = true;
      await comeBack(container);
      expect(container.read(notificationsRefusedProvider), isFalse);
      expect(platform.calls, ['hold', 'start']);
      expect(platform.held, isFalse);
      expect(container.read(liveProvider).serviceRunning, isTrue);
      expect(container.read(backgroundCheckProvider), BackgroundCheck.live);
    });

    test('the hold outlives the process, and Live comes back', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final before = withNotices(bridge, platform, notices);
      await comeBack(before);
      // The process dies while the notices are still blocked.
      before.dispose();

      // The next open, a new process: the notices get through again.
      notices.deliverableNow = true;
      final after = withNotices(bridge, platform, notices);
      await comeBack(after);
      expect(platform.calls, ['hold', 'start']);
      expect(after.read(liveProvider).serviceRunning, isTrue);
      // Never taken for a Stop pressed on the notification.
      expect(after.read(backgroundCheckProvider), BackgroundCheck.live);
      expect(bridge.appPrefs['notify.background'], isNot('900'));
    });

    test('held across a restart while still blocked, it waits', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final before = withNotices(bridge, platform, notices);
      await comeBack(before);
      before.dispose();

      final after = withNotices(bridge, platform, notices);
      await comeBack(after);
      expect(platform.calls, ['hold']);
      expect(platform.held, isTrue);
      expect(after.read(backgroundCheckProvider), BackgroundCheck.live);
    });

    test('another choice ends the hold, and nothing restarts', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final container = withNotices(bridge, platform, notices);
      await comeBack(container);

      await container
          .read(backgroundCheckProvider.notifier)
          .set(BackgroundCheck.hour);
      expect(platform.held, isFalse);

      notices.deliverableNow = true;
      await comeBack(container);
      expect(platform.calls, ['hold', 'stop']);
      expect(platform.running, isFalse);
      expect(container.read(backgroundCheckProvider), BackgroundCheck.hour);
    });

    test('a hold left behind is ended where Live is not chosen', () async {
      final bridge = _bridge(prefs: {'notify.background': '3600'});
      final platform = FakeLivePlatform(held: true);
      final notices = FakeNotifications();
      final container = withNotices(bridge, platform, notices);
      container.read(backgroundCheckProvider.notifier).hydrate('3600');

      await comeBack(container);
      expect(platform.calls, ['stop']);
      expect(platform.held, isFalse);
      expect(platform.running, isFalse);
    });

    test('with the notice off, the system is not asked', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final notices = FakeNotifications()..deliverableNow = false;
      final container = withNotices(bridge, platform, notices);
      holdPreferences(container, const PreferencesChange(notifyNewTx: false));

      await container.read(notifyNewTxProvider.notifier).checkSystem();
      expect(container.read(notificationsRefusedProvider), isFalse);
      expect(platform.calls, isEmpty);
    });

    testWidgets('the settings say it, with a way to the system page', (
      tester,
    ) async {
      final bridge = _bridge(prefs: {'notify.background': '900'});
      final platform = FakeLivePlatform();
      await _open(tester, _settings(bridge, platform: platform));
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)))
              .read(notificationsRefusedProvider.notifier)
              .state =
          true;
      await tester.pumpAndSettle();

      expect(
        find.text('Notifications are off for Gerfaut in the system settings.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open system settings'));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('appSettings'));
    });
  });

  group('with no wallet to watch', () {
    ProviderContainer chosen(FakeBridge bridge, FakeLivePlatform platform) {
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          livePlatformProvider.overrideWithValue(platform),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          notificationServiceProvider.overrideWithValue(FakeNotifications()),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));
      container.read(backgroundCheckProvider.notifier).hydrate('live');
      return container;
    }

    /// The wallet list read again, as a screen does after a change, and
    /// whatever that sets off left to run.
    Future<void> walletsChanged(ProviderContainer container) async {
      container.invalidate(walletsProvider);
      await container.read(walletsProvider.future);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('the last wallet removed stops Live, and the next one added starts '
        'it again, the choice kept', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = chosen(bridge, platform);
      await container.read(liveProvider.notifier).resume();
      expect(platform.calls, isEmpty);

      await bridge.removeWallet('w1');
      await walletsChanged(container);

      // Stopped, notification and all, and held rather than turned off.
      expect(platform.calls, ['hold']);
      expect(platform.running, isFalse);
      expect(platform.wanted, isFalse);
      expect(platform.held, isTrue);
      final live = container.read(liveProvider);
      expect(live.noWallet, isTrue);
      expect(liveStatusLine(live), 'Off until you add a wallet.');
      // Live is still the choice, in the vault and on screen.
      expect(bridge.appPrefs['notify.background'], isNot('900'));
      expect(container.read(backgroundCheckProvider), BackgroundCheck.live);

      // Coming back to the screen with nothing to watch starts nothing.
      await container.read(liveProvider.notifier).resume();
      expect(platform.calls, ['hold']);

      bridge.wallets = [makeMeta(id: 'w2', network: Network.signet)];
      await walletsChanged(container);

      expect(platform.calls, ['hold', 'start']);
      expect(platform.running, isTrue);
      expect(platform.held, isFalse);
      expect(container.read(liveProvider).noWallet, isFalse);
    });

    test('a wallet on another network is none to watch', () async {
      final bridge = _bridge()..wallets = [makeMeta(network: Network.mainnet)];
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = chosen(bridge, platform);

      await container.read(liveProvider.notifier).resume();

      expect(platform.calls, ['hold']);
      expect(container.read(liveProvider).noWallet, isTrue);
    });

    test('Live chosen with no wallet waits for one', () async {
      final bridge = _bridge()..wallets = [];
      final platform = FakeLivePlatform();
      final container = chosen(bridge, platform);

      await container.read(liveProvider.notifier).apply(wanted: true);

      expect(platform.calls, ['hold']);
      expect(platform.running, isFalse);
      expect(platform.held, isTrue);
    });

    testWidgets('the settings say why, and offer no restart', (tester) async {
      final bridge = _bridge()..wallets = [];
      final platform = FakeLivePlatform(held: true, batteryExempt: true);
      await _open(tester, _settings(bridge, platform: platform));

      expect(find.text('Off until you add a wallet.'), findsOneWidget);
      expect(find.textContaining('Stopped by Android'), findsNothing);
      await tester.tap(find.text('Off until you add a wallet.'));
      await tester.pumpAndSettle();
      expect(platform.calls, isNot(contains('start')));
    });
  });

  group('the app and the service', () {
    ProviderContainer app(FakeBridge bridge, FakeLivePlatform platform) {
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          livePlatformProvider.overrideWithValue(platform),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));
      container.read(backgroundCheckProvider.notifier).hydrate('live');
      return container;
    }

    test('opening the app brings a stopped service back', () async {
      final platform = FakeLivePlatform(wanted: true);
      final container = app(_bridge(), platform);
      await container.read(liveProvider.notifier).resume();
      expect(platform.calls, ['start']);
      expect(container.read(liveProvider).serviceRunning, isTrue);
    });

    test('a running service is left alone, and never started twice', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = app(bridge, platform);
      await container.read(liveProvider.notifier).resume();
      await container.read(liveProvider.notifier).resume();
      expect(platform.calls, isEmpty);
      // The screens never start the watch themselves.
      expect(bridge.liveStartCalls, 0);
    });

    test('Live stopped from its notification with no app to tell', () async {
      // The platform flag is off, the vault still says live.
      final bridge = _bridge();
      final platform = FakeLivePlatform();
      final container = app(bridge, platform);
      await container.read(liveProvider.notifier).resume();
      expect(
        container.read(backgroundCheckProvider),
        BackgroundCheck.quarterHour,
      );
      expect(bridge.appPrefs['notify.background'], '900');
      expect(platform.calls, ['stop']);
    });

    test('Live stopped from its notification while the app is open', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = app(bridge, platform);
      await container.read(liveProvider.notifier).resume();

      // What the service side does on "Stop", then the core's word.
      platform
        ..running = false
        ..wanted = false;
      bridge.appPrefs['notify.background'] = '900';
      bridge.liveController.add(const LiveStopped());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(backgroundCheckProvider),
        BackgroundCheck.quarterHour,
      );
      expect(container.read(liveProvider).serviceRunning, isFalse);
    });

    test('a wallet the watch synced is refreshed on screen', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = app(bridge, platform);
      bridge.snapshots['w1'] = makeSnapshot(meta: makeMeta());
      await container.read(liveProvider.notifier).resume();
      await container.read(snapshotProvider('w1').future);
      final before = bridge.snapshotCalls;

      bridge.liveController.add(LiveWalletSynced(_report()));
      await Future<void>.delayed(Duration.zero);
      await container.read(snapshotProvider('w1').future);
      expect(bridge.snapshotCalls, greaterThan(before));
    });

    test('the notice turned off takes Live down with it', () async {
      final bridge = _bridge();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          livePlatformProvider.overrideWithValue(platform),
          notificationServiceProvider.overrideWithValue(FakeNotifications()),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));
      container.read(backgroundCheckProvider.notifier).hydrate('live');
      await container.read(notifyNewTxProvider.notifier).set(false);
      expect(platform.calls, ['stop']);
    });
  });

  group('what the core says', () {
    test('every event reads, and an unknown one is left alone', () {
      expect(
        LiveEvent.fromJson({
          'type': 'transaction',
          'wallet_id': 'w1',
          'txid': 'aa',
          'net_sats': -5,
          'stage': 'confirmed',
        }),
        isA<LiveTransaction>()
            .having((e) => e.tx.stage, 'stage', TxStage.confirmed)
            .having((e) => e.tx.netSats, 'net', -5),
      );
      expect(
        LiveEvent.fromJson({
          'type': 'status',
          'state': 'polling',
          'transport': 'esplora_polling',
          'server': null,
          'detail': null,
          'watched_scripts': 40,
          'pushed_scripts': 0,
        }),
        isA<LiveStatusChanged>().having(
          (e) => e.status.state,
          'state',
          WatchState.polling,
        ),
      );
      expect(
        LiveEvent.fromJson({'type': 'new_block', 'height': 7}),
        isA<LiveNewBlock>(),
      );
      expect(LiveEvent.fromJson({'type': 'stopped'}), isA<LiveStopped>());
      expect(
        LiveEvent.fromJson({
          'type': 'transaction',
          'wallet_id': 'w1',
          'txid': 'aa',
          'net_sats': 150000,
          'stage': 'dropped',
        }),
        isA<LiveTransaction>().having(
          (e) => e.tx.stage,
          'stage',
          TxStage.dropped,
        ),
      );
      expect(LiveEvent.fromJson({'type': 'something_newer'}), isNull);
    });

    test('the status carries how much of each wallet is live', () {
      final event =
          LiveEvent.fromJson({
                'type': 'status',
                'state': 'connected',
                'transport': 'electrum',
                'server': 'electrum.blockstream.info',
                'detail': null,
                'watched_scripts': 2000,
                'pushed_scripts': 2000,
                'left_out_scripts': 1240,
                'left_out_wallets': 2,
                'wallets': [
                  {
                    'wallet_id': 'w1',
                    'coverage': 'partial',
                    'watched_scripts': 200,
                    'left_out_scripts': 1040,
                  },
                  {
                    'wallet_id': 'w2',
                    'coverage': 'live',
                    'watched_scripts': 36,
                    'left_out_scripts': 0,
                  },
                  {
                    'wallet_id': 'w3',
                    'coverage': 'sync_only',
                    'watched_scripts': 0,
                    'left_out_scripts': 200,
                    'refused_scripts': 200,
                  },
                ],
                'left_out': {
                  'reason': 'server_refused',
                  'limits': {'per_wallet': 200, 'total': 2000},
                  'own_node': false,
                  'remedy': {
                    'type': 'own_node',
                    'limits': {'per_wallet': 20000, 'total': 20000},
                  },
                },
              })!
              as LiveStatusChanged;
      final status = event.status;
      expect(status.leftOutScripts, 1240);
      expect(status.leftOutWallets, 2);
      expect(status.leavesSomeOut, isTrue);
      expect(status.leftOut!.reason, LeftOutReason.serverRefused);
      expect(status.leftOut!.limits.perWallet, 200);
      expect(status.leftOut!.ownNode, isFalse);
      expect((status.leftOut!.remedy! as OwnNodeRemedy).limits.total, 20000);
      expect(status.coverageOf('w3')!.refusedScripts, 200);
      expect(status.coverageOf('w1')!.refusedScripts, 0);
      expect(status.coverageOf('w1')!.coverage, Coverage.partial);
      expect(status.coverageOf('w1')!.leftOutScripts, 1040);
      expect(status.coverageOf('w2')!.coverage, Coverage.live);
      expect(status.coverageOf('w3')!.coverage, Coverage.syncOnly);
      expect(status.coverageOf('w4'), isNull);
    });

    test('a status from before the coverage reads as nothing left out', () {
      final status = LiveWatchStatus.fromJson({
        'state': 'connected',
        'watched_scripts': 40,
        'pushed_scripts': 40,
      });
      expect(status.leftOutScripts, 0);
      expect(status.wallets, isEmpty);
      expect(status.leavesSomeOut, isFalse);
      // A coverage a newer core names is never taken for live.
      expect(Coverage.fromId('something_newer'), Coverage.syncOnly);
    });

    test('the verdict names the setting of a node, or none it knows', () {
      LiveLeftOut verdict(Map<String, dynamic> remedy) => LiveLeftOut.fromJson({
        'reason': 'server_refused',
        'limits': {'per_wallet': 20000, 'total': 20000},
        'own_node': true,
        'remedy': remedy,
      })!;
      final electrumx =
          verdict({
                'type': 'raise_server_limit',
                'server': 'electrumx',
                'settings': ['COST_SOFT_LIMIT', 'COST_HARD_LIMIT'],
              }).remedy!
              as RaiseServerLimit;
      expect(electrumx.server, ServerSoftware.electrumx);
      expect(electrumx.settings, ['COST_SOFT_LIMIT', 'COST_HARD_LIMIT']);
      final unknown =
          verdict({
                'type': 'raise_server_limit',
                'server': null,
                'settings': <String>[],
              }).remedy!
              as RaiseServerLimit;
      expect(unknown.server, isNull);
      expect(unknown.settings, isEmpty);
      // A way out a newer core names is not offered.
      expect(verdict({'type': 'something_newer'}).remedy, isNull);
      expect(LiveLeftOut.fromJson(null), isNull);
    });
  });
}
