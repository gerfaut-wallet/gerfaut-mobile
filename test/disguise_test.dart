import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/settings/security_section.dart';
import 'package:gerfaut/src/background.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/notice.dart';

import 'fakes.dart';

/// Says the phone has no biometric, so the security card never waits on
/// a sensor that a test binding does not answer.
class _NoBiometrics implements BiometricGate {
  @override
  Future<bool> canCheck() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

/// Records what would have been posted instead of touching the platform.
class _RecordingNotifications implements NotificationService {
  final List<String> posted = [];
  int cleared = 0;

  /// Answers a clear the way a platform without the plugin does.
  bool refuseClear = false;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(int id, String title, String body) async =>
      posted.add(body);
  @override
  Future<void> cancelAll() async {
    if (refuseClear) throw MissingPluginException();
    cleared++;
    posted.clear();
  }
}

const AppLock _pinLock = AppLock(kind: LockKind.pin, biometric: false);
const AppLock _passwordLock = AppLock(
  kind: LockKind.password,
  biometric: false,
);

FakeBridge _locked({AppLock lock = _pinLock, String secret = '1234'}) {
  return FakeBridge(
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    )
    ..lock = lock
    ..lockSecret = secret;
}

Widget _securityApp(
  FakeBridge bridge,
  FakeDisguise disguise, {
  _RecordingNotifications? notifications,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(disguise),
      biometricGateProvider.overrideWithValue(_NoBiometrics()),
      notificationServiceProvider.overrideWithValue(
        notifications ?? _RecordingNotifications(),
      ),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(child: SecuritySection()),
      ),
    ),
  );
}

Finder _disguiseSwitch() => find.descendant(
  of: find.ancestor(
    of: find.text('Disguise the app'),
    matching: find.byType(Row),
  ),
  matching: find.byType(Switch),
);

