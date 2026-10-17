import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/calculator.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/updates.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/tap_target.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:gerfaut/widgets/update_notice.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

const String _releases =
    'https://github.com/gerfaut-wallet/gerfaut-mobile/releases/latest';

/// A vault with one wallet, whose core already knows of [known], a
/// newer release, and finds [finds] when a session asks.
FakeBridge _bridge({
  String? known,
  String? finds = '0.2.0',
  bool due = false,
  Map<String, String> prefs = const {},
}) {
  final bridge = FakeBridge(
    wallets: [makeMeta()],
    settings: Settings(
      preferences: kPreferences,
      activeNetwork: Network.mainnet,
      backends: const {},
      appPrefs: {'onboarding.seen': '1', ...prefs},
    ),
  );
  bridge.updates
    ..available = known
    ..finds = finds
    ..due = due;
  return bridge;
}

/// One launch of the app. The bridge outlives it, as the vault does.
Future<void> _launch(
  WidgetTester tester,
  FakeBridge bridge, {
  bool disguised = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // A new scope each time: nothing in memory survives a launch.
      key: UniqueKey(),
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        disguiseServiceProvider.overrideWithValue(
          FakeDisguise(disguised: disguised),
        ),
        biometricGateProvider.overrideWithValue(
          FakeBiometrics(available: false),
        ),
        windowGuardProvider.overrideWithValue(FakeWindowGuard()),
      ],
      child: const GerfautApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const String _line = 'Gerfaut 0.2.0 is available';

void main() {
  test('the version shown is the one pubspec.yaml stamps on the build', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final stamped = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, stamped);
  });

  group('the beta', () {
    test('every 0.x version is a beta, pre-releases included', () {
      for (final version in [
        '0.1.0',
        '0.1.1',
        '0.2.0',
        '0.99.12',
        '0.2.0-rc.1',
      ]) {
        expect(isBetaVersion(version), isTrue, reason: version);
      }
    });

    test('it stops at 1.0.0', () {
      for (final version in [
        '1.0.0',
        '1.0.0-rc.1',
        '1.2.3',
        '2.0.0',
        '10.0.0',
      ]) {
        expect(isBetaVersion(version), isFalse, reason: version);
      }
    });
  });

  group('the update notice', () {
    testWidgets('shows on the launch after the core found a newer release', (
      tester,
    ) async {
      final bridge = _bridge(due: true);
      await _launch(tester, bridge);
      // The check ran, and what it found waits for the next time.
      expect(bridge.updates.sessions, 1);
      expect(bridge.updates.checks, 1);
      expect(find.text(_line), findsNothing);

      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);
      expect(find.text('View release'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      // In the page, over nothing: no dialog, and the wallets are there.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('Later has the core close that release, across launches', (
      tester,
    ) async {
      final bridge = _bridge(known: '0.2.0');
      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text(_line), findsNothing);
      expect(bridge.updates.dismissed, '0.2.0');

      await _launch(tester, bridge);
      expect(find.text(_line), findsNothing);
    });

    testWidgets('shows nothing the core does not announce', (tester) async {
      final bridge = _bridge(known: '0.2.0');
      bridge.updates.dismissed = '0.2.0';
      await _launch(tester, bridge);
      expect(find.byType(UpdateNotice), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('a notice already up follows the core', (tester) async {
      final bridge = _bridge(known: '0.2.0', finds: '0.3.0', due: true);
      await _launch(tester, bridge);
      expect(find.text('Gerfaut 0.3.0 is available'), findsOneWidget);
      expect(find.text(_line), findsNothing);
    });

    testWidgets('offline says nothing', (tester) async {
      final bridge = _bridge(due: true)..updates.offline = true;
      await _launch(tester, bridge);
      await _launch(tester, bridge);
      expect(bridge.updates.checks, 1);
      expect(find.byType(UpdateNotice), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never over the lock screen, and there after the unlock', (
      tester,
    ) async {
      final bridge = _bridge(known: '0.2.0')
        ..lock = const AppLock(kind: LockKind.pin, biometric: false)
        ..lockSecret = '1234';
      await _launch(tester, bridge);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      // No session is opened from behind the lock either.
      expect(bridge.updates.sessions, 0);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text(_line), findsOneWidget);
      expect(bridge.updates.sessions, 1);
    });

    testWidgets('never while disguised, locked or open', (tester) async {
      final bridge = _bridge(known: '0.2.0', due: true)
        ..lock = const AppLock(kind: LockKind.pin, biometric: false)
        ..lockSecret = '1234';
      await _launch(tester, bridge, disguised: true);
      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.textContaining('Gerfaut'), findsNothing);

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.widgetWithText(InkWell, digit));
        await tester.pump();
      }
      await tester.tap(find.bySemanticsLabel('Equals'));
      await tester.pumpAndSettle();
      expect(find.text('Cold storage'), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      expect(bridge.updates.sessions, 0);
      expect(bridge.updates.checks, 0);
    });

    testWidgets('the button opens the release page and nothing else', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final bridge = _bridge(known: '0.2.0');
      await _launch(tester, bridge);

      await tester.tap(find.text('View release'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [_releases]);
      expect(releasePageUrl, _releases);
      // Asked once: the notice does not come back for this release.
      expect(find.text(_line), findsNothing);
      expect(bridge.updates.dismissed, '0.2.0');
    });

    testWidgets('both are full targets and a screen reader hears it all', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final bridge = _bridge(known: '0.2.0');
      await _launch(tester, bridge);

      for (final label in ['Later', 'View release']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(TapTarget)),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(GerfautTouch.target),
          reason: label,
        );
        expect(
          size.width,
          greaterThanOrEqualTo(GerfautTouch.target),
          reason: label,
        );
      }
      expect(find.bySemanticsLabel(_line), findsOneWidget);
      // One node each: the name, the hint and the tap together.
      for (final (label, hint) in [
        ('Later', 'Hides this notice until the next release'),
        ('View release', 'Opens the release page in your browser'),
      ]) {
        final node = tester.getSemantics(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(MergeSemantics),
              )
              .first,
        );
        // The merged reading: what a screen reader is handed.
        final data = node.getSemanticsData();
        expect(data.label, label);
        expect(data.hint, hint);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.flagsCollection.isButton, isTrue);
      }
      handle.dispose();
    });

    testWidgets('holds at a large text size on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final bridge = _bridge(known: '0.2.0');
      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wears the dark theme as a plain card', (tester) async {
      final bridge = _bridge(known: '0.2.0', prefs: {'mobile.theme': 'dark'});
      await _launch(tester, bridge);
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(_line), matching: find.byType(Container))
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, GerfautTokens.dark.surface);
      expect(
        (decoration.border! as Border).top.color,
        GerfautTokens.dark.border,
      );
      final text = tester.widget<Text>(find.text(_line));
      expect(text.style!.color, GerfautTokens.dark.text);
    });
  });

  group('the sessions', () {
    testWidgets('each launch opens one, and the core decides the rest', (
      tester,
    ) async {
      final bridge = _bridge(due: true);
      await _launch(tester, bridge);
      await _launch(tester, bridge);
      expect(bridge.updates.sessions, 2);
      expect(bridge.updates.checks, 1);
    });

    testWidgets('coming back from the background is a session too', (
      tester,
    ) async {
      final bridge = _bridge(due: true);
      await _launch(tester, bridge);
      expect(find.text(_line), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_line), findsOneWidget);
      expect(bridge.updates.sessions, 2);
    });

    testWidgets('the core asks nothing once turned off', (tester) async {
      final bridge = _bridge(due: true)..updates.automatic = false;
      await _launch(tester, bridge);
      await _launch(tester, bridge);
      expect(bridge.updates.checks, 0);
      expect(find.textContaining('is available'), findsNothing);
    });
  });

  group('the About card', () {
    Future<void> open(WidgetTester tester, FakeBridge bridge) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeProvider.overrideWithValue(bridge),
            disguiseServiceProvider.overrideWithValue(FakeDisguise()),
          ],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const SettingsScreen(section: SettingsSection.about),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what the automatic check does, and turns it off', (
      tester,
    ) async {
      final bridge = _bridge();
      await open(tester, bridge);
      expect(find.text('Check automatically'), findsOneWidget);
      // Two sentences, the most a setting's line may take.
      expect(
        find.text(
          'Asks GitHub for the latest release at most once a day while '
          'Gerfaut is unlocked, and downloads nothing. With a .onion node '
          'it goes through Tor or not at all, and never while the app is '
          'disguised.',
        ),
        findsOne,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(bridge.updates.automatic, isFalse);
    });

    testWidgets('reads the setting from the core', (tester) async {
      final bridge = _bridge()..updates.automatic = false;
      await open(tester, bridge);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('its own button opens the release page and nothing else', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final bridge = _bridge();
      await open(tester, bridge);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(bridge.updates.checks, 1);
      await tester.tap(find.text('Get 0.2.0'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [_releases]);
    });

    testWidgets('a 0.x version is marked Beta, with a way to report a '
        'problem', (tester) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      await open(tester, _bridge());

      final beta = isBetaVersion(appVersion);
      final pill = find.widgetWithText(StatusPill, 'Beta');
      expect(pill, beta ? findsOneWidget : findsNothing);
      expect(
        find.text(
          'This is a public beta. Check addresses and amounts on your '
          'signing device, and report anything that looks wrong.',
        ),
        beta ? findsOneWidget : findsNothing,
      );
      if (!beta) {
        expect(find.text('Report a problem'), findsNothing);
        return;
      }
      expect(tester.widget<StatusPill>(pill).tone, PillTone.pending);
      // On the line of the version, after it.
      expect(
        tester.getCenter(pill).dy,
        moreOrLessEquals(
          tester.getCenter(find.text('Gerfaut $appVersion')).dy,
          epsilon: 2,
        ),
      );

      await tester.tap(find.text('Report a problem'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [
        'https://github.com/gerfaut-wallet/gerfaut-mobile/issues',
      ]);
    });

    testWidgets('a Tor that is down is said as such, not as an outage', (
      tester,
    ) async {
      final bridge = _bridge()..updates.torDown = true;
      await open(tester, bridge);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(bridge.updates.checks, 0);
      expect(find.textContaining('Tor could not be reached'), findsOne);
      expect(find.textContaining('Could not reach the release'), findsNothing);

      // A check that goes out takes the line away.
      bridge.updates
        ..torDown = false
        ..finds = null;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You are up to date.'), findsOneWidget);
      expect(find.textContaining('Tor could not be reached'), findsNothing);
    });

    testWidgets('says so when the daily check found Tor down', (tester) async {
      final bridge = _bridge()..updates.torUnavailable = true;
      await open(tester, bridge);
      expect(find.textContaining('Tor could not be reached'), findsOne);
    });

    testWidgets('nothing newer reads as up to date, no answer as an outage', (
      tester,
    ) async {
      final bridge = _bridge(finds: null);
      await open(tester, bridge);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You are up to date.'), findsOneWidget);

      bridge.updates.offline = true;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not reach the release page. Try again later.'),
        findsOneWidget,
      );
    });
  });
}
