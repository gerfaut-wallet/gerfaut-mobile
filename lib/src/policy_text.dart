// The words of a policy: the sentence at the top of the page and the
// short digest on the balance card, a branch condition as a tree of
// phrases, one line per timelock, and where each branch stands. Pure
// functions over the core's snapshot, so every wording is tested
// without a widget.

import 'format.dart';
import 'models.dart';

/// Seconds a block takes on average; the basis of every estimate here,
/// the same as the core's.
const int blockSeconds = 600;

/// A lock with at most this long to go is close enough to colour: the
/// design system's threshold for the amber state.
const int soonThresholdSeconds = 30 * 86400;

/// Seconds left before a countdown ends, or its block count converted
/// when the core gave no time figure. Null when it gave neither.
int? secondsLeft(Remaining remaining) {
  final seconds = remaining.remainingSeconds;
  if (seconds != null) return seconds;
  final blocks = remaining.remainingBlocks;
  return blocks == null ? null : blocks * blockSeconds;
}

// --- the policy in a sentence -------------------------------------------

/// What the policy says, in one or two sentences: "2 of 3 keys sign.",
/// "Key A signs. A recovery key can spend once a coin has waited about
/// 1 year."
String describePolicy(PolicySnapshot snapshot) {
  switch (snapshot.kind) {
    case PolicyKind.address:
      return 'An address has no policy Gerfaut can read.';
    case PolicyKind.singleKey:
      return 'One key signs. Any coin is spendable now.';
    case PolicyKind.multisig:
      final condition = snapshot.branches.firstOrNull?.condition;
      if (condition is ThreshCondition) {
        if (condition.k == condition.n) return 'All ${condition.n} keys sign.';
        return '${condition.k} of ${condition.n} keys sign.';
      }
      return 'One key signs. Any coin is spendable now.';
    case PolicyKind.miniscript:
      final primaries = snapshot.branches
          .where((b) => b.role == BranchRole.primary)
          .toList();
      final others = snapshot.branches
          .where((b) => b.role != BranchRole.primary)
          .toList();
      final sentences = <String>[
        if (primaries.isNotEmpty) _primarySentence(primaries, snapshot),
        for (final branch in others) _pathSentence(branch, snapshot),
      ];
      return sentences.join(' ');
  }
}

/// "Key A signs.", "Any 2 of 3 keys sign.", "Key A or Key C signs.",
/// "Key A signs after block 801 432."
String _primarySentence(List<PolicyBranch> branches, PolicySnapshot snapshot) {
  final subjects = <_Subject>[];
  var clause = '';
  for (final branch in branches) {
    final subject = _subjectOf(branch.condition, snapshot);
    if (subject != null) subjects.add(subject);
    // Only the case where every path waits leaves a lock on a primary
    // branch; there is then one primary, and its lock is worth a word.
    if (clause.isEmpty) clause = _lockClause(branch);
  }
  if (subjects.isEmpty) return 'No key signs.';
  final last = subjects.last;
  final text = subjects.map((s) => s.text).join(' or ');
  return '$text ${last.plural ? 'sign' : 'signs'}$clause.';
}

/// "A recovery key can spend once a coin has waited about 1 year.",
/// "Any 2 of 3 emergency keys can spend after block 900 000.", "Another
/// path needs a secret to spend."
String _pathSentence(PolicyBranch branch, PolicySnapshot snapshot) {
  final subject = _pathSubject(branch);
  final clause = _lockClause(branch);
  if (branch.state is NeedsPreimage) {
    return '$subject needs a secret to spend$clause.';
  }
  return '$subject can spend$clause.';
}

