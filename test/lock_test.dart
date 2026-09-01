import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/security_section.dart';
import 'package:gerfaut/screens/welcome.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

/// Answers the phone's prompt the way a test asks it to.
class FakeBiometrics implements BiometricGate {
  FakeBiometrics({this.available = true, this.passes = true});

  bool available;
  bool passes;
  int prompts = 0;

  @override
  Future<bool> canCheck() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return passes;
  }
}

const AppLock pinLock = AppLock(kind: LockKind.pin, biometric: false);

FakeBridge locked({
  AppLock lock = pinLock,
  String secret = '1234',
  List<WalletMeta> wallets = const [],
}) {
  return FakeBridge(
      wallets: wallets,
      settings: const Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {'onboarding.seen': '1'},
      ),
    )
    ..lock = lock
    ..lockSecret = secret;
}

/// Every test substitutes the sensor: a widget test must never reach
/// the platform, which under a test binding simply never answers.
List<Override> _overrides(
  FakeBridge bridge,
  FakeBiometrics? biometrics, {
  FakeWindowGuard? guard,
}) => [
  bridgeProvider.overrideWithValue(bridge),
  biometricGateProvider.overrideWithValue(
    biometrics ?? FakeBiometrics(available: false),
  ),
  windowGuardProvider.overrideWithValue(guard ?? FakeWindowGuard()),
];

Widget app(
  FakeBridge bridge, {
  FakeBiometrics? biometrics,
  FakeWindowGuard? guard,
}) {
  return ProviderScope(
    overrides: _overrides(bridge, biometrics, guard: guard),
    child: const GerfautApp(),
  );
}

/// Sends a lifecycle state the way the platform does, so the test
/// walks the states the framework really synthesizes in between — the
/// hidden state lands on the way back in as well as on the way out.
Future<void> sendLifecycle(WidgetTester tester, AppLifecycleState state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage('$state'),
    (_) {},
  );
}

/// The lock as the vault hands it over: a PIN is set, so the screen
/// is up and the test unlocks it the way the user would.
({ProviderContainer container, LockController lock}) lockedApp() {
  final container = ProviderContainer(overrides: _overrides(locked(), null));
  addTearDown(container.dispose);
  final lock = container.read(lockProvider.notifier);
  lock.syncFromSettings(pinLock);
  return (container: container, lock: lock);
}

/// Pumps the whole app on a container the test keeps hold of, and
/// walks past the lock screen the way the user does.
Future<ProviderContainer> pumpUnlocked(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: _overrides(locked(wallets: [makeMeta()]), null),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const GerfautApp()),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '1234');
  await tester.tap(find.text('Unlock'));
  await tester.pumpAndSettle();
  return container;
}

