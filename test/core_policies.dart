// Policy snapshots as gerfaut-core writes them, for the tests of the
// policy page: the cases of its reference PolicySnapshot.json (see
// core_fixtures.dart), five wallets of the BIP-32 test vector keys read
// at block 800 000 and unix time 1 750 000 000, one of them twice.

import 'dart:convert';

import 'core_fixtures.dart';

/// The JSON the app receives over the bridge, decoded.
Map<String, dynamic> corePolicy(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

String _policy(String name) => coreCaseJson('PolicySnapshot', name);

/// Keys A and B together any time; Keys C and D after 4 320
/// blocks, Key D alone after 26 280, Key C alone after 52 560,
/// written farthest first. Three coins: one past every lock, one
/// 4 001 blocks old, one unconfirmed.
final String recoveryPathsPolicy = _policy('recovery_paths');

/// Liana's everyday shape: Key A any time, Key B once a coin has
/// waited 52 560 blocks. Two coins, one past the lock, one 10 001
/// blocks old.
final String relativePolicy = _policy('relative');

/// The same wallet, both coins past the lock.
final String relativeOpenPolicy = _policy('relative_open');

/// Key A any time, Key B after noon UTC on 17 March 2030, Key C
/// after block 801 432, the date written first.
final String absolutePolicy = _policy('absolute');

/// Any 2 of 3 keys.
final String multisigPolicy = _policy('multisig');
