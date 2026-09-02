// Policy snapshots as the core serializes them, for the model, wording
// and screen tests. The key material is a stand-in: only its shape is
// under test.

/// Blocks a relative lock of one year takes, at ten minutes a block.
const int yearInBlocks = 52560;

/// The chain tip and the clock every fixture is computed at.
const int fixtureTip = 800000;
const int fixtureNow = 1750000000;

Map<String, dynamic> _key(
  String id,
  String label,
  String fingerprint,
  String keyShort, {
  String? originPath = "m/48'/0'/0'/2'",
}) => {
  'id': id,
  'label': label,
  'fingerprint': fingerprint,
  'origin_path': originPath,
  'key_short': keyShort,
};

Map<String, dynamic> _remaining(int blocks) => {
  'remaining_blocks': blocks,
  'remaining_seconds': blocks * 600,
  'unlocks_at_unix': fixtureNow + blocks * 600,
};

/// A Liana-style wallet: Key A spends any time, Key B once a coin has
/// waited a year. One coin, [remainingBlocks] short of its unlock.
Map<String, dynamic> lianaPolicyJson({
  int remainingBlocks = 20440,
  int unlocked = 0,
  int waiting = 0,
  int locked = 1,
}) {
  final next = locked > 0 ? _remaining(remainingBlocks) : null;
  final perCoin = {
    'kind': 'per_coin',
    'unlocked': unlocked,
    'waiting': waiting,
    'locked': locked,
    'next': next,
  };
  return {
    'kind': 'miniscript',
    'script': 'witness_script',
    'descriptor':
        "wsh(or_d(pk([a1b2c3d4/48'/0'/0'/2']xpubKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/0/*),"
        "and_v(v:pkh([e5f60718/48'/0'/0'/2']xpubKeyBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB/0/*),"
        'older(52560))))#f00dbabe',
    'policy': 'or(pk(Key A),and(pk(Key B),older(52560)))',
    'keys': [
      _key('k0', 'Key A', 'a1b2c3d4', 'xpubKeyA…AAAAAA'),
      _key('k1', 'Key B', 'e5f60718', 'xpubKeyB…BBBBBB'),
    ],
    'branches': [
      {
        'id': 'b0',
        'role': 'primary',
        'label': 'Primary',
        'summary': 'Key A',
        'condition': {'kind': 'key', 'key_id': 'k0'},
        'timelocks': <Map<String, dynamic>>[],
        'state': {'kind': 'spendable_now'},
        'spendable_now': true,
      },
      {
        'id': 'b1',
        'role': 'recovery',
        'label': 'Recovery',
        'summary': 'Key B, once a coin has waited 52,560 blocks',
        'condition': {
          'kind': 'thresh',
          'k': 2,
          'n': 2,
          'items': [
            {'kind': 'key', 'key_id': 'k1'},
            {
              'kind': 'older',
              'lock': {'kind': 'blocks', 'blocks': yearInBlocks},
            },
          ],
        },
        'timelocks': [
          {
            'lock': {
              'kind': 'relative',
              'lock': {'kind': 'blocks', 'blocks': yearInBlocks},
            },
            'required': true,
            'state': perCoin,
          },
        ],
        'state': perCoin,
        'spendable_now': false,
      },
    ],
    'tip_height': fixtureTip,
    'computed_at': fixtureNow,
    'time_basis': 'wall_clock',
    'coins': unlocked + waiting + locked,
    'has_timelocks': true,
  };
}

/// A wallet whose only path opens at an absolute height, [remaining]
/// blocks ahead of the tip.
Map<String, dynamic> heightLockedPolicyJson({int remaining = 1432}) {
  final until = _remaining(remaining);
  return {
    'kind': 'miniscript',
    'script': 'witness_script',
    'descriptor': 'wsh(and_v(v:pk(xpubKeyA/0/*),after(801432)))#c0ffee00',
    'policy': 'and(pk(Key A),after(801432))',
    'keys': [_key('k0', 'Key A', 'a1b2c3d4', 'xpubKeyA…AAAAAA')],
    'branches': [
      {
        'id': 'b0',
        'role': 'primary',
        'label': 'Primary',
        'summary': 'Key A after block 801,432',
        'condition': {
          'kind': 'thresh',
          'k': 2,
          'n': 2,
          'items': [
            {'kind': 'key', 'key_id': 'k0'},
            {
              'kind': 'after',
              'lock': {'kind': 'height', 'height': fixtureTip + remaining},
            },
          ],
        },
        'timelocks': [
          {
            'lock': {
              'kind': 'absolute',
              'lock': {'kind': 'height', 'height': fixtureTip + remaining},
            },
            'required': true,
            'state': {'kind': 'locked', 'until': until},
          },
        ],
        'state': {'kind': 'locked', 'until': until},
        'spendable_now': false,
      },
    ],
    'tip_height': fixtureTip,
    'computed_at': fixtureNow,
    'time_basis': 'wall_clock',
    'coins': 2,
    'has_timelocks': true,
  };
}

