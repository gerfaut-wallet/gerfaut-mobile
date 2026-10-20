import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/policy.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/policy_text.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core_policies.dart';
import 'fakes.dart';

/// The glyph of a pill, by name.
String _glyph(IconData icon) {
  if (icon == LucideIcons.check) return 'check';
  if (icon == LucideIcons.clock) return 'clock';
  if (icon == LucideIcons.circleDashed) return 'circle-dashed';
  if (icon == LucideIcons.keyRound) return 'key-round';
  return 'other';
}

/// The policy page of a wallet as it reads, top to bottom, with the
/// balance card's digest first: every line of text, a pill with its
/// tone and glyph, a bar with how far it has come. The day a countdown
/// ends follows the device's time zone; only its shape is kept.
Future<List<String>> _readPage(WidgetTester tester, String json) async {
  final snapshot = PolicySnapshot.fromJson(corePolicy(json));
  final meta = makeMeta();
  final bridge = FakeBridge(
    wallets: [meta],
    snapshots: {'w1': makeSnapshot(meta: meta)},
  )..policies['w1'] = snapshot;
  tester.view.physicalSize = const Size(411, 731);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        theme: themeFrom(GerfautTokens.light, Brightness.light),
        home: const PolicyScreen(walletId: 'w1'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final lines = ['Balance card: ${policyDigest(snapshot)}'];
  void visit(Element element) {
    switch (element.widget) {
      case StatusPill(:final tone, :final icon, :final label):
        lines.add('[${tone.name} ${_glyph(icon)}] $label');
        return;
      case LockProgress(:final progress):
        lines.add('[bar ${(progress * 100).round()}%]');
        return;
      case Text(:final data, :final textSpan):
        final text = data ?? textSpan!.toPlainText();
        lines.add(
          text.replaceFirst(
            RegExp(r'^Around \w{3} \d{1,2}, \d{4}$'),
            'Around [date]',
          ),
        );
        return;
      case SelectableText(:final data, :final textSpan):
        lines.add(data ?? textSpan!.toPlainText());
        return;
    }
    element.visitChildren(visit);
  }

  tester.element(find.byType(PolicyScreen)).visitChildren(visit);
  return lines;
}

/// Four wallets the core read, the page they make. The same lines
/// whatever the core's version or the app's: a change here is a change
/// the person sees.
void main() {
  group('the policy page of a wallet the core read', () {
    testWidgets('reads several recovery paths', (tester) async {
      expect(await _readPage(tester, recoveryPathsPolicy), [
        'Balance card: Recovery in about 2 days 5 hours',
        'COLD STORAGE',
        'Keys A and B sign. Both recovery keys can spend once a coin has waited about 30 days. An emergency key can spend once a coin has waited about 183 days. Another key can spend once a coin has waited about 1 year.',
        'PRIMARY',
        'Key A and Key B',
        'Key A',
        '3442193e',
        'Key B',
        '5c1bd648',
        '[confirmed check] Spendable now',
        'RECOVERY',
        'Key C, Key D and a coin having waited 4\u00A0320 blocks',
        'Key C',
        'bef5a2f9',
        'Key D',
        'ee7ab90c',
        '4\u00A0320 blocks after the coin arrives ≈ 30 days',
        '[pending clock] 1 of 3 coins unlocked · next in 2 days 5 hours · 1 waiting for a block',
        'NEXT COIN',
        '319 blocks ≈ 2 days 5 hours',
        'Around [date]',
        '[bar 93%]',
        'EMERGENCY',
        'Key D and a coin having waited 26\u00A0280 blocks',
        'Key D',
        'ee7ab90c',
        '26\u00A0280 blocks after the coin arrives ≈ 183 days',
        '[neutral clock] 1 of 3 coins unlocked · next in 155 days · 1 waiting for a block',
        'NEXT COIN',
        '22\u00A0279 blocks ≈ 155 days',
        'Around [date]',
        '[bar 15%]',
        'RECOVERY 3',
        'Key C and a coin having waited 52\u00A0560 blocks',
        'Key C',
        'bef5a2f9',
        '52\u00A0560 blocks after the coin arrives ≈ 1 year',
        '[neutral clock] 1 of 3 coins unlocked · next in 337 days · 1 waiting for a block',
        'NEXT COIN',
        '48\u00A0559 blocks ≈ 337 days',
        'Around [date]',
        '[bar 8%]',
        'KEYS',
        'Key A  ·  3442193e',
        'xpub661M…GMcet8',
        'Key B  ·  5c1bd648',
        'xpub68Gm…vgGDnw',
        'Key C  ·  bef5a2f9',
        'xpub6ASu…puCkwQ',
        'Key D  ·  ee7ab90c',
        'xpub6D4B…6fcLW5',
        'DESCRIPTOR',
        'Policy',
      ]);
    });

    testWidgets('reads a relative lock while a coin waits', (tester) async {
      expect(await _readPage(tester, relativePolicy), [
        'Balance card: Recovery in about 296 days',
        'COLD STORAGE',
        'Key A signs. A recovery key can spend once a coin has waited about 1 year.',
        'PRIMARY',
        'Key A',
        'Key A',
        '3442193e',
        '[confirmed check] Spendable now',
        'RECOVERY',
        'Key B and a coin having waited 52\u00A0560 blocks',
        'Key B',
        '5c1bd648',
        '52\u00A0560 blocks after the coin arrives ≈ 1 year',
        '[neutral clock] 1 of 2 coins unlocked · next in 296 days',
        'NEXT COIN',
        '42\u00A0559 blocks ≈ 296 days',
        'Around [date]',
        '[bar 19%]',
        'KEYS',
        'Key A  ·  3442193e',
        'xpub661M…GMcet8',
        'Key B  ·  5c1bd648',
        'xpub68Gm…vgGDnw',
        'DESCRIPTOR',
        'Policy',
      ]);
    });

    testWidgets('reads a relative lock once every coin is past it', (
      tester,
    ) async {
      expect(await _readPage(tester, relativeOpenPolicy), [
        'Balance card: Recovery open',
        'COLD STORAGE',
        'Key A signs. A recovery key can spend once a coin has waited about 1 year.',
        'PRIMARY',
        'Key A',
        'Key A',
        '3442193e',
        '[confirmed check] Spendable now',
        'RECOVERY',
        'Key B and a coin having waited 52\u00A0560 blocks',
        'Key B',
        '5c1bd648',
        '52\u00A0560 blocks after the coin arrives ≈ 1 year',
        '[confirmed check] 2 of 2 coins unlocked',
        'KEYS',
        'Key A  ·  3442193e',
        'xpub661M…GMcet8',
        'Key B  ·  5c1bd648',
        'xpub68Gm…vgGDnw',
        'DESCRIPTOR',
        'Policy',
      ]);
    });

    testWidgets('reads absolute locks, a height and a date', (tester) async {
      expect(await _readPage(tester, absolutePolicy), [
        'Balance card: Recovery in about 10 days',
        'COLD STORAGE',
        'Key A signs. A recovery key can spend after block 801\u00A0432. An emergency key can spend after Mar 17, 2030.',
        'PRIMARY',
        'Key A',
        'Key A',
        '3442193e',
        '[confirmed check] Spendable now',
        'RECOVERY',
        'Key C and block 801\u00A0432 reached',
        'Key C',
        'bef5a2f9',
        'block 801\u00A0432 ≈ in 10 days',
        '[pending clock] In 1\u00A0432 blocks ≈ 10 days',
        'Around [date]',
        'EMERGENCY',
        'Key B and Mar 17, 2030 reached',
        'Key B',
        '5c1bd648',
        'after Mar 17, 2030 ≈ in 5 years',
        '[neutral clock] In 5 years',
        'Around [date]',
        "Time locks compare against this device's clock; the chain can lag by up to two hours.",
        'KEYS',
        'Key A  ·  3442193e',
        'xpub661M…GMcet8',
        'Key B  ·  5c1bd648',
        'xpub68Gm…vgGDnw',
        'Key C  ·  bef5a2f9',
        'xpub6ASu…puCkwQ',
        'DESCRIPTOR',
        'Policy',
      ]);
    });

    testWidgets('reads a multisig', (tester) async {
      expect(await _readPage(tester, multisigPolicy), [
        'Balance card: 2 of 3 keys',
        'COLD STORAGE',
        '2 of 3 keys sign.',
        'PRIMARY',
        'Any 2 of Key A, Key B, Key C',
        'Key A',
        '3442193e',
        'Key B',
        '5c1bd648',
        'Key C',
        'bef5a2f9',
        '[confirmed check] Spendable now',
        'KEYS',
        'Key A  ·  3442193e',
        'xpub661M…GMcet8',
        'Key B  ·  5c1bd648',
        'xpub68Gm…vgGDnw',
        'Key C  ·  bef5a2f9',
        'xpub6ASu…puCkwQ',
        'DESCRIPTOR',
        'Policy',
      ]);
    });
  });
}
