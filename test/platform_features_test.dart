// What changes with the system the app runs on. The screens' tests run
// as iOS through `TargetPlatformVariant`, so the set the app picks for
// itself is the one under test; the tests without a screen hand the set
// over directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/security_section.dart';
import 'package:gerfaut/src/background.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/platform_features.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/updates.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/select_field.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'notifications_test.dart' show FakeNotifications;

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// The notice on, and Live chosen: a vault restored from an Android
/// backup.
FakeBridge _fromAndroid({List<WalletMeta>? wallets}) => FakeBridge(
  wallets: wallets,
  settings: Settings(
    preferences: kPreferences.copyWith(notifyNewTx: true),
    activeNetwork: Network.mainnet,
    backends: const {},
    appPrefs: const {'onboarding.seen': '1', 'notify.background': 'live'},
  ),
);

/// The settings on [section], or on their root list, with the
/// preferences hydrated from [bridge] as the app does at start. Nothing
/// of the platform is overridden: the app picks its side by itself.
Widget _settings(FakeBridge bridge, {SettingsSection? section}) {
  return ProviderScope(
    retry: noRetry,
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      notificationServiceProvider.overrideWithValue(FakeNotifications()),
      backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
      biometricGateProvider.overrideWithValue(FakeBiometrics(available: false)),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: _Hydrated(section: section),
    ),
  );
}

class _Hydrated extends ConsumerStatefulWidget {
  const _Hydrated({this.section});

  final SettingsSection? section;

  @override
  ConsumerState<_Hydrated> createState() => _HydratedState();
}

class _HydratedState extends ConsumerState<_Hydrated> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final settings = await ref.read(settingsProvider.future);
      ref.read(preferencesProvider.notifier).hydrate(settings.preferences);
      ref
          .read(backgroundCheckProvider.notifier)
          .hydrate(settings.appPrefs['notify.background']);
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return SettingsScreen(section: widget.section);
  }
}

