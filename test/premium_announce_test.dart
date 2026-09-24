import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/premium.dart';
import 'package:gerfaut/widgets/alert_banner.dart';
import 'package:gerfaut/widgets/buttons.dart';

import 'fakes.dart';
import 'premium_harness.dart';

const String newDeviceBanner =
    'A new device asks for access to your Premium account. If it is not '
    'yours, refuse it and change your key.';

/// A key activated first on this phone, a Windows computer that entered
/// it an hour ago and waits.
FakeBridge withWaitingComputer() {
  final bridge = premiumBridge(activated: true);
  bridge.premiumAddDevice();
  return bridge;
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

    testWidgets('coming back to the app looks again', (tester) async {
      final bridge = premiumBridge(activated: true);
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