/// The keys of a path, named by the path's role: "A recovery key",
/// "Both emergency keys", "Any 2 of 3 recovery keys", "Another path".
String _pathSubject(PolicyBranch branch) {
  final (k, n) = _keyShape(branch.condition);
  final role = switch (branch.role) {
    BranchRole.recovery => 'recovery',
    BranchRole.emergency => 'emergency',
    BranchRole.primary => 'primary',
    BranchRole.other => 'other',
  };
  if (n == 0) return 'Another path';
  if (n == 1) {
    return branch.role == BranchRole.other
        ? 'Another key'
        : '${role == 'emergency' ? 'An' : 'A'} $role key';
  }
  if (k == n) return n == 2 ? 'Both $role keys' : 'All $n $role keys';
  return 'Any $k of $n $role keys';
}

/// How many keys a branch needs out of how many, read off the keys at
/// the top of its condition: `(1, 1)` for a lone key, `(2, 3)` for a
/// threshold of three keys, `(0, 0)` when no key is involved.
(int, int) _keyShape(PolicyCondition condition) {
  switch (condition) {
    case KeyCondition():
      return (1, 1);
    case ThreshCondition(:final k, :final n, :final items):
      final keys = items.whereType<KeyCondition>().length;
      if (keys == items.length) return (k, n);
      if (k == n) {
        // An "and": the keys sign, the rest are locks or a hash. A
        // nested threshold of keys inside it is the shape that counts.
        for (final item in items) {
          if (item is ThreshCondition) {
            final shape = _keyShape(item);
            if (shape.$2 > 0) return shape;
          }
        }
        return (keys, keys);
      }
      return (k, n);
    case AfterCondition() || OlderCondition() || PreimageCondition():
      return (0, 0);
  }
}

/// " once a coin has waited about 1 year", " after block 801 432",
/// " after Mar 17, 2030 and once a coin has waited about 14 hours".
/// Empty when nothing required holds the branch back.
String _lockClause(PolicyBranch branch) {
  final clauses = <String>[
    for (final lock in branch.timelocks)
      if (lock.required)
        switch (lock.lock) {
          RelativeTimelock(lock: BlocksLock(:final blocks)) =>
            'once a coin has waited ${formatDuration(blocks * blockSeconds)}',
          RelativeTimelock(lock: SecondsLock(:final seconds)) =>
            'once a coin has waited ${formatDuration(seconds)}',
          AbsoluteTimelock(lock: HeightLock(:final height)) =>
            'after block ${groupThousands('$height')}',
          AbsoluteTimelock(lock: TimeLock(:final unix)) =>
            'after ${formatDate(unix)}',
        },
  ];
  return clauses.isEmpty ? '' : ' ${_joinAnd(clauses)}';
}

class _Subject {
  const _Subject(this.text, {required this.plural});

  final String text;
  final bool plural;
}

/// Who signs on a branch: "Key A", "Keys A and B", "Any 2 of 3 keys".
/// Null when the condition names no key.
_Subject? _subjectOf(PolicyCondition condition, PolicySnapshot snapshot) {
  switch (condition) {
    case KeyCondition(:final keyId):
      return _Subject(_keyLabel(keyId, snapshot), plural: false);
    case ThreshCondition(:final k, :final n, :final items):
      final keys = items.whereType<KeyCondition>().toList();
      if (keys.length == items.length) {
        if (k == n) return _keyList(keys, snapshot);
        return _Subject(
          k == 1 ? 'Any of $n keys' : 'Any $k of $n keys',
          plural: true,
        );
      }
      if (k == n) {
        final parts = <_Subject>[
          if (keys.isNotEmpty) _keyList(keys, snapshot),
          for (final item in items)
            if (item is ThreshCondition) ?_subjectOf(item, snapshot),
        ];
        if (parts.isEmpty) return null;
        if (parts.length == 1) return parts.single;
        return _Subject(
          _joinAnd([for (final part in parts) part.text]),
          plural: true,
        );
      }
      return _Subject(
        'Any $k of: ${items.map((i) => _noun(i, snapshot)).join(', ')}',
        plural: true,
      );
    case AfterCondition() || OlderCondition() || PreimageCondition():
      return null;
  }
}