Widget settingsApp(FakeBridge bridge, {FakeBiometrics? biometrics}) {
  return ProviderScope(
    overrides: _overrides(bridge, biometrics),
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const SettingsScreen(),
    ),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the lock screen', () {
    testWidgets('a vault with a lock opens locked, and nothing is behind it', (
      tester,
    ) async {
      await tester.pumpWidget(app(locked(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      // Not a wallet in the tree: the lock replaces the app.
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('a wrong PIN is said plainly and the screen stays', (
      tester,
    ) async {
      final bridge = locked();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(find.byType(LockScreen), findsOneWidget);
    });

    testWidgets('the right PIN opens the app', (tester) async {
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('past three failures the wait is counted down', (tester) async {
      final bridge = locked();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.enterText(find.byType(TextField), '0000');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Too many attempts. Try again in 5 s'), findsOneWidget);
      final button = tester.widget<TextField>(find.byType(TextField));
      expect(button.enabled, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many attempts. Try again in 4 s'), findsOneWidget);
      // Let the countdown finish so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a PIN field takes digits only', (tester) async {
      await tester.pumpWidget(app(locked()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '12ab34');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1234',
      );
    });

    testWidgets('a phone that confirms opens the app without the secret', (
      tester,
    ) async {
      final biometrics = FakeBiometrics();
      await tester.pumpWidget(
        app(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(biometrics.prompts, 1);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('a refused prompt leaves the secret field', (tester) async {
      final biometrics = FakeBiometrics(passes: false);
      await tester.pumpWidget(
        app(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Use fingerprint or face'), findsOneWidget);
    });
  });

  group('the security card', () {
    testWidgets('turning the lock on asks twice and stores the kind', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SecuritySection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn on the app lock'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('lock.secret')), '1234');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(bridge.lockCalls, contains('set:pin'));
      expect(bridge.lock?.kind, LockKind.pin);
    });

    testWidgets('a mismatch never reaches the core', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SecuritySection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.secret')), '1234');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '4321');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.text('The two entries differ.'), findsOneWidget);
      expect(bridge.lockCalls, isEmpty);
    });

    testWidgets('a PIN shorter than four digits is refused on the spot', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SecuritySection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.secret')), '12');
      await tester.enterText(find.byKey(const Key('lock.confirm')), '12');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.text('A PIN is 4 to 12 digits.'), findsOneWidget);
      expect(bridge.lockCalls, isEmpty);
    });

    testWidgets('turning it off asks for the secret in place', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SecuritySection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '1234');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(bridge.lockCalls, contains('clear'));
      expect(bridge.lock, isNull);
    });

    testWidgets('a wrong secret leaves the lock in place, and says so', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(SecuritySection),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lock.current')), '0000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(find.text('wrong PIN or password'), findsOneWidget);
      expect(bridge.lock, isNotNull);
    });

    testWidgets('there is no delay to choose, and the card says so', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(settingsApp(locked()));
      await tester.pumpAndSettle();

      expect(find.text('Lock after'), findsNothing);
      expect(find.text('Immediately'), findsNothing);
      expect(find.text('Never'), findsNothing);
      expect(
        find.textContaining('every time it comes back from the background'),
        findsOneWidget,
      );
      // What the card still offers is unchanged.
      expect(find.text('Change PIN'), findsOneWidget);
      expect(find.text('Lock now'), findsOneWidget);
    });

    testWidgets('biometrics are offered only where the phone can answer', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(
        settingsApp(bridge, biometrics: FakeBiometrics(available: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlock with biometrics'), findsNothing);

      await tester.pumpWidget(
        settingsApp(locked(), biometrics: FakeBiometrics()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlock with biometrics'), findsOneWidget);
    });

    testWidgets('locking from a pushed screen brings the lock to the front', (
      tester,
    ) async {
      // The settings live above the home route: a lock that only
      // replaced the home would sit behind them, in plain view.
      useTallSurface(tester);
      final bridge = locked(wallets: [makeMeta()]);
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Network'), findsOneWidget);

      await tester.tap(find.text('Lock now'));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      // Nothing of the settings, and nothing of a wallet, is behind it.
      expect(find.text('Network'), findsNothing);
      expect(find.text('Cold storage'), findsNothing);
    });
  });

  group('the window', () {
    testWidgets('a vault with a lock marks the window secure', (tester) async {
      final guard = FakeWindowGuard();
      await tester.pumpWidget(app(locked(), guard: guard));
      await tester.pumpAndSettle();

      // The task switcher photographs the app before the lock draws;
      // only the window flag keeps a balance out of that picture.
      expect(guard.secure, isTrue);
    });

    testWidgets('a vault without a lock leaves the window plain', (
      tester,
    ) async {
      final guard = FakeWindowGuard();
      await tester.pumpWidget(app(FakeBridge(), guard: guard));
      await tester.pumpAndSettle();

      // Said once, and as plain: screenshots keep working, for the user
      // who wants to show a screen as much as for the emulator tests.
      expect(guard.calls, [false]);
    });

    test('the window follows the lock as the settings change', () {
      final guard = FakeWindowGuard();
      final container = ProviderContainer(
        overrides: _overrides(locked(), null, guard: guard),
      );
      addTearDown(container.dispose);
      final lock = container.read(lockProvider.notifier);

      lock.syncFromSettings(pinLock);
      expect(guard.secure, isTrue);

      // A refetch that says the same thing does not ask again.
      lock.syncFromSettings(pinLock);
      expect(guard.calls, [true]);

      // Turning the lock off hands the window back.
      lock.syncFromSettings(null);
      expect(guard.calls, [true, false]);

      // And on again, from the settings card, secures it again.
      lock.syncFromSettings(pinLock);
      expect(guard.calls, [true, false, true]);
    });
  });

  group('the welcome tour', () {
    testWidgets('a vault with nothing in it introduces the app', (
      tester,
    ) async {
      await tester.pumpWidget(app(FakeBridge()));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Watch, never spend'), findsOneWidget);
    });

    testWidgets('it is not shown again once seen', (tester) async {
      final bridge = FakeBridge(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('a vault that already holds a wallet skips it', (tester) async {
      await tester.pumpWidget(app(FakeBridge(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('walking to the end remembers it and lands on the wallets', (
      tester,
    ) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      for (var page = 0; page < welcomePages.length - 1; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Keep it yours'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['onboarding.seen'], '1');
      expect(find.text('No wallets yet'), findsOneWidget);
    });

    testWidgets('back is offered from the second page on', (tester) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      // Nothing to go back to on the first page: Skip has the row.
      expect(find.text('Back'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      // Back takes the left of the row Skip had to itself.
      expect(
        tester.getRect(find.text('Back')).left,
        lessThan(tester.getRect(find.text('Skip')).left),
      );

      // A page one can only leave or pass is re-read by starting over.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Watch, never spend'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      // Going back is not leaving: the tour is still unseen.
      expect(bridge.appPrefs['onboarding.seen'], isNull);

      // The swipe still does the same work; the button makes it visible.
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('skipping counts as seen', (tester) async {
      final bridge = FakeBridge();
      await tester.pumpWidget(app(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(bridge.appPrefs['onboarding.seen'], '1');
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('the settings can play it again', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        settings: const Settings(
          activeNetwork: Network.mainnet,
          backends: {},
          appPrefs: {'onboarding.seen': '1'},
        ),
      );
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show the welcome tour'));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('coming back from the background', () {
    test('any trip away at all asks for the secret again', () async {
      final app = lockedApp();
      expect(app.container.read(lockProvider).locked, isTrue);
      await app.lock.unlock('1234');
      expect(app.container.read(lockProvider).locked, isFalse);

      // Straight there and straight back: no delay to outlast.
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);

      // A settings refetch never re-locks an app already open.
      await app.lock.unlock('1234');
      app.lock.syncFromSettings(pinLock);
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('a return with no trip behind it leaves the app open', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // A permission dialog and the notification shade never hide the
      // app: there is nothing to come back from.
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('with no lock set, nothing ever locks', () async {
      final container = ProviderContainer(
        overrides: _overrides(FakeBridge(), null),
      );
      addTearDown(container.dispose);
      final lock = container.read(lockProvider.notifier);

      lock.syncFromSettings(null);
      expect(container.read(lockProvider).locked, isFalse);
      lock.noteHidden();
      lock.noteResumed();
      expect(container.read(lockProvider).locked, isFalse);
      lock.lockNow();
      expect(container.read(lockProvider).locked, isFalse);
    });
  });

  group('a system screen Gerfaut opened itself', () {
    test('coming back from a picker does not lock', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);
    });

    test('it covers its own return and nothing after it', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // Picked or waved away, the file picker gives back the same
      // return, and that return is the one it was announced for.
      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('one the phone never shows does not outlive its return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // The permission was granted already, so nothing came up and the
      // app never left the screen.
      app.lock.expectExcursion();
      app.lock.noteResumed();

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('two in a row each cover their own return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      for (var trip = 0; trip < 2; trip++) {
        app.lock.expectExcursion();
        app.lock.noteHidden();
        app.lock.noteResumed();
        expect(app.container.read(lockProvider).locked, isFalse);
      }

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('asking twice before leaving still buys one return', () async {
      final app = lockedApp();
      await app.lock.unlock('1234');

      // A screen that announces the same excursion twice has not
      // bought a second one.
      app.lock.expectExcursion();
      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isFalse);

      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });

    test('one asked for while locked leaves the screen up', () async {
      final app = lockedApp();
      expect(app.container.read(lockProvider).locked, isTrue);

      app.lock.expectExcursion();
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);

      // And it was spent there: the first trip after the unlock locks.
      await app.lock.unlock('1234');
      app.lock.noteHidden();
      app.lock.noteResumed();
      expect(app.container.read(lockProvider).locked, isTrue);
    });
  });

  group('the app as the platform moves it', () {
    testWidgets('a trip through the background brings the lock back', (
      tester,
    ) async {
      await pumpUnlocked(tester);
      expect(find.text('Cold storage'), findsOneWidget);

      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('a picker Gerfaut opened leaves the flow where it was', (
      tester,
    ) async {
      useTallSurface(tester);
      final container = await pumpUnlocked(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Network'), findsOneWidget);

      container.read(lockProvider.notifier).expectExcursion();
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Back from a file picker the user opened two seconds ago: the
      // screen they were on is still there, with no lock in front.
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('Network'), findsOneWidget);

      // A real absence right after still locks, and takes the pushed
      // screen with it.
      await sendLifecycle(tester, AppLifecycleState.paused);
      await sendLifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Network'), findsNothing);
    });
  });
}
