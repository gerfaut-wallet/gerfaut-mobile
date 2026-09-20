// Typed shapes of the bridge JSON. They mirror gerfaut-core's serde
// DTOs one to one (snake_case keys); if a field changes there, it
// changes here.

/// Networks Gerfaut can operate on.
enum Network {
  mainnet('mainnet', 'Mainnet'),
  signet('signet', 'Signet'),
  testnet4('testnet4', 'Testnet 4'),
  regtest('regtest', 'Regtest');

  const Network(this.id, this.label);

  /// Stable machine identifier, as serialized by the core.
  final String id;

  /// Display name.
  final String label;

  static Network fromId(String id) =>
      Network.values.firstWhere((n) => n.id == id);
}

/// Script type of a wallet.
enum ScriptKind {
  legacy('legacy', 'Legacy (P2PKH)'),
  nestedSegwit('nested_segwit', 'Nested SegWit (P2SH-P2WPKH)'),
  segwit('segwit', 'Native SegWit (P2WPKH)'),
  taproot('taproot', 'Taproot (P2TR)'),
  witnessScript('witness_script', 'Script (P2WSH)'),
  legacyScript('legacy_script', 'Script (P2SH)'),
  bare('bare', 'Bare script');

  const ScriptKind(this.id, this.label);

  final String id;
  final String label;

  static ScriptKind fromId(String id) =>
      ScriptKind.values.firstWhere((k) => k.id == id);
}

/// What the input classifier recognized.
enum RecognizedKind {
  descriptor('descriptor', 'Output descriptor'),
  descriptorPair('descriptor_pair', 'Descriptor pair (receive + change)'),
  multipathDescriptor('multipath_descriptor', 'Multipath descriptor (BIP-389)'),
  extendedKey('extended_key', 'Extended public key'),
  address('address', 'Single address'),
  walletExport('wallet_export', 'Wallet export file'),
  bsms('bsms', 'BSMS record');

  const RecognizedKind(this.id, this.label);

  final String id;
  final String label;

  static RecognizedKind fromId(String id) =>
      RecognizedKind.values.firstWhere((k) => k.id == id);
}

/// Non-fatal findings surfaced on the confirmation screen.
enum InputWarning {
  assumedSegwit(
    'assumed_segwit',
    'This key carries no script type. Check the one selected below.',
  ),
  slip132Converted(
    'slip132_converted',
    'The SLIP-132 prefix was converted to a standard extended key.',
  ),
  changeNotTracked(
    'change_not_tracked',
    'No change path was provided: change outputs will not be tracked.',
  ),
  multipleAccountsInFile(
    'multiple_accounts_in_file',
    'The file holds several account types; the preferred one was selected.',
  ),
  nonStandardDerivation(
    'non_standard_derivation',
    'The paths chosen are not the usual 0/* and 1/*: compare the first '
        'address with your wallet.',
  );

  const InputWarning(this.id, this.label);

  final String id;
  final String label;

  static InputWarning fromId(String id) =>
      InputWarning.values.firstWhere((w) => w.id == id);
}

/// Normalized wallet material produced by the classifier.
sealed class ParsedPayload {
  const ParsedPayload();

  factory ParsedPayload.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'descriptors' => DescriptorsPayload(
        external: json['external'] as String,
        internal: json['internal'] as String?,
        script: ScriptKind.fromId(json['script'] as String),
      ),
      'address' => AddressPayload(address: json['address'] as String),
      final other => throw FormatException('unknown payload type: $other'),
    };
  }
}

class DescriptorsPayload extends ParsedPayload {
  const DescriptorsPayload({
    required this.external,
    required this.internal,
    required this.script,
  });

  final String external;
  final String? internal;
  final ScriptKind script;
}

class AddressPayload extends ParsedPayload {
  const AddressPayload({required this.address});

  final String address;
}

/// Full classification result of pasted or imported wallet material.
class ParsedInput {
  const ParsedInput({
    required this.kind,
    required this.networks,
    required this.payload,
    required this.warnings,
    required this.rawJson,
    this.scriptOptions = const [],
    this.previewAddress,
    this.derivation,
    this.derivationEditable = false,
  });

  factory ParsedInput.fromJson(Map<String, dynamic> json, String rawJson) {
    return ParsedInput(
      kind: RecognizedKind.fromId(json['kind'] as String),
      networks: (json['networks'] as List)
          .map((n) => Network.fromId(n as String))
          .toList(),
      payload: ParsedPayload.fromJson(json['payload'] as Map<String, dynamic>),
      warnings: (json['warnings'] as List)
          .map((w) => InputWarning.fromId(w as String))
          .toList(),
      rawJson: rawJson,
      scriptOptions: ((json['script_options'] as List?) ?? const [])
          .map((s) => ScriptKind.fromId(s as String))
          .toList(),
      previewAddress: json['preview_address'] as String?,
      derivation: json['derivation'] == null
          ? null
          : DerivationChoice.fromJson(
              json['derivation'] as Map<String, dynamic>,
            ),
      derivationEditable: json['derivation_editable'] as bool? ?? false,
    );
  }

  final RecognizedKind kind;

  /// Candidate networks, in display order. More than one entry means the
  /// input alone cannot tell and the user decides.
  final List<Network> networks;
  final ParsedPayload payload;
  final List<InputWarning> warnings;

  /// The exact JSON the core produced, passed back verbatim to
  /// `add_wallet` so the roundtrip can never drift.
  final String rawJson;

  /// Script types the user may switch to. Empty when the input fixes
  /// its own script type; non-empty only for a lone extended key.
  final List<ScriptKind> scriptOptions;

  /// First receive address on the first candidate network, so the user
  /// can compare it with their wallet. Null when nothing derives.
  final String? previewAddress;

  /// The derivation in effect: set only for a lone extended key.
  final DerivationChoice? derivation;

  /// True when the input leaves the paths open (a lone extended key).
  final bool derivationEditable;
}

/// Where a lone extended key derives its addresses: the receive and
/// change branches under the key, and the key origin.
class DerivationChoice {
  const DerivationChoice({
    required this.receive,
    required this.change,
    required this.origin,
  });

  /// The paths the core applies when nothing else is asked.
  static const DerivationChoice standard = DerivationChoice(
    receive: '0/*',
    change: '1/*',
    origin: null,
  );

  factory DerivationChoice.fromJson(Map<String, dynamic> json) {
    return DerivationChoice(
      receive: json['receive'] as String,
      change: json['change'] as String?,
      origin: json['origin'] as String?,
    );
  }

  /// Receive branch, relative to the key: `0/*`, `*`, `2/0/*`.
  final String receive;

  /// Change branch in the same form; null leaves change untracked.
  final String? change;

  /// Key origin, `[fingerprint/path]`; null keeps the input's own.
  final String? origin;

  Map<String, dynamic> toJson() => {
    'receive': receive,
    'change': change,
    'origin': origin,
  };

  DerivationChoice copyWith({
    String? receive,
    String? Function()? change,
    String? Function()? origin,
  }) {
    return DerivationChoice(
      receive: receive ?? this.receive,
      change: change == null ? this.change : change(),
      origin: origin == null ? this.origin : origin(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DerivationChoice &&
      other.receive == receive &&
      other.change == change &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(receive, change, origin);
}

/// The advanced choices of the import screen, both optional. Inputs
/// that fix their own script type and paths ignore them.
class ImportOptions {
  const ImportOptions({this.script, this.derivation});

  final ScriptKind? script;
  final DerivationChoice? derivation;

  Map<String, dynamic> toJson() => {
    'script': script?.id,
    'derivation': derivation?.toJson(),
  };
}

/// Balance split as BDK reports it, in sats.
class BalanceSnapshot {
  const BalanceSnapshot({
    required this.confirmed,
    required this.trustedPending,
    required this.untrustedPending,
    required this.immature,
    required this.total,
    this.pendingNetSats,
  });

  factory BalanceSnapshot.fromJson(Map<String, dynamic> json) {
    return BalanceSnapshot(
      confirmed: json['confirmed'] as int,
      trustedPending: json['trusted_pending'] as int,
      untrustedPending: json['untrusted_pending'] as int,
      immature: json['immature'] as int,
      total: json['total'] as int,
      pendingNetSats: json['pending_net_sats'] as int?,
    );
  }

  final int confirmed;
  final int trustedPending;
  final int untrustedPending;
  final int immature;
  final int total;

  /// Signed sum of the transactions not yet in a block: what of [total]
  /// is still arriving, or has left it without the chain having taken
  /// it yet. Null once everything is settled.
  final int? pendingNetSats;
}

/// When and against what a wallet last synced.
class SyncStamp {
  const SyncStamp({
    required this.at,
    required this.tipHeight,
    required this.backend,
  });

  factory SyncStamp.fromJson(Map<String, dynamic> json) {
    return SyncStamp(
      at: json['at'] as int,
      tipHeight: json['tip_height'] as int,
      backend: json['backend'] as String,
    );
  }

  final int at;
  final int tipHeight;
  final String backend;
}

/// The glyph a wallet shows next to its name, chosen by the user. The
/// names are Lucide's, the set is the core's: both apps draw the same
/// icon for the same value. Listed in the order the picker shows them.
enum WalletIcon {
  wallet('wallet', 'Wallet'),
  key('key', 'Key'),
  shield('shield', 'Shield'),
  mapPin('map_pin', 'Map pin'),
  snowflake('snowflake', 'Snowflake'),
  landmark('landmark', 'Landmark'),
  piggyBank('piggy_bank', 'Piggy bank');

  const WalletIcon(this.id, this.label);

  /// Stable machine identifier, as serialized by the core.
  final String id;

  /// What a screen reader calls it.
  final String label;

  /// The icon behind an identifier; the generic wallet for one this
  /// build does not know, or a vault written before icons existed.
  static WalletIcon fromId(String? id) {
    for (final icon in WalletIcon.values) {
      if (icon.id == id) return icon;
    }
    return WalletIcon.wallet;
  }
}

/// Wallet metadata as stored in the vault.
class WalletMeta {
  const WalletMeta({
    required this.id,
    required this.name,
    this.icon = WalletIcon.wallet,
    required this.network,
    required this.kind,
    required this.recognizedAs,
    required this.createdAt,
    required this.gapLimit,
    required this.lastSync,
    required this.cachedBalance,
    required this.cachedTxCount,
    this.scanGap = 20,
  });

  factory WalletMeta.fromJson(Map<String, dynamic> json) {
    final cached = json['cached'] as Map<String, dynamic>;
    return WalletMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: WalletIcon.fromId(json['icon'] as String?),
      network: Network.fromId(json['network'] as String),
      kind: WalletKind.fromJson(json['kind'] as Map<String, dynamic>),
      recognizedAs: RecognizedKind.fromId(json['recognized_as'] as String),
      createdAt: json['created_at'] as int,
      gapLimit: json['gap_limit'] as int,
      // Same fallback as the core: wallets stored before scan tracking
      // were scanned with the default gap.
      scanGap: json['scan_gap'] as int? ?? 20,
      lastSync: json['last_sync'] == null
          ? null
          : SyncStamp.fromJson(json['last_sync'] as Map<String, dynamic>),
      cachedBalance: BalanceSnapshot.fromJson(
        cached['balance'] as Map<String, dynamic>,
      ),
      cachedTxCount: cached['tx_count'] as int,
    );
  }

  final String id;
  final String name;

  /// The glyph beside the name; the generic wallet unless the user
  /// picked another.
  final WalletIcon icon;
  final Network network;
  final WalletKind kind;
  final RecognizedKind recognizedAs;
  final int createdAt;
  final int gapLimit;

  /// Gap limit the last full scan actually used; a setting raised above
  /// it makes the next sync a full scan again.
  final int scanGap;
  final SyncStamp? lastSync;
  final BalanceSnapshot cachedBalance;
  final int cachedTxCount;

  bool get isSingleAddress => kind is SingleAddressKind;

  /// The same wallet with the name or the icon changed: what a rename
  /// or an icon pick leaves behind.
  WalletMeta copyWith({String? name, WalletIcon? icon}) {
    return WalletMeta(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      network: network,
      kind: kind,
      recognizedAs: recognizedAs,
      createdAt: createdAt,
      gapLimit: gapLimit,
      scanGap: scanGap,
      lastSync: lastSync,
      cachedBalance: cachedBalance,
      cachedTxCount: cachedTxCount,
    );
  }
}

/// What a wallet actually watches, as stored in the vault.
sealed class WalletKind {
  const WalletKind();

  factory WalletKind.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'single_address' => SingleAddressKind(address: json['address'] as String),
      _ => DescriptorsKind(
        external: json['external'] as String,
        internal: json['internal'] as String?,
        script: ScriptKind.fromId(json['script'] as String),
      ),
    };
  }
}