/// "Key A", "Keys A and B", "Keys A, B and C".
_Subject _keyList(List<KeyCondition> keys, PolicySnapshot snapshot) {
  if (keys.length == 1) {
    return _Subject(_keyLabel(keys.single.keyId, snapshot), plural: false);
  }
  final letters = [
    for (final key in keys)
      _keyLabel(key.keyId, snapshot).replaceFirst(RegExp(r'^Key '), ''),
  ];
  return _Subject('Keys ${_joinAnd(letters)}', plural: true);
}

String _keyLabel(String keyId, PolicySnapshot snapshot) =>
    snapshot.keyById(keyId)?.label ?? keyId;

/// "a", "a and b", "a, b and c".
String _joinAnd(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.single;
  final head = items.sublist(0, items.length - 1).join(', ');
  return '$head and ${items.last}';
}

// --- the digest on the balance card -------------------------------------

/// The policy in a few words for the balance card: "Single key", "2 of
/// 3 keys", "Recovery in about 142 days".
String policyDigest(PolicySnapshot snapshot) {
  switch (snapshot.kind) {
    case PolicyKind.address:
      return 'Watched address';
    case PolicyKind.singleKey:
      return 'Single key';
    case PolicyKind.multisig:
      final condition = snapshot.branches.firstOrNull?.condition;
      if (condition is ThreshCondition) {
        return '${condition.k} of ${condition.n} keys';
      }
      return 'Single key';
    case PolicyKind.miniscript:
      if (snapshot.branches.isEmpty) return 'No spending path';
      // The nearest timelocked path is what the card is asked about;
      // failing one, the primary path itself says where it stands.
      final branch =
          snapshot.branches
              .where((b) => b.role == BranchRole.recovery)
              .firstOrNull ??
          snapshot.branches
              .where((b) => b.role != BranchRole.primary)
              .firstOrNull ??
          snapshot.branches.first;
      final name = switch (branch.role) {
        BranchRole.primary => 'Spendable',
        BranchRole.recovery => 'Recovery',
        BranchRole.emergency => 'Emergency',
        BranchRole.other => branch.label,
      };
      return switch (branch.state) {
        SpendableNow() =>
          '$name ${branch.role == BranchRole.primary ? 'now' : 'open'}',
        LockedBranch(:final until) => _inDuration(name, until),
        PerCoinBranch(:final next, :final unlocked, :final waiting) =>
          next != null
              ? _inDuration(name, next)
              : unlocked > 0
              ? '$name ${branch.role == BranchRole.primary ? 'now' : 'open'}'
              : waiting > 0
              ? '$name waiting for a block'
              : name,
        NoCoinsBranch() => switch (_lockDuration(branch)) {
          final int seconds => '$name after ${formatDuration(seconds)}',
          null => 'No coins yet',
        },
        NeedsPreimage() => 'Needs a secret',
      };
  }
}

String _inDuration(String name, Remaining remaining) {
  final seconds = secondsLeft(remaining);
  return seconds == null ? name : '$name in ${formatDuration(seconds)}';
}

/// The full duration of the first required relative lock of a branch,
/// in seconds; null when it has none.
int? _lockDuration(PolicyBranch branch) {
  for (final lock in branch.timelocks) {
    if (!lock.required) continue;
    switch (lock.lock) {
      case RelativeTimelock(lock: BlocksLock(:final blocks)):
        return blocks * blockSeconds;
      case RelativeTimelock(lock: SecondsLock(:final seconds)):
        return seconds;
      case AbsoluteTimelock():
        continue;
    }
  }
  return null;
}

// --- conditions ---------------------------------------------------------

/// A condition as a phrase, with the parts of a nested threshold as
/// its own lines, one level in.
class ConditionLine {
  const ConditionLine(this.text, {this.children = const []});

  final String text;
  final List<ConditionLine> children;
}