void main() {
  group('the disguise switch', () {
    testWidgets('is offered with a PIN lock', (tester) async {
      await tester.pumpWidget(_securityApp(_locked(), FakeDisguise()));
      await tester.pumpAndSettle();

      expect(find.text('Disguise the app'), findsOneWidget);
      expect(tester.widget<Switch>(_disguiseSwitch()).onChanged, isNotNull);
    });

    testWidgets('is disabled and explained without a PIN lock', (tester) async {
      await tester.pumpWidget(
        _securityApp(_locked(lock: _passwordLock), FakeDisguise()),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(_disguiseSwitch()).onChanged, isNull);
      expect(find.textContaining('Needs a PIN lock'), findsOneWidget);
    });

    testWidgets('turning it on opens a sheet that says what changes', (
      tester,
    ) async {
      await tester.pumpWidget(_securityApp(_locked(), FakeDisguise()));
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('launcher will show a calculator'),
        findsOneWidget,
      );
      expect(find.textContaining('typing your PIN into it'), findsOneWidget);
      expect(find.textContaining('still list "Gerfaut"'), findsOneWidget);
      expect(find.textContaining('widgets are turned off'), findsOneWidget);
      expect(find.textContaining('older Gerfaut thumbnail'), findsOneWidget);
      // The facts are a list; the one consequence that bites is the
      // single note, and the only amber on the sheet.
      expect(find.textContaining('cannot be opened'), findsOneWidget);
      expect(find.byType(GerfautNotice), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GerfautNotice),
          matching: find.textContaining('cannot be opened'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with Live on, the sheet says it stops, and it does', (
      tester,
    ) async {
      final disguise = FakeDisguise();
      final platform = FakeLivePlatform(running: true, wanted: true);
      final bridge = _locked();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            disguiseServiceProvider.overrideWithValue(disguise),
            biometricGateProvider.overrideWithValue(_NoBiometrics()),
            livePlatformProvider.overrideWithValue(platform),
            backgroundSchedulerProvider.overrideWithValue((seconds) async {}),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.read(notifyNewTxProvider.notifier);
                  return const SingleChildScrollView(child: SecuritySection());
                },
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SecuritySection)),
      );
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      container.read(backgroundCheckProvider.notifier).hydrate('live');
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      expect(find.textContaining('Live watch is turned off'), findsOneWidget);

      await tester.tap(find.text('Turn on the disguise'));
      await tester.pumpAndSettle();
      expect(platform.calls, ['stop']);
      expect(bridge.appPrefs['notify.background'], '900');
      expect(disguise.disguised, isTrue);
    });

    testWidgets('without Live, the sheet does not mention it', (tester) async {
      await tester.pumpWidget(_securityApp(_locked(), FakeDisguise()));
      await tester.pumpAndSettle();
      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      expect(find.textContaining('Live watch'), findsNothing);
    });

    testWidgets('confirming enables the disguise and turns widgets off', (
      tester,
    ) async {
      final disguise = FakeDisguise();
      await tester.pumpWidget(_securityApp(_locked(), disguise));
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on the disguise'));
      await tester.pumpAndSettle();

      // Widgets off before the launcher swap, so nothing "Gerfaut" is
      // left on the home screen next to the calculator.
      expect(disguise.calls, ['widgets:false', 'disguise:true']);
      expect(disguise.disguised, isTrue);
      expect(tester.widget<Switch>(_disguiseSwitch()).value, isTrue);
    });

    testWidgets('turning it on takes what was said off the shade', (
      tester,
    ) async {
      // A notification from before stays in the shade otherwise, headed
      // "Gerfaut" and titled with a wallet's name, over the calculator.
      final disguise = FakeDisguise();
      final notifications = _RecordingNotifications();
      await notifications.show(1, 'Cold storage', 'New transaction · pending');
      await tester.pumpWidget(
        _securityApp(_locked(), disguise, notifications: notifications),
      );
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on the disguise'));
      await tester.pumpAndSettle();

      expect(disguise.disguised, isTrue);
      expect(notifications.cleared, 1);
      expect(notifications.posted, isEmpty);
    });

    testWidgets('a notification that cannot be cleared keeps the disguise', (
      tester,
    ) async {
      final disguise = FakeDisguise();
      await tester.pumpWidget(
        _securityApp(
          _locked(),
          disguise,
          notifications: _RecordingNotifications()..refuseClear = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on the disguise'));
      await tester.pumpAndSettle();

      expect(disguise.disguised, isTrue);
      expect(tester.widget<Switch>(_disguiseSwitch()).value, isTrue);
    });

    testWidgets('a launcher that refuses leaves the switch off and says why', (
      tester,
    ) async {
      final disguise = FakeDisguise()
        ..refusal = PlatformException(
          code: 'failed',
          message: 'the component could not be enabled',
        );
      await tester.pumpWidget(_securityApp(_locked(), disguise));
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on the disguise'));
      await tester.pumpAndSettle();

      expect(disguise.disguised, isFalse);
      expect(tester.widget<Switch>(_disguiseSwitch()).value, isFalse);
      expect(find.text('the component could not be enabled'), findsOneWidget);
    });

    testWidgets('cancelling the sheet changes nothing', (tester) async {
      final disguise = FakeDisguise();
      await tester.pumpWidget(_securityApp(_locked(), disguise));
      await tester.pumpAndSettle();

      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(disguise.calls, isEmpty);
      expect(disguise.disguised, isFalse);
    });

    testWidgets('turning it off reverses all of it', (tester) async {
      final disguise = FakeDisguise(disguised: true);
      final notifications = _RecordingNotifications();
      await tester.pumpWidget(
        _securityApp(_locked(), disguise, notifications: notifications),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(_disguiseSwitch()).value, isTrue);
      await tester.tap(_disguiseSwitch());
      await tester.pumpAndSettle();

      // The app's own face back first, then its widgets.
      expect(disguise.calls, ['disguise:false', 'widgets:true']);
      expect(disguise.disguised, isFalse);
      expect(notifications.cleared, 0);
    });

    testWidgets('removing the PIN while disguised drops the disguise with it', (
      tester,
    ) async {
      final bridge = _locked();
      final disguise = FakeDisguise(disguised: true);
      await tester.pumpWidget(_securityApp(bridge, disguise));
      await tester.pumpAndSettle();

      // The top switch turns the lock off.
      final appLock = find.descendant(
        of: find.ancestor(
          of: find.text('App lock'),
          matching: find.byType(Row),
        ),
        matching: find.byType(Switch),
      );
      await tester.tap(appLock);
      await tester.pumpAndSettle();

      // The sheet says the disguise goes too.
      expect(find.textContaining('turns the disguise off'), findsOneWidget);

      // The lock goes first, and only once the core agrees: a refused
      // secret leaves the launcher face exactly where it was.
      await tester.enterText(find.byKey(const Key('lock.current')), '0000');
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(find.text('wrong PIN or password'), findsOneWidget);
      expect(bridge.lock, isNotNull);
      expect(disguise.disguised, isTrue);
      expect(disguise.calls, isEmpty);

      await tester.tap(appLock);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(bridge.lock, isNull);
      expect(disguise.disguised, isFalse);
      expect(disguise.calls, ['disguise:false', 'widgets:true']);
    });
  });

  group('a disguise that outlived its lock', () {
    testWidgets('is taken off as soon as the vault says there is none', (
      tester,
    ) async {
      // The lock went without the settings card: storage the system
      // cleared, a backup restored elsewhere. The launcher still shows
      // the calculator, and nothing would ask for a PIN behind it.
      final disguise = FakeDisguise(disguised: true);
      final bridge = FakeBridge(
        wallets: [makeMeta()],
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            disguiseServiceProvider.overrideWithValue(disguise),
            biometricGateProvider.overrideWithValue(_NoBiometrics()),
            windowGuardProvider.overrideWithValue(FakeWindowGuard()),
          ],
          child: const GerfautApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The app opens on its wallets, as any vault without a lock does,
      // and the launcher gets its own face and its widgets back.
      expect(find.text('Cold storage'), findsOneWidget);
      expect(disguise.disguised, isFalse);
      expect(disguise.calls, ['disguise:false', 'widgets:true']);
    });

    testWidgets('stays while a lock stands', (tester) async {
      final disguise = FakeDisguise(disguised: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(_locked()),
            disguiseServiceProvider.overrideWithValue(disguise),
            biometricGateProvider.overrideWithValue(_NoBiometrics()),
            windowGuardProvider.overrideWithValue(FakeWindowGuard()),
          ],
          child: const GerfautApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(disguise.disguised, isTrue);
      expect(disguise.calls, isEmpty);
    });
  });

  group('notifications while disguised', () {
    test('the open app posts nothing when disguised', () async {
      final service = _RecordingNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()])..syncedIds.add('w1');
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(
            FakeDisguise(disguised: true),
          ),
          notificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      // Notifications turned on, and the disguise hydrated to true.
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      container.read(disguiseProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(disguiseProvider).disguised, isTrue);

      final synced = SyncReport(
        walletId: 'w1',
        newTxCount: 1,
        newTxs: [NewTx(txid: 'a', netSats: 1000, confirmed: true)],
        balance: makeBalance(0),
        tipHeight: 1,
        tookMs: 1,
        backend: 'x',
      );
      // What the core does after the sync: the news waits for a claim.
      bridge.recordNews(synced);
      await container.read(syncAnnouncerProvider).announce([synced]);

      expect(service.posted, isEmpty);
    });

    test('the open app posts when not disguised', () async {
      final service = _RecordingNotifications();
      final bridge = FakeBridge(wallets: [makeMeta()])..syncedIds.add('w1');
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          notificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      container.read(notifyNewTxProvider.notifier).hydrate('1');
      container.read(disguiseProvider);
      await Future<void>.delayed(Duration.zero);

      final synced = SyncReport(
        walletId: 'w1',
        newTxCount: 1,
        newTxs: [NewTx(txid: 'a', netSats: 1000, confirmed: true)],
        balance: makeBalance(0),
        tipHeight: 1,
        tookMs: 1,
        backend: 'x',
      );
      // What the core does after the sync: the news waits for a claim.
      bridge.recordNews(synced);
      await container.read(syncAnnouncerProvider).announce([synced]);

      // A wallet seen for the first time this run hands over its whole
      // history, which the announcer holds back; a second sync speaks.
      await container.read(syncAnnouncerProvider).announce([
        SyncReport(
          walletId: 'w1',
          newTxCount: 1,
          newTxs: [NewTx(txid: 'b', netSats: 2000, confirmed: true)],
          balance: makeBalance(0),
          tipHeight: 1,
          tookMs: 1,
          backend: 'x',
        ),
      ]);

      expect(service.posted, isNotEmpty);
    });

    test('the background check posts nothing when disguised', () async {
      final service = _RecordingNotifications();
      final bridge = FakeBridge(
        wallets: [makeMeta()],
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'notify.new_tx': '1'},
        ),
      );
      final ran = await runBackgroundCheck(
        bridge: bridge,
        service: service,
        bootstrap: () async {},
        isDisguised: () async => true,
      );
      expect(ran, isTrue);
      expect(service.posted, isEmpty);
    });
  });
}