class DescriptorsKind extends WalletKind {
  const DescriptorsKind({
    required this.external,
    required this.internal,
    required this.script,
  });

  final String external;
  final String? internal;
  final ScriptKind script;
}

class SingleAddressKind extends WalletKind {
  const SingleAddressKind({required this.address});

  final String address;
}

/// Confirmation state of a transaction or UTXO.
class TxStatus {
  const TxStatus.confirmed({required int this.height, this.timestamp})
    : confirmed = true;

  const TxStatus.pending() : confirmed = false, height = null, timestamp = null;

  factory TxStatus.fromJson(Map<String, dynamic> json) {
    return switch (json['state'] as String) {
      'confirmed' => TxStatus.confirmed(
        height: json['height'] as int,
        timestamp: json['timestamp'] as int?,
      ),
      _ => const TxStatus.pending(),
    };
  }

  final bool confirmed;
  final int? height;
  final int? timestamp;
}

/// One transaction in a wallet's list.
class TxSummary {
  const TxSummary({
    required this.txid,
    required this.netSats,
    required this.feeSats,
    required this.status,
    required this.confirmations,
  });

  factory TxSummary.fromJson(Map<String, dynamic> json) {
    return TxSummary(
      txid: json['txid'] as String,
      netSats: json['net_sats'] as int,
      feeSats: json['fee_sats'] as int?,
      status: TxStatus.fromJson(json['status'] as Map<String, dynamic>),
      confirmations: json['confirmations'] as int,
    );
  }

  final String txid;
  final int netSats;
  final int? feeSats;
  final TxStatus status;
  final int confirmations;
}

/// A decoded OP_RETURN payload.
class OpReturnData {
  const OpReturnData({required this.hex, required this.text, this.label});

  factory OpReturnData.fromJson(Map<String, dynamic> json) {
    return OpReturnData(
      hex: json['hex'] as String,
      text: json['text'] as String?,
      label: json['label'] as String?,
    );
  }

  /// Payload bytes in hex.
  final String hex;

  /// The payload as text, when it is printable UTF-8.
  final String? text;

  /// Name of a recognized protocol payload, when the prefix says so.
  final String? label;
}

/// One input or output of a transaction.
class TxIo {
  const TxIo({
    required this.address,
    required this.valueSats,
    required this.isMine,
    this.change = false,
    this.opReturn,
    this.prevTxid,
    this.prevVout,
  });

  factory TxIo.fromJson(Map<String, dynamic> json) {
    return TxIo(
      address: json['address'] as String?,
      valueSats: json['value_sats'] as int?,
      isMine: json['is_mine'] as bool,
      change: json['change'] as bool? ?? false,
      opReturn: json['op_return'] == null
          ? null
          : OpReturnData.fromJson(json['op_return'] as Map<String, dynamic>),
      prevTxid: json['prev_txid'] as String?,
      prevVout: json['prev_vout'] as int?,
    );
  }

  final String? address;
  final int? valueSats;
  final bool isMine;

  /// Output on the wallet's change keychain (descriptor wallets only).
  final bool change;

  /// Decoded OP_RETURN payload, for data-carrying outputs.
  final OpReturnData? opReturn;

  /// For an input, the transaction of the output it spends. Two inputs
  /// can share an address; only the outpoint names one of them.
  final String? prevTxid;

  /// For an input, the index of the output it spends.
  final int? prevVout;
}

/// A server address read out of a scan or a paste. Fills the backend
/// form; nothing is saved until the person presses Save.
class ScannedBackend {
  const ScannedBackend({
    required this.kind,
    required this.url,
    required this.host,
    required this.port,
    required this.tls,
    required this.onion,
  });

  factory ScannedBackend.fromJson(Map<String, dynamic> json) {
    return ScannedBackend(
      kind: json['kind'] as String,
      url: json['url'] as String,
      host: json['host'] as String,
      port: json['port'] as int?,
      tls: json['tls'] as bool,
      onion: json['onion'] as bool,
    );
  }

  /// `electrum` or `esplora`.
  final String kind;

  /// The address in the form the backend configuration stores.
  final String url;
  final String host;
  final int? port;
  final bool tls;
  final bool onion;
}

/// Deep transaction facts; absent only for watched-address entries
/// synced by older versions.
class TxExtras {
  const TxExtras({
    required this.sizeBytes,
    required this.vsize,
    required this.weightWu,
    required this.version,
    required this.locktime,
    required this.rbfSignaled,
    required this.segwit,
    required this.taproot,
    required this.isCoinbase,
    required this.coinbasePool,
    required this.sigops,
    required this.rawHex,
    this.coinbaseHeight,
    this.coinbaseTag,
  });

  factory TxExtras.fromJson(Map<String, dynamic> json) {
    return TxExtras(
      sizeBytes: json['size_bytes'] as int? ?? 0,
      vsize: json['vsize'] as int? ?? 0,
      weightWu: json['weight_wu'] as int? ?? 0,
      version: json['version'] as int? ?? 0,
      locktime: json['locktime'] as int? ?? 0,
      rbfSignaled: json['rbf_signaled'] as bool? ?? false,
      segwit: json['segwit'] as bool? ?? false,
      taproot: json['taproot'] as bool? ?? false,
      isCoinbase: json['is_coinbase'] as bool? ?? false,
      coinbasePool: json['coinbase_pool'] as String?,
      coinbaseHeight: json['coinbase_height'] as int?,
      coinbaseTag: json['coinbase_tag'] as String?,
      sigops: json['sigops'] as int? ?? 0,
      rawHex: json['raw_hex'] as String? ?? '',
    );
  }

  final int sizeBytes;
  final int vsize;
  final int weightWu;
  final int version;
  final int locktime;
  final bool rbfSignaled;
  final bool segwit;
  final bool taproot;
  final bool isCoinbase;
  final String? coinbasePool;

  /// Block height committed in the coinbase input (BIP-34).
  final int? coinbaseHeight;

  /// Printable text left in the coinbase signature script.
  final String? coinbaseTag;

  final int sigops;
  final String rawHex;
}

/// Full transaction detail.
class TxDetail {
  const TxDetail({
    required this.summary,
    required this.inputs,
    required this.outputs,
    required this.vsize,
    required this.feeRateSatVb,
    this.extras,
  });

  factory TxDetail.fromJson(Map<String, dynamic> json) {
    return TxDetail(
      summary: TxSummary.fromJson(json['summary'] as Map<String, dynamic>),
      inputs: (json['inputs'] as List)
          .map((io) => TxIo.fromJson(io as Map<String, dynamic>))
          .toList(),
      outputs: (json['outputs'] as List)
          .map((io) => TxIo.fromJson(io as Map<String, dynamic>))
          .toList(),
      vsize: json['vsize'] as int,
      feeRateSatVb: (json['fee_rate_sat_vb'] as num?)?.toDouble(),
      extras: json['extras'] == null
          ? null
          : TxExtras.fromJson(json['extras'] as Map<String, dynamic>),
    );
  }

  final TxSummary summary;
  final List<TxIo> inputs;
  final List<TxIo> outputs;
  final int vsize;
  final double? feeRateSatVb;
  final TxExtras? extras;
}

/// One unspent output.
class UtxoInfo {
  const UtxoInfo({
    required this.txid,
    required this.vout,
    required this.address,
    required this.valueSats,
    required this.status,
    required this.keychain,
    required this.derivationIndex,
  });

  factory UtxoInfo.fromJson(Map<String, dynamic> json) {
    return UtxoInfo(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      address: json['address'] as String?,
      valueSats: json['value_sats'] as int,
      status: TxStatus.fromJson(json['status'] as Map<String, dynamic>),
      keychain: json['keychain'] as String?,
      derivationIndex: json['derivation_index'] as int?,
    );
  }

  final String txid;
  final int vout;
  final String? address;
  final int valueSats;
  final TxStatus status;
  final String? keychain;
  final int? derivationIndex;

  String get outpoint => '$txid:$vout';
}

/// A receive address with its derivation index.
class AddressEntry {
  const AddressEntry({
    required this.index,
    required this.address,
    required this.used,
    this.derivation,
  });

  factory AddressEntry.fromJson(Map<String, dynamic> json) {
    return AddressEntry(
      index: json['index'] as int,
      address: json['address'] as String,
      used: json['used'] as bool,
      derivation: json['derivation'] as String?,
    );
  }

  final int index;
  final String address;
  final bool used;

  /// Absolute or relative derivation path (`m/84'/1'/0'/0/5` or `0/5`);
  /// null for a single watched address.
  final String? derivation;
}

/// One row of the address audit list.
class AddressRow {
  const AddressRow({
    required this.index,
    required this.address,
    required this.used,
    required this.balanceSats,
  });

  factory AddressRow.fromJson(Map<String, dynamic> json) {
    return AddressRow(
      index: json['index'] as int,
      address: json['address'] as String,
      used: json['used'] as bool,
      balanceSats: json['balance_sats'] as int,
    );
  }

  final int index;
  final String address;

  /// Whether the chain has seen this address used.
  final bool used;

  /// Sum of the unspent outputs currently on this address.
  final int balanceSats;
}

/// Revealed addresses of a wallet, by keychain, capped by the core.
class AddressList {
  const AddressList({
    required this.external,
    required this.internal,
    this.truncated = false,
  });

  factory AddressList.fromJson(Map<String, dynamic> json) {
    return AddressList(
      external: (json['external'] as List)
          .map((row) => AddressRow.fromJson(row as Map<String, dynamic>))
          .toList(),
      internal: (json['internal'] as List)
          .map((row) => AddressRow.fromJson(row as Map<String, dynamic>))
          .toList(),
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final List<AddressRow> external;

  /// Change addresses; empty when none were revealed (or for wallets
  /// without a change descriptor).
  final List<AddressRow> internal;

  /// True when a keychain had more rows than the core's cap.
  final bool truncated;
}

/// Keep only one direction of transactions in an export.
enum ExportDirection {
  incoming('incoming', 'Received'),
  outgoing('outgoing', 'Sent');

  const ExportDirection(this.id, this.label);

  final String id;
  final String label;
}

/// Filters for a transaction export. Empty options export everything.
class ExportOptions {
  const ExportOptions({
    this.from,
    this.to,
    this.direction,
    this.includePending = true,
  });

  /// Unix seconds, inclusive lower bound on the confirmation time.
  final int? from;

  /// Unix seconds, inclusive upper bound on the confirmation time.
  final int? to;
  final ExportDirection? direction;

  /// Pending transactions have no date: they only pass when no date
  /// bound is set.
  final bool includePending;

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'direction': direction?.id,
    'include_pending': includePending,
  };
}

/// A built export, ready to write.
class ExportResult {
  const ExportResult({required this.csv, required this.rows});

