// The one slot of the price credit: what it reads, and which screen it
// credits.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/window.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/price_credit.dart';

import 'fakes.dart';

void main() {
  late int asked;

  Widget credited(Widget home) => ProviderScope(
    overrides: [
      priceTableProvider.overrideWith((ref) {
        asked++;
        return Future.value(kPriceTable);
      }),
    ],
    child: creditedApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: home,
    ),
  );

  setUp(() => asked = 0);

  // The slot stands above the bootstrap: reading the table before the
  // vault is open would leave it failed for good.
  testWidgets('nothing marked, nothing asked of the core', (tester) async {
    await tester.pumpWidget(credited(const Text('no price here')));
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(find.text('Powered by CoinGecko'), findsNothing);
  });

  testWidgets('a figure CoinGecko priced is credited once, mempool.space '
      'never', (tester) async {
    await tester.pumpWidget(
      credited(
        const Column(
          children: [
            CreditMark(source: PriceSource.coingecko, child: Text('₹1')),
            CreditMark(source: PriceSource.coingecko, child: Text('₹2')),
            CreditMark(source: PriceSource.mempoolSpace, child: Text('€3')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Powered by CoinGecko'), findsOneWidget);
  });

  testWidgets('the lock takes the credit with it, in the same frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          priceTableProvider.overrideWith((ref) => Future.value(kPriceTable)),
          windowGuardProvider.overrideWithValue(FakeWindowGuard()),
        ],
        child: creditedApp(
          theme: themeFrom(GerfautTokens.light, Brightness.light),
          home: const CreditMark(
            source: PriceSource.coingecko,
            child: Text('₹1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Powered by CoinGecko'), findsOneWidget);

    final lock = ProviderScope.containerOf(tester.element(find.text('₹1')))
        .read(lockProvider.notifier);
    lock.syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));
    lock.lockNow();
    // One frame, and the mark still there: the credit is already gone.
    await tester.pump();
    expect(find.text('₹1'), findsOneWidget);
    expect(find.text('Powered by CoinGecko'), findsNothing);
  });

  testWidgets('only the screen on top is credited', (tester) async {
    await tester.pumpWidget(
      credited(
        Builder(
          builder: (context) => Column(
            children: [
              const CreditMark(
                source: PriceSource.coingecko,
                child: Text('₹1'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('no price')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Powered by CoinGecko'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Powered by CoinGecko'), findsNothing);

    Navigator.of(tester.element(find.text('no price'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Powered by CoinGecko'), findsOneWidget);
  });
}
