import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/addresses.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/status_pill.dart';

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

    // Usage: a pill each, same shape, never a bare word.
    expect(find.text('Used'), findsNWidgets(2));
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.byType(AddressStatePill), findsNWidgets(3));

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

  group('address state pills', () {
    /// Decoration of the pill carrying [label].
    BoxDecoration pill(WidgetTester tester, String label) {
      return tester
              .widget<Container>(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(Container),
                ).first,
              )
              .decoration!
          as BoxDecoration;
    }

    TextStyle pillText(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!;

    Widget themed(FakeBridge bridge, GerfautTokens tokens, Brightness mode) {
      return ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: themeFrom(tokens, mode),
          home: const AddressesScreen(walletId: 'w1'),
        ),
      );
    }

    FakeBridge bridgeWithBothStates() {
      final meta = makeMeta();
      return FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addressLists: {
          'w1': const AddressList(
            external: [
              AddressRow(
                index: 0,
                address: 'bc1qused',
                used: true,
                balanceSats: 0,
              ),
              AddressRow(
                index: 1,
                address: 'bc1qfresh',
                used: false,
                balanceSats: 0,
              ),
            ],
            internal: [],
          ),
        },
      );
    }

    testWidgets('both states are pills of the same shape', (tester) async {
      await tester.pumpWidget(addressesApp(bridgeWithBothStates()));
      await tester.pumpAndSettle();

      for (final label in ['Used', 'Fresh']) {
        final decoration = pill(tester, label);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(GerfautRadius.full),
        );
        expect(decoration.border!.top.width, 1);
        expect(pillText(tester, label).fontSize, 11);
        expect(pillText(tester, label).fontWeight, FontWeight.w500);
      }
    });

    testWidgets('used wears the alert role, fresh the primary one', (
      tester,
    ) async {
      await tester.pumpWidget(addressesApp(bridgeWithBothStates()));
      await tester.pumpAndSettle();

      final light = GerfautTokens.light;
      expect(pillText(tester, 'Used').color, light.alert);
      expect(pill(tester, 'Used').color, light.alertSurface);
      expect(
        pill(tester, 'Used').border!.top.color,
        light.alert.withValues(alpha: 0.25),
      );

      expect(pillText(tester, 'Fresh').color, light.primary);
      expect(pill(tester, 'Fresh').color, light.primary.withValues(alpha: 0.1));
      expect(
        pill(tester, 'Fresh').border!.top.color,
        light.primary.withValues(alpha: 0.25),
      );
    });

    testWidgets('the dark theme tints used, where the surface would not', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(bridgeWithBothStates(), GerfautTokens.dark, Brightness.dark),
      );
      await tester.pumpAndSettle();

      final dark = GerfautTokens.dark;
      // alertSurface is the card surface in the dark theme: a plain
      // tint would leave the pill invisible.
      expect(dark.alertSurface, dark.surface);
      expect(pillText(tester, 'Used').color, dark.alert);
      expect(pill(tester, 'Used').color, dark.alert.withValues(alpha: 0.1));
      expect(pillText(tester, 'Fresh').color, dark.primary);
      expect(pill(tester, 'Fresh').color, dark.primary.withValues(alpha: 0.1));
    });
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