  factory ExportResult.fromJson(Map<String, dynamic> json) {
    return ExportResult(csv: json['csv'] as String, rows: json['rows'] as int);
  }

  final String csv;
  final int rows;
}

/// Everything a wallet view needs.
class WalletSnapshot {
  const WalletSnapshot({
    required this.meta,
    required this.balance,
    required this.txs,
    required this.tipHeight,
    this.truncated = false,
  });

  factory WalletSnapshot.fromJson(Map<String, dynamic> json) {
    return WalletSnapshot(
      meta: WalletMeta.fromJson(json['meta'] as Map<String, dynamic>),
      balance: BalanceSnapshot.fromJson(
        json['balance'] as Map<String, dynamic>,
      ),
      txs: (json['txs'] as List)
          .map((tx) => TxSummary.fromJson(tx as Map<String, dynamic>))
          .toList(),
      tipHeight: json['tip_height'] as int,
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final WalletMeta meta;
  final BalanceSnapshot balance;
  final List<TxSummary> txs;
  final int tipHeight;

  /// True when the transaction list is partial (busy watched address);
  /// the balance stays exact.
  final bool truncated;
}

/// Outcome of syncing one wallet.
/// A transaction a sync brought in for the first time.
class NewTx {
  const NewTx({
    required this.txid,
    required this.netSats,
    required this.confirmed,
  });

  factory NewTx.fromJson(Map<String, dynamic> json) {
    return NewTx(
      txid: json['txid'] as String,
      netSats: json['net_sats'] as int,
      confirmed: json['confirmed'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'txid': txid,
    'net_sats': netSats,
    'confirmed': confirmed,
  };

  final String txid;

  /// Net effect on the wallet, in sats, signed like a summary.
  final int netSats;
  final bool confirmed;
}

/// How far a transaction had come when it was announced.
enum TxStage {
  mempool('mempool'),
  confirmed('confirmed');

  const TxStage(this.id);

  final String id;

  static TxStage fromId(String? id) =>
      id == 'confirmed' ? TxStage.confirmed : TxStage.mempool;
}

/// One transaction to announce, handed out once per stage by the core.
class LiveTx {
  const LiveTx({
    required this.walletId,
    required this.txid,
    required this.netSats,
    required this.stage,
  });

  factory LiveTx.fromJson(Map<String, dynamic> json) {
    return LiveTx(
      walletId: json['wallet_id'] as String,
      txid: json['txid'] as String,
      netSats: json['net_sats'] as int,
      stage: TxStage.fromId(json['stage'] as String?),
    );
  }

  final String walletId;
  final String txid;
  final int netSats;
  final TxStage stage;
}

/// Where the live watch stands.
enum WatchState {
  off('off'),
  connecting('connecting'),
  connected('connected'),
  reconnecting('reconnecting'),
  polling('polling');

  const WatchState(this.id);

  final String id;

  static WatchState fromId(String? id) {
    for (final state in WatchState.values) {
      if (state.id == id) return state;
    }
    return WatchState.off;
  }
}

/// How changes reach the watch.
enum WatchTransport {
  electrum('electrum', 'Electrum'),
  mempoolWebsocket('mempool_websocket', 'mempool'),
  esploraPolling('esplora_polling', 'Esplora');

  const WatchTransport(this.id, this.label);

  final String id;
  final String label;

  static WatchTransport? fromId(String? id) {
    for (final transport in WatchTransport.values) {
      if (transport.id == id) return transport;
    }
    return null;
  }
}

/// What a screen, or the permanent notification, shows about the live
/// watch. Not the premium server's watch: that one is in premium.dart.
class LiveWatchStatus {
  const LiveWatchStatus({
    this.state = WatchState.off,
    this.transport,
    this.server,
    this.detail,
    this.watchedScripts = 0,
    this.pushedScripts = 0,
  });

  factory LiveWatchStatus.fromJson(Map<String, dynamic> json) {
    return LiveWatchStatus(
      state: WatchState.fromId(json['state'] as String?),
      transport: WatchTransport.fromId(json['transport'] as String?),
      server: json['server'] as String?,
      detail: json['detail'] as String?,
      watchedScripts: json['watched_scripts'] as int? ?? 0,
      pushedScripts: json['pushed_scripts'] as int? ?? 0,
    );
  }

  final WatchState state;
  final WatchTransport? transport;

  /// The host in use or being tried, never a full address.
  final String? server;

  /// Why the last connection failed, while reconnecting.
  final String? detail;
  final int watchedScripts;
  final int pushedScripts;
}

/// What a running live watch says.
sealed class LiveEvent {
  const LiveEvent();

  /// Null for an event this build does not know: a newer core may say
  /// more, and what is not understood is not acted on.
  static LiveEvent? fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'transaction':
        return LiveTransaction(LiveTx.fromJson(json));
      case 'wallet_synced':
        return LiveWalletSynced(
          SyncReport.fromJson(json['report'] as Map<String, dynamic>),
        );
      case 'sync_failed':
        return LiveSyncFailed(
          walletId: json['wallet_id'] as String,
          message: json['message'] as String? ?? '',
        );
      case 'new_block':
        return LiveNewBlock(json['height'] as int);
      case 'status':
        return LiveStatusChanged(LiveWatchStatus.fromJson(json));
      case 'stopped':
        return const LiveStopped();
    }
    return null;
  }
}

/// Announce this. Handed out once per transaction and stage.
class LiveTransaction extends LiveEvent {
  const LiveTransaction(this.tx);
  final LiveTx tx;
}

/// A wallet was synced because it moved: refresh what shows it.
class LiveWalletSynced extends LiveEvent {
  const LiveWalletSynced(this.report);
  final SyncReport report;
}

class LiveSyncFailed extends LiveEvent {
  const LiveSyncFailed({required this.walletId, required this.message});
  final String walletId;
  final String message;
}

class LiveNewBlock extends LiveEvent {
  const LiveNewBlock(this.height);
  final int height;
}

class LiveStatusChanged extends LiveEvent {
  const LiveStatusChanged(this.status);
  final LiveWatchStatus status;
}

/// The watch ended: stopped by the app, or by the vault locking.
class LiveStopped extends LiveEvent {
  const LiveStopped();
}

class SyncReport {
  const SyncReport({
    required this.walletId,
    required this.newTxCount,
    required this.balance,
    required this.tipHeight,
    required this.tookMs,
    required this.backend,
    this.newTxs = const [],
    this.confirmedTxs = const [],
  });

  factory SyncReport.fromJson(Map<String, dynamic> json) {
    return SyncReport(
      walletId: json['wallet_id'] as String,
      newTxCount: json['new_tx_count'] as int,
      newTxs: ((json['new_txs'] as List?) ?? const [])
          .map((e) => NewTx.fromJson(e as Map<String, dynamic>))
          .toList(),
      confirmedTxs: ((json['confirmed_txs'] as List?) ?? const [])
          .map((e) => NewTx.fromJson(e as Map<String, dynamic>))
          .toList(),
      balance: BalanceSnapshot.fromJson(
        json['balance'] as Map<String, dynamic>,
      ),
      tipHeight: json['tip_height'] as int,
      tookMs: json['took_ms'] as int,
      backend: json['backend'] as String,
    );
  }

  final String walletId;
  final int newTxCount;

  /// The same transactions, one line each: what a notification says.
  final List<NewTx> newTxs;

  /// Transactions the wallet already held unconfirmed and that this
  /// sync found in a block. One first seen already confirmed is in
  /// [newTxs] only.
  final List<NewTx> confirmedTxs;

  /// Whether this sync found anything worth saying.
  bool get hasNews =>
      newTxs.isNotEmpty || confirmedTxs.isNotEmpty || newTxCount > 0;

  /// What the core needs to decide which of these nobody has announced
  /// yet: the wallet and the two lists.
  Map<String, dynamic> toFindingsJson() => {
    'wallet_id': walletId,
    'new_txs': [for (final tx in newTxs) tx.toJson()],
    'confirmed_txs': [for (final tx in confirmedTxs) tx.toJson()],
  };
  final BalanceSnapshot balance;
  final int tipHeight;
  final int tookMs;
  final String backend;
}

/// Outcome of syncing every wallet of a workspace.
class SyncAllReport {
  const SyncAllReport({required this.reports, required this.failures});

  factory SyncAllReport.fromJson(Map<String, dynamic> json) {
    return SyncAllReport(
      reports: (json['reports'] as List)
          .map((r) => SyncReport.fromJson(r as Map<String, dynamic>))
          .toList(),
      failures: (json['failures'] as List)
          .map((f) => SyncFailure.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<SyncReport> reports;
  final List<SyncFailure> failures;
}

/// One wallet that failed to sync; the others are unaffected.
class SyncFailure {
  const SyncFailure({required this.walletId, required this.message});

  factory SyncFailure.fromJson(Map<String, dynamic> json) {
    return SyncFailure(
      walletId: json['wallet_id'] as String,
      message: json['message'] as String,
    );
  }

  final String walletId;
  final String message;
}

/// Protocol a public server speaks.
enum ServerProtocol {
  esplora('esplora', 'Esplora'),
  electrum('electrum', 'Electrum');

  const ServerProtocol(this.id, this.label);

  final String id;

  /// Marker shown next to the host in the settings.
  final String label;

  static ServerProtocol fromId(String id) =>
      ServerProtocol.values.firstWhere((p) => p.id == id);
}

/// One public server offered in the settings.
class PublicServer {
  const PublicServer({
    required this.id,
    required this.label,
    required this.protocol,
    required this.url,
    this.selfSigned = false,
  });

  factory PublicServer.fromJson(Map<String, dynamic> json) {
    return PublicServer(
      id: json['id'] as String,
      label: json['label'] as String,
      protocol: ServerProtocol.fromId(json['protocol'] as String),
      url: json['url'] as String,
      selfSigned: json['self_signed'] as bool? ?? false,
    );
  }

  /// Stable key stored in the settings; it outlives a URL change.
  final String id;

  /// What the settings show: the host, nothing else.
  final String label;
  final ServerProtocol protocol;

  /// Endpoint Gerfaut talks to.
  final String url;

  /// Whether this server signs its own certificate, so the picker can
  /// say it before it is chosen rather than after.
  final bool selfSigned;
}

/// Chain data source for one network.
sealed class BackendConfig {
  const BackendConfig();

  factory BackendConfig.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'public_esplora' => PublicEsplora(server: json['server'] as String?),
      'custom_esplora' => CustomEsplora(url: json['url'] as String),
      'custom_electrum' => CustomElectrum(url: json['url'] as String),
      final other => throw FormatException('unknown backend type: $other'),
    };
  }

  Map<String, dynamic> toJson();
}

/// One of the public servers the core lists. Without a chosen operator
/// the public Esplora instances are rotated through; with one, that
/// server answers alone.
class PublicEsplora extends BackendConfig {
  const PublicEsplora({this.server});

  /// Identifier of the chosen server, null for the automatic rotation.
  final String? server;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'public_esplora',
    // Omitted when unset, so an automatic configuration serializes
    // exactly as every stored vault already carries it.
    if (server != null) 'server': server,
  };
}

class CustomEsplora extends BackendConfig {
  const CustomEsplora({required this.url});

  final String url;

  @override
  Map<String, dynamic> toJson() => {'type': 'custom_esplora', 'url': url};
}

class CustomElectrum extends BackendConfig {
  const CustomElectrum({required this.url});

  final String url;

  @override
  Map<String, dynamic> toJson() => {'type': 'custom_electrum', 'url': url};
}

/// Global settings stored in the vault.
class Settings {
  const Settings({
    required this.activeNetwork,
    required this.backends,
    required this.appPrefs,
    this.gapLimit = 20,
    this.electrumCerts = const {},
    this.appLock,
    this.tor = TorSettings.automatic,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    final backends = <Network, BackendConfig>{};
    (json['backends'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      backends[Network.fromId(key)] = BackendConfig.fromJson(
        value as Map<String, dynamic>,
      );
    });
    return Settings(
      activeNetwork: Network.fromId(json['active_network'] as String),
      backends: backends,
      appPrefs: (json['app_prefs'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as String),
      ),
      gapLimit: json['gap_limit'] as int? ?? 20,
      electrumCerts: (json['electrum_certs'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as String)),
      appLock: json['app_lock'] == null
          ? null
          : AppLock.fromJson(json['app_lock'] as Map<String, dynamic>),
      tor: json['tor'] == null
          ? TorSettings.automatic
          : TorSettings.fromJson(json['tor'] as Map<String, dynamic>),
    );
  }

  final Network activeNetwork;
  final Map<Network, BackendConfig> backends;
  final Map<String, String> appPrefs;

  /// Global gap limit applied to every descriptor wallet on sync.
  final int gapLimit;

  /// Electrum certificates the user accepted, by `host:port`. The core
  /// stores them the way every tool prints a fingerprint: uppercase hex
  /// pairs joined by colons.
  final Map<String, String> electrumCerts;

  /// The lock in place, without its hash; null when there is none.
  final AppLock? appLock;

  /// How `.onion` backends reach Tor.
  final TorSettings tor;

  /// Backend for a network, falling back to the public default.
  BackendConfig backendFor(Network network) =>
      backends[network] ?? const PublicEsplora();
}

/// What kind of secret unlocks the app.
enum LockKind {
  pin('pin', 'PIN'),
  password('password', 'Password');

  const LockKind(this.id, this.label);

  final String id;
  final String label;

  static LockKind fromId(String id) =>
      LockKind.values.firstWhere((k) => k.id == id);
}

/// The app lock as the apps see it: kind, never the hash.
///
/// When it comes back is not a setting: the secret is asked when the
/// app opens and again once Gerfaut has been to the background.
class AppLock {
  const AppLock({required this.kind, required this.biometric});

  factory AppLock.fromJson(Map<String, dynamic> json) {
    return AppLock(
      kind: LockKind.fromId(json['kind'] as String),
      biometric: json['biometric'] as bool? ?? false,
    );
  }

  final LockKind kind;

  /// Whether the phone's biometric prompt may stand in for the secret.
  final bool biometric;
}

/// Outcome of an unlock attempt.
class LockVerdict {
  const LockVerdict({
    required this.unlocked,
    required this.failures,
    required this.retryAfterSecs,
  });

  factory LockVerdict.fromJson(Map<String, dynamic> json) {
    return LockVerdict(
      unlocked: json['unlocked'] as bool,
      failures: json['failures'] as int,
      retryAfterSecs: json['retry_after_secs'] as int,
    );
  }

  final bool unlocked;

  /// Consecutive failures so far; zero once unlocked.
  final int failures;

  /// Seconds before the next attempt is looked at; zero when it can be.
  final int retryAfterSecs;
}

/// One server's certificate, and the key an acceptance is recorded
/// against. The core flattens the status into the same object; this
/// keeps the two apart so a screen can switch on the status alone.
class CertificateReport {
  const CertificateReport({required this.host, required this.status});

  factory CertificateReport.fromJson(Map<String, dynamic> json) {
    return CertificateReport(
      host: json['host'] as String,
      status: CertificateStatus.fromJson(json),
    );
  }

  /// `host:port`, scheme and path stripped.
  final String host;
  final CertificateStatus status;
}

/// What a handshake concluded about a server's certificate, mirroring
/// `CertificateStatus` in gerfaut-core.
sealed class CertificateStatus {
  const CertificateStatus();

  factory CertificateStatus.fromJson(Map<String, dynamic> json) {
    return switch (json['status'] as String) {
      'not_tls' => const NotTlsCertificate(),
      'tor' => const TorCertificate(),
      'trusted' => const TrustedCertificate(),
      'pinned' => PinnedCertificate(fingerprint: json['fingerprint'] as String),
      'unknown' => UnknownCertificate(
        fingerprint: json['fingerprint'] as String,
        reason: json['reason'] as String,
        subject: json['subject'] as String?,
        expires: json['expires'] as int?,
      ),
      'changed' => ChangedCertificate(
        stored: json['stored'] as String,
        presented: json['presented'] as String,
      ),
      'unreachable' => UnreachableCertificate(detail: json['detail'] as String),
      final other => throw FormatException('unknown status: $other'),
    };
  }
}

/// Plain TCP: there is no certificate, and nothing is encrypted.
class NotTlsCertificate extends CertificateStatus {
  const NotTlsCertificate();
}

/// An onion address is the server's identity; a certificate on top
/// authenticates nothing more.
class TorCertificate extends CertificateStatus {
  const TorCertificate();
}

/// A public certificate authority vouches for it.
class TrustedCertificate extends CertificateStatus {
  const TrustedCertificate();
}

/// Exactly the certificate accepted for this host.
class PinnedCertificate extends CertificateStatus {
  const PinnedCertificate({required this.fingerprint});

  final String fingerprint;
}

/// No authority vouches for it and this host has no accepted
/// certificate yet: the user decides, once.
class UnknownCertificate extends CertificateStatus {
  const UnknownCertificate({
    required this.fingerprint,
    required this.reason,
    this.subject,
    this.expires,
  });

  final String fingerprint;

  /// Why no authority vouches for it, in words a user can act on.
  final String reason;

  /// What the certificate calls itself, when it says so.
  final String? subject;

  /// When it stops being valid, in seconds since the epoch.
  final int? expires;
}

/// This host was accepted with a different certificate. Something
/// changed on the server, or something sits in between.
class ChangedCertificate extends CertificateStatus {
  const ChangedCertificate({required this.stored, required this.presented});

  final String stored;
  final String presented;
}

/// The server could not be reached, so nothing can be said about its
/// certificate yet.
class UnreachableCertificate extends CertificateStatus {
  const UnreachableCertificate({required this.detail});

  final String detail;
}

/// Where a fiat quote comes from. All endpoints are public and keyless.
enum PriceSource {
  coingecko('coingecko', 'CoinGecko'),
  kraken('kraken', 'Kraken'),
  mempoolSpace('mempool_space', 'mempool.space');

  const PriceSource(this.id, this.label);

  final String id;
  final String label;

  /// Whether this source quotes a currency without an API key. Kraken
  /// lists seven fiat pairs against XBT and the mempool projects
  /// publish the same seven; CoinGecko publishes them all.
  bool supportsCurrency(FiatCurrency currency) =>
      this == PriceSource.coingecko || currency.reach == CurrencyReach.every;

  static PriceSource? fromId(String? id) {
    for (final source in PriceSource.values) {
      if (source.id == id) return source;
    }
    return null;
  }
}

/// How many price sources quote a currency.
enum CurrencyReach {
  /// Every source quotes it: the seven Kraken and the mempool projects
  /// publish.
  every,

  /// CoinGecko alone quotes it.
  coingeckoOnly,
}

/// Display currencies offered in the settings, in display order.
///
/// The first seven are quoted by every source. The rest are the
/// currencies of the most populous countries and of the places where
/// Bitcoin is most used; CoinGecko is the only keyless source that
/// publishes them.
enum FiatCurrency {
  eur('eur', 'EUR', 'Euro', CurrencyReach.every),
  usd('usd', 'USD', 'US dollar', CurrencyReach.every),
  gbp('gbp', 'GBP', 'Pound sterling', CurrencyReach.every),
  chf('chf', 'CHF', 'Swiss franc', CurrencyReach.every),
  jpy('jpy', 'JPY', 'Japanese yen', CurrencyReach.every),
  cad('cad', 'CAD', 'Canadian dollar', CurrencyReach.every),
  aud('aud', 'AUD', 'Australian dollar', CurrencyReach.every),
  inr('inr', 'INR', 'Indian rupee', CurrencyReach.coingeckoOnly),
  cny('cny', 'CNY', 'Chinese yuan', CurrencyReach.coingeckoOnly),
  brl('brl', 'BRL', 'Brazilian real', CurrencyReach.coingeckoOnly),
  ngn('ngn', 'NGN', 'Nigerian naira', CurrencyReach.coingeckoOnly),
  idr('idr', 'IDR', 'Indonesian rupiah', CurrencyReach.coingeckoOnly),
  pkr('pkr', 'PKR', 'Pakistani rupee', CurrencyReach.coingeckoOnly),
  bdt('bdt', 'BDT', 'Bangladeshi taka', CurrencyReach.coingeckoOnly),
  rub('rub', 'RUB', 'Russian ruble', CurrencyReach.coingeckoOnly),
  mxn('mxn', 'MXN', 'Mexican peso', CurrencyReach.coingeckoOnly),
  php('php', 'PHP', 'Philippine peso', CurrencyReach.coingeckoOnly),
  vnd('vnd', 'VND', 'Vietnamese dong', CurrencyReach.coingeckoOnly),
  // `try` is a Dart keyword, so only the constant is spelled out; the
  // identifier the core stores stays `try`.
  tryLira('try', 'TRY', 'Turkish lira', CurrencyReach.coingeckoOnly),
  ars('ars', 'ARS', 'Argentine peso', CurrencyReach.coingeckoOnly),
  krw('krw', 'KRW', 'South Korean won', CurrencyReach.coingeckoOnly),
  zar('zar', 'ZAR', 'South African rand', CurrencyReach.coingeckoOnly),
  thb('thb', 'THB', 'Thai baht', CurrencyReach.coingeckoOnly),
  uah('uah', 'UAH', 'Ukrainian hryvnia', CurrencyReach.coingeckoOnly),
  pln('pln', 'PLN', 'Polish zloty', CurrencyReach.coingeckoOnly),
  sek('sek', 'SEK', 'Swedish krona', CurrencyReach.coingeckoOnly),
  sgd('sgd', 'SGD', 'Singapore dollar', CurrencyReach.coingeckoOnly),
  hkd('hkd', 'HKD', 'Hong Kong dollar', CurrencyReach.coingeckoOnly),
  aed('aed', 'AED', 'UAE dirham', CurrencyReach.coingeckoOnly),
  nzd('nzd', 'NZD', 'New Zealand dollar', CurrencyReach.coingeckoOnly);

  const FiatCurrency(this.id, this.code, this.label, this.reach);

  final String id;

  /// ISO 4217 code, uppercase.
  final String code;

  /// English name, so a list of thirty codes stays readable.
  final String label;

  /// Which sources quote this currency.
  final CurrencyReach reach;

  static FiatCurrency? fromId(String? id) {
    for (final currency in FiatCurrency.values) {
      if (currency.id == id) return currency;
    }
    return null;
  }
}

/// One BTC priced in a fiat currency, at a point in time.
class PriceQuote {
  const PriceQuote({
    required this.rate,
    required this.currency,
    required this.source,
    required this.at,
  });

  factory PriceQuote.fromJson(Map<String, dynamic> json) {
    return PriceQuote(
      rate: (json['rate'] as num).toDouble(),
      currency: FiatCurrency.fromId(json['currency'] as String)!,
      source: PriceSource.fromId(json['source'] as String)!,
      at: json['at'] as int,
    );
  }

  /// Price of 1 BTC in the currency.
  final double rate;
  final FiatCurrency currency;
  final PriceSource source;

  /// Unix timestamp, seconds, when the quote was fetched.
  final int at;
}

/// Outcome of a release check.
class UpdateCheck {
  const UpdateCheck({
    required this.latest,
    required this.url,
    required this.updateAvailable,
  });

  factory UpdateCheck.fromJson(Map<String, dynamic> json) {
    return UpdateCheck(
      latest: json['latest'] as String,
      url: json['url'] as String,
      updateAvailable: json['update_available'] as bool,
    );
  }

  /// Latest published tag, for example `v0.2.0`.
  final String latest;

  /// Web page of the latest release.
  final String url;

  /// True when the latest tag is newer than the running version.
  final bool updateAvailable;
}

/// Envelope recognized around a scanned QR frame.
enum QrFormat {
  /// The frame is the material itself.
  plain('plain'),

  /// Uniform Resource (`ur:`), single or multi-part.
  ur('ur'),

  /// BBQr (`B$`), single or multi-part.
  bbqr('bbqr');

  const QrFormat(this.id);

  final String id;

  static QrFormat fromId(String id) =>
      QrFormat.values.firstWhere((f) => f.id == id);
}

/// Where a scan stands after the frames seen so far.
class QrProgress {
  const QrProgress({
    required this.format,
    required this.received,
    required this.total,
    required this.complete,
    this.text,
  });

  factory QrProgress.fromJson(Map<String, dynamic> json) {
    return QrProgress(
      format: QrFormat.fromId(json['format'] as String),
      received: json['received'] as int,
      total: json['total'] as int,
      complete: json['complete'] as bool,
      text: json['text'] as String?,
    );
  }

  final QrFormat format;

  /// Distinct parts received (for a UR: fragments resolved).
  final int received;

  /// Parts announced by the envelope; 1 for a plain frame.
  final int total;
  final bool complete;

  /// The assembled text, once [complete].
  final String? text;

  /// True while an animated code is still being collected.
  bool get inProgress => total > 1 && !complete;
}

/// The container a transaction to broadcast came in.
enum TxSource {
  rawTransaction('raw_transaction', 'Raw transaction'),
  psbt('psbt', 'PSBT');

  const TxSource(this.id, this.label);

  final String id;
  final String label;

  static TxSource fromId(String id) =>
      TxSource.values.firstWhere((s) => s.id == id);
}

/// A watched wallet one side of a transaction belongs to.
class WalletRef {
  const WalletRef({required this.id, required this.name});

  factory WalletRef.fromJson(Map<String, dynamic> json) {
    return WalletRef(id: json['id'] as String, name: json['name'] as String);
  }

  final String id;
  final String name;
}

/// One input of a transaction to broadcast.
class TxInputPreview {
  const TxInputPreview({
    required this.txid,
    required this.vout,
    required this.signed,
    this.valueSats,
    this.address,
    this.wallet,
  });

  factory TxInputPreview.fromJson(Map<String, dynamic> json) {
    return TxInputPreview(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      valueSats: json['value_sats'] as int?,
      address: json['address'] as String?,
      signed: json['signed'] as bool,
      wallet: json['wallet'] == null
          ? null
          : WalletRef.fromJson(json['wallet'] as Map<String, dynamic>),
    );
  }

  final String txid;
  final int vout;

  /// Value of the coin spent, when the container, a watched wallet or
  /// the backend knew it.
  final int? valueSats;
  final String? address;

  /// Whether the input carries what the network needs to accept it.
  final bool signed;

  /// The watched wallet that owns the coin, when any.
  final WalletRef? wallet;

  String get outpoint => '$txid:$vout';
}

/// One output of a transaction to broadcast.
class TxOutputPreview {
  const TxOutputPreview({
    required this.index,
    required this.valueSats,
    this.address,
    this.opReturn,
    this.wallet,
    this.change = false,
  });

  factory TxOutputPreview.fromJson(Map<String, dynamic> json) {
    return TxOutputPreview(
      index: json['index'] as int,
      valueSats: json['value_sats'] as int,
      address: json['address'] as String?,
      opReturn: json['op_return'] == null
          ? null
          : OpReturnData.fromJson(json['op_return'] as Map<String, dynamic>),
      wallet: json['wallet'] == null
          ? null
          : WalletRef.fromJson(json['wallet'] as Map<String, dynamic>),
      change: json['change'] as bool? ?? false,
    );
  }

  final int index;
  final int valueSats;
  final String? address;
  final OpReturnData? opReturn;

  /// The watched wallet that receives this output, when any.
  final WalletRef? wallet;

  /// Output on a watched wallet's change keychain.
  final bool change;
}

/// What a caution on the broadcast preview is about.
enum TxWarningKind {
  unsigned('unsigned'),
  highFeeRate('high_fee_rate'),
  highFeeShare('high_fee_share'),
  locked('locked'),
  inputUnknown('input_unknown'),
  inputSpent('input_spent'),
  inputMismatch('input_mismatch'),
  feeUnknown('fee_unknown'),
  dustOutput('dust_output'),
  spendsWatched('spends_watched'),

  /// A kind this build does not know; shown with a generic icon.
  other('other');

  const TxWarningKind(this.id);

  final String id;

  static TxWarningKind fromId(String id) {
    for (final kind in TxWarningKind.values) {
      if (kind.id == id) return kind;
    }
    return TxWarningKind.other;
  }
}

/// How loudly a caution is read.
///
/// The core answers the one question — can the person lose funds or
/// lose privacy? — and sends the answer along with the caution. A
/// screen reads it and never derives it: two hand-written tables, one
/// per platform, is precisely how the tones drifted apart.
enum TxSeverity {
  /// Funds or privacy are at stake: the red panel.
  alert('alert'),

  /// Worth reading; nothing is at risk: the amber one.
  info('info');

  const TxSeverity(this.id);

  final String id;

  /// Anything this build cannot name reads as [info] — the tone a
  /// [TxWarningKind.other] gets too. A kind added by a newer core still
  /// arrives with its own severity, so this only applies to a wire that
  /// carries none, and quiet is the safe way to be wrong about a tone.
  static TxSeverity fromId(String? id) {
    for (final severity in TxSeverity.values) {
      if (severity.id == id) return severity;
    }
    return TxSeverity.info;
  }
}

/// A caution to read before broadcasting. Never blocks: the preview
/// only makes the transaction legible.
class TxWarning {
  const TxWarning({
    required this.kind,
    required this.message,
    required this.severity,
  });

  factory TxWarning.fromJson(Map<String, dynamic> json) {
    return TxWarning(
      kind: TxWarningKind.fromId(json['kind'] as String),
      message: json['message'] as String,
      severity: TxSeverity.fromId(json['severity'] as String?),
    );
  }

  final TxWarningKind kind;
  final String message;

  /// The tone to read it in, as the core decided it.
  final TxSeverity severity;
}

/// Everything shown before broadcasting a transaction.
class TxPreview {
  const TxPreview({
    required this.txid,
    required this.source,
    required this.network,
    required this.inputs,
    required this.outputs,
    required this.vsize,
    required this.weight,
    required this.size,
    required this.version,
    required this.locktime,
    required this.rbf,
    required this.ready,
    this.feeSats,
    this.feeRateSatVb,
    this.warnings = const [],
    this.hex,
  });

  factory TxPreview.fromJson(Map<String, dynamic> json) {
    return TxPreview(
      txid: json['txid'] as String,
      source: TxSource.fromId(json['source'] as String),
      network: Network.fromId(json['network'] as String),
      inputs: (json['inputs'] as List)
          .map((i) => TxInputPreview.fromJson(i as Map<String, dynamic>))
          .toList(),
      outputs: (json['outputs'] as List)
          .map((o) => TxOutputPreview.fromJson(o as Map<String, dynamic>))
          .toList(),
      feeSats: json['fee_sats'] as int?,
      feeRateSatVb: (json['fee_rate_sat_vb'] as num?)?.toDouble(),
      vsize: json['vsize'] as int,
      weight: json['weight'] as int,
      size: json['size'] as int,
      version: json['version'] as int,
      locktime: json['locktime'] as int,
      rbf: json['rbf'] as bool,
      ready: json['ready'] as bool,
      warnings: ((json['warnings'] as List?) ?? const [])
          .map((w) => TxWarning.fromJson(w as Map<String, dynamic>))
          .toList(),
      hex: json['hex'] as String?,
    );
  }

  final String txid;
  final TxSource source;
  final Network network;
  final List<TxInputPreview> inputs;
  final List<TxOutputPreview> outputs;

  /// Fee in sats, when every input's value is known.
  final int? feeSats;
  final double? feeRateSatVb;
  final int vsize;
  final int weight;
  final int size;
  final int version;

  /// Absolute lock time as the consensus integer: a block height below
  /// 500 000 000, a unix timestamp above.
  final int locktime;
  final bool rbf;

  /// Every input is signed and the transaction can be sent.
  final bool ready;
  final List<TxWarning> warnings;

  /// The transaction as the network takes it, present only when ready.
  final String? hex;

  /// Whether a coin this transaction spends went unconfirmed. The core
  /// says so with an `input_unknown` caution, which covers a backend
  /// that does not know the coin as well as no backend answering at
  /// all; either way the value shown for it, when the file carries one,
  /// and the fee resting on it are the file's own word, not the chain's.
  bool get inputsUnconfirmed =>
      warnings.any((w) => w.kind == TxWarningKind.inputUnknown);
}

/// Outcome of a broadcast.
class BroadcastReport {
  const BroadcastReport({
    required this.txid,
    required this.backend,
    required this.at,
  });

  factory BroadcastReport.fromJson(Map<String, dynamic> json) {
    return BroadcastReport(
      txid: json['txid'] as String,
      backend: json['backend'] as String,
      at: json['at'] as int,
    );
  }

  final String txid;

  /// Host that accepted the transaction.
  final String backend;

  /// Unix timestamp, seconds.
  final int at;
}

/// Where a broadcast transaction stands, as the backend sees it.
class BroadcastStatus {
  const BroadcastStatus({
    required this.txid,
    required this.found,
    required this.confirmed,
    required this.confirmations,
    required this.backend,
    required this.at,
    this.blockHeight,
  });

  factory BroadcastStatus.fromJson(Map<String, dynamic> json) {
    return BroadcastStatus(
      txid: json['txid'] as String,
      found: json['found'] as bool,
      confirmed: json['confirmed'] as bool,
      blockHeight: json['block_height'] as int?,
      confirmations: json['confirmations'] as int,
      backend: json['backend'] as String,
      at: json['at'] as int,
    );
  }

  final String txid;

  /// Whether the backend knows the transaction at all: it can drop out
  /// of the mempool, evicted or replaced.
  final bool found;
  final bool confirmed;
  final int? blockHeight;
  final int confirmations;
  final String backend;
  final int at;
}

/// A transaction this app sent, kept so it can be checked again after a
/// restart. Stored as JSON under the `broadcast.recent` preference.
class RecentBroadcast {
  const RecentBroadcast({
    required this.txid,
    required this.network,
    required this.hex,
    required this.at,
  });

  factory RecentBroadcast.fromJson(Map<String, dynamic> json) {
    return RecentBroadcast(
      txid: json['txid'] as String,
      network: Network.fromId(json['network'] as String),
      hex: json['hex'] as String,
      at: json['at'] as int,
    );
  }

  final String txid;
  final Network network;

  /// The transaction as sent: what the status check decodes.
  final String hex;

  /// Unix timestamp, seconds, of the broadcast.
  final int at;

  Map<String, dynamic> toJson() => {
    'txid': txid,
    'network': network.id,
    'hex': hex,
    'at': at,
  };
}

// --- backup ------------------------------------------------------------

/// What to seal: which wallets (null for every wallet on every
/// network), and whether the node settings travel with them.
class BackupOptions {
  const BackupOptions({this.walletIds, this.includeSettings = false});

  final List<String>? walletIds;
  final bool includeSettings;

  Map<String, dynamic> toJson() => {
    'wallet_ids': walletIds,
    'include_settings': includeSettings,
  };
}

/// A sealed backup in both transport forms.
class BackupBundle {
  const BackupBundle({
    required this.data,
    required this.frames,
    required this.walletCount,
    required this.sizeBytes,
  });

  factory BackupBundle.fromJson(Map<String, dynamic> json) {
    return BackupBundle(
      data: json['data'] as String,
      frames: (json['frames'] as List).cast<String>(),
      walletCount: json['wallet_count'] as int,
      sizeBytes: json['size_bytes'] as int,
    );
  }

  /// Base64 of the encrypted file bytes.
  final String data;

  /// UR frames to loop as an animated QR.
  final List<String> frames;
  final int walletCount;
  final int sizeBytes;
}

/// One wallet of a backup, before it is restored.
class BackupWalletPreview {
  const BackupWalletPreview({
    required this.index,
    required this.name,
    required this.network,
    required this.kind,
    required this.alreadyWatched,
  });

  factory BackupWalletPreview.fromJson(Map<String, dynamic> json) {
    return BackupWalletPreview(
      index: json['index'] as int,
      name: json['name'] as String,
      network: Network.fromId(json['network'] as String),
      kind: WalletKind.fromJson(json['kind'] as Map<String, dynamic>),
      alreadyWatched: json['already_watched'] as bool,
    );
  }

  final int index;
  final String name;
  final Network network;
  final WalletKind kind;

  /// The same material is already watched here: restoring it again
  /// would be a duplicate.
  final bool alreadyWatched;
}

/// What a backup holds, listed before anything is added.
class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.wallets,
    required this.hasSettings,
    this.backends = const [],
    this.electrumHosts = const [],
  });

