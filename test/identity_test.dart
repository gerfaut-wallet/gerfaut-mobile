import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/screens/confirm_identity.dart';
import 'package:gerfaut/screens/settings/premium_section.dart';
import 'package:gerfaut/src/identity.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:local_auth/local_auth.dart';

import 'fakes.dart';
import 'premium_harness.dart';

/// A channel the account already has, to take away.
const PremiumChannel ntfyChannel = PremiumChannel(
  id: 'ch1',
  kind: ChannelKind.ntfy,
  target: 'ntfy.gerfaut-wallet.com/ab***',
  linked: true,
  createdAt: 1,
);

/// Opens the channel's menu, chooses Remove, and answers the question
/// under the row: what every test below asks the owner to prove.
Future<void> askToRemove(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More for ntfy'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
  await tester.pumpAndSettle();
}

/// The phone's own authentication, answering what the test says.
class _Auth extends LocalAuthentication {
  _Auth({this.supported = true, this.answer, this.failure});

  final bool supported;
  final bool? answer;
  final LocalAuthException? failure;
  bool? biometricOnly;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    this.biometricOnly = biometricOnly;
    final failure = this.failure;
    if (failure != null) throw failure;
    return answer ?? false;
  }
}

void main() {
  group('the phone screen lock', () {
    test('lets the phone code stand in for a finger', () async {
      final auth = _Auth(answer: true);
      expect(
        await SystemScreenLockGate(auth).confirm(confirmItsYouTitle),
        ScreenLockOutcome.confirmed,
      );
      expect(auth.biometricOnly, isFalse);
    });

    test('a phone with no lock has nothing to ask with', () async {
      expect(
        await SystemScreenLockGate(_Auth(supported: false)).confirm('x'),
        ScreenLockOutcome.unavailable,
      );
      expect(
        await SystemScreenLockGate(
          _Auth(
            failure: const LocalAuthException(
              code: LocalAuthExceptionCode.noCredentialsSet,
            ),
          ),
        ).confirm('x'),
        ScreenLockOutcome.unavailable,
      );
    });

    test('a cancelled or failed prompt is a no', () async {
      expect(
        await SystemScreenLockGate(_Auth(answer: false)).confirm('x'),
        ScreenLockOutcome.refused,
      );
      expect(
        await SystemScreenLockGate(
          _Auth(
            failure: const LocalAuthException(
              code: LocalAuthExceptionCode.userCanceled,
            ),
          ),
        ).confirm('x'),
        ScreenLockOutcome.refused,
      );
    });
  });

  group('with an app lock', () {
    FakeBridge locked() {
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(ntfyChannel);
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      return bridge;
    }

    testWidgets('its PIN is asked, and a wrong one sends nothing', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      final screenLock = FakeScreenLock();
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(find.byType(ConfirmItsYouSheet), findsOneWidget);
      expect(find.text(confirmItsYouTitle), findsOneWidget);
      // The app lock answers for the phone: its own prompt is not put.
      expect(screenLock.asked, isEmpty);

      await tester.enterText(find.byKey(const Key('identity.secret')), '9999');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));

      await tester.enterText(find.byKey(const Key('identity.secret')), '1234');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmItsYouSheet), findsNothing);
      expect(bridge.premiumCalls, contains('delete:ch1'));
      // The same count as the lock screen, reset by the right secret.
      expect(bridge.lockCalls.where((c) => c == 'verify'), hasLength(2));
      expect(bridge.lockFailures, 0);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('too many wrong secrets make it wait, counting down', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byKey(const Key('identity.secret')),
          '000$i',
        );
        await tester.tap(find.widgetWithText(PrimaryButton, 'Confirm'));
        await tester.pump();
        await tester.pump();
      }
      expect(find.text('Too many attempts. Try again in 5 s'), findsOneWidget);
      final confirm = find.widgetWithText(PrimaryButton, 'Confirm');
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('identity.secret')))
            .enabled,
        isFalse,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many attempts. Try again in 4 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('Too many attempts'), findsNothing);
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNotNull);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));
    });

    testWidgets('a cancelled check leaves the question up, answerable', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      await tester.tap(find.widgetWithText(GhostButton, 'Cancel').last);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmItsYouSheet), findsNothing);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));
      expect(find.text(removeChannelQuestion), findsOneWidget);
      final remove = find.widgetWithText(DangerButton, 'Remove');
      expect(tester.widget<DangerButton>(remove).onPressed, isNotNull);
    });

    testWidgets('biometrics answer when the lock takes them', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: true);
      final fingerprint = FakeFingerprint();
      await tester.pumpWidget(premiumApp(bridge, fingerprint: fingerprint));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      // Offered at once, without a tap: the finger is the short way.
      expect(fingerprint.asked, [confirmItsYouTitle]);
      expect(bridge.lockCalls, isNot(contains('verify')));
      expect(bridge.premiumCalls, contains('delete:ch1'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused finger leaves the secret to type', (tester) async {
      useTallSurface(tester);
      final bridge = locked();
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: true);
      final fingerprint = FakeFingerprint(passes: false);
      await tester.pumpWidget(premiumApp(bridge, fingerprint: fingerprint));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(find.byType(ConfirmItsYouSheet), findsOneWidget);
      expect(find.text('Use fingerprint or face'), findsOneWidget);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));
    });

    testWidgets('a password lock asks the password, eye and all', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = locked();
      bridge.lock = const AppLock(kind: LockKind.password, biometric: false);
      bridge.lockSecret = 'correct horse';
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('identity.secret')),
        'correct horse',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('delete:ch1'));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('without an app lock', () {
    FakeBridge open() {
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(ntfyChannel);
      return bridge;
    }

    testWidgets('the phone screen lock answers', (tester) async {
      useTallSurface(tester);
      final bridge = open();
      final screenLock = FakeScreenLock();
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(screenLock.asked, [confirmItsYouTitle]);
      expect(bridge.premiumCalls, contains('delete:ch1'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refusal sends nothing and keeps the question', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = open();
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.refused);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));
      expect(find.text(removeChannelQuestion), findsOneWidget);
    });

    testWidgets('a phone with no lock at all is sent to set an app lock', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = open();
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.unavailable);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(find.text(appLockNeededMessage), findsOneWidget);
      expect(bridge.premiumCalls, isNot(contains('delete:ch1')));

      await tester.tap(find.text('Set an app lock'));
      await tester.pumpAndSettle();
      expect(find.text('Security'), findsWidgets);
      expect(find.text('App lock'), findsOneWidget);
    });
  });

  group('what asks', () {
    testWidgets('a second tap does not open a second prompt', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(ntfyChannel);
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await askToRemove(tester);
      expect(find.byType(ConfirmItsYouSheet), findsOneWidget);
      // Under the sheet, the question's answers are held.
      final remove = find.widgetWithText(DangerButton, 'Remove');
      expect(tester.widget<DangerButton>(remove).onPressed, isNull);
    });

    testWidgets('deleting the account asks, forgetting the key does not', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.refused);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete and forget'));
      await tester.pumpAndSettle();
      expect(screenLock.asked, hasLength(1));
      expect(bridge.premiumAccountDeleted, isFalse);
      expect(bridge.premiumKey, isNotNull);

      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget key'));
      await tester.pumpAndSettle();
      expect(screenLock.asked, hasLength(1));
      expect(bridge.premiumKey, isNull);
    });

    testWidgets('unwatching a wallet asks', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      bridge.premiumWatched.add(
        const WalletWatch(
          id: 'w1',
          name: 'Cold storage',
          scriptKind: 'segwit',
          watchedSince: 1,
          baselineAt: 2,
          baselineHeight: 900000,
          coins: 1,
          valueSats: 1,
        ),
      );
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.refused);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(screenLock.asked, hasLength(1));
      expect(bridge.premiumCalls, isNot(contains('unwatch:w1')));

      screenLock.outcome = ScreenLockOutcome.confirmed;
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('unwatch:w1'));
    });
  });
}