Future<void> _open(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

List<BackgroundCheck> _offered(WidgetTester tester) => [
  for (final item
      in tester
          .widget<GerfautSelect<BackgroundCheck>>(
            find.byType(GerfautSelect<BackgroundCheck>),
          )
          .items)
    item.value,
];

void main() {
  group('the set of each system', () {
    test('iOS has neither Live, the disguise nor widgets', () {
      expect(PlatformFeatures.of(TargetPlatform.iOS), PlatformFeatures.ios);
      expect(PlatformFeatures.ios.liveWatch, isFalse);
      expect(PlatformFeatures.ios.disguise, isFalse);
      expect(PlatformFeatures.ios.homeWidgets, isFalse);
      expect(PlatformFeatures.ios.checksKeepCadence, isFalse);
    });

    test('Android keeps every one of them', () {
      expect(
        PlatformFeatures.of(TargetPlatform.android),
        PlatformFeatures.android,
      );
      expect(
        BackgroundCheck.offeredOn(PlatformFeatures.android),
        BackgroundCheck.values,
      );
      expect(
        BackgroundCheck.live.on(PlatformFeatures.android),
        BackgroundCheck.live,
      );
    });

    test('Live without Live is the check it keeps under it', () {
      expect(
        BackgroundCheck.live.on(PlatformFeatures.ios),
        BackgroundCheck.quarterHour,
      );
      expect(
        BackgroundCheck.live.on(PlatformFeatures.ios).seconds,
        BackgroundCheck.live.seconds,
      );
      expect(
        BackgroundCheck.offeredOn(PlatformFeatures.ios),
        isNot(contains(BackgroundCheck.live)),
      );
    });
  });

  group('the notifications on iOS', () {
    testWidgets('offer no Live, and read a stored Live as 15 minutes', (
      tester,
    ) async {
      final bridge = _fromAndroid();
      await _open(
        tester,
        _settings(bridge, section: SettingsSection.notifications),
      );

      expect(_offered(tester), isNot(contains(BackgroundCheck.live)));
      expect(_offered(tester), contains(BackgroundCheck.quarterHour));
      expect(find.text('Every 15 min'), findsOneWidget);
      // No status line, no Live words, nothing the service would say.
      expect(find.textContaining('Live'), findsNothing);
      expect(find.textContaining('Android'), findsNothing);
      expect(find.textContaining('iOS decides when'), findsOneWidget);
      // Read, not rewritten: the vault still says what the backup said.
      expect(bridge.appPrefs, isEmpty);
      expect(
        _container(tester).read(livePlatformProvider),
        isA<NoLivePlatform>(),
      );
    }, variant: _ios);

    testWidgets('have no widgets card under them', (tester) async {
      await _open(
        tester,
        _settings(_fromAndroid(), section: SettingsSection.notifications),
      );
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('Show balances on widgets'), findsNothing);
      expect(find.text('Widgets'), findsNothing);
    }, variant: _ios);

    testWidgets('the root row says the cadence that runs', (tester) async {
      await _open(tester, _settings(_fromAndroid()));
      expect(find.text('On · every 15 min'), findsOneWidget);
      expect(find.text('On · Live'), findsNothing);
    }, variant: _ios);

    testWidgets('open the app’s page in Settings by its address', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await _open(
        tester,
        _settings(_fromAndroid(), section: SettingsSection.notifications),
      );
      _container(tester).read(notificationsRefusedProvider.notifier).put(true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open system settings'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [NoLivePlatform.appSettingsUrl]);
    }, variant: _ios);

    test('Live asked for is stored as the check that runs', () async {
      final bridge = _fromAndroid();
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          platformFeaturesProvider.overrideWithValue(PlatformFeatures.ios),
          livePlatformProvider.overrideWithValue(FakeLivePlatform()),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          notificationServiceProvider.overrideWithValue(FakeNotifications()),
          backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
        ],
      );
      addTearDown(container.dispose);
      holdPreferences(container, const PreferencesChange(notifyNewTx: true));

      await container
          .read(backgroundCheckProvider.notifier)
          .set(BackgroundCheck.live);
      expect(
        container.read(backgroundCheckProvider),
        BackgroundCheck.quarterHour,
      );
      expect(bridge.appPrefs['notify.background'], '900');
    });
  });

  group('the notifications on Android', () {
    testWidgets('still offer Live, with the widgets card under them', (
      tester,
    ) async {
      await _open(
        tester,
        _settings(_fromAndroid(), section: SettingsSection.notifications),
      );
      expect(_offered(tester), contains(BackgroundCheck.live));
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Show balances on widgets'), findsOneWidget);
      expect(find.textContaining('iOS'), findsNothing);
    });
  });

  group('the security card on iOS', () {
    testWidgets('has no disguise under a PIN lock', (tester) async {
      final bridge = _fromAndroid()
        ..lock = const AppLock(kind: LockKind.pin, biometric: false);
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            biometricGateProvider.overrideWithValue(
              FakeBiometrics(available: false),
            ),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const Scaffold(
              body: SingleChildScrollView(child: SecuritySection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('Lock now'), findsOneWidget);
      expect(find.text('Disguise the app'), findsNothing);
      expect(find.textContaining('calculator'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SecuritySection)),
      );
      expect(container.read(disguiseServiceProvider), isA<NoDisguise>());
    }, variant: _ios);
  });

  group('the widgets on iOS', () {
    test('nothing is asked, written or scheduled', () async {
      final board = FakeWidgetBoard(
        installed: {HomeWidgets.price, HomeWidgets.balance},
      );
      final scheduled = <bool>[];
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(
            FakeBridge(wallets: [makeMeta(totalSats: 5000)]),
          ),
          platformFeaturesProvider.overrideWithValue(PlatformFeatures.ios),
          widgetBoardProvider.overrideWithValue(board),
          widgetSchedulerProvider.overrideWithValue(
            (wanted) async => scheduled.add(wanted),
          ),
        ],
      );
      addTearDown(container.dispose);

      final feed = container.read(widgetFeedProvider);
      await container.read(walletsProvider.future);
      await container.read(settingsProvider.future);
      await feed.publish();
      feed.resume();
      await container.read(installedWidgetsProvider.future);
      await feed.publish();

      expect(scheduled, isEmpty);
      expect(board.installedAsks, 0);
      expect(board.data, isEmpty);
      expect(board.updates, isEmpty);
    });
  });

  group('the background check on iOS', () {
    FakeBridge synced(int secondsAgo) {
      final now = DateTime.fromMillisecondsSinceEpoch(1755003600 * 1000);
      return FakeBridge(
        wallets: [
          makeMeta(
            lastSync: SyncStamp(
              at: now.millisecondsSinceEpoch ~/ 1000 - secondsAgo,
              tipHeight: 100,
              backend: 'mempool.space',
            ),
          ),
        ],
        settings: Settings(
          preferences: kPreferences.copyWith(notifyNewTx: true),
          activeNetwork: Network.mainnet,
          backends: const {},
          appPrefs: const {'notify.background': '3600'},
        ),
      );
    }

    Future<void> run(FakeBridge bridge, PlatformFeatures features) =>
        runBackgroundCheck(
          bridge: bridge,
          service: FakeNotifications(),
          bootstrap: () async {},
          isDisguised: () async => false,
          features: features,
          now: DateTime.fromMillisecondsSinceEpoch(1755003600 * 1000),
        );

    test('skips a turn that comes before the cadence', () async {
      final bridge = synced(20 * 60);
      await run(bridge, PlatformFeatures.ios);
      expect(bridge.syncAllCalls, 0);
    });

    test('syncs once the cadence has passed', () async {
      final bridge = synced(61 * 60);
      await run(bridge, PlatformFeatures.ios);
      expect(bridge.syncAllCalls, 1);
    });

    test('syncs a wallet that never synced', () async {
      final bridge = synced(0)
        ..wallets.add(makeMeta(id: 'w2', name: 'Spending'));
      await run(bridge, PlatformFeatures.ios);
      expect(bridge.syncAllCalls, 1);
    });

    test('runs a stored Live as the 15-minute check', () async {
      final bridge = synced(16 * 60)
        ..settings = Settings(
          preferences: kPreferences.copyWith(notifyNewTx: true),
          activeNetwork: Network.mainnet,
          backends: const {},
          appPrefs: const {'notify.background': 'live'},
        );
      await run(bridge, PlatformFeatures.ios);
      expect(bridge.syncAllCalls, 1);
    });

    test('Android runs every turn it is given, as before', () async {
      final bridge = synced(20 * 60);
      await run(bridge, PlatformFeatures.android);
      expect(bridge.syncAllCalls, 1);
    });
  });

  group('the releases on iOS', () {
    test('a session asks GitHub nothing', () async {
      final bridge = _fromAndroid();
      final container = ProviderContainer(
        retry: noRetry,
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          platformFeaturesProvider.overrideWithValue(PlatformFeatures.ios),
        ],
      );
      addTearDown(container.dispose);
      await container.read(updateProvider.notifier).sessionStarted();
      expect(bridge.updates.sessions, 0);
      expect(container.read(updateProvider).notice, isNull);
    });

    testWidgets('About offers no update check', (tester) async {
      await _open(
        tester,
        _settings(_fromAndroid(), section: SettingsSection.about),
      );
      expect(find.text('Gerfaut $appVersion'), findsOneWidget);
      expect(find.text('Check for updates'), findsNothing);
      expect(find.text('Check automatically'), findsNothing);
      expect(find.text('Show the welcome tour'), findsOneWidget);
    }, variant: _ios);

    testWidgets('Android keeps the check', (tester) async {
      await _open(
        tester,
        _settings(_fromAndroid(), section: SettingsSection.about),
      );
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Check automatically'), findsOneWidget);
    });
  });
}
