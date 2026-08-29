import 'package:flutter/material.dart';
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

const AppLock pinLock = AppLock(
  kind: LockKind.pin,
  autoLockSecs: 60,
  biometric: false,
);

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
List<Override> _overrides(FakeBridge bridge, FakeBiometrics? biometrics) => [
  bridgeProvider.overrideWithValue(bridge),
  biometricGateProvider.overrideWithValue(
    biometrics ?? FakeBiometrics(available: false),
  ),
];

Widget app(FakeBridge bridge, {FakeBiometrics? biometrics}) {
  return ProviderScope(
    overrides: _overrides(bridge, biometrics),
    child: const GerfautApp(),
  );
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
  group('when the lock comes back', () {
    test('never on return when the timing is off', () {
      expect(
        shouldLock(away: const Duration(hours: 5), autoLockSecs: null),
        isFalse,
      );
    });

    test('at once when the timing is zero', () {
      expect(shouldLock(away: Duration.zero, autoLockSecs: 0), isTrue);
    });

    test('only past the chosen delay', () {
      expect(
        shouldLock(away: const Duration(seconds: 59), autoLockSecs: 60),
        isFalse,
      );
      expect(
        shouldLock(away: const Duration(seconds: 60), autoLockSecs: 60),
        isTrue,
      );
      expect(
        shouldLock(away: const Duration(minutes: 5), autoLockSecs: 60),
        isTrue,
      );
    });
  });

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
          locked(
            lock: const AppLock(
              kind: LockKind.pin,
              autoLockSecs: 60,
              biometric: true,
            ),
          ),
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
          locked(
            lock: const AppLock(
              kind: LockKind.pin,
              autoLockSecs: 60,
              biometric: true,
            ),
          ),
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

    testWidgets('the delay before it asks again is persisted', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(settingsApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('5 minutes'));
      await tester.pumpAndSettle();

      expect(bridge.lock?.autoLockSecs, 300);
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

  group('locking again on its own', () {
    test('an app away longer than the delay comes back locked', () async {
      final bridge = locked();
      final container = ProviderContainer(overrides: _overrides(bridge, null));
      addTearDown(container.dispose);

      await container.read(lockProvider.notifier).load();
      expect(container.read(lockProvider).locked, isTrue);
      await container.read(lockProvider.notifier).unlock('1234');
      expect(container.read(lockProvider).locked, isFalse);

      // Back at once, under the minute: still open.
      container.read(lockProvider.notifier).noteHidden();
      container.read(lockProvider.notifier).noteResumed();
      expect(container.read(lockProvider).locked, isFalse);
    });

    test('with no lock set, nothing ever locks', () async {
      final container = ProviderContainer(
        overrides: _overrides(FakeBridge(), null),
      );
      addTearDown(container.dispose);

      await container.read(lockProvider.notifier).load();
      expect(container.read(lockProvider).locked, isFalse);
      container.read(lockProvider.notifier).lockNow();
      expect(container.read(lockProvider).locked, isFalse);
    });
  });
}
