import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/calculator.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/src/calculator.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/window.dart';

import 'fakes.dart';

/// Answers the phone's prompt the way a test asks it to. Kept here so
/// the disguise tests can prove the calculator never raises it.
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

/// Types a run of keys into a calculator, one character at a time:
/// digits, '.', the operator glyphs, and the words c and =.
void type(Calculator calc, String keys) {
  for (final ch in keys.split('')) {
    switch (ch) {
      case ' ':
        break;
      case '.':
        calc.decimal();
      case '+':
        calc.operator(CalcOp.add);
      case '-':
        calc.operator(CalcOp.subtract);
      case '*':
        calc.operator(CalcOp.multiply);
      case '/':
        calc.operator(CalcOp.divide);
      case '%':
        calc.percent();
      case '~':
        calc.negate();
      case '=':
        calc.equals();
      case 'c':
        calc.clear();
      case '<':
        calc.backspace();
      default:
        calc.digit(int.parse(ch));
    }
  }
}

String eval(String keys) {
  final calc = Calculator();
  type(calc, keys);
  return calc.display;
}

Widget disguisedApp(
  FakeBridge bridge, {
  FakeDisguise? disguise,
  FakeBiometrics? biometrics,
  FakeWindowGuard? guard,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(
        disguise ?? FakeDisguise(disguised: true),
      ),
      biometricGateProvider.overrideWithValue(
        biometrics ?? FakeBiometrics(available: false),
      ),
      windowGuardProvider.overrideWithValue(guard ?? FakeWindowGuard()),
    ],
    child: const GerfautApp(),
  );
}

