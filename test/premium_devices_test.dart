import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/screens/change_key.dart';
import 'package:gerfaut/screens/confirm_identity.dart';
import 'package:gerfaut/screens/settings/premium_devices.dart';
import 'package:gerfaut/screens/settings/premium_protect.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/identity.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/premium.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/status_pill.dart';

import 'fakes.dart';
import 'premium_harness.dart';

const String waitingTitle = 'Waiting for approval';

/// A key activated first on this phone, a Windows computer that entered
/// it an hour ago and waits.
FakeBridge withWaitingComputer() {
  final bridge = premiumBridge(activated: true);
  bridge.premiumAddDevice();
  return bridge;
}

/// The device line of the second device, which is the waiting one.
Finder rowOf(String label) => find.text(label);

/// How many checklist steps a screen reader hears called [said].
int stepMarks(WidgetTester tester, String said) => find
    .byWidgetPredicate((w) => w is Icon && w.semanticLabel == said)
    .evaluate()
    .length;

/// A small phone at twice the text size: whatever does not fit fails
/// the test with the overflow the framework reports.
void useSmallLargeText(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 4000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

void main() {
  group('devices, in words', () {
    const waiting = PremiumDevice(
      id: 'd',
      platform: DevicePlatform.ios,
      connectedAt: 1000,
      access: DeviceAccess.pending,
      pendingUntil: 1000 + 10 * 86400,
    );

    test('a wait counts the day under way, never zero', () {
      expect(waitingLabel(waiting, nowUnix: 1000), 'Waiting · 10 days left');
      expect(
        waitingLabel(waiting, nowUnix: 1000 + 9 * 86400 + 1),
        'Waiting · 1 day left',
      );
      expect(waitingDaysLeft(waiting, nowUnix: 1000 + 20 * 86400), 1);
    });

    test('a device date is written day first', () {
      final fourth = DateTime(2026, 9, 4, 12).millisecondsSinceEpoch ~/ 1000;
      expect(formatDayMonthYear(fourth), '4 Sep 2026');
      final last = DateTime(2027, 12, 31, 12).millisecondsSinceEpoch ~/ 1000;
      expect(formatDayMonthYear(last), '31 Dec 2027');
    });

    test('every platform has its label and its glyph', () {
      expect(DevicePlatform.android.label, 'Android phone');
      expect(DevicePlatform.ios.label, 'iPhone');
      expect(DevicePlatform.windows.label, 'Windows computer');
      expect(DevicePlatform.macos.label, 'Mac');
      expect(DevicePlatform.linux.label, 'Linux computer');
      final unknown = PremiumDevice.fromJson(const {
        'id': 'x',
        'platform': 'toaster',
        'connected_at': 1,
        'access': 'strange',
      });
      // A platform or an access this build cannot read is shown, and
      // never granted anything.
      expect(unknown.label, 'Device');
      expect(unknown.fullAccess, isFalse);
    });

    test('the server sentences read as the server wrote them', () {
      String said(String kind, [String message = '']) =>
          premiumFailure(BridgeException(kind, message)).message;
      expect(
        said('premium_device_pending'),
        'This device is waiting for approval: approve it on another of your '
        'devices, or wait until it gets full access.',
      );
      expect(
        said('premium_device_disconnected'),
        'This device was disconnected from the Premium account.',
      );
      expect(
        said(
          'premium_too_many_devices',
          'this key already has 10 devices; disconnect one from a device '
              'with full access',
        ),
        'This key already has 10 devices; disconnect one from a device with '
        'full access.',
      );
      expect(
        said('premium_no_device'),
        'Connect this device with the Premium key first.',
      );
    });
  });

  group('connecting', () {
    testWidgets('the first device has full access and is told to protect', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(bridge.premiumCalls, contains('connect:abcd-efgh-ijkm-npqr'));
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Android phone'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Full access'), findsOneWidget);
      expect(find.text('Change key'), findsOneWidget);
      expect(find.text('Protect your Premium account'), findsOneWidget);
      expect(find.text('Watched wallets'), findsOneWidget);
      expect(find.text(waitingTitle), findsNothing);
      // Devices right after the licence, the checklist after them.
      final devices = tester.getTopLeft(find.text('Devices')).dy;
      final licence = tester.getTopLeft(find.text('Licence')).dy;
      final protect = tester
          .getTopLeft(find.text('Protect your Premium account'))
          .dy;
      final wallets = tester.getTopLeft(find.text('Watched wallets')).dy;
      expect(
        licence < devices && devices < protect && protect < wallets,
        isTrue,
      );
    });

    testWidgets('a later device waits and sees nothing of the account', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      // The account had a device before: this one is not the first.
      bridge.premiumAddDevice(platform: DevicePlatform.macos, waiting: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(find.text(waitingTitle), findsOneWidget);
      final now = bridge.premiumNow;
      expect(
        find.text(
          'This device connected to your Premium account on '
          '${formatDayMonthYear(now)}. It shows your watched wallets, channels '
          'and '
          'alerts once one of your other devices approves it, or on '
          '${formatDayMonthYear(now + 10 * 86400)} without approval.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Approve it in Gerfaut on another device: Settings › Premium › '
          'Devices.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The wait protects you if someone else gets your key: they see '
          'nothing and can change nothing while you are warned.',
        ),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Forget this key'), findsOneWidget);
      for (final card in [
        'Devices',
        'Watched wallets',
        'Channels',
        'Recent alerts',
        'Protect your Premium account',
      ]) {
        expect(find.text(card), findsNothing, reason: card);
      }
      expect(find.text('Change key'), findsNothing);
      // Nothing the server would refuse a waiting device is asked.
      for (final call in ['account', 'wallets', 'channels', 'events']) {
        expect(bridge.premiumCalls, isNot(contains(call)), reason: call);
      }
    });

    testWidgets('checking again opens the account once approved', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(waitingTitle), findsOneWidget);

      final gate = Completer<void>();
      bridge.onPremiumMe = () => gate.future;
      await tester.tap(find.text('Check again'));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      final button = find.widgetWithText(SecondaryButton, 'Checking…');
      expect(tester.widget<SecondaryButton>(button).onPressed, isNull);

      await bridge.premiumApproveDeviceOnServer(bridge.premiumThisDeviceId!);
      bridge.onPremiumMe = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(waitingTitle), findsNothing);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Watched wallets'), findsOneWidget);
    });

    testWidgets('a waiting device forgets its key the usual way', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not on the server'), findsOneWidget);
      // A waiting device cannot delete the account: no box to tick.
      expect(find.text('Also delete everything on the server'), findsNothing);
      await tester.tap(find.widgetWithText(DangerButton, 'Forget key'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('log-out'));
      expect(find.text('Activate'), findsOneWidget);
    });

    testWidgets('a key with every device it may have says so', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      bridge.onPremiumConnect = (_) => throw const BridgeException(
        'premium_too_many_devices',
        'this key already has 10 devices; disconnect one from a device with '
            'full access',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This key already has 10 devices; disconnect one from a device '
          'with full access.',
        ),
        findsOneWidget,
      );
      expect(bridge.premiumKey, isNull);
    });

    testWidgets('a key kept from before devices connects on its own', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      // A vault written by a version that had no devices: a key, a
      // certificate, and no token.
      bridge.premiumDeviceList.clear();
      bridge.premiumThisDeviceId = null;
      bridge.premiumHadDevice = false;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(bridge.premiumCalls, contains('ensure'));
      expect(bridge.premiumThisDeviceId, isNotNull);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
    });
  });

  group('disconnected', () {
    testWidgets('says so, and connects again as a new device', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumAddDevice(platform: DevicePlatform.linux, waiting: false);
      bridge.premiumDeviceList.removeWhere(
        (d) => d.id == bridge.premiumThisDeviceId,
      );
      bridge.premiumDisconnected = true;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(
        find.text('This device was disconnected from your Premium account.'),
        findsOneWidget,
      );
      expect(find.text('Watched wallets'), findsNothing);
      expect(find.text('Devices'), findsNothing);
      // Nothing is asked of a server that turned the device away.
      expect(bridge.premiumCalls, isNot(contains('me')));

      await tester.tap(find.text('Connect again'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('connect:abcdefghijkmnpqr'));
      expect(find.text(waitingTitle), findsOneWidget);
      expect(find.textContaining('was disconnected'), findsNothing);
    });

    testWidgets('a changed key brings the field back', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumDisconnected = true;
      bridge.premiumServerKey = 'zzzzzzzzzzzzzzzz';
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect again'));
      await tester.pumpAndSettle();
      expect(
        find.text('This key no longer works. Enter the new one.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('was disconnected'), findsNothing);

      bridge.premiumServerKey = 'abcdefghijkmnpqr';
      bridge.premiumHadDevice = false;
      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(
        find.text('This key no longer works. Enter the new one.'),
        findsNothing,
      );
      expect(find.text('Devices'), findsOneWidget);
    });

    testWidgets('a token refused on the way in reads as disconnected', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      // Refused on another device while this one was closed.
      bridge.premiumDeviceList.removeWhere(
        (d) => d.id == bridge.premiumThisDeviceId,
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      expect(
        find.text('This device was disconnected from your Premium account.'),
        findsOneWidget,
      );
      expect(find.text('Connect again'), findsOneWidget);
    });

    testWidgets('a wait turned away on checking again says so', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text(waitingTitle), findsOneWidget);

      // Refused on another device, or the key changed there, meanwhile:
      // the answer before this one must not go on standing.
      bridge.premiumDeviceList.removeWhere(
        (d) => d.id == bridge.premiumThisDeviceId,
      );
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text(waitingTitle), findsNothing);
      expect(
        find.text('This device was disconnected from your Premium account.'),
        findsOneWidget,
      );
    });

    testWidgets('a server out of reach leaves the wait as it was', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      bridge.onPremiumMe = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text(waitingTitle), findsOneWidget);
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
    });

    testWidgets('the root row says where the device stands', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumMakeWaiting(bridge.premiumThisDeviceId!);
      await tester.pumpWidget(premiumApp(bridge, root: true));
      await tester.pumpAndSettle();
      final until = formatDate(bridge.premiumPaidUntil);
      expect(
        find.text('Active until $until · waiting for approval'),
        findsOneWidget,
      );

      bridge.premiumDisconnected = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(premiumApp(bridge, root: true));
      await tester.pumpAndSettle();
      expect(find.text('Active until $until · disconnected'), findsOneWidget);
    });
  });

  group('the devices card', () {
    testWidgets('lists every device and what each can do', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      bridge.premiumAddDevice(platform: DevicePlatform.macos, waiting: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Every device that entered your key. A new one waits 10 days, or '
          'until you approve it here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Windows computer'), findsOneWidget);
      expect(find.text('Mac'), findsOneWidget);
      expect(find.text('Waiting · 10 days left'), findsOneWidget);
      expect(find.text('Full access'), findsNWidgets(2));
      expect(find.byIcon(deviceGlyph(DevicePlatform.android)), findsOneWidget);
      expect(find.byIcon(deviceGlyph(DevicePlatform.windows)), findsOneWidget);
      expect(find.byIcon(deviceGlyph(DevicePlatform.macos)), findsOneWidget);
      // The wait is amber; access is neutral.
      final wait = tester.widget<StatusPill>(
        find.ancestor(
          of: find.text('Waiting · 10 days left'),
          matching: find.byType(StatusPill),
        ),
      );
      expect(wait.tone, PillTone.pending);
      expect(find.widgetWithText(DangerButton, 'Refuse'), findsOneWidget);
      expect(find.widgetWithText(PremiumButton, 'Approve'), findsOneWidget);
      // The Mac, which has access and is not this phone, has a menu;
      // this phone does not.
      expect(find.byTooltip('More for Mac'), findsOneWidget);
      expect(find.byTooltip('More for Android phone'), findsNothing);
    });

    testWidgets('approving asks, checks who holds the phone, then tells', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      final screenLock = FakeScreenLock();
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text(DeviceAction.approve.question), findsOneWidget);
      final note = tester.widget<GerfautNotice>(
        find.ancestor(
          of: find.text(DeviceAction.approve.question),
          matching: find.byType(GerfautNotice),
        ),
      );
      expect(note.tone, NoticeTone.info);
      expect(screenLock.asked, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(DeviceAction.approve.question), findsNothing);

      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(GerfautNotice),
          matching: find.widgetWithText(PremiumButton, 'Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(screenLock.asked, [confirmItsYouTitle]);
      expect(bridge.premiumCalls, contains('approve:dev2'));
      expect(find.text('Device approved'), findsOneWidget);
      expect(find.text('Waiting · 10 days left'), findsNothing);
      expect(find.text('Full access'), findsNWidgets(2));
      expect(find.text(DeviceAction.approve.question), findsNothing);
    });

    testWidgets('refusing takes the device away', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      expect(find.text(DeviceAction.refuse.question), findsOneWidget);
      // The row's own two buttons give way to the question's.
      expect(find.widgetWithText(PremiumButton, 'Approve'), findsNothing);
      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('remove-device:dev2'));
      expect(find.text('Windows computer'), findsNothing);
      expect(find.text('Device refused'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('disconnecting a device with access goes by its menu', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumAddDevice(platform: DevicePlatform.linux, waiting: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for Linux computer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text(DeviceAction.disconnect.question), findsOneWidget);
      await tester.tap(find.widgetWithText(DangerButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('remove-device:dev2'));
      expect(find.text('Linux computer'), findsNothing);
      expect(find.text('Device disconnected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refused check sends nothing and keeps the question', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.refused);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, isNot(contains('remove-device:dev2')));
      expect(find.text(DeviceAction.refuse.question), findsOneWidget);
    });

    testWidgets('an app lock is asked by its PIN', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(GerfautNotice),
          matching: find.widgetWithText(PremiumButton, 'Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmItsYouSheet), findsOneWidget);
      await tester.enterText(find.byKey(const Key('identity.secret')), '1234');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('approve:dev2'));
    });

    testWidgets('an answer goes once, however many taps', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      final gate = Completer<void>();
      bridge.onPremiumApprove = (_) => gate.future;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      final approve = find.descendant(
        of: find.byType(GerfautNotice),
        matching: find.byType(PremiumButton),
      );
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(find.text('Approving…'), findsOneWidget);
      expect(tester.widget<PremiumButton>(approve).onPressed, isNull);
      await tester.tap(approve, warnIfMissed: false);
      await tester.pump();
      expect(
        bridge.premiumCalls.where((c) => c == 'approve:dev2'),
        hasLength(1),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Approving…'), findsNothing);
    });

    testWidgets('a refusal says why under the card and reads the list again', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      bridge.onPremiumApprove = (id) {
        // Approved on another device a moment before.
        unawaited(bridge.premiumApproveDeviceOnServer(id));
        throw const BridgeException(
          'premium_rejected',
          'this device already has full access',
        );
      };
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PremiumButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(GerfautNotice),
          matching: find.widgetWithText(PremiumButton, 'Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Gerfaut server refused.'), findsOneWidget);
      expect(find.text('this device already has full access'), findsOneWidget);
      expect(find.text('Waiting · 10 days left'), findsNothing);
    });

    testWidgets('a list the server would not give says so, with a retry', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      bridge.onPremiumDevices = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text('The server could not be asked.'), findsWidgets);
      expect(find.text('Could not reach the Gerfaut server.'), findsWidgets);

      bridge.onPremiumDevices = null;
      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();
      expect(find.text('Windows computer'), findsOneWidget);
    });

    testWidgets('fits a small phone at twice the text size', (tester) async {
      useSmallLargeText(tester);
      final bridge = withWaitingComputer();
      bridge.premiumAddDevice(platform: DevicePlatform.linux, waiting: false);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Refuse'));
      await tester.pumpAndSettle();
      final confirm = tester.getRect(
        find.descendant(
          of: find.byType(GerfautNotice),
          matching: find.byType(DangerButton),
        ),
      );
      expect(confirm.right, lessThanOrEqualTo(360));
      expect(confirm.height, 44);
    });

    testWidgets('reads in the dark theme', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      await tester.pumpWidget(premiumApp(bridge, dark: true));
      await tester.pumpAndSettle();
      final pill = tester.widget<Text>(find.text('Waiting · 10 days left'));
      expect(pill.style!.color, GerfautTokens.dark.pending);
    });
  });

  group('changing the key', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Change key'));
      await tester.pumpAndSettle();
    }

    testWidgets('warns, confirms, shows the new key once', (tester) async {
      useTallSurface(tester);
      final bridge = withWaitingComputer();
      final clipboard = FakeSensitiveClipboard();
      final screenLock = FakeScreenLock();
      await tester.pumpWidget(
        premiumApp(bridge, clipboard: clipboard, screenLock: screenLock),
      );
      await tester.pumpAndSettle();

      await openSheet(tester);
      expect(find.byType(ChangeKeySheet), findsOneWidget);
      expect(find.text('Change your Premium key'), findsOneWidget);
      expect(
        find.text(
          'A new key replaces this one. The old key stops working at once, on '
          'the website too. Every other device is disconnected: enter the new '
          'key there, then approve it here.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(DangerButton, 'Change key'));
      await tester.pumpAndSettle();
      expect(screenLock.asked, [confirmItsYouTitle]);
      expect(bridge.premiumCalls, contains('change-key'));

      expect(find.text('Your new key'), findsOneWidget);
      expect(find.text('wxyz-2345-6789-abcd'), findsOneWidget);
      expect(
        find.text(
          'Save it in your password manager now. This device keeps it, but '
          'nothing else does.',
        ),
        findsOneWidget,
      );
      final done = find.widgetWithText(PrimaryButton, 'Done');
      expect(tester.widget<PrimaryButton>(done).onPressed, isNull);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard.copied, ['wxyz-2345-6789-abcd']);
      expect(find.text('Copied'), findsOneWidget);

      // Back does not close it while the key is on screen.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your new key'), findsOneWidget);

      await tester.tap(find.text('I saved my new key'));
      await tester.pumpAndSettle();
      expect(tester.widget<PrimaryButton>(done).onPressed, isNotNull);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byType(ChangeKeySheet), findsNothing);
      expect(bridge.premiumKeySaved, isTrue);
      // The other devices are gone; this one stays.
      expect(find.text('Windows computer'), findsNothing);
      expect(find.text('This device'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(find.widgetWithText(GhostButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangeKeySheet), findsNothing);
      expect(bridge.premiumCalls, isNot(contains('change-key')));
    });

    testWidgets('a refused check changes nothing', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final screenLock = FakeScreenLock(outcome: ScreenLockOutcome.refused);
      await tester.pumpWidget(premiumApp(bridge, screenLock: screenLock));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(find.widgetWithText(DangerButton, 'Change key'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, isNot(contains('change-key')));
      expect(find.text('Change your Premium key'), findsOneWidget);
    });

    testWidgets('goes once however many taps, and says a failure', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final gate = Completer<void>();
      bridge.onPremiumChangeKey = () async {
        await gate.future;
        throw const BridgeException(
          'premium_unreachable',
          'the premium server is unreachable: could not connect',
        );
      };
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await openSheet(tester);
      final change = find.byType(DangerButton);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(find.text('Changing…'), findsOneWidget);
      await tester.tap(change, warnIfMissed: false);
      await tester.pump();
      expect(bridge.premiumCalls.where((c) => c == 'change-key'), hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.text('Change key'), findsWidgets);
      expect(bridge.premiumKey, 'abcdefghijkmnpqr');
    });

    testWidgets('the new key fits a small phone at twice the size', (
      tester,
    ) async {
      useSmallLargeText(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change key'));
      await openSheet(tester);
      await tester.tap(find.widgetWithText(DangerButton, 'Change key'));
      await tester.pumpAndSettle();
      expect(find.text('wxyz-2345-6789-abcd'), findsOneWidget);
      expect(find.text('I saved my new key'), findsOneWidget);
    });
  });

  group('protect your premium account', () {
    testWidgets('three steps, each checked from what the app knows', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Connect a second device'), findsOneWidget);
      expect(
        find.text(
          'Enter this key in Gerfaut on your computer or another phone, then '
          'approve it here. If this device is lost, the other keeps full '
          'access.',
        ),
        findsOneWidget,
      );
      expect(find.text('Turn on the app lock'), findsOneWidget);
      expect(
        find.text(
          "Anyone holding this device unlocked could approve a stranger's "
          'device. A PIN stops them.',
        ),
        findsOneWidget,
      );
      expect(find.text('Save your key in a password manager'), findsOneWidget);
      expect(
        find.text(
          'Your key is the whole account. Nobody can send it to you again.',
        ),
        findsOneWidget,
      );
      expect(stepMarks(tester, 'To do'), 3);
      expect(find.text('Set up'), findsOneWidget);
      expect(find.text('Copy key'), findsOneWidget);
      expect(find.text('Mark as done'), findsOneWidget);
    });

    testWidgets('copies the key and marks it saved', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final clipboard = FakeSensitiveClipboard();
      await tester.pumpWidget(premiumApp(bridge, clipboard: clipboard));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy key'));
      await tester.pumpAndSettle();
      expect(clipboard.copied, ['abcd-efgh-ijkm-npqr']);

      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      expect(bridge.premiumKeySaved, isTrue);
      expect(find.text('Mark as done'), findsNothing);
      expect(stepMarks(tester, 'Done'), 1);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('set up opens the security settings', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      expect(find.text('App lock'), findsOneWidget);
    });

    testWidgets('hides for good', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(bridge.premiumChecklistHidden, isTrue);
      expect(find.text('Protect your Premium account'), findsNothing);
    });

    testWidgets('goes once every step is done', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumAddDevice(waiting: false);
      bridge.lock = const AppLock(kind: LockKind.pin, biometric: false);
      bridge.premiumKeySaved = true;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      expect(find.text('Protect your Premium account'), findsNothing);
      expect(find.text('Devices'), findsOneWidget);
    });

    test('a second device counts once it has full access', () {
      const view = PremiumView(key: 'k');
      PremiumDevice device(String id, DeviceAccess access) => PremiumDevice(
        id: id,
        platform: DevicePlatform.android,
        connectedAt: 1,
        access: access,
      );
      final one = protectSteps(
        view: view,
        devices: [
          device('a', DeviceAccess.full),
          device('b', DeviceAccess.pending),
        ],
        lock: null,
      );
      expect(one.secondDevice, isFalse);
      final two = protectSteps(
        view: view,
        devices: [
          device('a', DeviceAccess.full),
          device('b', DeviceAccess.full),
        ],
        lock: const AppLock(kind: LockKind.pin, biometric: false),
      );
      expect(two.secondDevice, isTrue);
      expect(two.appLock, isTrue);
      expect(protectCardShows(view, two), isTrue);
      const saved = PremiumView(key: 'k', keySaved: true);
      final all = protectSteps(
        view: saved,
        devices: [
          device('a', DeviceAccess.full),
          device('b', DeviceAccess.full),
        ],
        lock: const AppLock(kind: LockKind.pin, biometric: false),
      );
      expect(protectCardShows(saved, all), isFalse);
      expect(
        protectCardShows(
          const PremiumView(key: 'k', checklistHidden: true),
          one,
        ),
        isFalse,
      );
    });
  });
}
