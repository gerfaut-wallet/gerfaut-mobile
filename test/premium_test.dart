import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/premium_channels.dart';
import 'package:gerfaut/screens/premium_consent.dart';
import 'package:gerfaut/screens/settings/premium_section.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
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
import 'premium_harness.dart';

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

/// What the server holds for a wallet this phone no longer has.
const WalletWatch oldLaptop = WalletWatch(
  id: 'w9',
  name: 'Old laptop',
  scriptKind: 'segwit',
  watchedSince: 1755000000,
  baselineAt: 1755000030,
  baselineHeight: 900000,
  coins: 2,
  valueSats: 200000,
);

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

  group('what a failure says', () {
    /// The first line of the note, for a failure carrying [message] —
    /// which is what the bridge sends, wrapper and all: the core writes
    /// the layer's name in front of its own errors.
    String said(String kind, [String message = 'the machine words']) =>
        premiumFailure(BridgeException(kind, message)).message;

    test('every kind the bridge can send has a sentence of its own', () {
      expect(said('premium_no_key'), 'Enter an account key first.');
      expect(said('premium_unknown_key'), 'Unknown key.');
      expect(said('premium_no_paid_time'), 'This key has no paid time.');
      expect(said('premium_rejected'), 'The Gerfaut server refused.');
      expect(
        said('premium_unreachable'),
        'Could not reach the Gerfaut server.',
      );
      expect(said('premium_invalid'), "The server's answer did not check out.");
      for (final kind in premiumErrorKinds) {
        expect(said(kind), isNot(contains('the machine words')), reason: kind);
      }
    });

    test('a request to slow down is calm, and counts the wait', () {
      final named = premiumFailure(
        const BridgeException(
          'premium_rate_limited',
          'the premium server asks to wait before trying again',
          retryAfter: 42,
        ),
      );
      // Word for word what the desktop app says.
      expect(named.message, 'The server asks to wait. Try again in 42 s.');
      expect(named.retry, isTrue);
      expect(named.detail, isNull);

      final long = premiumFailure(
        const BridgeException('premium_rate_limited', 'x', retryAfter: 600),
      );
      expect(long.message, 'The server asks to wait. Try again in 600 s.');

      final unnamed = premiumFailure(
        const BridgeException('premium_rate_limited', 'x'),
      );
      expect(
        unnamed.message,
        'The server asks to wait. Try again in a moment.',
      );
    });

    test('the kinds and the cases that answer them line up', () {
      final answered = <PremiumFailureKind>{};
      for (final kind in premiumErrorKinds) {
        final answer = premiumFailureKind(kind);
        expect(
          answer,
          isNot(PremiumFailureKind.other),
          reason: '$kind has no case of its own',
        );
        expect(answered.add(answer), isTrue, reason: '$kind shares a case');
      }
    });

    test('a 5xx reads as the sentence the server sent with it', () {
      final failure = premiumFailure(
        const BridgeException(
          'premium_unreachable',
          'the premium server is unreachable: HTTP 502: the confirmation '
              'e-mail could not be sent; try again later',
        ),
      );
      expect(
        failure.message,
        'The confirmation e-mail could not be sent; try again later.',
      );
      expect(failure.retry, isTrue);
    });

    test('an outage and a captive portal both read as out of reach', () {
      const messages = [
        'the premium server is unreachable: could not connect',
        'the premium server is unreachable: HTTP 500',
        'unexpected answer from the premium server: expected value at '
            'line 1 column 1',
      ];
      for (final message in messages) {
        final failure = premiumFailure(
          BridgeException('premium_unreachable', message),
        );
        expect(failure.message, 'Could not reach the Gerfaut server.');
        expect(failure.retry, isTrue);
      }
    });

    test('a kind from elsewhere still gets plain words', () {
      const raw = 'vault decryption failed: wrong key or corrupted file';
      final failure = premiumFailure(const BridgeException('vault', raw));
      expect(failure.message, 'That did not go through.');
      expect(failure.detail, raw);
    });

    test('a refusal names the step and keeps the words under it', () {
      final failure = premiumFailure(
        const BridgeException('premium_rejected', 'wrong or expired code'),
        refusal: 'The code was not accepted.',
      );
      expect(failure.message, 'The code was not accepted.');
      expect(failure.detail, 'wrong or expired code');
      expect(failure.retry, isFalse);
      // A refusal is the only thing that line is about: an outage in
      // the middle of the same step is still an outage.
      expect(
        premiumFailure(
          const BridgeException(
            'premium_unreachable',
            'the premium server is unreachable: could not connect',
          ),
          refusal: 'The code was not accepted.',
        ).message,
        'Could not reach the Gerfaut server.',
      );
    });

    testWidgets('every sentence fits a small phone at twice the size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final kind in [...premiumErrorKinds, 'tor', 'internal']) {
        final failure = premiumFailure(
          BridgeException(kind, 'the machine words, at some length'),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(GerfautSpacing.md),
                      child: GerfautNotice(
                        tone: NoticeTone.info,
                        message: failure.message,
                        hint: failure.hint,
                        detail: failure.detail,
                        liveRegion: true,
                        actionsBelow: true,
                        action: failure.retry
                            ? GhostButton(label: 'Retry', onPressed: () {})
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsOneWidget, reason: kind);
      }
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

      final activate = find.widgetWithText(PremiumButton, 'Activate');
      expect(tester.widget<PremiumButton>(activate).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ABCDEFGHIJKM');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'abcd-efgh-ijkm',
      );
      expect(tester.widget<PremiumButton>(activate).onPressed, isNull);

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      expect(tester.widget<PremiumButton>(activate).onPressed, isNotNull);
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
          throw const BridgeException(
            'premium_unreachable',
            'the premium server is unreachable: could not connect',
          );
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

    testWidgets('a captive portal is the server out of reach', (tester) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      // A hotel wifi answering its own login page where JSON was
      // promised: on a phone, the likeliest of these by far.
      bridge.onPremiumActivate = (_) => throw const BridgeException(
        'premium_unreachable',
        'unexpected answer from the premium server: expected value at '
            'line 1 column 1',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.textContaining('expected value'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a certificate that does not verify names the clock', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge();
      bridge.onPremiumActivate = (_) => throw const BridgeException(
        'premium_invalid',
        'invalid licence certificate: signature does not verify',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), knownKey);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(
        find.text("The server's answer did not check out."),
        findsOneWidget,
      );
      expect(
        find.text("Check this phone's date and time, then try again."),
        findsOneWidget,
      );
      expect(find.textContaining('signature does not verify'), findsNothing);
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

      // Ticked, the confirmation says what nothing brings back — the
      // paid time among it — and the button says what it does. Amber,
      // not red: nothing on chain is at stake, and red is kept for
      // what costs funds or privacy.
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.info);
      expect(note.message, contains('This cannot be undone'));
      expect(note.message, contains('paid time the key had left goes with it'));
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

    testWidgets('the confirmation buttons stack at twice the text size', (
      tester,
    ) async {
      // A small phone, the text doubled: "Cancel" and "Delete and
      // forget" no longer share a line and used to run past the card,
      // an overflow the framework reports, which is what fails this.
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();

      final cancel = tester.getRect(find.widgetWithText(GhostButton, 'Cancel'));
      final delete = tester.getRect(
        find.widgetWithText(DangerButton, 'Delete and forget'),
      );
      expect(delete.top, greaterThanOrEqualTo(cancel.bottom));
      expect(delete.right, lessThanOrEqualTo(360));
      expect(delete.height, 44);
    });

    testWidgets('deleting holds the confirmation until the server answers', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final gate = Completer<void>();
      bridge.onPremiumDeleteAccount = () => gate.future;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget this key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete everything on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete and forget'));
      await tester.pump();

      // The button says what it is doing; neither it, the way out nor
      // the box takes a press until the server has answered.
      expect(find.text('Deleting…'), findsOneWidget);
      final danger = find.byType(DangerButton);
      expect(tester.widget<DangerButton>(danger).onPressed, isNull);
      expect(
        tester
            .widget<GhostButton>(find.widgetWithText(GhostButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      await tester.tap(danger, warnIfMissed: false);
      await tester.pump();
      expect(
        bridge.premiumCalls.where((c) => c == 'delete-account'),
        hasLength(1),
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(bridge.premiumAccountDeleted, isTrue);
      expect(find.text('Activate'), findsOneWidget);
    });

    testWidgets('a server that refuses leaves the key where it was', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.onPremiumDeleteAccount = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
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
      bridge.onPremiumActivate = (_) => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
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
      // A single address is a wallet like another: it can be watched.
      expect(switchOf(tester, 'Donations').onChanged, isNotNull);
      expect(find.textContaining('cannot be watched yet'), findsNothing);
      expect(switchOf(tester, 'Cold storage').onChanged, isNotNull);
      expect(switchOf(tester, 'Cold storage').value, isFalse);
      // On, the switch is Bruyère: the server's watch reads as premium.
      expect(
        switchOf(tester, 'Cold storage').activeTrackColor,
        GerfautTokens.light.premium,
      );
    });

    testWidgets('a single address is asked about as what it is, then sent', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await toggle(tester, 'Donations');
      expect(find.byType(PremiumConsentScreen), findsOneWidget);
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.alert);
      expect(
        note.message,
        startsWith("Gerfaut's server will learn the address of this wallet"),
      );
      expect(find.text('The address'), findsOneWidget);
      expect(find.text('The descriptor'), findsNothing);
      expect(find.text('The name you gave the wallet'), findsOneWidget);

      await tester.tap(find.text('Watch this wallet'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('watch:w2'));
      expect(switchOf(tester, 'Donations').value, isTrue);
    });

    testWidgets('a wallet the server refused says why, in its words', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumWatched.add(
        const WalletWatch(
          id: 'w1',
          name: 'Cold storage',
          scriptKind: 'segwit',
          watchedSince: 1755000000,
          baselineAt: null,
          baselineHeight: null,
          coins: 0,
          valueSats: 0,
          watching: false,
          refusal: WalletRefusal(
            code: 'too_many_coins',
            message: 'This wallet holds more than 5,000 coins.',
          ),
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      final words = tester.widget<Text>(
        find.text('This wallet holds more than 5,000 coins.'),
      );
      expect(words.style!.color, GerfautTokens.light.pending);
      // Not watched, so not badged as watched, and not "scanning".
      expect(find.byType(WatchedPill), findsNothing);
      expect(find.text('Scanning…'), findsNothing);
      // The server holds the row: the switch is on, and takes it off.
      expect(switchOf(tester, 'Cold storage').value, isTrue);
      expect(switchOf(tester, 'Cold storage').onChanged, isNotNull);
    });

    test('a refusal reads from the server, and its absence means watched', () {
      final refused = WalletWatch.fromJson({
        'id': 'w1',
        'name': 'Cold storage',
        'script_kind': 'segwit',
        'watched_since': 1,
        'baseline_at': null,
        'baseline_height': null,
        'coins': 0,
        'value_sats': 0,
        'watching': false,
        'refusal': {'code': 'new_code', 'message': 'Not this one.'},
      });
      expect(refused.refused, isTrue);
      expect(refused.refusal!.message, 'Not this one.');
      // A server that predates the flag refuses no wallet.
      final older = WalletWatch.fromJson({
        'id': 'w1',
        'name': 'Cold storage',
        'script_kind': 'segwit',
        'watched_since': 1,
        'baseline_at': 2,
        'baseline_height': 3,
        'coins': 0,
        'value_sats': 0,
      });
      expect(older.refused, isFalse);
      expect(older.refusal, isNull);
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

      // Off: asked first, since the server deletes the wallet's alert
      // history with the watch. Amber, under the row, the switch still
      // on; the way out closes it, and nothing was called.
      await toggle(tester, 'Cold storage');
      expect(bridge.premiumCalls, isNot(contains('unwatch:w1')));
      expect(switchOf(tester, 'Cold storage').value, isTrue);
      final question = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(question.tone, NoticeTone.info);
      expect(question.actionsBelow, isTrue);
      expect(
        find.text(
          'Unwatching "Cold storage" also deletes its alert history on the '
          'server; the wallet stays on this device.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byType(GerfautNotice)).dy,
        greaterThan(tester.getBottomLeft(find.text('Cold storage')).dy),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(GerfautNotice), findsNothing);
      expect(bridge.premiumCalls, isNot(contains('unwatch:w1')));
      expect(switchOf(tester, 'Cold storage').value, isTrue);

      // The yes: one call, the question gone, the switch off.
      await toggle(tester, 'Cold storage');
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('unwatch:w1'));
      expect(find.byType(GerfautNotice), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isFalse);

      // On again: the yes was given, it is not asked twice.
      await toggle(tester, 'Cold storage');
      expect(find.byType(PremiumConsentScreen), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isTrue);
    });

    testWidgets('a refused unwatch keeps the question up for the next try', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await toggle(tester, 'Cold storage');
      expect(switchOf(tester, 'Cold storage').value, isTrue);

      bridge.onPremiumUnwatch = (_) {
        throw const BridgeException('premium_unreachable', 'timed out');
      };
      await toggle(tester, 'Cold storage');
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();

      // The server did not answer: the question is still there, the
      // switch still on, and the failure said under the card — the
      // next try is one tap, not a switch and a question over again.
      expect(bridge.premiumCalls.where((c) => c == 'unwatch:w1'), hasLength(1));
      expect(
        find.text(
          'Unwatching "Cold storage" also deletes its alert history on the '
          'server; the wallet stays on this device.',
        ),
        findsOneWidget,
      );
      expect(switchOf(tester, 'Cold storage').value, isTrue);
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Could not reach the Gerfaut server.')).dy,
        greaterThan(
          tester.getBottomLeft(find.textContaining('Unwatching "Cold')).dy,
        ),
      );

      bridge.onPremiumUnwatch = null;
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls.where((c) => c == 'unwatch:w1'), hasLength(2));
      expect(find.byType(GerfautNotice), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isFalse);
    });

    testWidgets('the question is held while the server answers', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();
      await toggle(tester, 'Cold storage');

      final gate = Completer<void>();
      bridge.onPremiumUnwatch = (id) async {
        await gate.future;
        bridge.premiumWatched.removeWhere((w) => w.id == id);
      };
      await toggle(tester, 'Cold storage');
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pump();

      // Neither answer can be given again while the call is out: a
      // second press on the deletion has nothing to land on.
      final deed = tester.widget<DangerButton>(find.byType(DangerButton));
      expect(deed.label, 'Unwatching…');
      expect(deed.onPressed, isNull);
      final wayOut = tester.widget<GhostButton>(
        find.widgetWithText(GhostButton, 'Cancel'),
      );
      expect(wayOut.onPressed, isNull);
      expect(find.text('Removing…'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls.where((c) => c == 'unwatch:w1'), hasLength(1));
      expect(find.byType(GerfautNotice), findsNothing);
      expect(switchOf(tester, 'Cold storage').value, isFalse);
    });

    testWidgets('each row is held until its own answer, not the first one', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(
        wallets: [
          makeMeta(id: 'w1', name: 'Cold storage'),
          makeMeta(id: 'w4', name: 'Savings'),
        ],
        activated: true,
      );
      bridge.premiumConsents.addAll(const [
        WatchConsent(walletId: 'w1', consentedAt: 1),
        WatchConsent(walletId: 'w4', consentedAt: 1),
      ]);
      final gates = {'w1': Completer<void>(), 'w4': Completer<void>()};
      bridge.onPremiumWatch = (id) => gates[id]!.future;
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      // Two calls out at once: both rows held.
      await toggle(tester, 'Cold storage');
      await toggle(tester, 'Savings');
      expect(switchOf(tester, 'Cold storage').onChanged, isNull);
      expect(switchOf(tester, 'Savings').onChanged, isNull);
      expect(find.text('Registering…'), findsNWidgets(2));

      // The first answer frees its own row, and no other.
      gates['w1']!.complete();
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'Cold storage').onChanged, isNotNull);
      expect(switchOf(tester, 'Savings').onChanged, isNull);
      expect(find.text('Registering…'), findsOneWidget);

      gates['w4']!.complete();
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'Savings').onChanged, isNotNull);
      expect(find.text('Registering…'), findsNothing);
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

    testWidgets('a Tor that cannot be reached says so in words', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      // What the core answers when the call would have gone through
      // Tor and no Tor answered. Nothing falls back to the clear.
      bridge.onPremiumWallets = () => throw const BridgeException(
        'tor',
        'tor: no Tor proxy to reach gerfaut.onion through',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Tor is not available on this phone.'), findsOneWidget);
      expect(
        find.text(
          'These calls go through Tor and never around it. The Tor card '
          'is under Network.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no Tor proxy to reach'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
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

    testWidgets('a wallet gone from this phone is listed, with a way off', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumWatched.add(oldLaptop);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      // After the phone's own wallets, under the name the server kept.
      expect(find.text('Old laptop'), findsOneWidget);
      expect(
        find.text('Removed from this phone, still watched by the server.'),
        findsOneWidget,
      );
      expect(find.byType(WatchedPill), findsOneWidget);
      expect(find.text('Unwatch'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Old laptop')).dy,
        greaterThan(tester.getTopLeft(find.text('Donations')).dy),
      );
      // No switch: there is no wallet for one to belong to.
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('Unwatch takes it off the server, and the row with it', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumWatched.add(oldLaptop);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      // The same question as the switch, with the server's name for
      // the wallet: nothing is called until it is answered.
      await tester.tap(find.text('Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, isNot(contains('unwatch:w9')));
      expect(
        find.text(
          'Unwatching "Old laptop" also deletes its alert history on the '
          'server.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('unwatch:w9'));
      expect(find.text('Old laptop'), findsNothing);
      expect(find.text('Unwatch'), findsNothing);
      expect(find.byType(GerfautNotice), findsNothing);
    });

    testWidgets("the phone's own wallets keep their switch beside it", (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumConsents.add(
        const WatchConsent(walletId: 'w1', consentedAt: 1),
      );
      bridge.premiumWatched.add(oldLaptop);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await toggle(tester, 'Cold storage');
      expect(bridge.premiumCalls, contains('watch:w1'));
      expect(switchOf(tester, 'Cold storage').value, isTrue);
      expect(find.byType(WatchedPill), findsNWidgets(2));

      await toggle(tester, 'Cold storage');
      await tester.tap(find.widgetWithText(DangerButton, 'Unwatch'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('unwatch:w1'));
      expect(bridge.premiumCalls, isNot(contains('unwatch:w9')));
      expect(switchOf(tester, 'Cold storage').value, isFalse);
      expect(find.text('Old laptop'), findsOneWidget);
    });

    testWidgets('a wallet gone from this phone shows with no local one', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(
        wallets: [
          makeMeta(id: 'w3', name: 'Signet tests', network: Network.signet),
        ],
        activated: true,
      );
      bridge.premiumWatched.add(oldLaptop);
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.textContaining('wallets to watch yet'), findsOneWidget);
      expect(find.text('Old laptop'), findsOneWidget);
      expect(find.text('Unwatch'), findsOneWidget);
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

    testWidgets('telegram: once the page rests, Check again asks out loud', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch1',
          kind: ChannelKind.telegram,
          target: '',
          linked: false,
          linkCode: 'code1',
          startUrl: 'https://t.me/GerfautAlertsBot?start=code1',
          createdAt: 1,
        ),
      );
      // A window of nothing: the first tick is the one that gives up,
      // and hands the asking to the button.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bridgeProvider.overrideWithValue(bridge)],
          child: MaterialApp(
            theme: themeFrom(GerfautTokens.light, Brightness.light),
            home: const TelegramChannelScreen(
              channelId: 'ch1',
              code: 'code1',
              startUrl: 'https://t.me/GerfautAlertsBot?start=code1',
              pollEvery: Duration(seconds: 1),
              pollFor: Duration.zero,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check again'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Check again'), findsOneWidget);
      final asked = bridge.premiumCalls.where((c) => c == 'channels').length;

      // Not linked yet: the tap says so, where a silent tap read as a
      // button that did nothing.
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls.where((c) => c == 'channels').length,
        asked + 1,
      );
      expect(find.textContaining('has not heard from you yet'), findsOneWidget);
      expect(find.text('Waiting for the bot'), findsOneWidget);

      // The server out of reach: said in amber under the button, where
      // the poll's silence used to swallow it.
      bridge.onPremiumChannels = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.textContaining('has not heard from you yet'), findsNothing);

      // The bot answered: the same button finds it.
      bridge.onPremiumChannels = null;
      bridge.premiumLinkTelegram('ch1');
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text('Telegram is linked'), findsOneWidget);
      expect(find.text('Could not reach the Gerfaut server.'), findsNothing);
      expect(find.text('Check again'), findsNothing);
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
      final add = find.widgetWithText(PremiumButton, 'Add e-mail');
      expect(tester.widget<PremiumButton>(add).onPressed, isNull);
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
      final hook = find.widgetWithText(PremiumButton, 'Add webhook');
      // The page under this one keeps its own fields: the finders stay
      // inside the form on top.
      final hookFields = find.descendant(
        of: find.byType(WebhookChannelScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(hookFields.first, 'http://example.org/hook');
      await tester.pumpAndSettle();
      // Only https will do.
      expect(tester.widget<PremiumButton>(hook).onPressed, isNull);
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

      final confirm = find.widgetWithText(PremiumButton, 'Confirm');
      expect(tester.widget<PremiumButton>(confirm).onPressed, isNull);
      // Six digits and nothing else.
      await tester.enterText(find.byType(TextField), 'abc12');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );
      expect(tester.widget<PremiumButton>(confirm).onPressed, isNull);

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
      bridge.onPremiumConfirmChannel = (_, _) => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
      await tester.enterText(find.byType(TextField), '333333');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the Gerfaut server.'), findsOneWidget);
      expect(find.text('The code was not accepted.'), findsNothing);
    });

    testWidgets('e-mail: the code field is a target, and holds six digits '
        'at twice the text size', (tester) async {
      tester.view.physicalSize = const Size(411, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(premiumApp(waitingForCode()));
      await tester.pumpAndSettle();

      // 44px tall at the body size, where the line and its padding
      // alone came to 42.
      final field = find.byType(TextField);
      expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
      final atOne = tester.getSize(field).width;

      // Doubled, the field grows with its digits instead of showing
      // four of the six, and nothing runs past the row.
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpAndSettle();
      await tester.enterText(field, '482913');
      await tester.pumpAndSettle();
      expect(tester.getSize(field).width, closeTo(atOne * 2, 1));
      expect(tester.getSize(field).height, greaterThanOrEqualTo(44));
      final digits = tester.getSize(find.text('482913'));
      expect(digits.width + 2 * GerfautSpacing.md, lessThan(atOne * 2));
      expect(
        tester
            .widget<PremiumButton>(
              find.widgetWithText(PremiumButton, 'Confirm'),
            )
            .onPressed,
        isNotNull,
      );
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
        'the premium server is unreachable: HTTP 502: the confirmation '
            'e-mail could not be sent; try again later',
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-mail'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'me@example.org');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PremiumButton, 'Add e-mail'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The confirmation e-mail could not be sent; try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('The server did not take this address.'), findsNothing);
      expect(find.text('Could not reach the Gerfaut server.'), findsNothing);
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
      // Asked under the row first; nothing has left yet.
      expect(find.text(removeChannelQuestion), findsOneWidget);
      expect(bridge.premiumCalls, isNot(contains('delete:ch9')));
      await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(bridge.premiumCalls, contains('delete:ch9'));
      expect(find.text('j***@example.org'), findsNothing);
      expect(find.text(removeChannelQuestion), findsNothing);
      expect(find.text('Channel removed'), findsOneWidget);
    });

    testWidgets('adding holds the button until the server answers', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      final gate = Completer<void>();
      // A kind the server makes on the spot: the one a second tap in
      // the same beat would make twice.
      bridge.onPremiumCreateChannel = (kind, _, _) async {
        await gate.future;
        return CreatedChannel(
          channel: PremiumChannel(
            id: 'chn',
            kind: kind,
            target: '',
            linked: true,
            createdAt: 1,
          ),
        );
      };
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telegram'));
      await tester.pumpAndSettle();

      expect(find.text('Adding…'), findsOneWidget);
      final add = find.widgetWithText(GhostButton, 'Adding…');
      expect(tester.widget<GhostButton>(add).onPressed, isNull);
      await tester.tap(add, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        bridge.premiumCalls.where((c) => c.startsWith('create:')),
        hasLength(1),
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Add a channel'), findsOneWidget);
      expect(bridge.premiumChannelList, hasLength(1));
    });

    testWidgets('a channel the server turned off says so, in amber', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = premiumBridge(activated: true);
      // Linked, as the server still reports it, and off: a row that
      // read only the first flag showed a channel receiving nothing as
      // healthy.
      bridge.premiumChannelList.add(
        const PremiumChannel(
          id: 'ch7',
          kind: ChannelKind.webhook,
          target: 'https://10.0.0.5/gerfaut',
          linked: true,
          enabled: false,
          createdAt: 1,
        ),
      );
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Not delivering'), findsOneWidget);
      expect(find.text('Linked'), findsNothing);
      final note = tester.widget<GerfautNotice>(find.byType(GerfautNotice));
      expect(note.tone, NoticeTone.info);
      expect(note.message, startsWith('This webhook points at an address'));
      expect(note.message, endsWith('add it again.'));
      // The target is still named, so the row says which one it is.
      expect(find.text('https://10.0.0.5/gerfaut'), findsOneWidget);

      // No test to offer: the server writes nothing to it. Removing it
      // is the one thing left.
      await tester.tap(find.byTooltip('More for Webhook'));
      await tester.pumpAndSettle();
      expect(find.text('Send a test'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('every kind the server can turn off has a sentence', (
      tester,
    ) async {
      for (final kind in ChannelKind.values) {
        final channel = PremiumChannel(
          id: 'x',
          kind: kind,
          target: '',
          linked: true,
          enabled: false,
          createdAt: 1,
        );
        expect(offReason(channel), contains('nothing is delivered'));
        expect(offReason(channel), endsWith('add it again.'));
      }
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
        PremiumEvent(
          id: -1,
          kind: AlertKind.fromId('wallet_refused'),
          wallet: 'w1',
          walletName: 'Cold storage',
          at: now - 10800,
          data: const {
            'code': 'too_many_coins',
            'limit': 5000,
            'message': 'This wallet holds more than 5,000 coins.',
          },
        ),
      ];
      await tester.pumpWidget(premiumApp(bridge));
      await tester.pumpAndSettle();

      expect(find.textContaining('coins are moving'), findsOneWidget);
      expect(find.textContaining('now watched by the server'), findsOneWidget);
      expect(
        find.textContaining(
          'refused by the server: This wallet holds more than 5,000 coins.',
        ),
        findsOneWidget,
      );
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
      bridge.onPremiumHeartbeat = () => throw const BridgeException(
        'premium_unreachable',
        'the premium server is unreachable: could not connect',
      );
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
      bridge.onPremiumHeartbeat = () => throw const BridgeException(
        'premium_invalid',
        "the heartbeat is 934 seconds off this device's clock",
      );
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
