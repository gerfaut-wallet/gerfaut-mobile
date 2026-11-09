import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';

import 'fakes.dart';

/// A sync of every wallet held open until the test lets it end.
class _HeldSyncAll extends FakeBridge {
  _HeldSyncAll()
    : super(
        wallets: [
          makeMeta(),
          makeMeta(id: 'w2', name: 'Spending'),
        ],
      );

  final gate = Completer<void>();

  @override
  Future<SyncAllReport> syncAll([Network? network]) async {
    await gate.future;
    return super.syncAll(network);
  }
}

ProviderContainer _container(GerfautBridge bridge) {
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [bridgeProvider.overrideWithValue(bridge)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the sync of each wallet', () {
    test(
      'a wallet already in a sync of every wallet is not synced twice',
      () async {
        final bridge = _HeldSyncAll();
        final container = _container(bridge);
        final sync = container.read(syncProvider.notifier);

        final all = sync.syncAll(Network.mainnet);
        await pumpEventQueue();
        // The wallet's own refresh, asked while the sync of every wallet
        // still runs: that sync covers it.
        expect(await sync.syncWallet('w1'), isNull);
        expect(bridge.syncWalletCalls, 0);

        bridge.gate.complete();
        await all;
      },
    );
  });
}