  factory BackupPreview.fromJson(Map<String, dynamic> json) {
    return BackupPreview(
      createdAt: json['created_at'] as int,
      wallets: (json['wallets'] as List)
          .map((w) => BackupWalletPreview.fromJson(w as Map<String, dynamic>))
          .toList(),
      hasSettings: json['has_settings'] as bool,
      backends: ((json['backends'] as List?) ?? const [])
          .map((b) => BackupBackend.fromJson(b as Map<String, dynamic>))
          .toList(),
      electrumHosts: ((json['electrum_hosts'] as List?) ?? const [])
          .map((h) => h as String)
          .toList(),
    );
  }

  final int createdAt;
  final List<BackupWalletPreview> wallets;
  final bool hasSettings;

  /// The node the settings would put in place, one entry per network.
  /// Empty when the backup carries no settings.
  final List<BackupBackend> backends;

  /// Every `host:port` whose Electrum certificate the settings would
  /// pin. Empty when the backup carries no settings.
  final List<String> electrumHosts;
}

/// One node a backup would put in place, as its preview names it.
class BackupBackend {
  const BackupBackend({required this.network, required this.backend});

  factory BackupBackend.fromJson(Map<String, dynamic> json) {
    return BackupBackend(
      network: Network.fromId(json['network'] as String),
      backend: json['backend'] as String,
    );
  }

