import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/receive.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';

Widget receiveApp(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const ReceiveScreen(walletId: 'w1'),
    ),
  );
}

void main() {
  testWidgets('skipping peeks the next index and returns to the first', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addresses: {
        'w1': const [AddressEntry(index: 4, address: 'tb1qfirst', used: false)],
      },
    );
    await tester.pumpWidget(receiveApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
    expect(find.text('tb1qfirst'), findsOneWidget);
    expect(find.text('First unused'), findsNothing);

    await tester.tap(find.text('Next address'));
    await tester.pumpAndSettle();

    // One step further down the derivation path, nothing retired.
    expect(find.text('UNUSED ADDRESS · INDEX 5'), findsOneWidget);
    expect(find.text('tb1qfirst1'), findsOneWidget);
    expect(bridge.receiveLookaheads.last, 1);

    await tester.tap(find.text('Next address'));
    await tester.pumpAndSettle();
    expect(find.text('UNUSED ADDRESS · INDEX 6'), findsOneWidget);

    await tester.tap(find.text('First unused'));
    await tester.pumpAndSettle();
    expect(find.text('NEXT UNUSED ADDRESS · INDEX 4'), findsOneWidget);
    expect(find.text('tb1qfirst'), findsOneWidget);
    expect(find.text('First unused'), findsNothing);
  });

  testWidgets('a single-address wallet shows its one address, no skip', (
    tester,
  ) async {
    final meta = makeMeta(
      name: 'Donation address',
      kind: const SingleAddressKind(address: 'bc1qwatched'),
    );
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addresses: {
        'w1': const [AddressEntry(index: 0, address: 'bc1qwatched', used: true)],
      },
    );
    await tester.pumpWidget(receiveApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('WATCHED ADDRESS'), findsOneWidget);
    expect(find.text('bc1qwatched'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Next address'), findsNothing);
    expect(find.text('First unused'), findsNothing);
    expect(find.byIcon(LucideIcons.skipForward), findsNothing);
    // A single watched address has no derivation path to show.
    expect(find.text('DERIVATION PATH'), findsNothing);
  });

  testWidgets('the derivation path shows when the core provides one', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addresses: {
        'w1': const [
          AddressEntry(
            index: 0,
            address: 'tb1qfirst',
            used: false,
            derivation: "m/84'/1'/0'/0/0",
          ),
        ],
      },
    );
    await tester.pumpWidget(receiveApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('DERIVATION PATH'), findsOneWidget);
    expect(find.text("m/84'/1'/0'/0/0"), findsOneWidget);
  });

  testWidgets('no derivation line when the core sends none', (tester) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addresses: {
        'w1': const [AddressEntry(index: 0, address: 'tb1qfirst', used: false)],
      },
    );
    await tester.pumpWidget(receiveApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('DERIVATION PATH'), findsNothing);
  });

  testWidgets('peeking past the gap limit raises the warning', (tester) async {
    final meta = makeMeta(gapLimit: 2);
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
    );
    await tester.pumpWidget(receiveApp(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next address'));
    await tester.pumpAndSettle();
    expect(find.textContaining('beyond the gap limit'), findsNothing);

    await tester.tap(find.text('Next address'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'This is 2 addresses past the next unused one — beyond the gap '
        'limit of 2, other wallet software may not detect funds received '
        'here.',
      ),
      findsOneWidget,
    );
    // The verify panel and the gap panel each carry the triangle.
    expect(find.byIcon(LucideIcons.triangleAlert), findsNWidgets(2));

    await tester.tap(find.text('First unused'));
    await tester.pumpAndSettle();
    expect(find.textContaining('beyond the gap limit'), findsNothing);
  });
}
