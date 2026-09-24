import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/premium.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/widgets/alert_banner.dart';
import 'package:gerfaut/widgets/buttons.dart';

import 'fakes.dart';
import 'premium_harness.dart';

const String newDeviceBanner =
    'A new device asks for access to your Premium account. If it is not '
    'yours, refuse it and change your key.';

/// A key activated first on this phone, a Windows computer that entered
/// it an hour ago and waits.
FakeBridge withWaitingComputer({bool notifying = true}) {
  final bridge = premiumBridge(activated: true);
  bridge.premiumAddDevice();
  if (notifying) notifyOn(bridge);
  return bridge;
}

/// The app's notifications turned on, as the settings keep them.
void notifyOn(FakeBridge bridge) {
  bridge.settings = Settings(
    activeNetwork: bridge.settings.activeNetwork,
    backends: bridge.settings.backends,
    appPrefs: {...bridge.settings.appPrefs, 'notify.new_tx': '1'},
  );
}

void main() {
  group('what a notification says', () {
    const waiting = PremiumDevice(
      id: 'd',
      platform: DevicePlatform.ios,
      connectedAt: 1000,
      access: DeviceAccess.pending,
      pendingUntil: 1000 + 10 * 86400,
    );

    test('a notification names the kind of device, and no more', () {
      final plain = deviceNotice(waiting, locked: false);
      expect(plain.title, 'Gerfaut Premium: new device');
      expect(
        plain.body,
        'A new iPhone asks for access to your Premium account. Open Gerfaut '
        'to approve or refuse it.',
      );
      // Under an app lock, the generic form every notification takes
      // there: the app's name, and no particulars.
      final locked = deviceNotice(waiting, locked: true);
      expect(locked.title, 'Gerfaut');
      expect(
        locked.body,
        'A new device asks for access. Open Gerfaut to approve or refuse it.',
      );
      expect(locked.id, plain.id);
    });
  });

  group('a new device, announced', () {
    testWidgets('a red banner on the home screen, until nothing waits', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text(newDeviceBanner), findsOneWidget);
      expect(find.byType(AlertBanner), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Devices'), findsOneWidget);
      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsNothing);
    });

    testWidgets('an approval answered after the page was left ends it too', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      final gate = Completer<void>();
      bridge.onPremiumApprove = (_) => gate.future;
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pump();
      expect(find.text('Approving…'), findsOneWidget);

      // Home before the server answers: the banner goes with its answer,
      // not at the next check five minutes on.
      await tester.pageBack();
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsNothing);
    });

    testWidgets('no banner while nothing waits', (tester) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumAddDevice(waiting: false);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsNothing);
    });

    testWidgets('one notification per device, once', (tester) async {
      final bridge = withWaitingComputer();
      final notifications = RecordingNotifications();
      await tester.pumpWidget(wholeApp(bridge, notifications: notifications));
      await tester.pumpAndSettle();

      expect(notifications.posted, hasLength(1));
      expect(notifications.posted.single.title, 'Gerfaut Premium: new device');
      expect(
        notifications.posted.single.body,
        'A new Windows computer asks for access to your Premium account. '
        'Open Gerfaut to approve or refuse it.',
      );
      expect(bridge.premiumAnnounced, ['dev2']);

      // Five minutes on, a second device has come; the first is not
      // said again.
      bridge.premiumAddDevice(platform: DevicePlatform.ios);
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(notifications.posted, hasLength(2));
      expect(notifications.posted.last.body, contains('iPhone'));
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(notifications.posted, hasLength(2));
    });

    testWidgets('under an app lock the title is the app', (tester) async {
      final bridge = withWaitingComputer();
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      final notifications = RecordingNotifications();
      await tester.pumpWidget(wholeApp(bridge, notifications: notifications));
      await tester.pumpAndSettle();
      expect(notifications.posted.single.title, 'Gerfaut');
      expect(notifications.posted.single.body, isNot(contains('Windows')));
    });

    testWidgets('disguised, nothing is posted, and nothing later', (
      tester,
    ) async {
      final bridge = withWaitingComputer();
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      final notifications = RecordingNotifications();
      await tester.pumpWidget(
        wholeApp(
          bridge,
          notifications: notifications,
          disguise: FakeDisguise(disguised: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(notifications.posted, isEmpty);
      // Counted as announced all the same: taking the disguise off later
      // does not bring an old notice up.
      expect(bridge.premiumAnnounced, ['dev2']);
    });

    testWidgets('a waiting device announces nothing', (tester) async {
      final bridge = withWaitingComputer();
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      final notifications = RecordingNotifications();
      await tester.pumpWidget(wholeApp(bridge, notifications: notifications));
      await tester.pumpAndSettle();
      expect(notifications.posted, isEmpty);
      expect(find.text(newDeviceBanner), findsNothing);
      expect(bridge.premiumCalls, isNot(contains('devices')));
    });

    testWidgets('with notifications off, the banner alone', (tester) async {
      final bridge = withWaitingComputer(notifying: false);
      final notifications = RecordingNotifications();
      await tester.pumpWidget(wholeApp(bridge, notifications: notifications));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsOneWidget);
      expect(notifications.posted, isEmpty);
      // Counted all the same: turning notifications on later does not
      // bring up an old device.
      expect(bridge.premiumAnnounced, ['dev2']);
    });

    testWidgets('the banner goes with a device the server turned away', (
      tester,
    ) async {
      final bridge = withWaitingComputer();
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsOneWidget);

      // Refused from the computer, or the key changed there.
      bridge.premiumDeviceList.removeWhere(
        (d) => d.id == bridge.premiumThisDeviceId,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsNothing);
    });

    testWidgets('a waiting device finds out by itself it was approved', (
      tester,
    ) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      final asked = bridge.premiumCalls.where((c) => c == 'me').length;
      expect(bridge.premiumCalls, isNot(contains('devices')));

      await bridge.premiumApproveDeviceOnServer(bridge.premiumThisDeviceId!);
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls.where((c) => c == 'me').length,
        greaterThan(asked),
      );
      // Full access now: the account's devices are read, which a
      // waiting device never does.
      expect(bridge.premiumCalls, contains('devices'));
    });

    testWidgets('a waiting device keeps asking after a failed read', (
      tester,
    ) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();

      // A tunnel at the next check: the read fails, and says nothing of
      // where this device stands.
      bridge.onPremiumMe = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      final asked = bridge.premiumCalls.where((c) => c == 'me').length;

      // Out of the tunnel, and approved meanwhile: the next check finds
      // out, with no return to the app to prompt it.
      bridge.onPremiumMe = null;
      await bridge.premiumApproveDeviceOnServer(bridge.premiumThisDeviceId!);
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls.where((c) => c == 'me').length,
        greaterThan(asked),
      );
      expect(bridge.premiumCalls, contains('devices'));
    });

    testWidgets('a device the server turned away stops asking', (tester) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();

      // Refused from the computer.
      bridge.premiumDeviceList.removeWhere(
        (d) => d.id == bridge.premiumThisDeviceId,
      );
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumDisconnected, isTrue);
      final asked = bridge.premiumCalls.length;
      await tester.pump(deviceCheckPeriod * 3);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls
            .skip(asked)
            .where((c) => c == 'me' || c == 'devices'),
        isEmpty,
      );
    });

    testWidgets('out of sight nothing is asked, and all of it on return', (
      tester,
    ) async {
      final bridge = withWaitingComputer();
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsOneWidget);

      /// The device calls made since [from].
      List<String> since(int from) => [
        for (final call in bridge.premiumCalls.skip(from))
          if (call == 'me' || call == 'devices') call,
      ];

      // Behind the launcher, with Live keeping the process alive: the
      // timers would go on firing every five minutes.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = bridge.premiumCalls.length;
      await tester.pump(deviceCheckPeriod * 3);
      await tester.pumpAndSettle();
      expect(since(before), isEmpty);

      // Back in front: at once, then on the rhythm again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(since(before), contains('devices'));
      final back = bridge.premiumCalls.length;
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(since(back), contains('devices'));
    });

    testWidgets('a waiting device asks nothing out of sight either', (
      tester,
    ) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = bridge.premiumCalls.length;
      await tester.pump(deviceCheckPeriod * 3);
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls.skip(before), isNot(contains('me')));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls.skip(before), contains('me'));
      final back = bridge.premiumCalls.length;
      await tester.pump(deviceCheckPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls.skip(back), contains('me'));
    });

    test('a list read under another connection raises nothing', () async {
      final bridge = withWaitingComputer();
      final container = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);
      container.listen(waitingDevicesProvider, (previous, next) {});
      await container.read(premiumDevicesProvider.future);
      expect(container.read(waitingDevicesProvider), hasLength(1));

      /// The vault moved on, and the next list is held on its way.
      Future<Completer<void>> moveOn(void Function() change) async {
        final gate = Completer<void>();
        bridge.onPremiumDevices = () => gate.future;
        change();
        container.invalidate(premiumStateProvider);
        await container.read(premiumFullAccessProvider.future);
        await pumpEventQueue();
        return gate;
      }

      Future<void> letThrough(Completer<void> gate) async {
        bridge.onPremiumDevices = null;
        gate.complete();
        await container.read(premiumDevicesProvider.future);
        await pumpEventQueue();
      }

      // The key changed: the list read with the old one says nothing of
      // who waits now.
      var gate = await moveOn(() => bridge.premiumKey = 'wxyz23456789abcd');
      expect(container.read(accountDevicesProvider), isNull);
      expect(container.read(waitingDevicesProvider), isEmpty);
      await letThrough(gate);
      expect(container.read(waitingDevicesProvider), hasLength(1));

      // Another key connected this device anew: the last account's
      // list is nobody's business here.
      gate = await moveOn(() {
        bridge.premiumKey = 'mnpq23456789abcd';
        bridge.premiumThisDeviceId = bridge.premiumAddDevice(
          platform: DevicePlatform.android,
          waiting: false,
        );
      });
      expect(container.read(waitingDevicesProvider), isEmpty);
      await letThrough(gate);
      expect(container.read(waitingDevicesProvider), hasLength(1));

      // Logged out: nothing, at once.
      bridge.premiumKey = null;
      bridge.premiumThisDeviceId = null;
      container.invalidate(premiumStateProvider);
      await container.read(premiumStateProvider.future);
      expect(container.read(waitingDevicesProvider), isEmpty);
    });

    testWidgets('logouts the server did not hear of go at the start, or on '
        'the way back', (tester) async {
      final bridge = premiumBridge(activated: true);
      final gone = bridge.premiumAddDevice(waiting: false);
      bridge.premiumPendingLogouts.add(gone);
      bridge.onPremiumRevoke = (_) => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('flush-logouts'));
      expect(bridge.premiumPendingLogouts, [gone]);

      bridge.onPremiumRevoke = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bridge.premiumPendingLogouts, isEmpty);
      expect(bridge.premiumDeviceList.where((d) => d.id == gone), isEmpty);
    });

    testWidgets('the heartbeat sends a lost connection again', (tester) async {
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      // Disconnected, and connecting again lost its answer on the way.
      bridge.premiumDisconnected = true;
      bridge.premiumConnectPending = 'abcdefghijkmnpqr';
      bridge.onPremiumEnsure = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      expect(bridge.premiumConnectPending, isNotNull);

      bridge.onPremiumEnsure = null;
      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumConnectPending, isNull);
      expect(bridge.premiumDisconnected, isFalse);
    });

    testWidgets('coming back to the app looks again', (tester) async {
      final bridge = premiumBridge(activated: true);
      notifyOn(bridge);
      final notifications = RecordingNotifications();
      await tester.pumpWidget(wholeApp(bridge, notifications: notifications));
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsNothing);

      bridge.premiumAddDevice();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(newDeviceBanner), findsOneWidget);
      expect(notifications.posted, hasLength(1));
    });
  });
}