  final Network network;

  /// The host alone, never a full URL: a URL may carry credentials.
  final String backend;
}

/// Which wallets to restore (null for all) and whether to apply the
/// node settings the backup carries.
class ImportChoices {
  const ImportChoices({this.indexes, this.applySettings = false});

  final List<int>? indexes;
  final bool applySettings;

  Map<String, dynamic> toJson() => {
    'indexes': indexes,
    'apply_settings': applySettings,
  };
}

class ImportReport {
  const ImportReport({
    required this.added,
    required this.skipped,
    required this.settingsApplied,
  });

  factory ImportReport.fromJson(Map<String, dynamic> json) {
    return ImportReport(
      added: (json['added'] as List)
          .map((w) => WalletMeta.fromJson(w as Map<String, dynamic>))
          .toList(),
      skipped: json['skipped'] as int,
      settingsApplied: json['settings_applied'] as bool,
    );
  }

  final List<WalletMeta> added;

  /// Wallets left out: already watched, or not chosen.
  final int skipped;
  final bool settingsApplied;
}

// --- tor ---------------------------------------------------------------

/// How `.onion` backends reach Tor.
enum TorMode {
  auto('auto', 'Automatic'),
  system('system', 'System Tor'),
  embedded('embedded', 'Built-in');

  const TorMode(this.id, this.label);

