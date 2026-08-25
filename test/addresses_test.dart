import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/addresses.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';

import 'fakes.dart';

Widget addressesApp(FakeBridge bridge) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: const AddressesScreen(walletId: 'w1'),
    ),
  );
}

void main() {
  testWidgets('addresses list sections external and change keychains', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addressLists: {
        'w1': const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 150000,
            ),
            AddressRow(
              index: 1,
              address: 'bc1qsecond',
              used: false,
              balanceSats: 0,
            ),
          ],
          internal: [
            AddressRow(
              index: 0,
              address: 'bc1qchange',
              used: true,
              balanceSats: 0,
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(addressesApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('EXTERNAL'), findsOneWidget);
    expect(find.text('CHANGE'), findsOneWidget);
    expect(find.text('Receive addresses, in derivation order.'), findsOneWidget);
    expect(
      find.text('Internal addresses used by outgoing transactions.'),
      findsOneWidget,
    );

    // Usage: a pill for used, muted text for fresh.
    expect(find.text('Used'), findsNWidgets(2));
    expect(find.text('Fresh'), findsOneWidget);

    // Balances: an amount when coins sit there, a dash otherwise.
    expect(find.textContaining('0.00150000'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));

    // No cap note when nothing was truncated.
    expect(find.textContaining('Long keychains are capped'), findsNothing);
  });

  testWidgets('an empty change keychain says so', (tester) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addressLists: {
        'w1': const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: false,
              balanceSats: 0,
            ),
          ],
          internal: [],
        ),
      },
    );
    await tester.pumpWidget(addressesApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('No change addresses revealed yet.'), findsOneWidget);
  });

  testWidgets('a truncated keychain states the cap', (tester) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addressLists: {
        'w1': const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 0,
            ),
          ],
          internal: [],
          truncated: true,
        ),
      },
    );
    await tester.pumpWidget(addressesApp(bridge));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Long keychains are capped: only the first 200 addresses of each '
        'are listed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a single watched address shows one section', (tester) async {
    final meta = makeMeta(
      kind: const SingleAddressKind(address: 'bc1qwatched'),
    );
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addressLists: {
        'w1': const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qwatched',
              used: true,
              balanceSats: 5000,
            ),
          ],
          internal: [],
        ),
      },
    );
    await tester.pumpWidget(addressesApp(bridge));
    await tester.pumpAndSettle();

    expect(find.text('WATCHED ADDRESS'), findsOneWidget);
    expect(find.text('EXTERNAL'), findsNothing);
    expect(find.text('CHANGE'), findsNothing);
    expect(find.text('No change addresses revealed yet.'), findsNothing);
  });

  testWidgets('masking hides the balances on the address list', (
    tester,
  ) async {
    final meta = makeMeta();
    final bridge = FakeBridge(
      wallets: [meta],
      snapshots: {'w1': makeSnapshot(meta: meta)},
      addressLists: {
        'w1': const AddressList(
          external: [
            AddressRow(
              index: 0,
              address: 'bc1qfirst',
              used: true,
              balanceSats: 150000,
            ),
          ],
          internal: [],
        ),
      },
    );
    await tester.pumpWidget(addressesApp(bridge));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddressesScreen)),
      listen: false,
    );
    container.read(maskedProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(find.textContaining('0.00150000'), findsNothing);
    expect(find.text('•••••'), findsOneWidget);
  });
}
