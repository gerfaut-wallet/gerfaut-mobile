import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/wallet_home.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/state.dart';

import 'core_fixtures.dart';
import 'fakes.dart';

/// A vault opened before, with two wallets: the app lands on them.
FakeBridge _returning({List<WalletMeta>? wallets}) {
  final shown = wallets ?? [makeMeta(), makeMeta(id: 'w2', name: 'Spending')];
  return FakeBridge(
    wallets: shown,
    snapshots: {for (final meta in shown) meta.id: makeSnapshot(meta: meta)},
    settings: const Settings(
      preferences: kPreferences,
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {'onboarding.seen': '1'},
    ),
  );
}

Widget _app(FakeBridge bridge) {
  return ProviderScope(
    retry: noRetry,
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      disguiseServiceProvider.overrideWithValue(FakeDisguise()),
    ],
    child: const GerfautApp(),
  );
}

ProviderContainer _container(GerfautBridge bridge) {
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [bridgeProvider.overrideWithValue(bridge)],
  );
  addTearDown(container.dispose);
  return container;
}

WalletSync _told(String walletId, CoreSyncState state) =>
    WalletSync(walletId: walletId, state: state);

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

/// A reading of where every wallet stands held open until the test
/// lets it answer.
class _HeldStates extends FakeBridge {
  _HeldStates() : super(wallets: [makeMeta()]);

  final gate = Completer<void>();

  @override
  Future<List<WalletSync>> walletSyncStates([Network? network]) async {
    await gate.future;
    return super.walletSyncStates(network);
  }
}