  final String id;
  final String label;

  static TorMode fromId(String id) =>
      TorMode.values.firstWhere((m) => m.id == id, orElse: () => TorMode.auto);
}

class TorSettings {
  const TorSettings({required this.mode, this.socksProxy});

  /// The default: a system daemon if one answers, else the built-in.
  static const TorSettings automatic = TorSettings(mode: TorMode.auto);

  factory TorSettings.fromJson(Map<String, dynamic> json) {
    return TorSettings(
      mode: TorMode.fromId(json['mode'] as String? ?? 'auto'),
      socksProxy: json['socks_proxy'] as String?,
    );
  }

  final TorMode mode;

  /// `host:port` of the system SOCKS proxy; null means 127.0.0.1:9050.
  final String? socksProxy;

  Map<String, dynamic> toJson() => {'mode': mode.id, 'socks_proxy': socksProxy};
}

/// Which Tor a route goes through.
enum TorVia {
  system('system', 'system Tor'),
  embedded('embedded', 'built-in Tor');

  const TorVia(this.id, this.label);

  final String id;
  final String label;

  static TorVia? fromId(String? id) {
    for (final via in TorVia.values) {
      if (via.id == id) return via;
    }
    return null;
  }
}

class TorRoute {
  const TorRoute({required this.socks, required this.via});

  factory TorRoute.fromJson(Map<String, dynamic> json) {
    return TorRoute(
      socks: json['socks'] as String,
      via: TorVia.fromId(json['via'] as String?) ?? TorVia.system,
    );
  }

  final String socks;
  final TorVia via;
}

/// Where Tor stands right now.
class TorStatus {
  const TorStatus({
    required this.mode,
    required this.socksProxy,
    required this.via,
    required this.socks,
    required this.running,
    required this.bootstrapped,
    required this.bootstrapPercent,
    required this.error,
    required this.embeddedAvailable,
  });

  factory TorStatus.fromJson(Map<String, dynamic> json) {
    return TorStatus(
      mode: TorMode.fromId(json['mode'] as String? ?? 'auto'),
      socksProxy: json['socks_proxy'] as String? ?? '127.0.0.1:9050',
      via: TorVia.fromId(json['via'] as String?),
      socks: json['socks'] as String?,
      running: json['running'] as bool? ?? false,
      bootstrapped: json['bootstrapped'] as bool? ?? false,
      bootstrapPercent: json['bootstrap_percent'] as int? ?? 0,
      error: json['error'] as String?,
      embeddedAvailable: json['embedded_available'] as bool? ?? false,
    );
  }

  final TorMode mode;

  /// The effective system proxy address.
  final String socksProxy;
  final TorVia? via;

  /// The SOCKS address in use, once a route was resolved.
  final String? socks;
  final bool running;
  final bool bootstrapped;
  final int bootstrapPercent;
  final String? error;

  /// Whether this build carries the built-in client.
  final bool embeddedAvailable;
}

// --- policy --------------------------------------------------------------

/// The shape of a wallet's policy, at a glance.
enum PolicyKind {
  /// One key, nothing else.
  singleKey('single_key'),

  /// One threshold of plain keys.
  multisig('multisig'),

  /// Anything with a timelock, a hash, or nested conditions.
  miniscript('miniscript'),

  /// A watched address: no descriptor to read.
  address('address');

  const PolicyKind(this.id);

  final String id;

  static PolicyKind fromId(String id) =>
      PolicyKind.values.firstWhere((k) => k.id == id);
}

/// What the time-based figures of a snapshot were measured against.
enum TimeBasis {
  /// The device clock. The chain's median time trails it by up to a
  /// couple of hours.
  wallClock('wall_clock');

  const TimeBasis(this.id);

  final String id;

  static TimeBasis fromId(String id) =>
      TimeBasis.values.firstWhere((b) => b.id == id);
}

/// What a spending branch is for, guessed by the core from its locks.
enum BranchRole {
  /// No timelock: the everyday path.
  primary('primary'),

  /// The shortest timelocked path.
  recovery('recovery'),

  /// The second shortest timelocked path.
  emergency('emergency'),

  /// Further timelocked paths, and paths with no key or needing a
  /// hash preimage.
  other('other');

  const BranchRole(this.id);

  final String id;

  static BranchRole fromId(String id) =>
      BranchRole.values.firstWhere((r) => r.id == id);
}

/// One key of the policy. The same extended key on two derivation
/// paths is one key.
class PolicyKey {
  const PolicyKey({
    required this.id,
    required this.label,
    required this.fingerprint,
    required this.originPath,
    required this.keyShort,
  });

  factory PolicyKey.fromJson(Map<String, dynamic> json) {
    return PolicyKey(
      id: json['id'] as String,
      label: json['label'] as String,
      fingerprint: json['fingerprint'] as String?,
      originPath: json['origin_path'] as String?,
      keyShort: json['key_short'] as String,
    );
  }

  /// Stable within the snapshot: `k0`, `k1`, ...
  final String id;

  /// `Key A`, `Key B`, ... then `Key 27` past the alphabet.
  final String label;

  /// Eight lowercase hex digits, when the key carries an origin.
  final String? fingerprint;

  /// Origin path, `m/48'/1'/0'/2'`, when the key carries one.
  final String? originPath;

  /// The key as written, shortened around an ellipsis.
  final String keyShort;
}

/// An absolute lock: `after(n)`, a block height or a unix time.
sealed class AbsoluteLock {
  const AbsoluteLock();

  factory AbsoluteLock.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'height' => HeightLock(height: json['height'] as int),
      'time' => TimeLock(unix: json['unix'] as int),
      final other => throw FormatException('unknown absolute lock: $other'),
    };
  }
}

class HeightLock extends AbsoluteLock {
  const HeightLock({required this.height});

  final int height;
}

class TimeLock extends AbsoluteLock {
  const TimeLock({required this.unix});

  final int unix;
}

/// A relative lock: `older(n)`, counted from each coin's confirmation.
/// A time-based one comes with its seconds already multiplied out.
sealed class RelativeLock {
  const RelativeLock();

  factory RelativeLock.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'blocks' => BlocksLock(blocks: json['blocks'] as int),
      'seconds' => SecondsLock(seconds: json['seconds'] as int),
      final other => throw FormatException('unknown relative lock: $other'),
    };
  }

  /// Whether the lock counts time rather than blocks.
  bool get isTimeBased => this is SecondsLock;
}

class BlocksLock extends RelativeLock {
  const BlocksLock({required this.blocks});

  final int blocks;
}

class SecondsLock extends RelativeLock {
  const SecondsLock({required this.seconds});

  final int seconds;
}

/// A spending condition, as the policy states it. A threshold with
/// `k == n` is an "and", one with `k == 1` an "or".
sealed class PolicyCondition {
  const PolicyCondition();

