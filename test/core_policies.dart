// Policy snapshots as gerfaut-core writes them, for the tests of the
// policy page: four wallets read at block 800 000 and unix time
// 1 750 000 000, one of them twice. Captured from the core's analysis,
// the key material swapped for stand-ins.

import 'dart:convert';

/// The JSON the app receives over the bridge, decoded.
Map<String, dynamic> corePolicy(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// Keys A and B together any time; Keys C and D after 4 320
/// blocks, Key D alone after 26 280, Key C alone after 52 560,
/// written farthest first. Three coins: one past every lock, one
/// 4 001 blocks old, one unconfirmed.
const String recoveryPathsPolicy = r'''{
  "kind": "miniscript",
  "script": "witness_script",
  "descriptor": "wsh(or_d(multi(2,xpubKeyA/0/*,xpubKeyB/0/*),or_i(and_v(v:pkh(xpubKeyC/0/*),older(52560)),or_i(and_v(v:pkh(xpubKeyD/0/*),older(26280)),and_v(v:multi(2,xpubKeyC/1/*,xpubKeyD/1/*),older(4320))))))",
  "policy": "or(and(pk(Key A),pk(Key B)),and(pk(Key C),older(52560)),and(pk(Key D),older(26280)),and(pk(Key C),pk(Key D),older(4320)))",
  "keys": [
    {
      "id": "k0",
      "label": "Key A",
      "fingerprint": "a1b2c3d4",
      "origin_path": null,
      "key_short": "xpubKeyA…AAAAAA"
    },
    {
      "id": "k1",
      "label": "Key B",
      "fingerprint": "e5f60718",
      "origin_path": null,
      "key_short": "xpubKeyB…BBBBBB"
    },
    {
      "id": "k2",
      "label": "Key C",
      "fingerprint": "19283746",
      "origin_path": null,
      "key_short": "xpubKeyC…CCCCCC"
    },
    {
      "id": "k3",
      "label": "Key D",
      "fingerprint": "0f1e2d3c",
      "origin_path": null,
      "key_short": "xpubKeyD…DDDDDD"
    }
  ],
  "branches": [
    {
      "id": "b0",
      "role": "primary",
      "label": "Primary",
      "summary": "Keys A and B",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k0"},
          {"kind": "key", "key_id": "k1"}
        ]
      },
      "timelocks": [],
      "state": {"kind": "spendable_now"},
      "spendable_now": true,
      "tone": "confirmed"
    },
    {
      "id": "b3",
      "role": "recovery",
      "label": "Recovery",
      "summary": "Keys C and D, once a coin has waited 4,320 blocks",
      "condition": {
        "kind": "thresh",
        "k": 3,
        "n": 3,
        "items": [
          {"kind": "key", "key_id": "k2"},
          {"kind": "key", "key_id": "k3"},
          {"kind": "older", "lock": {"kind": "blocks", "blocks": 4320}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "relative",
            "lock": {"kind": "blocks", "blocks": 4320}
          },
          "required": true,
          "state": {
            "kind": "per_coin",
            "unlocked": 1,
            "waiting": 1,
            "locked": 1,
            "next": {
              "remaining_blocks": 319,
              "remaining_seconds": 191400,
              "unlocks_at_unix": 1750191400
            }
          }
        }
      ],
      "state": {
        "kind": "per_coin",
        "unlocked": 1,
        "waiting": 1,
        "locked": 1,
        "next": {
          "remaining_blocks": 319,
          "remaining_seconds": 191400,
          "unlocks_at_unix": 1750191400
        }
      },
      "spendable_now": false,
      "tone": "pending"
    },
    {
      "id": "b2",
      "role": "emergency",
      "label": "Emergency",
      "summary": "Key D, once a coin has waited 26,280 blocks",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k3"},
          {"kind": "older", "lock": {"kind": "blocks", "blocks": 26280}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "relative",
            "lock": {"kind": "blocks", "blocks": 26280}
          },
          "required": true,
          "state": {
            "kind": "per_coin",
            "unlocked": 1,
            "waiting": 1,
            "locked": 1,
            "next": {
              "remaining_blocks": 22279,
              "remaining_seconds": 13367400,
              "unlocks_at_unix": 1763367400
            }
          }
        }
      ],
      "state": {
        "kind": "per_coin",
        "unlocked": 1,
        "waiting": 1,
        "locked": 1,
        "next": {
          "remaining_blocks": 22279,
          "remaining_seconds": 13367400,
          "unlocks_at_unix": 1763367400
        }
      },
      "spendable_now": false,
      "tone": "neutral"
    },
    {
      "id": "b1",
      "role": "other",
      "label": "Recovery 3",
      "summary": "Key C, once a coin has waited 52,560 blocks",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k2"},
          {"kind": "older", "lock": {"kind": "blocks", "blocks": 52560}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "relative",
            "lock": {"kind": "blocks", "blocks": 52560}
          },
          "required": true,
          "state": {
            "kind": "per_coin",
            "unlocked": 1,
            "waiting": 1,
            "locked": 1,
            "next": {
              "remaining_blocks": 48559,
              "remaining_seconds": 29135400,
              "unlocks_at_unix": 1779135400
            }
          }
        }
      ],
      "state": {
        "kind": "per_coin",
        "unlocked": 1,
        "waiting": 1,
        "locked": 1,
        "next": {
          "remaining_blocks": 48559,
          "remaining_seconds": 29135400,
          "unlocks_at_unix": 1779135400
        }
      },
      "spendable_now": false,
      "tone": "neutral"
    }
  ],
  "tip_height": 800000,
  "computed_at": 1750000000,
  "time_basis": "wall_clock",
  "coins": 3,
  "has_timelocks": true
}''';

/// Liana's everyday shape: Key A any time, Key B once a coin has
/// waited 52 560 blocks. Two coins, one past the lock, one 10 001
/// blocks old.
const String relativePolicy = r'''{
  "kind": "miniscript",
  "script": "witness_script",
  "descriptor": "wsh(or_d(pk(xpubKeyA/0/*),and_v(v:pkh(xpubKeyB/0/*),older(52560))))",
  "policy": "or(pk(Key A),and(pk(Key B),older(52560)))",
  "keys": [
    {
      "id": "k0",
      "label": "Key A",
      "fingerprint": "a1b2c3d4",
      "origin_path": null,
      "key_short": "xpubKeyA…AAAAAA"
    },
    {
      "id": "k1",
      "label": "Key B",
      "fingerprint": "e5f60718",
      "origin_path": null,
      "key_short": "xpubKeyB…BBBBBB"
    }
  ],
  "branches": [
    {
      "id": "b0",
      "role": "primary",
      "label": "Primary",
      "summary": "Key A",
      "condition": {"kind": "key", "key_id": "k0"},
      "timelocks": [],
      "state": {"kind": "spendable_now"},
      "spendable_now": true,
      "tone": "confirmed"
    },
    {
      "id": "b1",
      "role": "recovery",
      "label": "Recovery",
      "summary": "Key B, once a coin has waited 52,560 blocks",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k1"},
          {"kind": "older", "lock": {"kind": "blocks", "blocks": 52560}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "relative",
            "lock": {"kind": "blocks", "blocks": 52560}
          },
          "required": true,
          "state": {
            "kind": "per_coin",
            "unlocked": 1,
            "waiting": 0,
            "locked": 1,
            "next": {
              "remaining_blocks": 42559,
              "remaining_seconds": 25535400,
              "unlocks_at_unix": 1775535400
            }
          }
        }
      ],
      "state": {
        "kind": "per_coin",
        "unlocked": 1,
        "waiting": 0,
        "locked": 1,
        "next": {
          "remaining_blocks": 42559,
          "remaining_seconds": 25535400,
          "unlocks_at_unix": 1775535400
        }
      },
      "spendable_now": false,
      "tone": "neutral"
    }
  ],
  "tip_height": 800000,
  "computed_at": 1750000000,
  "time_basis": "wall_clock",
  "coins": 2,
  "has_timelocks": true
}''';

/// The same wallet, both coins past the lock.
const String relativeOpenPolicy = r'''{
  "kind": "miniscript",
  "script": "witness_script",
  "descriptor": "wsh(or_d(pk(xpubKeyA/0/*),and_v(v:pkh(xpubKeyB/0/*),older(52560))))",
  "policy": "or(pk(Key A),and(pk(Key B),older(52560)))",
  "keys": [
    {
      "id": "k0",
      "label": "Key A",
      "fingerprint": "a1b2c3d4",
      "origin_path": null,
      "key_short": "xpubKeyA…AAAAAA"
    },
    {
      "id": "k1",
      "label": "Key B",
      "fingerprint": "e5f60718",
      "origin_path": null,
      "key_short": "xpubKeyB…BBBBBB"
    }
  ],
  "branches": [
    {
      "id": "b0",
      "role": "primary",
      "label": "Primary",
      "summary": "Key A",
      "condition": {"kind": "key", "key_id": "k0"},
      "timelocks": [],
      "state": {"kind": "spendable_now"},
      "spendable_now": true,
      "tone": "confirmed"
    },
    {
      "id": "b1",
      "role": "recovery",
      "label": "Recovery",
      "summary": "Key B, once a coin has waited 52,560 blocks",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k1"},
          {"kind": "older", "lock": {"kind": "blocks", "blocks": 52560}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "relative",
            "lock": {"kind": "blocks", "blocks": 52560}
          },
          "required": true,
          "state": {
            "kind": "per_coin",
            "unlocked": 2,
            "waiting": 0,
            "locked": 0,
            "next": null
          }
        }
      ],
      "state": {
        "kind": "per_coin",
        "unlocked": 2,
        "waiting": 0,
        "locked": 0,
        "next": null
      },
      "spendable_now": false,
      "tone": "confirmed"
    }
  ],
  "tip_height": 800000,
  "computed_at": 1750000000,
  "time_basis": "wall_clock",
  "coins": 2,
  "has_timelocks": true
}''';

/// Key A any time, Key B after noon UTC on 17 March 2030, Key C
/// after block 801 432, the date written first.
const String absolutePolicy = r'''{
  "kind": "miniscript",
  "script": "witness_script",
  "descriptor": "wsh(or_d(pk(xpubKeyA/0/*),or_i(and_v(v:pkh(xpubKeyB/0/*),after(1899979200)),and_v(v:pkh(xpubKeyC/0/*),after(801432)))))",
  "policy": "or(pk(Key A),and(pk(Key B),after(1899979200)),and(pk(Key C),after(801432)))",
  "keys": [
    {
      "id": "k0",
      "label": "Key A",
      "fingerprint": "a1b2c3d4",
      "origin_path": null,
      "key_short": "xpubKeyA…AAAAAA"
    },
    {
      "id": "k1",
      "label": "Key B",
      "fingerprint": "e5f60718",
      "origin_path": null,
      "key_short": "xpubKeyB…BBBBBB"
    },
    {
      "id": "k2",
      "label": "Key C",
      "fingerprint": "19283746",
      "origin_path": null,
      "key_short": "xpubKeyC…CCCCCC"
    }
  ],
  "branches": [
    {
      "id": "b0",
      "role": "primary",
      "label": "Primary",
      "summary": "Key A",
      "condition": {"kind": "key", "key_id": "k0"},
      "timelocks": [],
      "state": {"kind": "spendable_now"},
      "spendable_now": true,
      "tone": "confirmed"
    },
    {
      "id": "b2",
      "role": "recovery",
      "label": "Recovery",
      "summary": "Key C after block 801,432",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k2"},
          {"kind": "after", "lock": {"kind": "height", "height": 801432}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "absolute",
            "lock": {"kind": "height", "height": 801432}
          },
          "required": true,
          "state": {
            "kind": "locked",
            "until": {
              "remaining_blocks": 1432,
              "remaining_seconds": 859200,
              "unlocks_at_unix": 1750859200
            }
          }
        }
      ],
      "state": {
        "kind": "locked",
        "until": {
          "remaining_blocks": 1432,
          "remaining_seconds": 859200,
          "unlocks_at_unix": 1750859200
        }
      },
      "spendable_now": false,
      "tone": "pending"
    },
    {
      "id": "b1",
      "role": "emergency",
      "label": "Emergency",
      "summary": "Key B after 2030-03-17",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 2,
        "items": [
          {"kind": "key", "key_id": "k1"},
          {"kind": "after", "lock": {"kind": "time", "unix": 1899979200}}
        ]
      },
      "timelocks": [
        {
          "lock": {
            "kind": "absolute",
            "lock": {"kind": "time", "unix": 1899979200}
          },
          "required": true,
          "state": {
            "kind": "locked",
            "until": {
              "remaining_blocks": null,
              "remaining_seconds": 149979200,
              "unlocks_at_unix": 1899979200
            }
          }
        }
      ],
      "state": {
        "kind": "locked",
        "until": {
          "remaining_blocks": null,
          "remaining_seconds": 149979200,
          "unlocks_at_unix": 1899979200
        }
      },
      "spendable_now": false,
      "tone": "neutral"
    }
  ],
  "tip_height": 800000,
  "computed_at": 1750000000,
  "time_basis": "wall_clock",
  "coins": 1,
  "has_timelocks": true
}''';

/// Any 2 of 3 keys.
const String multisigPolicy = r'''{
  "kind": "multisig",
  "script": "witness_script",
  "descriptor": "wsh(sortedmulti(2,xpubKeyA/0/*,xpubKeyB/0/*,xpubKeyC/0/*))",
  "policy": "thresh(2,pk(Key A),pk(Key B),pk(Key C))",
  "keys": [
    {
      "id": "k0",
      "label": "Key A",
      "fingerprint": "a1b2c3d4",
      "origin_path": null,
      "key_short": "xpubKeyA…AAAAAA"
    },
    {
      "id": "k1",
      "label": "Key B",
      "fingerprint": "e5f60718",
      "origin_path": null,
      "key_short": "xpubKeyB…BBBBBB"
    },
    {
      "id": "k2",
      "label": "Key C",
      "fingerprint": "19283746",
      "origin_path": null,
      "key_short": "xpubKeyC…CCCCCC"
    }
  ],
  "branches": [
    {
      "id": "b0",
      "role": "primary",
      "label": "Primary",
      "summary": "Any 2 of 3 keys",
      "condition": {
        "kind": "thresh",
        "k": 2,
        "n": 3,
        "items": [
          {"kind": "key", "key_id": "k0"},
          {"kind": "key", "key_id": "k1"},
          {"kind": "key", "key_id": "k2"}
        ]
      },
      "timelocks": [],
      "state": {"kind": "spendable_now"},
      "spendable_now": true,
      "tone": "confirmed"
    }
  ],
  "tip_height": 800000,
  "computed_at": 1750000000,
  "time_basis": "wall_clock",
  "coins": 1,
  "has_timelocks": false
}''';