/// The condition of a branch in words: "Any 2 of Key A, Key B, Key C",
/// "Key B and a coin having waited 52 560 blocks". A threshold holding
/// another threshold becomes a heading, "Any 2 of:", over one line per
/// part.
ConditionLine describeCondition(
  PolicyCondition condition,
  PolicySnapshot snapshot,
) {
  if (condition is! ThreshCondition) {
    return ConditionLine(_noun(condition, snapshot));
  }
  final ThreshCondition(:k, :n, :items) = condition;
  final nested = items.any((item) => item is ThreshCondition);
  if (nested) {
    return ConditionLine(
      k == n
          ? 'All of:'
          : k == 1
          ? 'Any of:'
          : 'Any $k of:',
      children: [for (final item in items) describeCondition(item, snapshot)],
    );
  }
  final nouns = [for (final item in items) _noun(item, snapshot)];
  if (k == n) return ConditionLine(_joinAnd(nouns));
  if (k == 1) return ConditionLine('Any of ${nouns.join(', ')}');
  return ConditionLine('Any $k of ${nouns.join(', ')}');
}

/// A condition as a noun phrase, for use inside a list.
String _noun(PolicyCondition condition, PolicySnapshot snapshot) {
  return switch (condition) {
    KeyCondition(:final keyId) => _keyLabel(keyId, snapshot),
    ThreshCondition() => describeCondition(condition, snapshot).text,
    PreimageCondition(:final hash) => 'the preimage of a $hash hash',
    AfterCondition(lock: HeightLock(:final height)) =>
      'block ${groupThousands('$height')} reached',
    AfterCondition(lock: TimeLock(:final unix)) =>
      '${formatDate(unix)} reached',
    OlderCondition(lock: BlocksLock(:final blocks)) =>
      'a coin having waited ${formatBlocks(blocks)}',
    OlderCondition(lock: SecondsLock(:final seconds)) =>
      'a coin having waited ${formatDuration(seconds)}',
  };
}

// --- timelocks ----------------------------------------------------------

/// One timelock on one line: "52 560 blocks after the coin arrives ≈
/// 1 year", "block 801 432 ≈ in 10 days", "after Mar 17, 2030". A lock
/// the branch can do without ends in "(optional)". The "≈" is the
/// hedge: an estimate said as "about" behind it would be hedged twice.
String describeTimelock(PolicyTimelock timelock) {
  final text = switch (timelock.lock) {
    RelativeTimelock(lock: BlocksLock(:final blocks)) =>
      '${formatBlocks(blocks)} after the coin arrives '
          '≈ ${formatDuration(blocks * blockSeconds, hedge: false)}',
    RelativeTimelock(lock: SecondsLock(:final seconds)) =>
      '${formatDuration(seconds)} after the coin arrives',
    AbsoluteTimelock(lock: HeightLock(:final height)) => _absolute(
      'block ${groupThousands('$height')}',
      timelock.state,
    ),
    AbsoluteTimelock(lock: TimeLock(:final unix)) => _absolute(
      'after ${formatDate(unix)}',
      timelock.state,
    ),
  };
  return timelock.required ? text : '$text (optional)';
}

/// An absolute lock with where the chain stands against it.
String _absolute(String lock, LockState state) {
  switch (state) {
    case UnlockedLock():
      return '$lock · passed';
    case LockedLock(:final remaining):
      final seconds = secondsLeft(remaining);
      if (seconds == null) return lock;
      return '$lock ≈ in ${formatDuration(seconds, hedge: false)}';
    case PerCoinLock() || NoCoinsLock():
      return lock;
  }
}

// --- branch state -------------------------------------------------------

/// How a branch's state is coloured. The colour arrives only at the
/// thresholds: open, or closing within thirty days; everything else is
/// neutral.
enum StateTone {
  /// Spendable now.
  open,

  /// Locked, with thirty days or less to go.
  soon,

  /// Locked, further off than that.
  far,

  /// Nothing to count from: no coin, or a coin still in the mempool.
  idle,

  /// A hash preimage is needed; nothing here can say whether it is at
  /// hand.
  secret,
}

/// Where a branch stands, worded for its pill.
class BranchStatus {
  const BranchStatus(this.tone, this.label, {this.date, this.progress});