  factory PolicyCondition.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'key' => KeyCondition(keyId: json['key_id'] as String),
      'thresh' => ThreshCondition(
        k: json['k'] as int,
        n: json['n'] as int,
        items: (json['items'] as List)
            .map((c) => PolicyCondition.fromJson(c as Map<String, dynamic>))
            .toList(),
      ),
      'after' => AfterCondition(
        lock: AbsoluteLock.fromJson(json['lock'] as Map<String, dynamic>),
      ),
      'older' => OlderCondition(
        lock: RelativeLock.fromJson(json['lock'] as Map<String, dynamic>),
      ),
      'preimage' => PreimageCondition(hash: json['hash'] as String),
      final other => throw FormatException('unknown condition: $other'),
    };
  }
}

class KeyCondition extends PolicyCondition {
  const KeyCondition({required this.keyId});

  final String keyId;
}

class ThreshCondition extends PolicyCondition {
  const ThreshCondition({
    required this.k,
    required this.n,
    required this.items,
  });

  final int k;
  final int n;
  final List<PolicyCondition> items;
}

class AfterCondition extends PolicyCondition {
  const AfterCondition({required this.lock});

  final AbsoluteLock lock;
}

class OlderCondition extends PolicyCondition {
  const OlderCondition({required this.lock});

  final RelativeLock lock;
}

/// A hash whose preimage must be revealed: `sha256`, `hash256`,
/// `ripemd160` or `hash160`.
class PreimageCondition extends PolicyCondition {
  const PreimageCondition({required this.hash});

  final String hash;
}

/// Which lock a [PolicyTimelock] entry is about.
sealed class TimelockRef {
  const TimelockRef();

  factory TimelockRef.fromJson(Map<String, dynamic> json) {
    final lock = json['lock'] as Map<String, dynamic>;
    return switch (json['kind'] as String) {
      'absolute' => AbsoluteTimelock(lock: AbsoluteLock.fromJson(lock)),
      'relative' => RelativeTimelock(lock: RelativeLock.fromJson(lock)),
      final other => throw FormatException('unknown timelock: $other'),
    };
  }

  /// Whether the lock is judged by a clock rather than by a height.
  bool get isTimeBased => switch (this) {
    AbsoluteTimelock(:final lock) => lock is TimeLock,
    RelativeTimelock(:final lock) => lock.isTimeBased,
  };
}

class AbsoluteTimelock extends TimelockRef {
  const AbsoluteTimelock({required this.lock});

  final AbsoluteLock lock;
}

class RelativeTimelock extends TimelockRef {
  const RelativeTimelock({required this.lock});

  final RelativeLock lock;
}

/// What still separates a lock from opening. Block figures come with
/// their ten-minute estimate; a time figure has no block count.
class Remaining {
  const Remaining({
    required this.remainingBlocks,
    required this.remainingSeconds,
    required this.unlocksAtUnix,
  });

  factory Remaining.fromJson(Map<String, dynamic> json) {
    return Remaining(
      remainingBlocks: json['remaining_blocks'] as int?,
      remainingSeconds: json['remaining_seconds'] as int?,
      unlocksAtUnix: json['unlocks_at_unix'] as int?,
    );
  }

  final int? remainingBlocks;
  final int? remainingSeconds;
  final int? unlocksAtUnix;
}

/// Where one lock stands against the chain and the coins.
sealed class LockState {
  const LockState();

  factory LockState.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'unlocked' => const UnlockedLock(),
      // The countdown sits under `until`, as it does on a branch; every
      // figure in it may be null when the chain's position is unknown.
      'locked' => LockedLock(
        remaining: Remaining.fromJson(json['until'] as Map<String, dynamic>),
      ),
      'per_coin' => PerCoinLock(
        unlocked: json['unlocked'] as int,
        waiting: json['waiting'] as int,
        locked: json['locked'] as int,
        next: json['next'] == null
            ? null
            : Remaining.fromJson(json['next'] as Map<String, dynamic>),
      ),
      'no_coins' => NoCoinsLock(
        blocks: json['blocks'] as int?,
        seconds: json['seconds'] as int?,
      ),
      final other => throw FormatException('unknown lock state: $other'),
    };
  }
}

/// An absolute lock the chain has passed.
class UnlockedLock extends LockState {
  const UnlockedLock();
}

/// An absolute lock still ahead.
class LockedLock extends LockState {
  const LockedLock({required this.remaining});

  final Remaining remaining;
}

/// A relative lock, counted coin by coin. `waiting` coins are not
/// confirmed yet, so their count has not started; `next` is the locked
/// coin that opens first.
class PerCoinLock extends LockState {
  const PerCoinLock({
    required this.unlocked,
    required this.waiting,
    required this.locked,
    required this.next,
  });

  final int unlocked;
  final int waiting;
  final int locked;
  final Remaining? next;
}

/// A relative lock with no coin to count from: the raw duration.
class NoCoinsLock extends LockState {
  const NoCoinsLock({required this.blocks, required this.seconds});

  final int? blocks;
  final int? seconds;
}

/// One timelock of a branch.
class PolicyTimelock {
  const PolicyTimelock({
    required this.lock,
    required this.required,
    required this.state,
  });

  factory PolicyTimelock.fromJson(Map<String, dynamic> json) {
    return PolicyTimelock(
      lock: TimelockRef.fromJson(json['lock'] as Map<String, dynamic>),
      required: json['required'] as bool,
      state: LockState.fromJson(json['state'] as Map<String, dynamic>),
    );
  }

  final TimelockRef lock;

  /// False when the lock sits under a threshold that can be met
  /// without it: it then never holds the branch back.
  final bool required;
  final LockState state;
}

/// Whether a branch can be spent from right now.
sealed class BranchState {
  const BranchState();

  factory BranchState.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'spendable_now' => const SpendableNow(),
      'locked' => LockedBranch(
        until: Remaining.fromJson(json['until'] as Map<String, dynamic>),
      ),
      'per_coin' => PerCoinBranch(
        unlocked: json['unlocked'] as int,
        waiting: json['waiting'] as int,
        locked: json['locked'] as int,
        next: json['next'] == null
            ? null
            : Remaining.fromJson(json['next'] as Map<String, dynamic>),
      ),
      'no_coins' => const NoCoinsBranch(),
      'needs_preimage' => const NeedsPreimage(),
      final other => throw FormatException('unknown branch state: $other'),
    };
  }
}

class SpendableNow extends BranchState {
  const SpendableNow();
}

/// Only absolute locks, and the chain has not passed them all.
class LockedBranch extends BranchState {
  const LockedBranch({required this.until});

  final Remaining until;
}

/// At least one relative lock: a coin is unlocked once every lock of
/// the branch is met for it.
class PerCoinBranch extends BranchState {
  const PerCoinBranch({
    required this.unlocked,
    required this.waiting,
    required this.locked,
    required this.next,
  });

  final int unlocked;
  final int waiting;
  final int locked;
  final Remaining? next;

  int get total => unlocked + waiting + locked;
}

/// A relative lock with no coin to count from.
class NoCoinsBranch extends BranchState {
  const NoCoinsBranch();
}

/// The branch needs a hash preimage; keys and locks say nothing about
/// whether one is at hand.
class NeedsPreimage extends BranchState {
  const NeedsPreimage();
}

/// One way to spend: a top-level alternative of the policy.
class PolicyBranch {
  const PolicyBranch({
    required this.id,
    required this.role,
    required this.label,
    required this.summary,
    required this.condition,
    required this.timelocks,
    required this.state,
    required this.spendableNow,
  });

  factory PolicyBranch.fromJson(Map<String, dynamic> json) {
    return PolicyBranch(
      id: json['id'] as String,
      role: BranchRole.fromId(json['role'] as String),
      label: json['label'] as String,
      summary: json['summary'] as String,
      condition: PolicyCondition.fromJson(
        json['condition'] as Map<String, dynamic>,
      ),
      timelocks: (json['timelocks'] as List)
          .map((t) => PolicyTimelock.fromJson(t as Map<String, dynamic>))
          .toList(),
      state: BranchState.fromJson(json['state'] as Map<String, dynamic>),
      spendableNow: json['spendable_now'] as bool,
    );
  }

  /// Stable within the snapshot: `b0`, `b1`, ...
  final String id;
  final BranchRole role;

  /// `Primary`, `Recovery`, `Emergency`, `Primary B`, `Recovery 3`...
  final String label;

  /// The core's one-sentence reading of the branch.
  final String summary;
  final PolicyCondition condition;

  /// Every lock of the branch, optional ones included, in the order
  /// the policy names them.
  final List<PolicyTimelock> timelocks;
  final BranchState state;
  final bool spendableNow;
}

/// A wallet's policy read against the chain.
class PolicySnapshot {
  const PolicySnapshot({
    required this.kind,
    required this.script,
    required this.descriptor,
    required this.policy,
    required this.keys,
    required this.branches,
    required this.tipHeight,
    required this.computedAt,
    required this.timeBasis,
    required this.coins,
    required this.hasTimelocks,
  });

  factory PolicySnapshot.fromJson(Map<String, dynamic> json) {
    return PolicySnapshot(
      kind: PolicyKind.fromId(json['kind'] as String),
      script: ScriptKind.fromId(json['script'] as String),
      descriptor: json['descriptor'] as String,
      policy: json['policy'] as String,
      keys: (json['keys'] as List)
          .map((k) => PolicyKey.fromJson(k as Map<String, dynamic>))
          .toList(),
      branches: (json['branches'] as List)
          .map((b) => PolicyBranch.fromJson(b as Map<String, dynamic>))
          .toList(),
      tipHeight: json['tip_height'] as int?,
      computedAt: json['computed_at'] as int,
      timeBasis: TimeBasis.fromId(json['time_basis'] as String),
      coins: json['coins'] as int,
      hasTimelocks: json['has_timelocks'] as bool,
    );
  }

  final PolicyKind kind;
  final ScriptKind script;

  /// The external descriptor as given, or the address of a watched
  /// address.
  final String descriptor;

  /// The normalized semantic policy with key labels in place of keys:
  /// `or(pk(Key A),and(pk(Key B),older(52560)))`.
  final String policy;
  final List<PolicyKey> keys;
  final List<PolicyBranch> branches;

  /// The chain tip the absolute locks were read against; null for a
  /// wallet that has never synced, whose absolute locks then stand with
  /// nothing to count down from.
  final int? tipHeight;

  /// When the snapshot was computed, unix seconds.
  final int computedAt;
  final TimeBasis timeBasis;

  /// Number of coins the relative locks were counted over.
  final int coins;
  final bool hasTimelocks;

  /// The key a condition names, by its id.
  PolicyKey? keyById(String id) {
    for (final key in keys) {
      if (key.id == id) return key;
    }
    return null;
  }

  /// Whether any lock of any branch is judged by a clock: those read
  /// against this device's time, which the chain can trail.
  bool get hasTimeBasedLocks => branches.any(
    (branch) => branch.timelocks.any((lock) => lock.lock.isTimeBased),
  );
}

// --- premium -------------------------------------------------------------

/// The signed part of a licence certificate, read after the core checked
/// the signature against the key it embeds. Dart never verifies one: it
/// only compares these dates with the clock.
class LicenceClaims {
  const LicenceClaims({
    required this.subject,
    required this.expiresAt,
    required this.issuedAt,
  });

  factory LicenceClaims.fromJson(Map<String, dynamic> json) {
    return LicenceClaims(
      subject: json['sub'] as String,
      expiresAt: json['exp'] as int,
      issuedAt: json['iat'] as int,
    );
  }

  /// Hex of the key hash: a stable name for the account, nothing more.
  final String subject;

  /// Unix seconds: when the paid time ends.
  final int expiresAt;

