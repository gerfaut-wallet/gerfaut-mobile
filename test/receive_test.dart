import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/receive.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
import 'package:gerfaut/widgets/status_pill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fakes.dart';

Widget receiveApp(
  FakeBridge bridge, {
  GerfautTokens? tokens,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
    child: MaterialApp(
      theme: themeFrom(tokens ?? GerfautTokens.light, brightness),
      home: const ReceiveScreen(walletId: 'w1'),
    ),
  );
}

/// A surface tall enough to build the whole page at once.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A bridge with one wallet and the given audit list.
FakeBridge bridgeWith(AddressList list, {WalletMeta? meta}) {
  final wallet = meta ?? makeMeta();
  return FakeBridge(
    wallets: [wallet],
    snapshots: {'w1': makeSnapshot(meta: wallet)},
    addressLists: {'w1': list},
  );
}

AddressRow row(int index, {bool used = false, int balance = 0}) => AddressRow(
  index: index,
  address: 'bc1qaddress$index',
  used: used,
  balanceSats: balance,
);

void main() {
  group('the address on offer', () {
    testWidgets('skipping peeks the next index and returns to the first', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
        addresses: {
          'w1': const [
            AddressEntry(index: 4, address: 'tb1qfirst', used: false),
          ],
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
      // One past the address on display, to know whether there is a next.
      expect(bridge.receiveLookaheads.last, 2);

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
      useTallSurface(tester);
      final meta = makeMeta(
        name: 'Donation address',
        kind: const SingleAddressKind(address: 'bc1qwatched'),
      );
      final bridge = bridgeWith(
        const AddressList(
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
        meta: meta,
      );
      bridge.addresses['w1'] = const [
        AddressEntry(index: 0, address: 'bc1qwatched', used: true),
      ];
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // The label above the address and the card title share the words.
      expect(find.text('WATCHED ADDRESS'), findsNWidgets(2));
      // Once in full above, once as the card's chip.
      expect(find.text('bc1qwatched'), findsNWidgets(2));
      expect(find.text('Copy address'), findsOneWidget);
      expect(find.text('Next address'), findsNothing);
      expect(find.text('First unused'), findsNothing);
      expect(find.byIcon(LucideIcons.skipForward), findsNothing);
      // A single watched address has no derivation path to show.
      expect(find.text('DERIVATION PATH'), findsNothing);
      // One card, no keychain vocabulary.
      expect(find.text('The one address this wallet watches.'), findsOneWidget);
      expect(find.text('EXTERNAL'), findsNothing);
      expect(find.text('CHANGE'), findsNothing);
      expect(find.text('No change addresses revealed yet.'), findsNothing);
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
          'w1': const [
            AddressEntry(index: 0, address: 'tb1qfirst', used: false),
          ],
        },
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('DERIVATION PATH'), findsNothing);
    });

    testWidgets('peeking past the gap limit raises the warning', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 2);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beyond the gap limit'), findsNothing);

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This is 2 addresses past the next unused one. Beyond the gap '
          'limit of 2, other wallet software may not detect funds received '
          'here.',
        ),
        findsOneWidget,
      );
      // Two panels, two tones, and the glyph says which is which: the
      // triangle is the verify warning, which is about funds; the gap
      // note only states a convention, so it carries the info glyph.
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
      expect(
        find.text(
          'Verify this address on your signing device before sharing it.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beyond the gap limit'), findsNothing);
    });

    testWidgets('an address a payment reached is skipped, and counted', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 3);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      )..paidAhead['w1'] = {1, 2};
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next address'));
      await tester.pumpAndSettle();
      // Indexes 1 and 2 were paid: the next on offer is 3, three past
      // the next unused on the derivation path, which is what the gap
      // limit counts.
      expect(find.text('UNUSED ADDRESS · INDEX 3'), findsOneWidget);
      expect(
        find.textContaining('This is 3 addresses past the next unused one.'),
        findsOneWidget,
      );
    });

    testWidgets('skipping stops at the most the core offers', (tester) async {
      useTallSurface(tester);
      final meta = makeMeta(gapLimit: 500);
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      for (var i = 0; i < maxReceivePeek; i++) {
        await tester.tap(find.text('Next address'));
        await tester.pumpAndSettle();
      }
      expect(find.text('UNUSED ADDRESS · INDEX 200'), findsOneWidget);
      expect(bridge.receiveLookaheads.every((n) => n <= 200), isTrue);
      final next = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Next address'),
      );
      expect(next.onPressed, isNull);
      expect(
        find.text(
          'Gerfaut offers at most 200 addresses past the next unused one.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('First unused'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT UNUSED ADDRESS · INDEX 0'), findsOneWidget);
    });

    testWidgets('a descriptor without a wildcard offers no next address', (
      tester,
    ) async {
      useTallSurface(tester);
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      )..withoutWildcard.add('w1');
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('NEXT UNUSED ADDRESS · INDEX 0'), findsOneWidget);
      expect(find.text('Next address'), findsNothing);
    });

    testWidgets('the small QR code opens large and closes on a tap', (
      tester,
    ) async {
      final meta = makeMeta();
      final bridge = FakeBridge(
        wallets: [meta],
        snapshots: {'w1': makeSnapshot(meta: meta)},
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // One code on the page, at its compact size.
      expect(find.byType(QrImageView), findsOneWidget);
      final small = tester.getSize(find.byType(QrImageView));
      expect(small.width, lessThanOrEqualTo(140));

      await tester.tap(find.byType(QrImageView));
      await tester.pumpAndSettle();

      // The dialog draws a second, larger one on a white card.
      expect(find.byType(QrImageView), findsNWidgets(2));
      expect(find.text('Tap anywhere to close'), findsOneWidget);
      final large = tester.getSize(find.byType(QrImageView).last);
      expect(large.width, greaterThan(300));
      final card = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(QrImageView).last,
              matching: find.byType(Container),
            )
            .first,
      );
      expect((card.decoration! as BoxDecoration).color, GerfautQr.background);

      await tester.tap(find.text('Tap anywhere to close'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);

      // Escape closes it as well.
      await tester.tap(find.byType(QrImageView));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  group('the revealed addresses', () {
    testWidgets('external and change keychains sit in their own cards', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
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
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('EXTERNAL'), findsOneWidget);
      expect(find.text('CHANGE'), findsOneWidget);
      expect(
        find.text('Receive addresses, in derivation order.'),
        findsOneWidget,
      );
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

      // Short keychains have nothing to unfold; nothing was truncated.
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.textContaining('Long keychains are capped'), findsNothing);
    });

    testWidgets('a long keychain shows five rows, then all of them', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        AddressList(
          external: [for (var i = 0; i < 12; i++) row(i, used: i < 8)],
          internal: [for (var i = 0; i < 7; i++) row(i, used: true)],
        ),
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      // Five per card, the counts in the headers.
      expect(find.byType(AddressStatePill), findsNWidgets(10));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Show all 12'), findsOneWidget);
      expect(find.text('Show all 7'), findsOneWidget);

      // Unfolding one card leaves the other folded.
      await tester.tap(find.text('Show all 12'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressStatePill), findsNWidgets(17));
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show all 7'), findsOneWidget);
      expect(find.text('Fresh'), findsNWidgets(4));

      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressStatePill), findsNWidgets(10));
      expect(find.text('Show all 12'), findsOneWidget);
    });

    testWidgets('an empty change keychain says so', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
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
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(find.text('No change addresses revealed yet.'), findsOneWidget);
    });

    testWidgets('a truncated keychain states the cap', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
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
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Long keychains are capped: only the first 200 addresses of each '
          'are listed.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('masking hides the balances on the cards', (tester) async {
      useTallSurface(tester);
      final bridge = bridgeWith(
        const AddressList(
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
      );
      await tester.pumpWidget(receiveApp(bridge));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveScreen)),
        listen: false,
      );
      container.read(maskedProvider.notifier).toggle();
      await tester.pumpAndSettle();

      expect(find.textContaining('0.00150000'), findsNothing);
      expect(find.text('•••••'), findsOneWidget);
    });
  });

  group('address state pills', () {
    /// Decoration of the pill carrying [label].
    BoxDecoration pill(WidgetTester tester, String label) {
      return tester
              .widget<Container>(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;
    }

    TextStyle pillText(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!;

    FakeBridge bridgeWithBothStates() {
      return bridgeWith(
        const AddressList(
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
      );
    }

    testWidgets('both states are pills of the same shape', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(receiveApp(bridgeWithBothStates()));
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
      useTallSurface(tester);
      await tester.pumpWidget(receiveApp(bridgeWithBothStates()));
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
      useTallSurface(tester);
      await tester.pumpWidget(
        receiveApp(
          bridgeWithBothStates(),
          tokens: GerfautTokens.dark,
          brightness: Brightness.dark,
        ),
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
}