  final StateTone tone;

  /// "Spendable now", "In 1 432 blocks ≈ 10 days", "3 of 5 coins
  /// unlocked · next in about 12 days", "No coins yet".
  final String label;

  /// The estimated day the countdown ends, when there is one.
  final String? date;

  /// How far along the nearest coin's wait is, 0 to 1, for a relative
  /// lock with a coin to count from.
  final double? progress;
}

/// The state of a branch as its pill says it.
BranchStatus describeBranchState(PolicyBranch branch) {
  switch (branch.state) {
    case SpendableNow():
      return const BranchStatus(StateTone.open, 'Spendable now');
    case NoCoinsBranch():
      return const BranchStatus(StateTone.idle, 'No coins yet');
    case NeedsPreimage():
      return const BranchStatus(StateTone.secret, 'Needs a secret');
    case LockedBranch(:final until):
      return BranchStatus(
        _toneOf(until),
        _countdown(until),
        date: _dateOf(until),
      );
    case PerCoinBranch(
      :final unlocked,
      :final waiting,
      :final locked,
      :final next,
      :final total,
    ):
      if (total == 1) {
        // One coin: its own countdown reads better than "0 of 1 coins".
        if (unlocked == 1) {
          return const BranchStatus(StateTone.open, 'Spendable now');
        }
        if (next == null) {
          return const BranchStatus(StateTone.idle, 'Waiting for a block');
        }
        return BranchStatus(
          _toneOf(next),
          _countdown(next),
          date: _dateOf(next),
          progress: _progress(branch, next),
        );
      }
      final parts = <String>[
        '$unlocked of $total coins unlocked',
        if (next != null)
          if (secondsLeft(next) case final int seconds)
            'next in ${formatDuration(seconds)}',
        if (waiting > 0) '$waiting waiting for a block',
      ];
      final tone = locked == 0 && waiting == 0
          ? StateTone.open
          : next != null
          ? _toneOf(next)
          : StateTone.idle;
      return BranchStatus(
        tone,
        parts.join(' · '),
        date: next == null ? null : _dateOf(next),
        progress: next == null ? null : _progress(branch, next),
      );
  }
}

StateTone _toneOf(Remaining remaining) {
  final seconds = secondsLeft(remaining);
  if (seconds == null) return StateTone.far;
  return seconds <= soonThresholdSeconds ? StateTone.soon : StateTone.far;
}

/// "In 1 432 blocks ≈ 10 days", or "In about 10 days" for a lock the
/// chain judges by time: the estimate is hedged once, by the "≈" where
/// there is one and by the word where there is not.
String _countdown(Remaining remaining) {
  final blocks = remaining.remainingBlocks;
  final seconds = secondsLeft(remaining);
  if (seconds == null) return 'Locked';
  if (blocks == null) return 'In ${formatDuration(seconds)}';
  return 'In ${formatBlocks(blocks)} '
      '≈ ${formatDuration(seconds, hedge: false)}';
}

String? _dateOf(Remaining remaining) {
  final at = remaining.unlocksAtUnix;
  return at == null ? null : formatDate(at);
}

/// (total − remaining) / total of the nearest coin against the branch's
/// first required relative lock; null without one.
double? _progress(PolicyBranch branch, Remaining next) {
  for (final lock in branch.timelocks) {
    if (!lock.required) continue;
    final (int total, int? left) = switch (lock.lock) {
      RelativeTimelock(lock: BlocksLock(:final blocks)) => (
        blocks,
        next.remainingBlocks ?? _blocksOf(next.remainingSeconds),
      ),
      RelativeTimelock(lock: SecondsLock(:final seconds)) => (
        seconds,
        next.remainingSeconds,
      ),
      AbsoluteTimelock() => (0, null),
    };
    if (total <= 0 || left == null) continue;
    return ((total - left) / total).clamp(0.0, 1.0);
  }
  return null;
}

int? _blocksOf(int? seconds) =>
    seconds == null ? null : seconds ~/ blockSeconds;