  /// Unix seconds: when the certificate was issued.
  final int issuedAt;

  /// Whether the paid time covers [nowUnix], the way the server judges
  /// it: active up to the second it ends.
  bool isActive(int nowUnix) => nowUnix < expiresAt;
}

/// A wallet the user agreed to have watched by the server, and when.
class WatchConsent {
  const WatchConsent({required this.walletId, required this.consentedAt});

  factory WatchConsent.fromJson(Map<String, dynamic> json) {
    return WatchConsent(
      walletId: json['wallet_id'] as String,
      consentedAt: json['consented_at'] as int,
    );
  }

  final String walletId;

  /// Unix seconds.
  final int consentedAt;
}

/// The premium account as the vault keeps it, with the claims of its
/// certificate already verified offline. Empty until a key is entered.
class PremiumView {
  const PremiumView({
    this.key,
    this.keyDisplay,
    this.claims,
    this.watched = const [],
    this.acknowledgedOfflineUntil,
    this.ntfyBaseUrl = 'https://ntfy.gerfaut-wallet.com',
    this.telegramBot = 'GerfautAlertsBot',
  });

  factory PremiumView.fromJson(Map<String, dynamic> json) {
    return PremiumView(
      key: json['key'] as String?,
      keyDisplay: json['key_display'] as String?,
      claims: json['claims'] == null
          ? null
          : LicenceClaims.fromJson(json['claims'] as Map<String, dynamic>),
      watched: (json['watched'] as List? ?? const [])
          .map((w) => WatchConsent.fromJson(w as Map<String, dynamic>))
          .toList(),
      acknowledgedOfflineUntil: json['acknowledged_offline_until'] as int?,
      ntfyBaseUrl:
          json['ntfy_base_url'] as String? ?? 'https://ntfy.gerfaut-wallet.com',
      telegramBot: json['telegram_bot'] as String? ?? 'GerfautAlertsBot',
    );
  }

  /// The account key, normalized; null until one is entered.
  final String? key;

  /// The key as it is shown, `abcd-efgh-ijkm-npqr`.
  final String? keyDisplay;

  /// The stored certificate's claims; null without a key, or when the
  /// certificate no longer verifies.
  final LicenceClaims? claims;

  /// The wallets the user agreed to send to the server.
  final List<WatchConsent> watched;

  /// Unix seconds until which the "watch is offline" banner stays
  /// hidden because the user dismissed it.
  final int? acknowledgedOfflineUntil;

  /// The ntfy instance the server publishes to.
  final String ntfyBaseUrl;

  /// The Telegram bot that links channels, without the `@`.
  final String telegramBot;

  bool get hasKey => key != null;

  /// Whether the user already said yes for this wallet.
  bool consented(String walletId) => watched.any((w) => w.walletId == walletId);
}

/// `GET /v1/licence`, its certificate verified by the core.
class PremiumLicence {
  const PremiumLicence({
    required this.certificate,
    required this.paidUntil,
    required this.claims,
  });

  factory PremiumLicence.fromJson(Map<String, dynamic> json) {
    return PremiumLicence(
      certificate: json['certificate'] as String,
      paidUntil: json['paid_until'] as int,
      claims: LicenceClaims.fromJson(json['claims'] as Map<String, dynamic>),
    );
  }

  final String certificate;

  /// Unix seconds.
  final int paidUntil;
  final LicenceClaims claims;
}

/// `GET /v1/account`.
class PremiumAccount {
  const PremiumAccount({
    required this.active,
    required this.paidUntil,
    required this.wallets,
    required this.channels,
    required this.network,
  });

  factory PremiumAccount.fromJson(Map<String, dynamic> json) {
    return PremiumAccount(
      active: json['active'] as bool,
      paidUntil: json['paid_until'] as int?,
      wallets: json['wallets'] as int,
      channels: json['channels'] as int,
      network: json['network'] as String,
    );
  }

  final bool active;

  /// Unix seconds; null for a key never paid for.
  final int? paidUntil;
  final int wallets;
  final int channels;

  /// The network the server watches, as it names it (`bitcoin`).
  final String network;

  /// The server's network in the app's own terms; null for a name this
  /// build does not know.
  Network? get chain => switch (network) {
    'bitcoin' || 'main' || 'mainnet' => Network.mainnet,
    'signet' => Network.signet,
    'testnet4' || 'testnet' || 'test' => Network.testnet4,
    'regtest' => Network.regtest,
    _ => null,
  };
}

/// One wallet the server watches for the account.
class WalletWatch {
  const WalletWatch({
    required this.id,
    required this.name,
    required this.scriptKind,
    required this.watchedSince,
    required this.baselineAt,
    required this.baselineHeight,
    required this.coins,
    required this.valueSats,
    this.baselinePending,
    this.watching = true,
    this.refusal,
  });

  factory WalletWatch.fromJson(Map<String, dynamic> json) {
    return WalletWatch(
      id: json['id'] as String,
      name: json['name'] as String,
      scriptKind: json['script_kind'] as String,
      watchedSince: json['watched_since'] as int,
      baselineAt: json['baseline_at'] as int?,
      baselineHeight: json['baseline_height'] as int?,
      baselinePending: json['baseline_pending'] as bool?,
      coins: json['coins'] as int,
      valueSats: json['value_sats'] as int,
      // A server that predates the flag refuses no wallet.
      watching: json['watching'] as bool? ?? true,
      refusal: switch (json['refusal']) {
        final Map<String, dynamic> refusal => WalletRefusal.fromJson(refusal),
        _ => null,
      },
    );
  }

  /// The app's own wallet id.
  final String id;
  final String name;
  final String scriptKind;

  /// False once the server has refused the wallet: it keeps the row to
  /// say why, and watches nothing under it.
  final bool watching;

  /// Why the server does not watch this wallet, when it does not.
  final WalletRefusal? refusal;

  /// The server holds the wallet and does not watch it.
  bool get refused => !watching;

  /// Unix seconds.
  final int watchedSince;

  /// Unix seconds when the first scan of the UTXO set finished; null
  /// while it runs.
  final int? baselineAt;
  final int? baselineHeight;
  final int coins;
  final int valueSats;

  /// What the server says about the first scan, when it says anything:
  /// null from a server that does not report it.
  final bool? baselinePending;

  /// The first scan of the UTXO set has not finished: the balances and
  /// the counts here are not the wallet's yet.
  ///
  /// The server states it; a server that does not is read by the date
  /// it stamps when the scan ends, which says the same thing.
  bool get scanning => baselinePending ?? (baselineAt == null);
}

/// Why the server stopped watching a wallet, or never started.
class WalletRefusal {
  const WalletRefusal({required this.code, required this.message});

  factory WalletRefusal.fromJson(Map<String, dynamic> json) {
    return WalletRefusal(
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  /// For the app; `too_many_coins` is the only one today.
  final String code;

  /// For the person who owns the wallet, to show as it is.
  final String message;
}

/// Where an account wants to be told.
enum ChannelKind {
  ntfy('ntfy', 'ntfy'),
  telegram('telegram', 'Telegram'),
  email('email', 'E-mail'),
  webhook('webhook', 'Webhook');

  const ChannelKind(this.id, this.label);

  /// Stable machine identifier, as serialized by the core.
  final String id;
  final String label;

  static ChannelKind fromId(String id) =>
      ChannelKind.values.firstWhere((k) => k.id == id);
}

/// One channel, as the server describes it.
class PremiumChannel {
  const PremiumChannel({
    required this.id,
    required this.kind,
    required this.target,
    required this.linked,
    this.linkCode,
    this.startUrl,
    this.linkedName,
    this.enabled = true,
    required this.createdAt,
  });

  factory PremiumChannel.fromJson(Map<String, dynamic> json) {
    return PremiumChannel(
      id: json['id'] as String,
      kind: ChannelKind.fromId(json['kind'] as String),
      target: json['target'] as String? ?? '',
      linked: json['linked'] as bool? ?? true,
      linkCode: json['link_code'] as String?,
      startUrl: json['start_url'] as String?,
      linkedName: json['linked_name'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: json['created_at'] as int,
    );
  }

  final String id;
  final ChannelKind kind;

  /// Masked except for webhooks: proof it is the right one, not a copy
  /// of it.
  final String target;

  /// False for a Telegram channel whose code was not sent to the bot yet.
  final bool linked;

  /// The code to send the bot, while a Telegram channel is unlinked.
  final String? linkCode;

  /// Opens the bot with the code filled in, while it waits for it.
  final String? startUrl;

  /// Who receives the alerts, when the server knows a name for them:
  /// the Telegram chat that sent the code. Null for the other kinds,
  /// and from a server that predates it.
  final String? linkedName;
  final bool enabled;

  /// Unix seconds.
  final int createdAt;

  /// A Telegram channel the bot has not heard from yet.
  bool get waitingForBot => kind == ChannelKind.telegram && !linked;
}

/// What creating a channel hands back: the channel, and for ntfy the
/// topic drawn for it, shown once with the URL to subscribe to.
class CreatedChannel {
  const CreatedChannel({required this.channel, this.topic, this.subscribeUrl});

  factory CreatedChannel.fromJson(Map<String, dynamic> json) {
    return CreatedChannel(
      channel: PremiumChannel.fromJson(json['channel'] as Map<String, dynamic>),
      topic: json['topic'] as String?,
      subscribeUrl: json['subscribe_url'] as String?,
    );
  }

  final PremiumChannel channel;
  final String? topic;

  /// `https://ntfy.gerfaut-wallet.com/<topic>`.
  final String? subscribeUrl;
}

/// What happened to a watched wallet. A kind this build does not know
/// reads as [other], so a newer server never breaks the list.
enum AlertKind {
  spendDetected('spend_detected'),
  spendConfirmed('spend_confirmed'),
  coinsGone('coins_gone'),
  receiveDetected('receive_detected'),
  receiveConfirmed('receive_confirmed'),
  timelockDue('timelock_due'),
  walletRegistered('wallet_registered'),
  walletRefused('wallet_refused'),
  other('other');

  const AlertKind(this.id);

  final String id;

  static AlertKind fromId(String? id) {
    for (final kind in AlertKind.values) {
      if (kind.id == id) return kind;
    }
    return AlertKind.other;
  }
}

/// One entry of the account's event log.
class PremiumEvent {
  const PremiumEvent({
    required this.id,
    required this.kind,
    required this.wallet,
    required this.walletName,
    required this.at,
    this.data = const {},
  });

  factory PremiumEvent.fromJson(Map<String, dynamic> json) {
    return PremiumEvent(
      id: json['id'] as int,
      kind: AlertKind.fromId(json['kind'] as String?),
      wallet: json['wallet'] as String,
      walletName: json['wallet_name'] as String,
      at: json['at'] as int,
      data: json['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Increasing; the cursor of the server's log.
  final int id;
  final AlertKind kind;

  /// The app's own wallet id.
  final String wallet;
  final String walletName;

  /// Unix seconds.
  final int at;

  /// The kind's own fields, as the API documents them.
  final Map<String, dynamic> data;
}

/// `GET /v1/heartbeat`, verified by the core against the embedded key
/// and this device's clock.
class HeartbeatReport {
  const HeartbeatReport({required this.now, required this.tipHeight});

  factory HeartbeatReport.fromJson(Map<String, dynamic> json) {
    final heartbeat = json['heartbeat'] as Map<String, dynamic>;
    return HeartbeatReport(
      now: heartbeat['now'] as int,
      tipHeight: heartbeat['tip_height'] as int?,
    );
  }

  /// Unix seconds on the server.
  final int now;

  /// The chain tip the server watches from; null before its first block.
  final int? tipHeight;
}
