import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/background.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'notifications_test.dart' show FakeNotifications;

const _serviceChannel = MethodChannel('gerfaut/live_service');

const Map<String, String> _livePrefs = {
  'notify.new_tx': '1',
  'notify.background': 'live',
};

FakeBridge _bridge({
  Map<String, String> prefs = _livePrefs,
  AppLock? lock,
  Network network = Network.signet,
  Map<Network, BackendConfig> backends = const {},
}) {
  return FakeBridge(
    wallets: [makeMeta()],
    settings: Settings(
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
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_serviceChannel, (call) async {
          told.add((call.method, call.arguments));
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
    );
  }

  final FakeBridge bridge;
  final FakeNotifications notifications = FakeNotifications();
  final List<(String, Object?)> told = [];
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
      ref.read(notifyNewTxProvider.notifier).hydrate(prefs['notify.new_tx']);
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
      expect(posted.map((p) => p.body), [
        'Received ${formatAmount(5000, AmountUnit.btc)} · pending',
        'Received ${formatAmount(5000, AmountUnit.btc)} · confirmed',
      ]);
      expect(posted.map((p) => p.title).toSet(), {'Cold storage'});
      // The confirmation replaces the arrival instead of stacking.
      expect(posted[0].id, posted[1].id);
    });

    test('an exit says so', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('bb', -7000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(
        service.notifications.posted.single.body,
        '${formatAmount(7000, AmountUnit.btc)} left this wallet · pending',
      );
    });

    test('past three in one sync, the rest are counted', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      for (var i = 0; i < 5; i++) {
        service.bridge.liveController.add(LiveTransaction(_live('tx$i', 1000)));
      }
      service.bridge.liveController.add(LiveWalletSynced(_report()));
      await service.settle();
      final bodies = service.notifications.posted.map((p) => p.body);
      expect(bodies, hasLength(noticesPerWallet + 1));
      expect(bodies.last, '2 more new transactions');
    });

    test('a batch whose report never comes is said all the same', () async {
      final service = _Service(
        _bridge(),
        flushAfter: const Duration(milliseconds: 20),
      );
      await service.runner.run();
      service.bridge.liveController.add(LiveTransaction(_live('cc', 1)));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(service.notifications.posted, hasLength(1));
    });

    test('no amount while balances are masked', () async {
      final service = _Service(
        _bridge(prefs: {..._livePrefs, 'mobile.masked': '1'}),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('dd', 9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(
        service.notifications.posted.single.body,
        'New transaction · pending',
      );
    });

    test('no amount while an app lock exists', () async {
      final service = _Service(
        _bridge(lock: const AppLock(kind: LockKind.pin, biometric: false)),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('ee', -9000)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(
        service.notifications.posted.single.body,
        'New outgoing transaction · pending',
      );
    });

    test('the unit is the one on screen', () async {
      final service = _Service(
        _bridge(prefs: {..._livePrefs, 'display.unit': 'sats'}),
      );
      await service.runner.run();
      service.bridge.liveController
        ..add(LiveTransaction(_live('ff', 1234)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(
        service.notifications.posted.single.body,
        'Received ${formatAmount(1234, AmountUnit.sats)} · pending',
      );
    });

    test('nothing once the notice was turned off under it', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      service.bridge.appPrefs['notify.new_tx'] = '0';
      service.bridge.liveController
        ..add(LiveTransaction(_live('gg', 1)))
        ..add(LiveWalletSynced(_report()));
      await service.settle();
      expect(service.notifications.posted, isEmpty);
    });
  });

  group('the service starts, ticks and stops', () {
    test('stands down when Live is not what the settings ask for', () async {
      final service = _Service(
        _bridge(prefs: {'notify.new_tx': '1', 'notify.background': '900'}),
      );
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
        expect(service.told.last, ('status', 'Reconnecting'));
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

    test('a stop asked by the app leaves the setting to the app', () async {
      final service = _Service(_bridge());
      await service.runner.run();
      await service.send('stop', false);
      expect(service.bridge.liveStopCalls, 1);
      expect(service.bridge.appPrefs['notify.background'], isNull);
      expect(service.scheduled, isEmpty);
    });
  });

  group('a transaction is said once', () {
    test('by the service, then not by the periodic task', () async {
      final bridge = _bridge();
      final service = _Service(bridge);
      await service.runner.run();

      // The core claims before it hands an event out.
      final seen = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      for (final tx in await bridge.claimAnnouncements(seen)) {
        bridge.liveController.add(LiveTransaction(tx));
      }
      bridge.liveController.add(LiveWalletSynced(seen));
      await service.settle();
      expect(service.notifications.posted, hasLength(1));

      // The safety net syncs on its own and finds the same transaction.
      bridge.syncedIds.add('w1');
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
      final bridge = _bridge();
      final pending = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 5000, confirmed: false)],
      );
      final mined = _report(
        confirmed: [const NewTx(txid: 'aa', netSats: 5000, confirmed: true)],
      );
      final net = FakeNotifications();
      bridge.syncedIds.add('w1');
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
      expect(net.posted.map((p) => p.body), [
        'Received ${formatAmount(5000, AmountUnit.btc)} · pending',
        'Received ${formatAmount(5000, AmountUnit.btc)} · confirmed',
      ]);
    });

    test('by a pull to refresh, then not by the service', () async {
      final bridge = _bridge();
      final notifications = FakeNotifications();
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          notificationServiceProvider.overrideWithValue(notifications),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
          livePlatformProvider.overrideWithValue(FakeLivePlatform()),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
      );
      addTearDown(container.dispose);
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      // A wallet synced before: what a sync finds now is news.
      bridge.syncedIds.add('w1');

      final seen = _report(
        fresh: [const NewTx(txid: 'zz', netSats: 800, confirmed: false)],
      );
      bridge.onSyncWallet = (_) => seen;
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(notifications.posted, hasLength(1));

      // The watch syncs the same wallet a moment later: the core has
      // nothing left to hand out for that transaction.
      expect(await bridge.claimAnnouncements(seen), isEmpty);
    });

    test('a first sync is kept quiet, and stays said', () async {
      final bridge = _bridge();
      final notifications = FakeNotifications();
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          notificationServiceProvider.overrideWithValue(notifications),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
          livePlatformProvider.overrideWithValue(FakeLivePlatform()),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
        ],
      );
      addTearDown(container.dispose);
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      final history = _report(
        fresh: [const NewTx(txid: 'old', netSats: 1, confirmed: true)],
      );
      bridge.onSyncWallet = (_) => history;
      await container.read(syncProvider.notifier).syncWallet('w1');
      expect(notifications.posted, isEmpty);
      expect(await bridge.claimAnnouncements(history), isEmpty);
    });
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
        'Reconnecting',
      );
      expect(
        liveStatusLine(
          running(const LiveWatchStatus(state: WatchState.connecting)),
        ),
        'Connecting',
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

  group('choosing Live', () {
    const onPrefs = {'notify.new_tx': '1', 'notify.background': '900'};

    testWidgets('explains first, and "Not now" changes nothing', (
      tester,
    ) async {
      final bridge = _bridge(prefs: onPrefs);
      final platform = FakeLivePlatform();
      await _open(tester, _settings(bridge, platform: platform));
      await _pick(tester, 'Live');

      expect(find.text('Live watch'), findsOneWidget);
      expect(find.textContaining('small permanent notification'), findsOne);
      expect(find.textContaining('has not been measured yet'), findsOne);
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

    test('only the four makers get a card, sister brands included', () {
      expect(PhoneMaker.of('Xiaomi'), PhoneMaker.xiaomi);
      expect(PhoneMaker.of('POCO'), PhoneMaker.xiaomi);
      expect(PhoneMaker.of('HONOR'), PhoneMaker.huawei);
      expect(PhoneMaker.of('samsung'), PhoneMaker.samsung);
      expect(PhoneMaker.of('realme'), PhoneMaker.onePlus);
      expect(PhoneMaker.of('Google'), isNull);
      expect(PhoneMaker.of(''), isNull);
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
    testWidgets('Live cannot be chosen while disguised, and says why', (
      tester,
    ) async {
      final bridge = _bridge(
        prefs: {'notify.new_tx': '1', 'notify.background': '900'},
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
      await _pick(tester, 'Live');
      expect(
        find.text('Not available while the app is disguised'),
        findsOneWidget,
      );
      expect(find.text('Live watch'), findsNothing);
      expect(platform.calls, isEmpty);
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
      container.read(notifyNewTxProvider.notifier).hydrate('1');
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
      container.read(notifyNewTxProvider.notifier).hydrate('1');
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
      container.read(notifyNewTxProvider.notifier).hydrate('1');
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
      expect(LiveEvent.fromJson({'type': 'something_newer'}), isNull);
    });

    test('a report hands back what a claim needs, and nothing else', () {
      final report = _report(
        fresh: [const NewTx(txid: 'aa', netSats: 1, confirmed: false)],
        confirmed: [const NewTx(txid: 'bb', netSats: -2, confirmed: true)],
      );
      expect(report.toFindingsJson(), {
        'wallet_id': 'w1',
        'new_txs': [
          {'txid': 'aa', 'net_sats': 1, 'confirmed': false},
        ],
        'confirmed_txs': [
          {'txid': 'bb', 'net_sats': -2, 'confirmed': true},
        ],
      });
    });
  });
}