void main() {
  group('the evaluator', () {
    test('adds, subtracts, multiplies and divides', () {
      expect(eval('12+34='), '46');
      expect(eval('50-8='), '42');
      expect(eval('6*7='), '42');
      expect(eval('84/2='), '42');
    });

    test('runs times and divide before plus and minus', () {
      expect(eval('2+3*4='), '14');
      expect(eval('2*3+4='), '10');
      expect(eval('10-2*3='), '4');
    });

    test('runs equal operators left to right', () {
      expect(eval('10-2-3='), '5');
      expect(eval('100/2/5='), '10');
    });

    test('percent of a pending sum adds a proportion', () {
      expect(eval('200+10%='), '220');
      expect(eval('200-10%='), '180');
    });

    test('percent of a bare number is a hundredth', () {
      expect(eval('50%'), '0.5');
      expect(eval('200*10%='), '20');
    });

    test('the sign key flips the entry', () {
      expect(eval('5~'), '-5');
      expect(eval('5~~'), '5');
    });

    test('divides down to a decimal with sensible precision', () {
      expect(eval('1/3='), '0.333333333333');
      expect(eval('10/4='), '2.5');
    });

    test('division by zero is an error, cleared by the next digit', () {
      final calc = Calculator();
      type(calc, '5/0=');
      expect(calc.display, 'Error');
      expect(calc.hasError, isTrue);
      type(calc, '7');
      expect(calc.display, '7');
    });

    test('backspace drops the last character typed', () {
      final calc = Calculator();
      type(calc, '123<');
      expect(calc.display, '12');
      type(calc, '<<');
      expect(calc.display, '0');
    });

    test('clear wipes the display and the history', () {
      final calc = Calculator();
      type(calc, '2+2=');
      expect(calc.history, '2 + 2 =');
      type(calc, 'c');
      expect(calc.display, '0');
      expect(calc.history, '');
    });

    test('large integers are grouped by thousands', () {
      expect(eval('12345*100='), '1,234,500');
    });

    test('a bare number reads back its digits, an expression does not', () {
      final bare = Calculator()
        ..digit(1)
        ..digit(2)
        ..digit(3)
        ..digit(4);
      expect(bare.bareDigits, '1234');

      final leading = Calculator()
        ..digit(0)
        ..digit(0)
        ..digit(4)
        ..digit(2);
      expect(leading.bareDigits, '0042', reason: 'a PIN keeps its zeros');

      final withOp = Calculator();
      type(withOp, '12+34');
      expect(withOp.bareDigits, isNull);

      final withDot = Calculator();
      type(withDot, '12.5');
      expect(withDot.bareDigits, isNull);

      final result = Calculator();
      type(result, '2+2=');
      expect(result.bareDigits, isNull, reason: 'a result is not typed');
    });
  });

  group('the calculator as the lock screen', () {
    testWidgets('a disguised locked vault shows the calculator, not the lock', (
      tester,
    ) async {
      await tester.pumpWidget(disguisedApp(locked(wallets: [makeMeta()])));
      await tester.pumpAndSettle();

      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
      // Nothing of a wallet is behind it.
      expect(find.text('Cold storage'), findsNothing);
    });

    testWidgets('the right PIN then equals opens the app', (tester) async {
      final bridge = locked(wallets: [makeMeta()]);
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(InkWell, d));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();

      expect(find.byType(CalculatorScreen), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
      expect(bridge.lockCalls, contains('verify'));
    });

    testWidgets('a wrong PIN shows the number, and says nothing', (
      tester,
    ) async {
      final bridge = locked();
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      for (final d in ['9', '9', '9', '9']) {
        await tester.tap(find.widgetWithText(InkWell, d));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();

      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.text('9,999'), findsOneWidget);
      expect(find.textContaining('Wrong'), findsNothing);
      expect(find.text('Error'), findsNothing);
      expect(bridge.lockCalls, contains('verify'));
    });

    testWidgets('a throttled verdict shows the number all the same', (
      tester,
    ) async {
      // Three failures already stand, so the core answers the next
      // guess with a delay. The calculator ignores it: no delay, no
      // hint, just the number.
      final bridge = locked()..lockFailures = 3;
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      for (final d in ['5', '6', '7', '8']) {
        await tester.tap(find.widgetWithText(InkWell, d));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();

      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.text('5,678'), findsOneWidget);
      expect(bridge.lockCalls, contains('verify'));
    });

    testWidgets('an expression with an operator never asks the core', (
      tester,
    ) async {
      final bridge = locked();
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Plus'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '6'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();

      // A sum whose result is two digits: no single key wears it, so
      // the one on the display is the one found.
      expect(bridge.lockCalls, isEmpty);
      expect(find.text('11'), findsOneWidget);
      expect(find.byType(CalculatorScreen), findsOneWidget);
    });

    testWidgets('a number too short for a PIN is only arithmetic', (
      tester,
    ) async {
      final bridge = locked(secret: '12');
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();

      // Three digits at least before the core is troubled: a two-key
      // sum must not wind the anti-PIN delay up.
      expect(bridge.lockCalls, isEmpty);
      expect(find.byType(CalculatorScreen), findsOneWidget);
    });

    testWidgets(
      'the calculator leaves the window plain, the wallet secures it',
      (tester) async {
        final guard = FakeWindowGuard();
        await tester.pumpWidget(
          disguisedApp(locked(wallets: [makeMeta()]), guard: guard),
        );
        await tester.pumpAndSettle();

        // A blank thumbnail titled "Calculator" would give the app away:
        // the calculator is photographed as any calculator is.
        expect(find.byType(CalculatorScreen), findsOneWidget);
        expect(guard.secure, isFalse);

        for (final d in ['1', '2', '3', '4']) {
          await tester.tap(find.widgetWithText(InkWell, d));
          await tester.pump();
        }
        await tester.tap(find.bySemanticsLabel('Equals'));
        await tester.pumpAndSettle();

        // The wallet is what the switcher must never show.
        expect(find.text('Cold storage'), findsOneWidget);
        expect(guard.secure, isTrue);
      },
    );

    testWidgets('no biometric prompt is ever raised while disguised', (
      tester,
    ) async {
      final biometrics = FakeBiometrics();
      await tester.pumpWidget(
        disguisedApp(
          locked(lock: const AppLock(kind: LockKind.pin, biometric: true)),
          biometrics: biometrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(biometrics.prompts, 0);
      expect(find.byType(CalculatorScreen), findsOneWidget);
    });
  });

  group('the gate under a disguise', () {
    testWidgets('not disguised, a locked vault shows the lock screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        disguisedApp(locked(), disguise: FakeDisguise(disguised: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(CalculatorScreen), findsNothing);
    });

    testWidgets('disguised but unlocked, the app is shown', (tester) async {
      final bridge = locked(wallets: [makeMeta()]);
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          disguiseServiceProvider.overrideWithValue(
            FakeDisguise(disguised: true),
          ),
          biometricGateProvider.overrideWithValue(
            FakeBiometrics(available: false),
          ),
          windowGuardProvider.overrideWithValue(FakeWindowGuard()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const GerfautApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(lockProvider.notifier).unlock('1234');
      await tester.pumpAndSettle();

      expect(find.byType(CalculatorScreen), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('the calculator returns after a trip to the background', (
      tester,
    ) async {
      final bridge = locked(wallets: [makeMeta()]);
      await tester.pumpWidget(disguisedApp(bridge));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(InkWell, d));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();
      expect(find.text('Cold storage'), findsOneWidget);

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.lifecycle.name,
        const StringCodec().encodeMessage('${AppLifecycleState.paused}'),
        (_) {},
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.lifecycle.name,
        const StringCodec().encodeMessage('${AppLifecycleState.resumed}'),
        (_) {},
      );
      await tester.pumpAndSettle();

      // The lock rose again, and disguised that means the calculator.
      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.text('Cold storage'), findsNothing);
    });
  });
}