/// A wallet whose only path opens at block 900 000, read on a device
/// that has never synced: no tip, so the lock is known to stand and
/// nothing counts down to it.
Map<String, dynamic> unsyncedHeightLockedPolicyJson() {
  const until = {
    'remaining_blocks': null,
    'remaining_seconds': null,
    'unlocks_at_unix': null,
  };
  return {
    'kind': 'miniscript',
    'script': 'witness_script',
    'descriptor': 'wsh(and_v(v:pk(xpubKeyA/0/*),after(900000)))#0dd5eed5',
    'policy': 'and(pk(Key A),after(900000))',
    'keys': [_key('k0', 'Key A', 'a1b2c3d4', 'xpubKeyA…AAAAAA')],
    'branches': [
      {
        'id': 'b0',
        'role': 'primary',
        'label': 'Primary',
        'summary': 'Key A after block 900,000',
        'condition': {
          'kind': 'thresh',
          'k': 2,
          'n': 2,
          'items': [
            {'kind': 'key', 'key_id': 'k0'},
            {
              'kind': 'after',
              'lock': {'kind': 'height', 'height': 900000},
            },
          ],
        },
        'timelocks': [
          {
            'lock': {
              'kind': 'absolute',
              'lock': {'kind': 'height', 'height': 900000},
            },
            'required': true,
            'state': {'kind': 'locked', 'until': until},
          },
        ],
        'state': {'kind': 'locked', 'until': until},
        'spendable_now': false,
      },
    ],
    'tip_height': null,
    'computed_at': fixtureNow,
    'time_basis': 'wall_clock',
    'coins': 0,
    'has_timelocks': true,
  };
}

/// A 1-of-3 multisig: one branch, any key alone.
Map<String, dynamic> oneOfThreePolicyJson() => {
  'kind': 'multisig',
  'script': 'witness_script',
  'descriptor':
      'wsh(sortedmulti(1,xpubKeyA/0/*,xpubKeyB/0/*,xpubKeyC/0/*))#0badcafe',
  'policy': 'or(pk(Key A),pk(Key B),pk(Key C))',
  'keys': [
    _key('k0', 'Key A', 'a1b2c3d4', 'xpubKeyA…AAAAAA'),
    _key('k1', 'Key B', 'e5f60718', 'xpubKeyB…BBBBBB'),
    _key('k2', 'Key C', '19283746', 'xpubKeyC…CCCCCC', originPath: null),
  ],
  'branches': [
    {
      'id': 'b0',
      'role': 'primary',
      'label': 'Primary',
      'summary': 'Any of 3 keys',
      'condition': {
        'kind': 'thresh',
        'k': 1,
        'n': 3,
        'items': [
          {'kind': 'key', 'key_id': 'k0'},
          {'kind': 'key', 'key_id': 'k1'},
          {'kind': 'key', 'key_id': 'k2'},
        ],
      },
      'timelocks': <Map<String, dynamic>>[],
      'state': {'kind': 'spendable_now'},
      'spendable_now': true,
    },
  ],
  'tip_height': fixtureTip,
  'computed_at': fixtureNow,
  'time_basis': 'wall_clock',
  'coins': 1,
  'has_timelocks': false,
};

/// A 2-of-3 multisig: one primary branch, open now.
Map<String, dynamic> multisigPolicyJson() => {
  'kind': 'multisig',
  'script': 'witness_script',
  'descriptor':
      'wsh(sortedmulti(2,xpubKeyA/0/*,xpubKeyB/0/*,xpubKeyC/0/*))#deadbeef',
  'policy': 'thresh(2,pk(Key A),pk(Key B),pk(Key C))',
  'keys': [
    _key('k0', 'Key A', 'a1b2c3d4', 'xpubKeyA…AAAAAA'),
    _key('k1', 'Key B', 'e5f60718', 'xpubKeyB…BBBBBB'),
    _key('k2', 'Key C', '19283746', 'xpubKeyC…CCCCCC', originPath: null),
  ],
  'branches': [
    {
      'id': 'b0',
      'role': 'primary',
      'label': 'Primary',
      'summary': 'Any 2 of 3 keys',
      'condition': {
        'kind': 'thresh',
        'k': 2,
        'n': 3,
        'items': [
          {'kind': 'key', 'key_id': 'k0'},
          {'kind': 'key', 'key_id': 'k1'},
          {'kind': 'key', 'key_id': 'k2'},
        ],
      },
      'timelocks': <Map<String, dynamic>>[],
      'state': {'kind': 'spendable_now'},
      'spendable_now': true,
    },
  ],
  'tip_height': fixtureTip,
  'computed_at': fixtureNow,
  'time_basis': 'wall_clock',
  'coins': 3,
  'has_timelocks': false,
};

/// A single key, nothing else.
Map<String, dynamic> singleKeyPolicyJson() => {
  'kind': 'single_key',
  'script': 'segwit',
  'descriptor': "wpkh([a1b2c3d4/84'/0'/0']xpubKeyA/<0;1>/*)#0badf00d",
  'policy': 'pk(Key A)',
  'keys': [
    _key(
      'k0',
      'Key A',
      'a1b2c3d4',
      'xpubKeyA…AAAAAA',
      originPath: "m/84'/0'/0'",
    ),
  ],
  'branches': [
    {
      'id': 'b0',
      'role': 'primary',
      'label': 'Primary',
      'summary': 'Key A',
      'condition': {'kind': 'key', 'key_id': 'k0'},
      'timelocks': <Map<String, dynamic>>[],
      'state': {'kind': 'spendable_now'},
      'spendable_now': true,
    },
  ],
  'tip_height': fixtureTip,
  'computed_at': fixtureNow,
  'time_basis': 'wall_clock',
  'coins': 1,
  'has_timelocks': false,
};

/// A watched address: nothing to read.
Map<String, dynamic> addressPolicyJson() => {
  'kind': 'address',
  'script': 'segwit',
  'descriptor': 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
  'policy': 'address',
  'keys': <Map<String, dynamic>>[],
  'branches': <Map<String, dynamic>>[],
  'tip_height': fixtureTip,
  'computed_at': fixtureNow,
  'time_basis': 'wall_clock',
  'coins': 1,
  'has_timelocks': false,
};
