// The preferences a background isolate acts on, as the vault takes them
// or refuses them. The periodic task and the Live service read them
// fresh from the vault: a switch on screen that the vault does not hold
// is a promise nothing keeps.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/live.dart';
import 'package:gerfaut/src/notifications.dart';
import 'package:gerfaut/src/onboarding.dart';
import 'package:gerfaut/src/prefs.dart';
import 'package:gerfaut/src/state.dart';

import 'core_fixtures.dart';
import 'fakes.dart';

/// Grants the permission and records nothing else.
class _Granting implements NotificationService {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> deliverable() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A vault whose writes of this app's preferences wait for the test,
/// or are refused while [refusing].
class _AppPrefsGate extends FakeBridge {
  _AppPrefsGate({super.wallets});

  bool refusing = false;
  final List<Completer<void>> _gates = [];

  void release() => _gates.removeAt(0).complete();

  bool get waiting => _gates.isNotEmpty;

  @override
  Future<void> setAppPref(String key, String value) async {
    if (refusing) throw coreFailure('vault', 'disk full');
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return super.setAppPref(key, value);
  }
}

void main() {
  late List<int> scheduled;
  late FakeLivePlatform platform;

  ProviderContainer screens(FakeBridge bridge) {
    scheduled = [];
    platform = FakeLivePlatform();
    final made = ProviderContainer(
      retry: noRetry,
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        notificationServiceProvider.overrideWithValue(_Granting()),
        backgroundSchedulerProvider.overrideWithValue((seconds) async {
          scheduled.add(seconds);
        }),
        livePlatformProvider.overrideWithValue(platform),
        disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      ],
    );
    addTearDown(made.dispose);
    made.read(preferencesProvider.notifier).hydrate(bridge.preferences);
    return made;
  }

  group('the new-transaction notice', () {
    test('goes back off when the vault refuses it twice', () async {
      final bridge = FakeBridge(wallets: [makeMeta()])
        ..onSetPreferences = (_, _) => throw coreFailure('vault', 'disk full');
      final made = screens(bridge);
      made.read(backgroundCheckProvider.notifier).hydrate('900');

      await made.read(notifyNewTxProvider.notifier).set(true);

      // The periodic task reads "off" from the vault and says nothing:
      // the switch says the same, and nothing is scheduled for it.
      expect(bridge.preferences.notifyNewTx, isFalse);
      expect(made.read(notifyNewTxProvider), isFalse);
      expect(scheduled.where((seconds) => seconds > 0), isEmpty);
      expect(platform.calls, isNot(contains('start')));
    });

    test('is in the vault before Live is asked to start', () async {
      final gate = GatedBridge()..wallets = [makeMeta()];
      final made = screens(gate);
      made.read(backgroundCheckProvider.notifier).hydrate('live');

      final on = made.read(notifyNewTxProvider.notifier).set(true);
      await pumpEventQueue();
      // The service reads the notice from the vault as it starts: asked
      // now, it would read "off" and stand down.
      expect(platform.calls, isEmpty);
      expect(scheduled, isEmpty);

      gate.release();
      await on;
      expect(gate.preferences.notifyNewTx, isTrue);
      expect(platform.calls, ['start']);
      expect(scheduled, [BackgroundCheck.live.seconds]);
    });
  });

  group('the background cadence', () {
    test('is in the vault before Live is asked to start', () async {
      final gate = _AppPrefsGate(wallets: [makeMeta()])
        ..preferences = kPreferences.copyWith(notifyNewTx: true);
      final made = screens(gate);

      final chosen = made
          .read(backgroundCheckProvider.notifier)
          .set(BackgroundCheck.live);
      await pumpEventQueue();
      expect(gate.waiting, isTrue);
      expect(platform.calls, isEmpty);

      gate.release();
      await chosen;
      expect(gate.appPrefs[Pref.background], 'live');
      expect(platform.calls, ['start']);
    });

    test('goes back to what the vault holds when it refuses', () async {
      final gate = _AppPrefsGate(wallets: [makeMeta()])
        ..preferences = kPreferences.copyWith(notifyNewTx: true)
        ..refusing = true;
      final made = screens(gate);
      made.read(backgroundCheckProvider.notifier).hydrate('3600');

      await made
          .read(backgroundCheckProvider.notifier)
          .set(BackgroundCheck.live);

      // The task and Live follow what the vault holds.
      expect(made.read(backgroundCheckProvider), BackgroundCheck.hour);
      expect(platform.calls, isNot(contains('start')));
      expect(scheduled, [BackgroundCheck.hour.seconds]);
    });
  });

