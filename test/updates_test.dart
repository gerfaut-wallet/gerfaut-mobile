import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/calculator.dart';
import 'package:gerfaut/screens/lock_screen.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/updates.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/update_notice.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';

const String _releases =
    'https://github.com/gerfaut-wallet/gerfaut-mobile/releases/latest';

class _NoBiometrics implements BiometricGate {
  @override
  Future<bool> canCheck() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

/// A clock a test moves by hand.
class _Clock {
  int now = 1800000000;
}

/// A vault opened before, whose release check answers [latest]; null is
/// a phone that is offline.
FakeBridge _bridge({
  String? latest = 'v0.2.0',
  Map<String, String> prefs = const {},
  Map<Network, BackendConfig> backends = const {},
  bool openedBefore = true,
}) {
  final bridge = FakeBridge(
    wallets: [makeMeta()],
    settings: Settings(
      activeNetwork: Network.mainnet,
      backends: backends,
      // An app that has been open before today, unless a test says
      // otherwise: the first day is a case of its own.
      appPrefs: {
        'onboarding.seen': '1',
        if (openedBefore) 'updates.checked_at': '1',
        ...prefs,
      },
    ),
  );
  bridge.onCheckUpdate = (current) {
    if (latest == null) throw const BridgeException('sync', 'offline');
    return UpdateCheck(
      latest: latest,
      // Never the page that opens: the app has its own.
      url: 'https://evil.example/releases',
      updateAvailable: true,
    );
  };
  return bridge;
}

/// One launch of the app. The bridge outlives it, as the vault does.
Future<void> _launch(
  WidgetTester tester,
  FakeBridge bridge, {
  _Clock? clock,
  bool disguised = false,
}) async {
  final time = clock ?? _Clock();
  await tester.pumpWidget(
    ProviderScope(
      // A new scope each time: nothing in memory survives a launch.
      key: UniqueKey(),
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        disguiseServiceProvider.overrideWithValue(
          FakeDisguise(disguised: disguised),
        ),
        biometricGateProvider.overrideWithValue(_NoBiometrics()),
        windowGuardProvider.overrideWithValue(FakeWindowGuard()),
        updateClockProvider.overrideWithValue(() => time.now),
      ],
      child: const GerfautApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const String _line = 'Gerfaut 0.2.0 is available';

void main() {
  group('versions', () {
    ReleaseVersion parse(String text) => ReleaseVersion.tryParse(text)!;

    test('a leading v and build metadata change nothing', () {
      expect(parse('v1.2.3'), parse('1.2.3'));
      expect(parse('V1.2.3'), parse('1.2.3'));
      expect(parse('1.2.3+build.7'), parse('1.2.3'));
      expect('${parse(' v1.2.3+build ')}', '1.2.3');
    });

    test('numbers compare as numbers', () {
      expect(parse('0.1.10') > parse('0.1.9'), isTrue);
      expect(parse('0.10.0') > parse('0.9.9'), isTrue);
      expect(parse('1.0.0') > parse('0.99.99'), isTrue);
      expect(parse('0.1.0') > parse('0.1.0'), isFalse);
    });

    test('pre-releases follow the order of the specification', () {
      const ordered = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
      ];
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(
          parse(ordered[i + 1]) > parse(ordered[i]),
          isTrue,
          reason: '${ordered[i + 1]} > ${ordered[i]}',
        );
        expect(parse(ordered[i]) > parse(ordered[i + 1]), isFalse);
      }
      // A numeric identifier of any size, without overflow.
      expect(
        parse('1.0.0-99999999999999999999999') >
            parse('1.0.0-9999999999999999999999'),
        isTrue,
      );
    });

    test('anything else is not a version', () {
      final garbage = [
        '',
        ' ',
        'v',
        'nightly',
        'latest',
        '1',
        '1.2',
        '1.2.3.4',
        '01.2.3',
        '1.02.3',
        '1.2.3-',
        '1.2.3-01',
        '1.2.3-a..b',
        '1.2.3+',
        '-1.2.3',
        'vv1.2.3',
        '1.2.3 is out',
        '1.2.3\n<script>',
        '1.2.٣',
        '9999999.0.0',
        '1.2.3-${'a' * 80}',
      ];
      for (final text in garbage) {
        expect(ReleaseVersion.tryParse(text), isNull, reason: text);
      }
      expect(ReleaseVersion.tryParse(null), isNull);
    });

    test('only a newer stable release is announced', () {
      expect('${announcedVersion('v0.2.0', current: '0.1.0')}', '0.2.0');
      expect(announcedVersion('0.1.0', current: '0.1.0'), isNull);
      expect(announcedVersion('0.0.9', current: '0.1.0'), isNull);
      expect(announcedVersion('0.2.0-rc.1', current: '0.1.0'), isNull);
      expect(announcedVersion('nightly', current: '0.1.0'), isNull);
      expect(announcedVersion('0.2.0', current: 'garbage'), isNull);
      // Someone on a release candidate hears about the release.
      expect('${announcedVersion('0.2.0', current: '0.2.0-rc.1')}', '0.2.0');
    });

    test('a node behind Tor is recognized, widely', () {
      Settings on(BackendConfig backend) => Settings(
        activeNetwork: Network.mainnet,
        backends: {Network.mainnet: backend},
        appPrefs: const {},
      );
      expect(nodeThroughTor(on(const PublicEsplora())), isFalse);
      expect(
        nodeThroughTor(on(const CustomEsplora(url: 'https://node.example'))),
        isFalse,
      );
      expect(
        nodeThroughTor(on(const CustomEsplora(url: 'http://abc.ONION/api'))),
        isTrue,
      );
      expect(
        nodeThroughTor(on(const CustomElectrum(url: 'tcp://abc.onion:50001'))),
        isTrue,
      );
      // Another network's onion does not count: it is not the one in use.
      expect(
        nodeThroughTor(
          const Settings(
            activeNetwork: Network.mainnet,
            backends: {
              Network.signet: CustomElectrum(url: 'tcp://abc.onion:50001'),
            },
            appPrefs: {},
          ),
        ),
        isFalse,
      );
    });
  });

  group('the update notice', () {
    testWidgets('shows on the launch after a newer release is known', (
      tester,
    ) async {
      final bridge = _bridge();
      await _launch(tester, bridge);
      // The check ran, and what it found waits for the next time.
      expect(bridge.checkUpdateCalls, 1);
      expect(bridge.appPrefs['updates.latest'], '0.2.0');
      expect(find.text(_line), findsNothing);

      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);
      expect(find.text('View release'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      // In the page, over nothing: no dialog, and the wallets are there.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
    });

    testWidgets('Later closes it for that release, across launches', (
      tester,
    ) async {
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'});
      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text(_line), findsNothing);
      expect(bridge.appPrefs['updates.dismissed'], '0.2.0');

      await _launch(tester, bridge);
      expect(find.text(_line), findsNothing);
    });

    testWidgets('a release newer than the one closed shows again', (
      tester,
    ) async {
      final bridge = _bridge(
        latest: 'v0.3.0',
        prefs: {'updates.latest': '0.3.0', 'updates.dismissed': '0.2.0'},
      );
      await _launch(tester, bridge);
      expect(find.text('Gerfaut 0.3.0 is available'), findsOneWidget);
      expect(find.text(_line), findsNothing);
    });

    testWidgets('offline says nothing', (tester) async {
      final bridge = _bridge(latest: null);
      await _launch(tester, bridge);
      await _launch(tester, bridge);
      expect(bridge.checkUpdateCalls, 1);
      expect(find.byType(UpdateNotice), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tag that is not a version says nothing', (tester) async {
      for (final tag in ['nightly', 'v0.2', '0.2.0-rc.1', '<b>9.9.9</b>']) {
        final bridge = _bridge(latest: tag);
        await _launch(tester, bridge);
        await _launch(tester, bridge);
        expect(find.textContaining('is available'), findsNothing, reason: tag);
        expect(bridge.appPrefs['updates.latest'] ?? '', isEmpty, reason: tag);
      }
    });

    testWidgets('a stored value that is not a version says nothing', (
      tester,
    ) async {
      final bridge = _bridge(latest: null, prefs: {'updates.latest': 'soon'});
      await _launch(tester, bridge);
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('a release no newer than this build says nothing', (
      tester,
    ) async {
      final bridge = _bridge(
        latest: null,
        prefs: {'updates.latest': appVersion},
      );
      await _launch(tester, bridge);
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('a withdrawn release stops being offered', (tester) async {
      final bridge = _bridge(
        latest: 'v$appVersion',
        prefs: {'updates.latest': '0.2.0'},
      );
      await _launch(tester, bridge);
      // The check of this launch answered with the running version.
      expect(find.text(_line), findsNothing);
      expect(bridge.appPrefs['updates.latest'], '');
    });

    testWidgets('never over the lock screen, and there after the unlock', (
      tester,
    ) async {
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'})
        ..lock = const AppLock(kind: LockKind.pin, biometric: false)
        ..lockSecret = '1234';
      await _launch(tester, bridge);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
      // Nothing is asked from behind the lock either.
      expect(bridge.checkUpdateCalls, 0);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text(_line), findsOneWidget);
      expect(bridge.checkUpdateCalls, 1);
    });

    testWidgets('never while disguised, locked or open', (tester) async {
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'})
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
      expect(bridge.checkUpdateCalls, 0);
    });

    testWidgets('the button opens the release page and nothing else', (
      tester,
    ) async {
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'});
      await _launch(tester, bridge);

      await tester.tap(find.text('View release'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [_releases]);
      expect(releasePageUrl, _releases);
      // Asked once: the notice does not come back for this release.
      expect(find.text(_line), findsNothing);
      expect(bridge.appPrefs['updates.dismissed'], '0.2.0');
    });

    testWidgets('both targets are 44 px and a screen reader hears it all', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'});
      await _launch(tester, bridge);

      for (final label in ['Later', 'View release']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
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
      final bridge = _bridge(prefs: {'updates.latest': '0.2.0'});
      await _launch(tester, bridge);
      expect(find.text(_line), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wears the dark theme as a plain card', (tester) async {
      final bridge = _bridge(
        prefs: {'updates.latest': '0.2.0', 'mobile.theme': 'dark'},
      );
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

  group('the automatic check', () {
    testWidgets('asks once a day at most', (tester) async {
      final clock = _Clock();
      final bridge = _bridge();
      await _launch(tester, bridge, clock: clock);
      expect(bridge.checkUpdateCalls, 1);

      clock.now += updateCheckPeriod - 1;
      await _launch(tester, bridge, clock: clock);
      expect(bridge.checkUpdateCalls, 1);

      clock.now += 1;
      await _launch(tester, bridge, clock: clock);
      expect(bridge.checkUpdateCalls, 2);
    });

    testWidgets('asks nothing on the day of the first launch', (tester) async {
      final clock = _Clock();
      final fresh = _bridge(openedBefore: false);
      await _launch(tester, fresh, clock: clock);
      expect(fresh.checkUpdateCalls, 0);
      expect(fresh.appPrefs['updates.checked_at'], '${clock.now}');

      clock.now += updateCheckPeriod - 1;
      await _launch(tester, fresh, clock: clock);
      expect(fresh.checkUpdateCalls, 0);

      clock.now += 1;
      await _launch(tester, fresh, clock: clock);
      expect(fresh.checkUpdateCalls, 1);
    });

    testWidgets('a failed check counts: the next one is tomorrow', (
      tester,
    ) async {
      final clock = _Clock();
      final bridge = _bridge(latest: null);
      await _launch(tester, bridge, clock: clock);
      clock.now += 3600;
      await _launch(tester, bridge, clock: clock);
      expect(bridge.checkUpdateCalls, 1);
    });

    testWidgets('coming back from the background is a session too', (
      tester,
    ) async {
      final clock = _Clock();
      final bridge = _bridge();
      await _launch(tester, bridge, clock: clock);
      expect(find.text(_line), findsNothing);

      clock.now += updateCheckPeriod;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_line), findsOneWidget);
      expect(bridge.checkUpdateCalls, 2);
    });

    testWidgets('asks nothing once turned off', (tester) async {
      final bridge = _bridge(prefs: {'updates.auto': '0'});
      await _launch(tester, bridge);
      await _launch(tester, bridge);
      expect(bridge.checkUpdateCalls, 0);
    });

    testWidgets('asks nothing while the node is an onion', (tester) async {
      final bridge = _bridge(
        backends: {
          Network.mainnet: const CustomElectrum(url: 'tcp://abc.onion:50001'),
        },
      );
      await _launch(tester, bridge);
      expect(bridge.checkUpdateCalls, 0);
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
      expect(find.textContaining('GitHub sees your IP address'), findsOne);
      expect(find.textContaining('does not go through Tor'), findsOne);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(bridge.appPrefs['updates.auto'], '0');
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
      await tester.tap(find.text('Get 0.2.0'));
      await tester.pumpAndSettle();
      expect(launcher.launched, [_releases]);
      // What an asked-for check finds is kept for the notice too.
      expect(bridge.appPrefs['updates.latest'], '0.2.0');
    });

    testWidgets('a tag that is not a version reads as up to date', (
      tester,
    ) async {
      final bridge = _bridge(latest: 'Get rich <now>');
      await open(tester, bridge);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('You are up to date.'), findsOneWidget);
      expect(find.textContaining('rich'), findsNothing);
    });
  });
}
