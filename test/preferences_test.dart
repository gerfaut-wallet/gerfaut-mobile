// The preferences both apps keep, as the screens hold them: the core
// stores them and decides what can be, the screens show it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';

import 'core_fixtures.dart';
import 'fakes.dart';

void main() {
  ProviderContainer screens(FakeBridge bridge) {
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    container.read(preferencesProvider.notifier).hydrate(bridge.preferences);
    return container;
  }

  test('the screens show what the vault answered', () {
    final bridge = FakeBridge()
      ..preferences = kPreferences.copyWith(
        unit: AmountUnit.sats,
        masked: true,
        fiatCurrency: const FiatCurrency('usd'),
        priceSource: PriceSource.coingecko,
      );
    final container = screens(bridge);
    expect(container.read(unitProvider), AmountUnit.sats);
    expect(container.read(maskedProvider), isTrue);
    expect(container.read(fiatCurrencyProvider), const FiatCurrency('usd'));
    expect(container.read(fiatSourceProvider), PriceSource.coingecko);
  });

  test('the pair the price is asked by is shown as the core kept it', () async {
    // mempool.space, the default, does not quote the rupee.
    final bridge = FakeBridge();
    final container = screens(bridge);
    expect(container.read(fiatSourceProvider), PriceSource.mempoolSpace);

    final setting = container
        .read(fiatCurrencyProvider.notifier)
        .set(const FiatCurrency('inr'));
    // Not before the vault answered.
    expect(container.read(fiatCurrencyProvider), const FiatCurrency('eur'));
    await setting;
    expect(container.read(fiatCurrencyProvider), const FiatCurrency('inr'));
    // Only the currency was asked for; the core moved the source.
    expect(bridge.preferencesChanges.single.toJson(), {'fiat_currency': 'inr'});
    expect(container.read(fiatSourceProvider), PriceSource.coingecko);
  });

  test('a pair the vault refuses leaves the screen as it was', () async {
    final bridge = FakeBridge()
      ..onSetPreferences = (_, _) =>
          throw const BridgeException('vault', 'disk full');
    final container = screens(bridge);
    await container
        .read(fiatSourceProvider.notifier)
        .set(PriceSource.coingecko);
    expect(container.read(fiatSourceProvider), PriceSource.mempoolSpace);
  });

  test(
    'the amounts hide at once, and stay hidden when the vault refuses',
    () async {
      final bridge = FakeBridge()
        ..onSetPreferences = (_, _) =>
            throw const BridgeException('vault', 'disk full');
      final container = screens(bridge);
      container.read(maskedProvider.notifier).toggle();
      expect(container.read(maskedProvider), isTrue);
      await pumpEventQueue();
      // Asked twice, then said: the widget and the notifications read
      // the vault, which still shows amounts.
      expect(bridge.preferencesChanges.map((change) => change.toJson()), [
        {'masked': true},
        {'masked': true},
      ]);
      expect(container.read(maskedProvider), isTrue);
      expect(container.read(maskUnsavedProvider), isTrue);
      expect(bridge.preferences.masked, isFalse);

      // Shown again, the amounts are where the vault has them: nothing
      // left to say.
      container.read(maskedProvider.notifier).toggle();
      await pumpEventQueue();
      expect(container.read(maskUnsavedProvider), isFalse);
    },
  );

  test('a mask the vault refuses once is asked again, and kept', () async {
    var refusals = 1;
    final bridge = FakeBridge()
      ..onSetPreferences = (stored, change) {
        if (refusals-- > 0) throw coreFailure('vault', 'disk full');
        return coreChange(stored, change);
      };
    final container = screens(bridge);
    container.read(maskedProvider.notifier).toggle();
    await pumpEventQueue();
    expect(bridge.preferencesChanges, hasLength(2));
    expect(bridge.preferences.masked, isTrue);
    expect(container.read(maskUnsavedProvider), isFalse);
  });

  test('a mask refused twice is written again from the screen', () async {
    var refusals = 2;
    final bridge = FakeBridge()
      ..onSetPreferences = (stored, change) {
        if (refusals-- > 0) throw coreFailure('vault', 'disk full');
        return coreChange(stored, change);
      };
    final container = screens(bridge);
    container.read(maskedProvider.notifier).toggle();
    await pumpEventQueue();
    expect(container.read(maskUnsavedProvider), isTrue);

    container.read(maskedProvider.notifier).retry();
    await pumpEventQueue();
    expect(bridge.preferences.masked, isTrue);
    expect(container.read(maskUnsavedProvider), isFalse);
    expect(container.read(maskedProvider), isTrue);
  });

  test('a mask refused once is not asked again over a newer one', () async {
    final gate = GatedBridge();
    final container = screens(gate);
    // Hidden, and refused twice: the note is up.
    container.read(maskedProvider.notifier).toggle();
    await pumpEventQueue();
    gate.refuse();
    await pumpEventQueue();
    gate.refuse();
    await pumpEventQueue();
    expect(container.read(maskUnsavedProvider), isTrue);

    // Shown, and refused once; hidden again before the vault answered.
    container.read(maskedProvider.notifier).toggle();
    await pumpEventQueue();
    container.read(maskedProvider.notifier).toggle();
    gate.refuse();
    await pumpEventQueue();
    gate.release();
    await pumpEventQueue();
    // Asked again after the mask, the shown balances would undo it in
    // the vault, which the widget and the notifications read.
    expect(gate.asked.skip(2).map((change) => change.toJson()), [
      {'masked': false},
      {'masked': true},
    ]);
    expect(gate.preferences.masked, isTrue);
    expect(container.read(maskedProvider), isTrue);
    expect(container.read(maskUnsavedProvider), isFalse);
  });

  test('changes are written one after the other, in order', () async {
    final gate = GatedBridge();
    final container = screens(gate);

    container.read(unitProvider.notifier).set(AmountUnit.sats);
    final source = container
        .read(fiatSourceProvider.notifier)
        .set(PriceSource.coingecko);
    await pumpEventQueue();
    // The second waits for the first to be answered.
    expect(gate.asked.map((change) => change.toJson()), [
      {'unit': 'sats'},
    ]);
    gate.release();
    await pumpEventQueue();
    expect(gate.asked.map((change) => change.toJson()), [
      {'unit': 'sats'},
      {'price_source': 'coingecko'},
    ]);
    gate.release();
    await source;
    expect(container.read(fiatSourceProvider), PriceSource.coingecko);
    expect(container.read(unitProvider), AmountUnit.sats);
    expect(gate.preferences.unit, AmountUnit.sats);
  });
}
