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
    'This key carries no script type: check the one selected below.',
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
}

/// Balance split as BDK reports it, in sats.
class BalanceSnapshot {
  const BalanceSnapshot({
    required this.confirmed,
    required this.trustedPending,
    required this.untrustedPending,
    required this.immature,
    required this.total,
  });

  factory BalanceSnapshot.fromJson(Map<String, dynamic> json) {
    return BalanceSnapshot(
      confirmed: json['confirmed'] as int,
      trustedPending: json['trusted_pending'] as int,
      untrustedPending: json['untrusted_pending'] as int,
      immature: json['immature'] as int,
      total: json['total'] as int,
    );
  }

  final int confirmed;
  final int trustedPending;
  final int untrustedPending;
  final int immature;
  final int total;

  bool get hasPending => trustedPending > 0 || untrustedPending > 0;
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

/// Wallet metadata as stored in the vault.
class WalletMeta {
  const WalletMeta({
    required this.id,
    required this.name,
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
    );
  }

  final String? address;
  final int? valueSats;
  final bool isMine;

  /// Output on the wallet's change keychain (descriptor wallets only).
  final bool change;

  /// Decoded OP_RETURN payload, for data-carrying outputs.
  final OpReturnData? opReturn;
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
class SyncReport {
  const SyncReport({
    required this.walletId,
    required this.newTxCount,
    required this.balance,
    required this.tipHeight,
    required this.tookMs,
    required this.backend,
  });

  factory SyncReport.fromJson(Map<String, dynamic> json) {
    return SyncReport(
      walletId: json['wallet_id'] as String,
      newTxCount: json['new_tx_count'] as int,
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
  });

  factory PublicServer.fromJson(Map<String, dynamic> json) {
    return PublicServer(
      id: json['id'] as String,
      label: json['label'] as String,
      protocol: ServerProtocol.fromId(json['protocol'] as String),
      url: json['url'] as String,
    );
  }

  /// Stable key stored in the settings; it outlives a URL change.
  final String id;

  /// What the settings show: the host, nothing else.
  final String label;
  final ServerProtocol protocol;

  /// Endpoint Gerfaut talks to.
  final String url;
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
    );
  }

  final Network activeNetwork;
  final Map<Network, BackendConfig> backends;
  final Map<String, String> appPrefs;

  /// Global gap limit applied to every descriptor wallet on sync.
  final int gapLimit;

  /// Backend for a network, falling back to the public default.
  BackendConfig backendFor(Network network) =>
      backends[network] ?? const PublicEsplora();
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

  /// The network will refuse the transaction, or already took the coin:
  /// read in the alert style. Everything else is a caution.
  bool get blocking =>
      this == TxWarningKind.unsigned || this == TxWarningKind.inputSpent;
}

/// A caution to read before broadcasting. Never blocks: the preview
/// only makes the transaction legible.
class TxWarning {
  const TxWarning({required this.kind, required this.message});

  factory TxWarning.fromJson(Map<String, dynamic> json) {
    return TxWarning(
      kind: TxWarningKind.fromId(json['kind'] as String),
      message: json['message'] as String,
    );
  }

  final TxWarningKind kind;
  final String message;
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
