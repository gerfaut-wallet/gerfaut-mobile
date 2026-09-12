import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/premium_channels.dart';
import 'package:gerfaut/screens/premium_consent.dart';
import 'package:gerfaut/screens/settings.dart';
import 'package:gerfaut/screens/settings/premium_section.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/apps.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/clipboard.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/premium.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/alert_banner.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/notice.dart';
import 'package:gerfaut/widgets/premium_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fakes.dart';
import 'menu.dart';

/// The key the fake server knows, as a person would type it.
const String knownKey = 'ABCD-EFGH-IJKM-NPQR';

/// A vault opened before, on mainnet, with a descriptor wallet and a
/// watched address.
FakeBridge premiumBridge({List<WalletMeta>? wallets, bool activated = false}) {
  final bridge = FakeBridge(
    wallets:
        wallets ??
        [
          makeMeta(id: 'w1', name: 'Cold storage'),
          makeMeta(
            id: 'w2',
            name: 'Donations',
            kind: const SingleAddressKind(address: 'bc1qdonations'),
          ),
          makeMeta(id: 'w3', name: 'Signet tests', network: Network.signet),
        ],
    settings: const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
  if (activated) {
    bridge.premiumKey = 'abcdefghijkmnpqr';
    bridge.premiumClaims = LicenceClaims(
      subject: 'ab' * 32,
      expiresAt: bridge.premiumPaidUntil,
      issuedAt: bridge.premiumPaidUntil - 60 * 86400,
    );
  }
  return bridge;
}

/// The settings opened on the Premium section, or on the root list.
Widget premiumApp(
  FakeBridge bridge, {
  bool root = false,
  FakeSensitiveClipboard? clipboard,
  FakeAppOpener? appOpener,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
      if (clipboard != null)
        sensitiveClipboardProvider.overrideWithValue(clipboard),
      if (appOpener != null) appOpenerProvider.overrideWithValue(appOpener),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: SettingsScreen(section: root ? null : SettingsSection.premium),
    ),
  );
}

/// The whole app, the way it starts: the banner lives on the home screen.
Widget wholeApp(FakeBridge bridge) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: const GerfautApp(),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The switch on the row that names [wallet].
Switch switchOf(WidgetTester tester, String wallet) {
  return tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(of: find.text(wallet), matching: find.byType(Row)),
      matching: find.byType(Switch),
    ),
  );
}

