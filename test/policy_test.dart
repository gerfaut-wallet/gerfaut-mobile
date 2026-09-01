import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/models.dart';

import 'policy_fixtures.dart';

void main() {
  group('PolicySnapshot.fromJson', () {
    test('reads a Liana-style policy down to the coin count', () {
      final snapshot = PolicySnapshot.fromJson(
        jsonDecode(jsonEncode(lianaPolicyJson())) as Map<String, dynamic>,
      );

      expect(snapshot.kind, PolicyKind.miniscript);
      expect(snapshot.script, ScriptKind.witnessScript);
      expect(snapshot.policy, 'or(pk(Key A),and(pk(Key B),older(52560)))');
      expect(snapshot.tipHeight, fixtureTip);
      expect(snapshot.computedAt, fixtureNow);
      expect(snapshot.timeBasis, TimeBasis.wallClock);
      expect(snapshot.coins, 1);
      expect(snapshot.hasTimelocks, isTrue);
      expect(snapshot.hasTimeBasedLocks, isFalse, reason: 'a block lock');

      expect(snapshot.keys, hasLength(2));
      final keyB = snapshot.keys[1];
      expect(keyB.id, 'k1');
      expect(keyB.label, 'Key B');
      expect(keyB.fingerprint, 'e5f60718');
      expect(keyB.originPath, "m/48'/0'/0'/2'");
      expect(keyB.keyShort, 'xpubKeyB…BBBBBB');
      expect(snapshot.keyById('k1'), same(keyB));
      expect(snapshot.keyById('k9'), isNull);

      final [primary, recovery] = snapshot.branches;
      expect(primary.role, BranchRole.primary);
      expect(primary.label, 'Primary');
      expect(primary.condition, isA<KeyCondition>());
      expect(primary.timelocks, isEmpty);
      expect(primary.state, isA<SpendableNow>());
      expect(primary.spendableNow, isTrue);

      expect(recovery.role, BranchRole.recovery);
      expect(recovery.summary, 'Key B, once a coin has waited 52,560 blocks');
      final condition = recovery.condition as ThreshCondition;
      expect((condition.k, condition.n), (2, 2));
      expect((condition.items[0] as KeyCondition).keyId, 'k1');
      final older = condition.items[1] as OlderCondition;
      expect((older.lock as BlocksLock).blocks, yearInBlocks);

      final lock = recovery.timelocks.single;
      expect(lock.required, isTrue);
      final ref = lock.lock as RelativeTimelock;
      expect((ref.lock as BlocksLock).blocks, yearInBlocks);
      expect(ref.isTimeBased, isFalse);
      final lockState = lock.state as PerCoinLock;
      expect(
        (lockState.unlocked, lockState.waiting, lockState.locked),
        (0, 0, 1),
      );
      expect(lockState.next?.remainingBlocks, 20440);

      final state = recovery.state as PerCoinBranch;
      expect(state.total, 1);
      expect(state.next?.remainingSeconds, 20440 * 600);
      expect(state.next?.unlocksAtUnix, fixtureNow + 20440 * 600);
      expect(recovery.spendableNow, isFalse);
    });

    test('reads an absolute lock and its countdown', () {
      final snapshot = PolicySnapshot.fromJson(heightLockedPolicyJson());
      final branch = snapshot.branches.single;
      final state = branch.state as LockedBranch;
      expect(state.until.remainingBlocks, 1432);
      expect(state.until.remainingSeconds, 1432 * 600);
      final lock = branch.timelocks.single;
      final ref = lock.lock as AbsoluteTimelock;
      expect((ref.lock as HeightLock).height, fixtureTip + 1432);
      expect((lock.state as LockedLock).remaining.remainingBlocks, 1432);
      final condition = branch.condition as ThreshCondition;
      expect(condition.items[1], isA<AfterCondition>());
    });

    test('reads the other lock states and conditions', () {
      expect(LockState.fromJson({'kind': 'unlocked'}), isA<UnlockedLock>());
      final noCoins = LockState.fromJson({
        'kind': 'no_coins',
        'blocks': 100,
        'seconds': null,
      }) as NoCoinsLock;
      expect((noCoins.blocks, noCoins.seconds), (100, null));
      expect(BranchState.fromJson({'kind': 'no_coins'}), isA<NoCoinsBranch>());
      expect(
        BranchState.fromJson({'kind': 'needs_preimage'}),
        isA<NeedsPreimage>(),
      );
      final preimage = PolicyCondition.fromJson({
        'kind': 'preimage',
        'hash': 'sha256',
      }) as PreimageCondition;
      expect(preimage.hash, 'sha256');
      final time = TimelockRef.fromJson({
        'kind': 'absolute',
        'lock': {'kind': 'time', 'unix': 1900000000},
      });
      expect(time.isTimeBased, isTrue);
      final seconds = TimelockRef.fromJson({
        'kind': 'relative',
        'lock': {'kind': 'seconds', 'seconds': 51200},
      });
      expect(seconds.isTimeBased, isTrue);
      expect(
        ((seconds as RelativeTimelock).lock as SecondsLock).seconds,
        51200,
      );
    });

    test('a watched address has no keys and no branches', () {
      final snapshot = PolicySnapshot.fromJson(addressPolicyJson());
      expect(snapshot.kind, PolicyKind.address);
      expect(snapshot.script, ScriptKind.segwit);
      expect(snapshot.policy, 'address');
      expect(snapshot.descriptor, startsWith('tb1q'));
      expect(snapshot.keys, isEmpty);
      expect(snapshot.branches, isEmpty);
      expect(snapshot.hasTimelocks, isFalse);
    });

    test('a variant this build does not know fails loudly', () {
      expect(
        () => PolicyCondition.fromJson({'kind': 'ripemd', 'hash': 'x'}),
        throwsFormatException,
      );
      expect(
        () => BranchState.fromJson({'kind': 'frozen'}),
        throwsFormatException,
      );
      expect(() => BranchRole.fromId('backup'), throwsStateError);
      expect(() => PolicyKind.fromId('taproot_tree'), throwsStateError);
    });
  });
}
