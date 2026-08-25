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
  multipathDescriptor(
    'multipath_descriptor',
    'Multipath descriptor (BIP-389)',
  ),
  extendedKey('extended_key', 'Extended public key'),
  address('address', 'Single address'),
  walletExport('wallet_export', 'Wallet export file');

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
    'The key does not say its script type: Native SegWit was assumed.',
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
      'single_address' => SingleAddressKind(
        address: json['address'] as String,
      ),
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

/// Chain data source for one network.
sealed class BackendConfig {
  const BackendConfig();

  factory BackendConfig.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'public_esplora' => const PublicEsplora(),
      'custom_esplora' => CustomEsplora(url: json['url'] as String),
      'custom_electrum' => CustomElectrum(url: json['url'] as String),
      final other => throw FormatException('unknown backend type: $other'),
    };
  }

  Map<String, dynamic> toJson();
}

class PublicEsplora extends BackendConfig {
  const PublicEsplora();

  @override
  Map<String, dynamic> toJson() => {'type': 'public_esplora'};
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

  static PriceSource? fromId(String? id) {
    for (final source in PriceSource.values) {
      if (source.id == id) return source;
    }
    return null;
  }
}

/// Display currencies offered in the settings.
enum FiatCurrency {
  eur('eur', 'EUR'),
  usd('usd', 'USD'),
  gbp('gbp', 'GBP'),
  chf('chf', 'CHF');

  const FiatCurrency(this.id, this.code);

  final String id;

  /// ISO 4217 code, uppercase.
  final String code;

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