Future<void> toggle(WidgetTester tester, String wallet) async {
  await tester.tap(
    find.descendant(
      of: find.ancestor(of: find.text(wallet), matching: find.byType(Row)),
      matching: find.byType(Switch),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the key', () {
    test('formats as it is typed, in lowercase, pasted or not', () {
      expect(formatKey('ABCDEFGHIJKMNPQR'), 'abcd-efgh-ijkm-npqr');
      expect(formatKey('abcd-efgh-ijkm-npqr'), 'abcd-efgh-ijkm-npqr');
      expect(formatKey('abcdef'), 'abcd-ef');
      expect(isWellFormedKey('abcd efgh ijkm npqr'), isTrue);
      expect(isWellFormedKey('abcd-efgh-ijkm-npq'), isFalse);
      // The alphabet leaves out what a screen misreads.
      expect(isWellFormedKey('abcd-efgh-ijkl-npqr'), isFalse);
      expect(keyStrangers('abcd-efgh-ijkl-npq0'), {'l', '0'});
    });

    test('the formatter keeps the caret with its symbol', () {
      const formatter = AccountKeyFormatter();
      final pasted = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'ABCD EFGH-IJKM_NPQRSTUV',
          selection: TextSelection.collapsed(offset: 23),
        ),
      );
      expect(pasted.text, 'abcd-efgh-ijkm-npqr');
      expect(pasted.selection.baseOffset, 19);
      final typing = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'abcde',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(typing.text, 'abcd-e');
      expect(typing.selection.baseOffset, 6);
    });

    test('a distance in words', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1_800_000_000 * 1000);
      final at = 1_800_000_000;
      expect(relativeTimeWords(at, now: now), 'just now');
      expect(relativeTimeWords(at - 3 * 86400, now: now), '3 days ago');
      expect(relativeTimeWords(at - 86400, now: now), 'yesterday');
      expect(relativeTimeWords(at - 3600, now: now), 'an hour ago');
      expect(relativeTimeWords(at - 5 * 60, now: now), '5 minutes ago');
    });
  });

  group('the root row', () {
    testWidgets('is the eighth, with the gem in Bruyère', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(premiumApp(premiumBridge(), root: true));
      await tester.pumpAndSettle();

      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Not activated'), findsOneWidget);
      final gem = tester.widget<Icon>(find.byIcon(LucideIcons.gem));
      expect(gem.color, GerfautTokens.light.premium);
      // The other rows keep the muted glyph.
      final about = tester.widget<Icon>(find.byIcon(LucideIcons.info));
      expect(about.color, GerfautTokens.light.textMuted);
    });

    testWidgets('says the paid time and the count once active', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge, root: true));
      await tester.pumpAndSettle();

      final until = formatDate(bridge.premiumPaidUntil);
      expect(
        find.text('Active until $until · no wallets watched'),
        findsOneWidget,
      );
    });

    testWidgets('says how long ago the key expired', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      bridge.premiumClaims = LicenceClaims(
        subject: 'ab' * 32,
        expiresAt: now - 3 * 86400,
        issuedAt: now - 40 * 86400,
      );
      await tester.pumpWidget(premiumApp(bridge, root: true));
      await tester.pumpAndSettle();

      expect(find.text('Expired 3 days ago'), findsOneWidget);
    });
  });

  group('the licence card', () {
    testWidgets('asks the server nothing without a key', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Licence'), findsOneWidget);
      expect(find.text('Watched wallets'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Recent alerts'), findsOneWidget);
      expect(
        find.text(
          'No alerts yet. Gerfaut will tell you here and on your channels.',
        ),
        findsOneWidget,
      );
      expect(bridge.premiumCalls.where((c) => c != 'state'), isEmpty);
      // The section sells nothing: one link to the site, no price.
      expect(find.text('Get Premium'), findsOneWidget);
      expect(find.textContaining('€'), findsNothing);
    });

    testWidgets('formats the key, activates it and shows the date', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      final activate = find.widgetWithText(PrimaryButton, 'Activate');
      expect(tester.widget<PrimaryButton>(activate).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ABCDEFGHIJKM');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'abcd-efgh-ijkm',
      );
      expect(tester.widget<PrimaryButton>(activate).onPressed, isNull);

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      expect(tester.widget<PrimaryButton>(activate).onPressed, isNotNull);
      await tester.tap(activate);
      await tester.pumpAndSettle();

      expect(bridge.premiumKey, 'abcdefghijkmnpqr');
      expect(
        find.text('Active until ${formatDate(bridge.premiumPaidUntil)}'),
        findsOneWidget,
      );
      expect(find.byType(PremiumPill), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
      expect(find.text('Forget this key'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('names an unknown key and a key with no paid time', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz-zzzz-zzzz-zzzz');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(find.text('Unknown key.'), findsOneWidget);
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.info);
      expect(bridge.premiumKey, isNull);

      bridge.onPremiumActivate = (_) => throw const BridgeException(
        'premium_no_paid_time',
        'this key has no paid time left',
      );
      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(find.text('This key has no paid time.'), findsOneWidget);
      expect(find.text('Unknown key.'), findsNothing);
    });

    testWidgets('an unreachable server gets an amber note and a retry', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      var attempts = 0;
      bridge.onPremiumActivate = (key) {
        attempts++;
        if (attempts == 1) {
          throw const BridgeException('premium_unreachable', 'timed out');
        }
        return PremiumLicence(
          certificate: 'c',
          paidUntil: bridge.premiumPaidUntil,
          claims: LicenceClaims(
            subject: 'ab' * 32,
            expiresAt: bridge.premiumPaidUntil,
            issuedAt: 0,
          ),
        );
      };
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.textContaining('Active until'), findsOneWidget);
    });

    testWidgets('forgetting the key asks first, then clears it here only', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not on the server'), findsOneWidget);
      expect(bridge.premiumKey, isNotNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not on the server'), findsNothing);

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget key'));
      await tester.pumpAndSettle();
      expect(bridge.premiumKey, isNull);
      // The yes given for a wallet outlives the key.
      expect(bridge.premiumConsents, hasLength(1));
      expect(find.text('Activate'), findsOneWidget);
    });

    testWidgets('the same confirmation can take the account with it', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch1',
          kind: ChannelKind.webhook,
          target: 'https://example.org/hook',
          linked: true,
          createdAt: 1,
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      expect(find.text('Forget key'), findsOneWidget);

      // Ticked, the confirmation says what nothing brings back, and
      // the button says what it does.
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.alert);
      expect(note.message, contains('nothing brings any of it back'));
      expect(find.text('Forget key'), findsNothing);
      expect(find.text('Delete and forget'), findsOneWidget);
      expect(bridge.premiumAccountDeleted, isFalse);

      // Cancelling puts the box back down: a tick is for one press.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      expect(find.text('Forget key'), findsOneWidget);

      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete and forget'));
      await tester.pumpAndSettle();

      expect(bridge.premiumCalls, contains('delete-account'));
      expect(bridge.premiumCalls, isNot(contains('forget')));
      expect(bridge.premiumAccountDeleted, isTrue);
      // The server went first, and everything went with it.
      expect(bridge.premiumChannelList, isEmpty);
      expect(bridge.premiumConsents, isEmpty);
      expect(bridge.premiumKey, isNull);
      expect(find.text('Activate'), findsOneWidget);
    });

    testWidgets('a server that refuses leaves the key where it was', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.onPremiumDeleteAccount = () =>
          throw const BridgeException('premium_unreachable', 'timed out');
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete and forget'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(bridge.premiumAccountDeleted, isFalse);
      expect(bridge.premiumKey, isNotNull);
    });

    testWidgets('an expired key says so in amber, with the grace', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      bridge.premiumClaims = LicenceClaims(
        subject: 'ab' * 32,
        expiresAt: now - 86400,
        issuedAt: now - 40 * 86400,
      );
      // The refresh on opening would restore the fake's paid time.
      bridge.onPremiumActivate = (_) =>
          throw const BridgeException('premium_unreachable', 'offline');
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      final line = tester.widget<Text>(
        find.textContaining('alerts stop 7 days after expiry'),
      );
      expect(line.data, startsWith('Expired on ${formatDate(now - 86400)}'));
      expect(line.style!.color, GerfautTokens.light.pending);
      expect(find.text('Renew'), findsOneWidget);
    });

    testWidgets('renewing opens the form and copies the key', (tester) async {
      useTallSurface(tester);
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final clipboard = FakeSensitiveClipboard();
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge, clipboard: clipboard));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renew'));
      await tester.pumpAndSettle();

      // The address carries no key: it would be written into the
      // browser's history, offered by every completion afterwards, and
      // passed to every redirect on the way. The fragment names the
      // form and never leaves the browser.
      expect(launcher.launched, ['https://gerfaut-wallet.com/premium#renew']);
      expect(launcher.launched.single, isNot(contains(bridge.premiumKey!)));

      // The key travels by the guarded clipboard, and the line says so.
      expect(clipboard.copied, [bridge.premiumKey]);
      expect(
        find.text('Key copied, paste it on the renewal page'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the watched wallets card', () {
    testWidgets('lists the wallets of the server network only', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Cold storage'), findsOneWidget);
      expect(find.text('Donations'), findsOneWidget);
      expect(find.text('Signet tests'), findsNothing);
      // A single address is greyed and says why.
      expect(switchOf(tester, 'Donations').onChanged, isNull);
      expect(
        find.text('Single addresses cannot be watched yet.'),
        findsOneWidget,
      );
      expect(switchOf(tester, 'Cold storage').onChanged, isNotNull);
      expect(switchOf(tester, 'Cold storage').value, isFalse);
    });

    testWidgets('the first switch-on asks for consent, in red, once', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await toggle(tester, 'Cold storage');
      expect(find.byType(PremiumConsentScreen), findsOneWidget);
      expect(find.text('Watch this wallet from the server'), findsOneWidget);
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.alert);
      expect(note.message, startsWith("Gerfaut's server will learn every"));
      expect(find.text('The descriptor'), findsOneWidget);
      expect(find.text('The name you gave the wallet'), findsOneWidget);

      // Cancel: nothing leaves the device.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumConsentScreen), findsNothing);
      expect(bridge.premiumCalls.where((c) => c.startsWith('watch:')), isEmpty);
      expect(bridge.premiumConsents, isEmpty);

      // Yes: the wallet is handed over and the yes is kept.
      await toggle(tester, 'Cold storage');
      await tester.tap(find.text('Watch this wallet'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('watch:w1'));
      expect(bridge.premiumConsents.map((c) => c.walletId), ['w1']);
      expect(switchOf(tester, 'Cold storage').value, isTrue);
      expect(find.byType(WatchedPill), findsOneWidget);
      expect(find.textContaining('Watched since'), findsOneWidget);
      expect(find.textContaining('· 3 coins'), findsOneWidget);

      // Off: removed at once, no question asked.
      await toggle(tester, 'Cold storage');
      expect(bridge.premiumCalls, contains('unwatch:w1'));
      expect(find.byType(GerfautNotice), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isFalse);

      // On again: the yes was given, it is not asked twice.
      await toggle(tester, 'Cold storage');
      expect(find.byType(PremiumConsentScreen), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isTrue);
    });

    testWidgets('says Scanning until the first scan ends, then the coins', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumScansInstantly = false;
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await toggle(tester, 'Cold storage');
      expect(find.text('Scanning…'), findsOneWidget);
      expect(find.byType(WatchedPill), findsNothing);

      bridge.premiumFinishScans(coins: 5);
      final asked = bridge.premiumCalls.where((c) => c == 'wallets').length;
      await tester.pump(scanPollEvery);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls.where((c) => c == 'wallets').length,
        greaterThan(asked),
      );
      expect(find.text('Scanning…'), findsNothing);
      expect(find.textContaining('· 5 coins'), findsOneWidget);
      expect(find.byType(WatchedPill), findsOneWidget);
    });

    testWidgets('a scan the server says is queued is named as one', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      // The server states the pending scan itself: the row says what
      // it is, rather than guessing from a date it has not stamped.
      bridge.premiumWatched.add(
        const WalletWatch(
          id: 'w1',
          name: 'Cold storage',
          scriptKind: 'segwit',
          watchedSince: 1755000000,
          baselineAt: null,
          baselineHeight: null,
          baselinePending: true,
          coins: 0,
          valueSats: 0,
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('First scan pending'), findsOneWidget);
      expect(find.text('Scanning…'), findsNothing);
      // Not watched yet, as far as the balances go.
      expect(find.byType(WatchedPill), findsNothing);

      bridge.premiumFinishScans(coins: 2);
      await tester.pump(scanPollEvery);
      await tester.pumpAndSettle();
      expect(find.text('First scan pending'), findsNothing);
      expect(find.textContaining('· 2 coins'), findsOneWidget);
      expect(find.byType(WatchedPill), findsOneWidget);
    });

    testWidgets('a refusal lands under the card, in amber', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      bridge.onPremiumWatch = (_) => throw const BridgeException(
        'premium_no_paid_time',
        'this key has no paid time left',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await toggle(tester, 'Cold storage');
      expect(find.text('This key has no paid time.'), findsOneWidget);
      expect(switchOf(tester, 'Cold storage').value, isFalse);
    });
  });

  group('the channels card', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('offers four kinds, each explained', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      for (final kind in ChannelKind.values) {
        expect(find.text(kind.label), findsOneWidget);
        expect(find.text(channelHint(kind)), findsOneWidget);
      }
    });

    testWidgets('ntfy: a topic is drawn, shown once, opened in the app', (
      tester,
    ) async {
      useTallSurface(tester);
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final opener = FakeAppOpener();
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge, appOpener: opener));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ntfy'));
      await tester.pumpAndSettle();

      // Created with no target: the topic is the core's to draw.
      expect(bridge.premiumCalls, contains('create:ntfy:'));
      expect(find.byType(NtfyChannelScreen), findsOneWidget);
      expect(
        find.text('Subscribe to this topic in the ntfy app'),
        findsOneWidget,
      );
      // The topic the core drew, kept in the vault by channel id.
      final topic = bridge.appPrefs['premium.ntfy.ch1']!;
      expect(topic, hasLength(24));
      expect(
        find.text('https://ntfy.gerfaut-wallet.com/$topic'),
        findsOneWidget,
      );
      expect(find.text('Copy'), findsOneWidget);
      // The first channel is tried at once.
      expect(bridge.premiumCalls, contains('test:ch1'));

      // To ntfy by name, never to whoever declared the scheme: the
      // chooser an implicit intent raises would be a chooser for who
      // reads the alerts of this account.
      await tester.tap(find.text('Open in ntfy'));
      await tester.pumpAndSettle();
      expect(opener.opened, [
        'io.heckel.ntfy ntfy://ntfy.gerfaut-wallet.com/$topic',
      ]);
      expect(launcher.launched, isEmpty);
      expect(find.textContaining('not installed'), findsNothing);

      // The topic stays reachable from the row.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ntfy'), findsOneWidget);
      await tester.tap(find.byTooltip('More for ntfy'));
      await tester.pumpAndSettle();
      expect(find.text('Subscribe link'), findsOneWidget);
      expect(find.text('Send a test'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('ntfy: a phone without the app is told so', (tester) async {
      useTallSurface(tester);
      UrlLauncherPlatform.instance = FakeUrlLauncher();
      final opener = FakeAppOpener(installed: false);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge, appOpener: opener));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ntfy'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open in ntfy'));
      await tester.pumpAndSettle();
      // Nothing started, so the sentence is exact: no other app was
      // offered the topic on the way.
      expect(opener.opened, hasLength(1));
      expect(
        find.text('The ntfy app is not installed on this phone.'),
        findsOneWidget,
      );
      // The topic is still there to copy into it once installed.
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('ntfy: the topic is copied as a secret', (tester) async {
      useTallSurface(tester);
      UrlLauncherPlatform.instance = FakeUrlLauncher();
      final clipboard = FakeSensitiveClipboard();
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge, clipboard: clipboard));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ntfy'));
      await tester.pumpAndSettle();

      // The topic is the whole secret of the channel: whoever holds it
      // reads the alerts of this account. It never goes on the
      // clipboard the system previews and keeps a history of.
      final topic = bridge.appPrefs['premium.ntfy.ch1']!;
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(clipboard.copied, ['https://ntfy.gerfaut-wallet.com/$topic']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('telegram: the code, the link, and Linked by itself', (
      tester,
    ) async {
      useTallSurface(tester);
      final launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telegram'));
      await tester.pumpAndSettle();

      expect(find.byType(TelegramChannelScreen), findsOneWidget);
      expect(find.text('Send this to @GerfautAlertsBot'), findsOneWidget);
      expect(find.text('/start code1'), findsOneWidget);
      expect(find.text('Waiting for the bot'), findsOneWidget);
      // Not tested before the bot has it: the test would only fail.
      expect(bridge.premiumCalls.where((c) => c.startsWith('test:')), isEmpty);

      await tester.tap(find.text('Open Telegram'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://t.me/GerfautAlertsBot?start=code1']);

      // Three seconds later the server is asked; the bot has answered.
      bridge.premiumLinkTelegram('ch1');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Telegram is linked'), findsOneWidget);
      expect(find.text('Linked'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Linked'), findsOneWidget);
      expect(find.text('Waiting for the bot'), findsNothing);
    });

    testWidgets('telegram: the row names the chat the bot answers', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch7',
          kind: ChannelKind.telegram,
          target: 'linked',
          linked: true,
          linkedName: 'Alice',
          createdAt: 1,
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Linked'), findsOneWidget);
      // A chat id is nothing anyone recognizes; the name the bot
      // learned is.
      expect(find.text('Linked to Alice'), findsOneWidget);
      expect(find.text('linked'), findsNothing);
    });

    testWidgets('e-mail and webhook each take a form', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-mail'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Alerts say which wallet moved, never an address or an amount.',
        ),
        findsOneWidget,
      );
      final add = find.widgetWithText(PrimaryButton, 'Add e-mail');
      expect(tester.widget<PrimaryButton>(add).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'me@example.org');
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('create:email:me@example.org'));
      expect(
        find.text('Confirmation sent to m***@example.org'),
        findsOneWidget,
      );
      // Nothing is sent to an address that has not answered yet, not
      // even the test the first channel usually gets.
      expect(bridge.premiumCalls.where((c) => c.startsWith('test:')), isEmpty);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Webhook'));
      await tester.pumpAndSettle();
      expect(
        find.text('Signed with HMAC-SHA256. See the docs.'),
        findsOneWidget,
      );
      final hook = find.widgetWithText(PrimaryButton, 'Add webhook');
      // The page under this one keeps its own fields: the finders stay
      // inside the form on top.
      final hookFields = find.descendant(
        of: find.byType(WebhookChannelScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(hookFields.first, 'http://example.org/hook');
      await tester.pumpAndSettle();
      // Only https will do.
      expect(tester.widget<PrimaryButton>(hook).onPressed, isNull);
      await tester.enterText(hookFields.first, 'https://example.org/hook');
      await tester.enterText(hookFields.last, 'shh');
      await tester.pumpAndSettle();
      await tester.tap(hook);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls,
        contains('create:webhook:https://example.org/hook'),
      );
      expect(find.text('https://example.org/hook'), findsOneWidget);
    });

    /// An account with one e-mail channel the address has not answered
    /// for yet: the state the server leaves a new one in.
    FakeBridge waitingForCode() {
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch4',
          kind: ChannelKind.email,
          target: 'm***@example.org',
          linked: false,
          createdAt: 1,
        ),
      );
      return bridge;
    }

    testWidgets('e-mail: the code links the channel from its row', (
      tester,
    ) async {
      // The width of a small phone, and height enough to lay the whole
      // section out: the field, the button and the row they sit under
      // have to hold at 411dp.
      tester.view.physicalSize = const Size(411, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bridge = waitingForCode();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for the code'), findsOneWidget);
      expect(
        find.text('Confirmation sent to m***@example.org'),
        findsOneWidget,
      );
      // Nothing reaches an address that has not answered: no test to
      // offer until it has.
      await tester.tap(find.byTooltip('More for E-mail'));
      await tester.pumpAndSettle();
      expect(find.text('Send a test'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(PrimaryButton, 'Confirm');
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNull);
      // Six digits and nothing else.
      await tester.enterText(find.byType(TextField), 'abc12');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );
      expect(tester.widget<PrimaryButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '482913');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(bridge.premiumCalls, contains('confirm:ch4:482913'));
      expect(find.text('Waiting for the code'), findsNothing);
      expect(find.textContaining('Confirmation sent to'), findsNothing);
      expect(find.text('m***@example.org'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('e-mail: a refused code says so beside the field', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = waitingForCode();
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      // 400: the server's own words say which of the two it is.
      await tester.enterText(find.byType(TextField), '111111');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('The code was not accepted.'), findsOneWidget);
      expect(find.text('that code is wrong or has expired'), findsOneWidget);
      expect(find.text('Waiting for the code'), findsOneWidget);

      // 429: the same sentence, the server's own reason under it.
      bridge.onPremiumConfirmChannel = (_, _) => throw const BridgeException(
        'premium_rejected',
        'too many wrong codes; add the channel again for a new one',
      );
      await tester.enterText(find.byType(TextField), '222222');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('too many wrong codes; add the channel again for a new one'),
        findsOneWidget,
      );
      expect(find.text('that code is wrong or has expired'), findsNothing);

      // A server out of reach is not a code that was refused.
      bridge.onPremiumConfirmChannel = (_, _) =>
          throw const BridgeException('premium_unreachable', 'timed out');
      await tester.enterText(find.byType(TextField), '333333');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.text('The code was not accepted.'), findsNothing);
    });

    testWidgets('e-mail: a confirmation that never left says so', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      // The server answered, and the mail behind it did not go out:
      // 502, which the core reads as the server being out of reach.
      bridge.onPremiumCreateChannel = (_, _, _) => throw const BridgeException(
        'premium_unreachable',
        'HTTP 502: the confirmation e-mail could not be sent; try again later',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-mail'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'me@example.org');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add e-mail'));
      await tester.pumpAndSettle();

      expect(
        find.text('The confirmation e-mail could not be sent.'),
        findsOneWidget,
      );
      expect(find.text('The server did not take this address.'), findsNothing);
      // The address is still there to try again with.
      expect(find.byType(EmailChannelScreen), findsOneWidget);
    });

    testWidgets('the menu sends a test or removes the channel', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch9',
          kind: ChannelKind.email,
          target: 'j***@example.org',
          linked: true,
          createdAt: 1,
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for E-mail'));
      await tester.pumpAndSettle();
      expect(menuRowHeight(tester, 'Send a test'), greaterThanOrEqualTo(44));
      await tester.tap(find.text('Send a test'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('test:ch9'));
      expect(find.text('Test sent to E-mail'), findsOneWidget);

      bridge.onPremiumTestChannel = (_) => throw const BridgeException(
        'premium_rejected',
        'the provider refused: mailbox unavailable',
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More for E-mail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test'));
      await tester.pumpAndSettle();
      expect(find.text('The Gerfaut server refused.'), findsOneWidget);
      expect(
        find.text('the provider refused: mailbox unavailable'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('More for E-mail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('delete:ch9'));
      expect(find.text('j***@example.org'), findsNothing);
      expect(find.text('Channel removed'), findsOneWidget);
    });
  });

  group('the recent alerts card', () {
    testWidgets('lists the events and opens the wallet', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      bridge.premiumEvents = [
        PremiumEvent(
          id: 2,
          kind: AlertKind.spendDetected,
          wallet: 'w1',
          walletName: 'Cold storage',
          at: now - 120,
        ),
        PremiumEvent(
          id: 1,
          kind: AlertKind.walletRegistered,
          wallet: 'w1',
          walletName: 'Cold storage',
          at: now - 3600,
        ),
        // The same event twice, as two servers might send it.
        PremiumEvent(
          id: 1,
          kind: AlertKind.walletRegistered,
          wallet: 'w1',
          walletName: 'Cold storage',
          at: now - 3600,
        ),
        PremiumEvent(
          id: 0,
          kind: AlertKind.other,
          wallet: 'gone',
          walletName: 'Removed',
          at: now - 7200,
        ),
      ];
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.textContaining('coins are moving'), findsOneWidget);
      expect(find.textContaining('now watched by the server'), findsOneWidget);
      expect(find.text('2 min ago'), findsOneWidget);
      expect(find.text('1 h ago'), findsOneWidget);
      // A wallet this vault no longer has opens nothing.
      expect(find.textContaining('something happened'), findsOneWidget);

      await tester.tap(find.textContaining('coins are moving'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletHomeScreen), findsOneWidget);
    });
  });

  group('the watch offline banner', () {
    FakeBridge watching() {
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      return bridge;
    }

    testWidgets('one missed beat says nothing, two say it in red', (
      tester,
    ) async {
      final bridge = watching();
      bridge.onPremiumHeartbeat = () =>
          throw const BridgeException('premium_unreachable', 'timed out');
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();

      expect(bridge.premiumHeartbeatCalls, 1);
      expect(find.byType(AlertBanner), findsNothing);

      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumHeartbeatCalls, 2);
      expect(find.byType(AlertBanner), findsOneWidget);
      expect(
        find.textContaining("Gerfaut's watch is offline since"),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your wallets are not being monitored.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);

      // Acknowledged: down, and remembered in the vault.
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertBanner), findsNothing);
      expect(bridge.premiumAcknowledgedUntil, isNotNull);

      // The server is back: the acknowledgement is lifted for next time.
      bridge.onPremiumHeartbeat = null;
      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumAcknowledgedUntil, isNull);
      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('a verified beat clears an unacknowledged banner', (
      tester,
    ) async {
      final bridge = watching();
      bridge.onPremiumHeartbeat = () =>
          throw const BridgeException('premium_stale_heartbeat', 'off');
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(find.byType(AlertBanner), findsOneWidget);

      bridge.onPremiumHeartbeat = null;
      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(find.byType(AlertBanner), findsNothing);
    });

    testWidgets('nothing beats while no wallet is watched', (tester) async {
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(wholeApp(bridge));
      await tester.pumpAndSettle();
      await tester.pump(heartbeatPeriod);
      await tester.pumpAndSettle();
      expect(bridge.premiumHeartbeatCalls, 0);
    });

    testWidgets('the banner keeps its red in the dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFrom(GerfautTokens.dark, Brightness.dark),
          home: Scaffold(
            body: AlertBanner(
              message: 'Offline',
              stamp: 'now',
              actionLabel: 'Acknowledge',
              onAction: () {},
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('Offline'));
      expect(text.style!.color, GerfautTokens.dark.alert);
    });
  });
}