void main() {
  group('where the sync of each wallet stands', () {
    test("a sync the core says runs for one wallet is not another's", () async {
      final bridge = FakeBridge(
        wallets: [
          makeMeta(),
          makeMeta(id: 'w2', name: 'Spending'),
        ],
      );
      final container = _container(bridge);
      await container.read(syncProvider.notifier).listen();

      bridge.syncChangesController.add(_told('w2', const CoreSyncRunning()));
      await pumpEventQueue();

      final syncs = container.read(syncProvider);
      expect(syncs.isSyncing('w2'), isTrue);
      expect(syncs.isSyncing('w1'), isFalse);
      expect(syncs.syncingAny, isTrue);
      // Running from the core, w1 can still be synced on its own; w2
      // cannot, whoever started its sync.
      expect(
        await container.read(syncProvider.notifier).syncWallet('w2'),
        isNull,
      );
      expect(
        await container.read(syncProvider.notifier).syncWallet('w1'),
        isNotNull,
      );
      expect(bridge.syncWalletCalls, 1);

      bridge.syncChangesController.add(_told('w2', const CoreSyncIdle()));
      await pumpEventQueue();
      expect(container.read(syncProvider).syncingAny, isFalse);
    });

    testWidgets("the page of a wallet does not say another wallet's sync", (
      tester,
    ) async {
      final bridge = _returning();
      await tester.pumpWidget(_app(bridge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cold storage'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletHomeScreen), findsOneWidget);

      // The live watch syncs the other wallet.
      bridge.syncChangesController.add(_told('w2', const CoreSyncRunning()));
      await tester.pump();

      expect(find.textContaining('Syncing'), findsNothing);
      expect(find.text('Never synced'), findsOneWidget);

      // The same word about this wallet shows here.
      bridge.syncChangesController.add(_told('w1', const CoreSyncRunning()));
      await tester.pump();
      expect(find.text('Syncing…'), findsOneWidget);
    });

    testWidgets('a failure from before a restart shows on the wallet', (
      tester,
    ) async {
      // The core's own reference case: a wallet whose last sync failed,
      // as the vault keeps it across a restart.
      final failed = WalletSync.fromJson(
        jsonDecode(coreCaseJson('WalletSync', 'failed'))
            as Map<String, dynamic>,
      )!;
      final state = failed.state as CoreSyncFailed;
      final bridge = _returning(wallets: [makeMeta(id: failed.walletId)])
        ..syncStates = [failed];
      await tester.pumpWidget(_app(bridge));
      await tester.pumpAndSettle();
      expect(bridge.walletSyncStatesCalls, greaterThan(0));

      await tester.tap(find.text('Cold storage'));
      await tester.pumpAndSettle();

      expect(find.text('Sync failed'), findsOneWidget);
      expect(find.text(state.message), findsOneWidget);
      expect(find.text('Sync failed: nothing fetched yet.'), findsOneWidget);
    });

    test('the answer of a sync the core took over is not heard', () async {
      final bridge = FakeBridge(wallets: [makeMeta()])
        ..syncGate = Completer<void>()
        ..onSyncWallet = (_) =>
            throw const BridgeException('sync', 'connection refused');
      final container = _container(bridge);
      final sync = container.read(syncProvider.notifier);
      await sync.listen();

      final ours = sync.syncWallet('w1');
      await pumpEventQueue();
      expect(container.read(syncProvider).of('w1'), isA<WalletSyncing>());

      // The core says the wallet syncs, then that it stands idle: its
      // word replaced this app's ticket, and settled the wallet.
      bridge.syncChangesController
        ..add(_told('w1', const CoreSyncRunning()))
        ..add(_told('w1', const CoreSyncIdle()));
      await pumpEventQueue();
      expect(container.read(syncProvider).of('w1'), isA<WalletSyncIdle>());

      // The failure this app's own sync comes back with is stale: the
      // caller still hears it, the wallet does not show it.
      bridge.syncGate!.complete();
      await expectLater(ours, throwsA(isA<BridgeException>()));
      expect(container.read(syncProvider).of('w1'), isA<WalletSyncIdle>());
      expect(container.read(syncErrorsProvider), isEmpty);
    });

    test(
      "a sync the core says runs waits for the core's word to end",
      () async {
        final bridge = FakeBridge(wallets: [makeMeta()])
          ..syncGate = Completer<void>();
        final container = _container(bridge);
        final sync = container.read(syncProvider.notifier);
        await sync.listen();

        final ours = sync.syncWallet('w1');
        await pumpEventQueue();
        bridge.syncChangesController.add(_told('w1', const CoreSyncRunning()));
        await pumpEventQueue();
        bridge.syncGate!.complete();
        await ours;

        // The core still counts a sync of the wallet.
        expect(container.read(syncProvider).isSyncing('w1'), isTrue);
        bridge.syncChangesController.add(
          _told(
            'w1',
            const CoreSyncFailed(
              message: 'a proof did not hold',
              kind: 'false_proof',
              at: 1749999940,
            ),
          ),
        );
        await pumpEventQueue();
        // In the words a sync of every wallet would say it with.
        expect(container.read(syncErrorsProvider), {'w1': falseProofMessage});
      },
    );

    test(
      'a sync of every wallet lights the whole app, and no wallet id',
      () async {
        final bridge = _HeldSyncAll();
        final container = _container(bridge);

        final all = container
            .read(syncProvider.notifier)
            .syncAll(Network.mainnet);
        await pumpEventQueue();

        final syncs = container.read(syncProvider);
        expect(syncs.syncingAll, isNotNull);
        expect(syncs.syncingAny, isTrue);
        expect(syncs.wallets, isEmpty);
        expect(syncs.isSyncing('w1'), isTrue);
        expect(
          await container.read(syncProvider.notifier).syncAll(Network.mainnet),
          isNull,
        );

        bridge.gate.complete();
        await all;
        expect(container.read(syncProvider).syncingAny, isFalse);
        expect(container.read(syncProvider).syncingAll, isNull);
      },
    );

    test(
      'a failure kept from a sync stays shown while the next one runs',
      () async {
        final bridge = FakeBridge(wallets: [makeMeta()])
          ..onSyncWallet = (_) =>
              throw const BridgeException('sync', 'connection refused');
        final container = _container(bridge);
        final sync = container.read(syncProvider.notifier);
        await expectLater(sync.syncWallet('w1'), throwsA(anything));
        expect(container.read(syncErrorsProvider), {
          'w1': 'connection refused',
        });

        bridge
          ..onSyncWallet = null
          ..syncGate = Completer<void>();
        final again = sync.syncWallet('w1');
        await pumpEventQueue();
        expect(container.read(syncProvider).isSyncing('w1'), isTrue);
        expect(container.read(syncErrorsProvider), {
          'w1': 'connection refused',
        });

        bridge.syncGate!.complete();
        await again;
        expect(container.read(syncErrorsProvider), isEmpty);
      },
    );

    test('a reading older than a change leaves that wallet alone', () async {
      final bridge = _HeldStates()
        ..syncStates = [
          _told('w1', const CoreSyncFailed(message: 'refused', at: 1749999940)),
        ];
      final container = _container(bridge);
      final listening = container.read(syncProvider.notifier).listen();
      await pumpEventQueue();

      // The wallet syncs, and then succeeds, after the reading was
      // asked and before it answers.
      bridge.syncChangesController
        ..add(_told('w1', const CoreSyncRunning()))
        ..add(_told('w1', const CoreSyncIdle()));
      await pumpEventQueue();
      bridge.gate.complete();
      await listening;

      expect(container.read(syncProvider).of('w1'), isA<WalletSyncIdle>());
      expect(container.read(syncErrorsProvider), isEmpty);
    });
  });

  test('what the live watch says is heard only while no sync runs', () {
    var syncs = nextSyncs(
      const WalletSyncs(),
      const LiveSyncHeard('w1', 'timed out'),
    );
    syncs = nextSyncs(syncs, const CoreSyncStarted('w1'));
    // Late, from another channel: the sync that runs is not over.
    syncs = nextSyncs(syncs, const LiveSyncHeard('w1', null));
    expect(syncs.of('w1'), isA<WalletSyncing>());
    expect(syncs.failureOf('w1'), 'timed out');
    syncs = nextSyncs(syncs, const CoreSyncSettled('w1', null));
    syncs = nextSyncs(syncs, const LiveSyncHeard('w1', 'refused'));
    expect(syncs.failureOf('w1'), 'refused');
  });
}