  group('the disguise', () {
    test('stops Live even when the vault keeps it as the choice', () async {
      final gate = _AppPrefsGate(wallets: [makeMeta()])
        ..preferences = kPreferences.copyWith(notifyNewTx: true)
        ..refusing = true;
      final made = screens(gate);
      made.read(backgroundCheckProvider.notifier).hydrate('live');
      platform
        ..running = true
        ..wanted = true;

      await made.read(disguiseProvider.notifier).set(true);

      // Its notification is headed with the app's name: whatever the
      // refused choice kept up, the service ends stopped.
      expect(platform.calls.last, 'stop');
    });
  });

  group('a preference of this app alone', () {
    test('a refused switch says what the isolates will read', () async {
      final gate = _AppPrefsGate()..refusing = true;
      final made = screens(gate);
      made.read(notifyDetailsProvider.notifier).hydrate(null);
      made.read(widgetBalancesProvider.notifier).hydrate(null);

      expect(
        await made.read(notifyDetailsProvider.notifier).set(false),
        Shown.refused,
      );
      expect(
        await made.read(widgetBalancesProvider.notifier).set(true),
        Shown.refused,
      );
      expect(made.read(notifyDetailsProvider), isTrue);
      expect(made.read(widgetBalancesProvider), isFalse);
    });

    test('a tour closed stays closed, the vault refusing or not', () async {
      final gate = _AppPrefsGate()..refusing = true;
      final made = screens(gate);
      made.read(onboardingSeenProvider.notifier).markSeen();
      await pumpEventQueue();
      expect(made.read(onboardingSeenProvider), isTrue);
    });

    test('the isolates read by the rule the screens hydrate by', () {
      for (final stored in <String?>[null, '', '0', '1', 'live', 'junk']) {
        final raw = {
          Pref.notifyDetails: ?stored,
          Pref.background: ?stored,
          Pref.widgetBalances: ?stored,
        };
        final made = screens(FakeBridge());
        made.read(notifyDetailsProvider.notifier).hydrate(stored);
        made.read(backgroundCheckProvider.notifier).hydrate(stored);
        made.read(widgetBalancesProvider.notifier).hydrate(stored);
        expect(
          AppPrefs(raw).notifyDetails,
          made.read(notifyDetailsProvider),
          reason: 'details, stored $stored',
        );
        expect(
          AppPrefs(raw).background,
          made.read(backgroundCheckProvider),
          reason: 'cadence, stored $stored',
        );
        expect(
          AppPrefs(raw).widgetBalances,
          made.read(widgetBalancesProvider),
          reason: 'widget balances, stored $stored',
        );
      }
    });
  });

  group('two changes in a row', () {
    test('the vault refusing the second, the task and Live follow '
        'the first', () async {
      final gate = GatedBridge()..wallets = [makeMeta()];
      final made = screens(gate);
      made.read(backgroundCheckProvider.notifier).hydrate('live');

      final on = made.read(notifyNewTxProvider.notifier).set(true);
      await pumpEventQueue();
      final off = made.read(notifyNewTxProvider.notifier).set(false);
      gate.release();
      await pumpEventQueue();
      gate.refuse();
      await pumpEventQueue();
      gate.refuse();
      await Future.wait([on, off]);

      // The vault took the "on" and refused the "off": the switch, the
      // task and Live are on, as the vault is.
      expect(gate.preferences.notifyNewTx, isTrue);
      expect(made.read(notifyNewTxProvider), isTrue);
      expect(scheduled.last, BackgroundCheck.live.seconds);
      expect(platform.calls.last, 'start');
    });
  });
}
