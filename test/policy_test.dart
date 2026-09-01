import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/policy_text.dart';

import 'policy_fixtures.dart';

PolicySnapshot _snapshot(Map<String, dynamic> json) =>
    PolicySnapshot.fromJson(json);

/// A time lock at noon UTC on 17 March 2030, still far ahead of the
/// fixture clock.
const int _noonMarch2030 = 1899979200;

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

  group('describePolicy', () {
    test('says the policy in a sentence or two', () {
      expect(
        describePolicy(_snapshot(multisigPolicyJson())),
        '2 of 3 keys sign.',
      );
      expect(
        describePolicy(_snapshot(lianaPolicyJson())),
        'Key A signs. '
        'A recovery key can spend once a coin has waited about 1 year.',
      );
      expect(
        describePolicy(_snapshot(singleKeyPolicyJson())),
        'One key signs. Any coin is spendable now.',
      );
      expect(
        describePolicy(_snapshot(addressPolicyJson())),
        'An address has no policy Gerfaut can read.',
      );
      // The only path waits: its lock is part of the sentence.
      expect(
        describePolicy(_snapshot(heightLockedPolicyJson())),
        'Key A signs after block 801 432.',
      );
    });
  });

  group('policyDigest', () {
    test('fits the balance card', () {
      expect(policyDigest(_snapshot(multisigPolicyJson())), '2 of 3 keys');
      expect(policyDigest(_snapshot(singleKeyPolicyJson())), 'Single key');
      expect(policyDigest(_snapshot(addressPolicyJson())), 'Watched address');
      expect(
        policyDigest(_snapshot(lianaPolicyJson())),
        'Recovery in about 142 days',
      );
      expect(
        policyDigest(_snapshot(lianaPolicyJson(locked: 0, unlocked: 1))),
        'Recovery open',
      );
      expect(
        policyDigest(_snapshot(lianaPolicyJson(locked: 0, waiting: 1))),
        'Recovery waiting for a block',
      );
      expect(
        policyDigest(_snapshot(heightLockedPolicyJson())),
        'Spendable in about 10 days',
      );
    });
  });

  group('describeCondition', () {
    test('a flat threshold reads as one line', () {
      final multisig = _snapshot(multisigPolicyJson());
      final line = describeCondition(
        multisig.branches.single.condition,
        multisig,
      );
      expect(line.text, 'Any 2 of Key A, Key B, Key C');
      expect(line.children, isEmpty);

      final liana = _snapshot(lianaPolicyJson());
      expect(
        describeCondition(liana.branches[1].condition, liana).text,
        'Key B and a coin having waited 52 560 blocks',
      );
    });

    test('a nested threshold is a heading over one line per part', () {
      final liana = _snapshot(lianaPolicyJson());
      const condition = ThreshCondition(
        k: 1,
        n: 2,
        items: [
          KeyCondition(keyId: 'k0'),
          ThreshCondition(
            k: 2,
            n: 2,
            items: [
              KeyCondition(keyId: 'k1'),
              OlderCondition(lock: BlocksLock(blocks: 144)),
            ],
          ),
        ],
      );
      final line = describeCondition(condition, liana);
      expect(line.text, 'Any of:');
      expect(line.children.map((c) => c.text), [
        'Key A',
        'Key B and a coin having waited 144 blocks',
      ]);
    });
  });

  group('describeTimelock', () {
    test('words each kind of lock with its estimate', () {
      final liana = _snapshot(lianaPolicyJson());
      expect(
        describeTimelock(liana.branches[1].timelocks.single),
        '52 560 blocks after the coin arrives ≈ about 1 year',
      );
      final height = _snapshot(heightLockedPolicyJson());
      expect(
        describeTimelock(height.branches.single.timelocks.single),
        'block 801 432 ≈ in about 10 days',
      );
      expect(
        describeTimelock(
          const PolicyTimelock(
            lock: AbsoluteTimelock(lock: HeightLock(height: 800000)),
            required: true,
            state: UnlockedLock(),
          ),
        ),
        'block 800 000 · passed',
      );
      expect(
        describeTimelock(
          PolicyTimelock(
            lock: const AbsoluteTimelock(lock: TimeLock(unix: _noonMarch2030)),
            required: true,
            state: LockedLock(
              remaining: Remaining(
                remainingBlocks: null,
                remainingSeconds: _noonMarch2030 - fixtureNow,
                unlocksAtUnix: _noonMarch2030,
              ),
            ),
          ),
        ),
        'after Mar 17, 2030 ≈ in about 5 years',
      );
      expect(
        describeTimelock(
          const PolicyTimelock(
            lock: RelativeTimelock(lock: BlocksLock(blocks: 100)),
            required: false,
            state: NoCoinsLock(blocks: 100, seconds: null),
          ),
        ),
        '100 blocks after the coin arrives ≈ about 17 hours (optional)',
      );
      expect(
        describeTimelock(
          const PolicyTimelock(
            lock: RelativeTimelock(lock: SecondsLock(seconds: 51200)),
            required: true,
            state: NoCoinsLock(blocks: null, seconds: 51200),
          ),
        ),
        'about 14 hours after the coin arrives',
      );
    });
  });

  group('describeBranchState', () {
    PolicyBranch recovery(Map<String, dynamic> json) =>
        _snapshot(json).branches[1];

    test('a lone coin gets its own countdown and progress', () {
      final far = describeBranchState(recovery(lianaPolicyJson()));
      expect(far.tone, StateTone.far);
      expect(far.label, 'In 20 440 blocks ≈ about 142 days');
      expect(far.date, isNotNull);
      expect(far.progress, closeTo((52560 - 20440) / 52560, 0.001));

      final soon = describeBranchState(
        recovery(lianaPolicyJson(remainingBlocks: 1432)),
      );
      expect(soon.tone, StateTone.soon);
      expect(soon.label, 'In 1 432 blocks ≈ about 10 days');

      expect(
        describeBranchState(recovery(lianaPolicyJson(locked: 0, unlocked: 1))),
        isA<BranchStatus>()
            .having((s) => s.tone, 'tone', StateTone.open)
            .having((s) => s.label, 'label', 'Spendable now'),
      );
      expect(
        describeBranchState(recovery(lianaPolicyJson(locked: 0, waiting: 1))),
        isA<BranchStatus>()
            .having((s) => s.tone, 'tone', StateTone.idle)
            .having((s) => s.label, 'label', 'Waiting for a block'),
      );
    });

    test('several coins are counted, the nearest one timed', () {
      final status = describeBranchState(
        recovery(
          lianaPolicyJson(
            unlocked: 3,
            locked: 1,
            waiting: 2,
            remainingBlocks: 1728,
          ),
        ),
      );
      expect(status.tone, StateTone.soon);
      expect(
        status.label,
        '3 of 6 coins unlocked · next in about 12 days · 2 waiting for a block',
      );
      expect(status.progress, closeTo((52560 - 1728) / 52560, 0.001));

      final open = describeBranchState(
        recovery(lianaPolicyJson(unlocked: 2, locked: 0)),
      );
      expect(open.tone, StateTone.open);
      expect(open.label, '2 of 2 coins unlocked');
      expect(open.progress, isNull);
    });

    test('an absolute lock colours only within thirty days', () {
      final soon = describeBranchState(
        _snapshot(heightLockedPolicyJson()).branches.single,
      );
      expect(soon.tone, StateTone.soon);
      expect(soon.label, 'In 1 432 blocks ≈ about 10 days');
      expect(soon.progress, isNull, reason: 'no coin to count from');

      final far = describeBranchState(
        _snapshot(heightLockedPolicyJson(remaining: 20000)).branches.single,
      );
      expect(far.tone, StateTone.far);
      expect(far.label, 'In 20 000 blocks ≈ about 139 days');
    });

    test('states without a countdown have their own words', () {
      PolicyBranch withState(BranchState state) => PolicyBranch(
        id: 'b1',
        role: BranchRole.recovery,
        label: 'Recovery',
        summary: '',
        condition: const KeyCondition(keyId: 'k1'),
        timelocks: const [],
        state: state,
        spendableNow: state is SpendableNow,
      );
      expect(
        describeBranchState(withState(const SpendableNow())).label,
        'Spendable now',
      );
      expect(
        describeBranchState(withState(const NoCoinsBranch())).label,
        'No coins yet',
      );
      expect(
        describeBranchState(withState(const NeedsPreimage())).tone,
        StateTone.secret,
      );
    });
  });
}
