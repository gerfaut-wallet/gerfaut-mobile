// A configurable in-memory bridge so widget tests never touch native
// code. Screens observe the same contract as the real bridge, including
// BridgeException errors.

import 'dart:async';

import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/electrum.dart';
import 'package:gerfaut/src/models.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Captures external launches instead of touching the platform.
/// Install with `UrlLauncherPlatform.instance = FakeUrlLauncher()`.
class FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

WalletMeta makeMeta({
  String id = 'w1',
  String name = 'Cold storage',
  Network network = Network.mainnet,
  int totalSats = 0,
  int gapLimit = 20,
  SyncStamp? lastSync,
  WalletKind kind = const DescriptorsKind(
    external: 'wpkh(tpub.../0/*)#checksum',
    internal: 'wpkh(tpub.../1/*)#checksum',
    script: ScriptKind.segwit,
  ),
}) {
  return WalletMeta(
    id: id,
    name: name,
    network: network,
    kind: kind,
    recognizedAs: RecognizedKind.multipathDescriptor,
    createdAt: 1755000000,
    gapLimit: gapLimit,
    lastSync: lastSync,
    cachedBalance: makeBalance(totalSats),
    cachedTxCount: 0,
  );
}

BalanceSnapshot makeBalance(int totalSats) {
  return BalanceSnapshot(
    confirmed: totalSats,
    trustedPending: 0,
    untrustedPending: 0,
    immature: 0,
    total: totalSats,
  );
}

WalletSnapshot makeSnapshot({
  WalletMeta? meta,
  int totalSats = 0,
  List<TxSummary> txs = const [],
  int tipHeight = 0,
  bool truncated = false,
}) {
  return WalletSnapshot(
    meta: meta ?? makeMeta(totalSats: totalSats),
    balance: makeBalance(totalSats),
    txs: txs,
    tipHeight: tipHeight,
    truncated: truncated,
  );
}

ParsedInput makeParsedInput({
  RecognizedKind kind = RecognizedKind.multipathDescriptor,
  List<Network> networks = const [
    Network.signet,
    Network.testnet4,
    Network.regtest,
  ],
  ParsedPayload payload = const DescriptorsPayload(
    external: 'wpkh(tpub.../0/*)#checksum',
    internal: 'wpkh(tpub.../1/*)#checksum',
    script: ScriptKind.segwit,
  ),
  List<InputWarning> warnings = const [],
  List<ScriptKind> scriptOptions = const [],
  String? previewAddress,
}) {
  return ParsedInput(
    kind: kind,
    networks: networks,
    payload: payload,
    warnings: warnings,
    rawJson: '{}',
    scriptOptions: scriptOptions,
    previewAddress: previewAddress,
  );
}

PublicServer _esplora(String host, String url) => PublicServer(
  id: host,
  label: host,
  protocol: ServerProtocol.esplora,
  url: url,
);

PublicServer _electrum(
  String host,
  String label,
  String url, {
  bool selfSigned = false,
}) => PublicServer(
  id: 'electrum:$host',
  label: label,
  protocol: ServerProtocol.electrum,
  url: url,
  selfSigned: selfSigned,
);

/// The catalogue gerfaut-core publishes, network by network: the public
/// Esplora instances first, then the Electrum servers. Mirrored here so
/// the settings list under test is the one the app really offers.
final Map<Network, List<PublicServer>> defaultPublicServers = {
  Network.mainnet: [
    _esplora('mempool.space', 'https://mempool.space/api'),
    _esplora('blockstream.info', 'https://blockstream.info/api'),
    _esplora('mempool.emzy.de', 'https://mempool.emzy.de/api'),
    _electrum(
      'blockstream.info',
      'blockstream.info:700',
      'ssl://blockstream.info:700',
    ),
    _electrum(
      'electrum.blockstream.info',
      'electrum.blockstream.info:50002',
      'ssl://electrum.blockstream.info:50002',
    ),
    _electrum(
      'electrum.diynodes.com',
      'electrum.diynodes.com:50022',
      'ssl://electrum.diynodes.com:50022',
    ),
    _electrum(
      'frigate.2140.dev',
      'frigate.2140.dev:50002',
      'ssl://frigate.2140.dev:50002',
    ),
    // The rest of Sparrow's list; these four sign their own certificate.
    _electrum(
      'bitcoin.lu.ke',
      'bitcoin.lu.ke:50002',
      'ssl://bitcoin.lu.ke:50002',
      selfSigned: true,
    ),
    _electrum(
      'electrum.emzy.de',
      'electrum.emzy.de:50002',
      'ssl://electrum.emzy.de:50002',
      selfSigned: true,
    ),
    _electrum(
      'electrum.bitaroo.net',
      'electrum.bitaroo.net:50002',
      'ssl://electrum.bitaroo.net:50002',
      selfSigned: true,
    ),
    _electrum(
      'fulcrum.sethforprivacy.com',
      'fulcrum.sethforprivacy.com:50002',
      'ssl://fulcrum.sethforprivacy.com:50002',
      selfSigned: true,
    ),
  ],
  Network.signet: [
    _esplora('mempool.space', 'https://mempool.space/signet/api'),
    _esplora('blockstream.info', 'https://blockstream.info/signet/api'),
    _esplora('mempool.emzy.de', 'https://mempool.emzy.de/signet/api'),
    _electrum(
      'mempool.space',
      'mempool.space:60602',
      'ssl://mempool.space:60602',
    ),
  ],
  Network.testnet4: [
    _esplora('mempool.space', 'https://mempool.space/testnet4/api'),
    _esplora('mempool.emzy.de', 'https://mempool.emzy.de/testnet4/api'),
    _electrum(
      'mempool.space',
      'mempool.space:40002',
      'ssl://mempool.space:40002',
    ),
    _electrum(
      'blackie.c3-soft.com',
      'blackie.c3-soft.com:57010',
      'ssl://blackie.c3-soft.com:57010',
    ),
  ],
  // A local chain has no public server, by definition.
  Network.regtest: [],
};

/// The key the core records an acceptance against: `host:port`, scheme
/// and path stripped. Mirrors `certificate_key` in gerfaut-core.
String _certificateKey(String url) {
  final parts = parseElectrumUrl(url);
  return parts.port.isEmpty ? parts.host : '${parts.host}:${parts.port}';
}

class FakeBridge implements GerfautBridge {
  FakeBridge({
    List<WalletMeta>? wallets,
    this.settings = const Settings(
      activeNetwork: Network.mainnet,
      backends: {},
      appPrefs: {},
    ),
    Map<String, WalletSnapshot>? snapshots,
    Map<String, List<UtxoInfo>>? utxos,
    Map<String, TxDetail>? txDetails,
    Map<String, List<AddressEntry>>? addresses,
    Map<String, AddressList>? addressLists,
    this.onParse,
    this.onParseWith,
  }) : wallets = wallets ?? [],
       snapshots = snapshots ?? {},
       utxoMap = utxos ?? {},
       txDetails = txDetails ?? {},
       addresses = addresses ?? {},
       addressLists = addressLists ?? {};

  List<WalletMeta> wallets;
  Settings settings;
  Map<String, WalletSnapshot> snapshots;
  Map<String, List<UtxoInfo>> utxoMap;

  /// Keyed by `'$walletId:$txid'`.
  Map<String, TxDetail> txDetails;
  Map<String, List<AddressEntry>> addresses;
  Map<String, AddressList> addressLists;

  /// Classification hook; throw a [BridgeException] to simulate a
  /// rejection (private material, unrecognized input, ...).
  ParsedInput Function(String input)? onParse;

  /// Classification hook that also sees the script type choice; takes
  /// precedence over [onParse] when set.
  ParsedInput Function(String input, ScriptKind? script)? onParseWith;

  /// The script argument of every parseInput call, for assertions.
  final List<ScriptKind?> parseScripts = [];

  /// Every `set_app_pref` write, for assertions.
  final Map<String, String> appPrefs = {};

  /// Every backend save, for assertions.
  final Map<Network, BackendConfig> savedBackends = {};

  int addWalletCalls = 0;
  int syncWalletCalls = 0;
  int syncAllCalls = 0;
  int loadMoreHistoryCalls = 0;
  Network? lastActiveNetworkSet;

  /// History round hook; the default reports nothing left to fetch.
  /// Throw a [BridgeException] to simulate a failed round.
  int Function(String id)? onLoadMoreHistory;

  @override
  Future<ParsedInput> parseInput(String input, {ScriptKind? script}) async {
    parseScripts.add(script);
    final parseWith = onParseWith;
    if (parseWith != null) return parseWith(input, script);
    final parse = onParse;
    if (parse == null) {
      throw const BridgeException('unrecognized_input', 'no parser configured');
    }
    return parse(input);
  }

  /// QR assembly hook; the default takes the last frame as the whole
  /// code. Throw a [BridgeException] to simulate an unsupported
  /// envelope or material that is not a wallet to watch.
  FutureOr<QrProgress> Function(List<String> frames)? onAssembleQr;

  /// The frame list of every assembleQr call, for assertions.
  final List<List<String>> assembleCalls = [];

  @override
  Future<QrProgress> assembleQr(List<String> frames) async {
    assembleCalls.add(List.of(frames));
    final assemble = onAssembleQr;
    if (assemble != null) return assemble(frames);
    return QrProgress(
      format: QrFormat.plain,
      received: 1,
      total: 1,
      complete: true,
      text: frames.last,
    );
  }

  @override
  Future<WalletMeta> addWallet(
    String name,
    ParsedInput parsed,
    Network network,
  ) async {
    addWalletCalls += 1;
    final meta = makeMeta(
      id: 'w${wallets.length + 1}',
      name: name,
      network: network,
    );
    wallets = [...wallets, meta];
    snapshots[meta.id] = makeSnapshot(meta: meta);
    return meta;
  }

  @override
  Future<List<WalletMeta>> listWallets([Network? network]) async {
    if (network == null) return wallets;
    return wallets.where((w) => w.network == network).toList();
  }

  @override
  Future<WalletSnapshot> walletSnapshot(String id) async {
    final snapshot = snapshots[id];
    if (snapshot == null) {
      throw BridgeException('wallet_not_found', 'wallet not found: $id');
    }
    return snapshot;
  }

  @override
  Future<TxDetail> txDetail(String id, String txid) async {
    final detail = txDetails['$id:$txid'];
    if (detail == null) {
      throw BridgeException('internal', 'no tx detail for $id:$txid');
    }
    return detail;
  }

  @override
  Future<List<UtxoInfo>> utxos(String id) async => utxoMap[id] ?? [];

  /// Lookahead of every receiveAddresses call, for assertions.
  final List<int> receiveLookaheads = [];

  @override
  Future<List<AddressEntry>> receiveAddresses(String id, int lookahead) async {
    receiveLookaheads.add(lookahead);
    final base =
        addresses[id] ??
        const [AddressEntry(index: 0, address: 'tb1qexample', used: false)];
    final first = base.first;
    // Mirrors the core: the next unused entry plus `lookahead` peeked
    // ones, continuing past the configured list when it runs short.
    return [
      for (var i = 0; i <= lookahead; i++)
        i < base.length
            ? base[i]
            : AddressEntry(
                index: first.index + i,
                address: '${first.address}$i',
                used: false,
              ),
    ];
  }

  @override
  Future<AddressList> addressList(String id) async {
    final list = addressLists[id];
    if (list != null) return list;
    return const AddressList(external: [], internal: []);
  }

  /// Every export call's options, for assertions.
  final List<ExportOptions> exportCalls = [];

  @override
  Future<ExportResult> exportTransactions(
    String id,
    ExportOptions options,
  ) async {
    exportCalls.add(options);
    // Mirrors gerfaut-core's export::passes so counters and results
    // agree in tests.
    final txs = (snapshots[id]?.txs ?? []).where((tx) {
      if (options.direction == ExportDirection.incoming && tx.netSats < 0) {
        return false;
      }
      if (options.direction == ExportDirection.outgoing && tx.netSats >= 0) {
        return false;
      }
      final unbounded = options.from == null && options.to == null;
      if (!tx.status.confirmed) return options.includePending && unbounded;
      final at = tx.status.timestamp;
      if (at == null) return unbounded;
      return (options.from == null || at >= options.from!) &&
          (options.to == null || at <= options.to!);
    }).toList();
    final csv = StringBuffer(
      'txid,date_utc,block_height,confirmations,direction,amount_sats,'
      'amount_btc,fee_sats\n',
    );
    for (final tx in txs) {
      csv.writeln(
        '${tx.txid},,,,${tx.netSats >= 0 ? 'in' : 'out'},'
        '${tx.netSats},,',
      );
    }
    return ExportResult(csv: csv.toString(), rows: txs.length);
  }

  /// Sync hooks; throw a [BridgeException] to simulate a failure.
  SyncReport Function(String id)? onSyncWallet;
  SyncAllReport Function(Network? network)? onSyncAll;

  @override
  Future<SyncReport> syncWallet(String id) async {
    syncWalletCalls += 1;
    final sync = onSyncWallet;
    if (sync != null) return sync(id);
    return SyncReport(
      walletId: id,
      newTxCount: 0,
      balance: snapshots[id]?.balance ?? makeBalance(0),
      tipHeight: 100,
      tookMs: 1,
      backend: 'mempool.space',
    );
  }

  @override
  Future<int> loadMoreHistory(String id) async {
    loadMoreHistoryCalls += 1;
    final load = onLoadMoreHistory;
    return load != null ? load(id) : 0;
  }

  @override
  Future<SyncAllReport> syncAll([Network? network]) async {
    syncAllCalls += 1;
    final sync = onSyncAll;
    if (sync != null) return sync(network);
    return const SyncAllReport(reports: [], failures: []);
  }

  @override
  Future<void> renameWallet(String id, String name) async {
    wallets = [
      for (final wallet in wallets)
        if (wallet.id == id) makeMeta(id: id, name: name) else wallet,
    ];
  }

  @override
  Future<void> removeWallet(String id) async {
    wallets = wallets.where((w) => w.id != id).toList();
    snapshots.remove(id);
  }

  @override
  Future<Settings> getSettings() async => settings;

  /// Rewrites the stored settings one field at a time, the way the
  /// vault does: everything left out stays as it was.
  void _store({
    Network? activeNetwork,
    Map<Network, BackendConfig>? backends,
    int? gapLimit,
    Map<String, String>? electrumCerts,
  }) {
    settings = Settings(
      activeNetwork: activeNetwork ?? settings.activeNetwork,
      backends: backends ?? settings.backends,
      appPrefs: settings.appPrefs,
      gapLimit: gapLimit ?? settings.gapLimit,
      electrumCerts: electrumCerts ?? settings.electrumCerts,
    );
  }

  @override
  Future<void> setActiveNetwork(Network network) async {
    lastActiveNetworkSet = network;
    _store(activeNetwork: network);
  }

  /// Last accepted gap limit, for assertions; null when never set.
  int? lastGapLimitSet;

  @override
  Future<void> setGapLimit(int gapLimit) async {
    // Mirrors the core bound: 1..=500 or CoreError::InvalidInput.
    if (gapLimit < 1 || gapLimit > 500) {
      throw const BridgeException(
        'invalid_input',
        'gap limit must be between 1 and 500',
      );
    }
    lastGapLimitSet = gapLimit;
    _store(gapLimit: gapLimit);
  }

  @override
  Future<void> setBackend(Network network, BackendConfig config) async {
    savedBackends[network] = config;
    _store(backends: {...settings.backends, network: config});
  }

  /// Catalogue hook; throw a [BridgeException] to simulate a bridge
  /// that cannot answer. The default serves [defaultPublicServers].
  List<PublicServer> Function(Network network)? onPublicServers;

  /// Every network the catalogue was asked for, for assertions.
  final List<Network> publicServerCalls = [];

  @override
  Future<List<PublicServer>> publicServers(Network network) async {
    publicServerCalls.add(network);
    final servers = onPublicServers;
    if (servers != null) return servers(network);
    return defaultPublicServers[network] ?? const [];
  }

  /// Certificate hook; the default reports one a public authority
  /// vouches for. Return an [UnknownCertificate] or a
  /// [ChangedCertificate] to exercise the acceptance dialogs.
  CertificateStatus Function(String url)? onInspectCertificate;

  /// Every inspected URL, in order, for assertions.
  final List<String> inspectedCertificates = [];

  /// Every accepted certificate, in order, for assertions.
  final List<({String url, String fingerprint})> trustedCertificates = [];

  /// Every forgotten host, in order, for assertions.
  final List<String> forgottenCertificates = [];

  @override
  Future<CertificateReport> inspectCertificate(String url) async {
    inspectedCertificates.add(url);
    final inspect = onInspectCertificate;
    return CertificateReport(
      host: _certificateKey(url),
      status: inspect != null ? inspect(url) : const TrustedCertificate(),
    );
  }

  @override
  Future<void> trustCertificate(String url, String fingerprint) async {
    trustedCertificates.add((url: url, fingerprint: fingerprint));
    _store(
      electrumCerts: {
        ...settings.electrumCerts,
        _certificateKey(url): fingerprint,
      },
    );
  }

  @override
  Future<void> forgetCertificate(String host) async {
    forgottenCertificates.add(host);
    _store(electrumCerts: {...settings.electrumCerts}..remove(host));
  }

  @override
  Future<void> setAppPref(String key, String value) async {
    appPrefs[key] = value;
  }

  /// Price hook; throw a [BridgeException] to simulate an unreachable
  /// source. The default rate keeps fiat lines deterministic in tests.
  PriceQuote Function(PriceSource source, FiatCurrency currency)? onFetchPrice;

  @override
  Future<PriceQuote> fetchPrice(
    PriceSource source,
    FiatCurrency currency,
  ) async {
    final fetch = onFetchPrice;
    if (fetch != null) return fetch(source, currency);
    return PriceQuote(
      rate: 50000,
      currency: currency,
      source: source,
      at: 1755000000,
    );
  }

  /// Update hook; the default reports the running version as current.
  UpdateCheck Function(String currentVersion)? onCheckUpdate;

  @override
  Future<UpdateCheck> checkUpdate(String currentVersion) async {
    final check = onCheckUpdate;
    if (check != null) return check(currentVersion);
    return UpdateCheck(
      latest: 'v$currentVersion',
      url: 'https://github.com/gerfaut-wallet/gerfaut-mobile/releases/latest',
      updateAvailable: false,
    );
  }

  /// Preview hook; throw a [BridgeException] to simulate input the core
  /// cannot decode. Without one, every input is refused as unreadable.
  FutureOr<TxPreview> Function(String input, Network network)? onPreview;

  /// Every preview call's input, for assertions.
  final List<String> previewInputs = [];

  @override
  Future<TxPreview> previewTransaction(String input, Network network) async {
    previewInputs.add(input);
    final preview = onPreview;
    if (preview == null) {
      throw const BridgeException(
        'invalid_input',
        'not a transaction: expected a PSBT (base64, hex or .psbt file) or '
            'a signed transaction (hex or .txn file)',
      );
    }
    return preview(input, network);
  }

  /// Broadcast hook; throw a [BridgeException] to simulate the node
  /// refusing the transaction.
  FutureOr<BroadcastReport> Function(Network network, String hex)? onBroadcast;

  /// Every broadcast call's hex, for assertions.
  final List<String> broadcastHexes = [];

  @override
  Future<BroadcastReport> broadcastTransaction(
    Network network,
    String hex,
  ) async {
    broadcastHexes.add(hex);
    final broadcast = onBroadcast;
    if (broadcast != null) return broadcast(network, hex);
    return BroadcastReport(
      txid: fakeTxid,
      backend: 'mempool.space',
      at: 1755000000,
    );
  }

  /// Status hook; the default reports the transaction waiting in the
  /// mempool. Throw a [BridgeException] to simulate a backend that
  /// cannot be reached.
  FutureOr<BroadcastStatus> Function(Network network, String hex)? onStatus;

  int statusCalls = 0;

  @override
  Future<BroadcastStatus> transactionStatus(Network network, String hex) async {
    statusCalls += 1;
    final status = onStatus;
    if (status != null) return status(network, hex);
    return BroadcastStatus(
      txid: fakeTxid,
      found: true,
      confirmed: false,
      confirmations: 0,
      backend: 'mempool.space',
      at: 1755000000,
    );
  }
}

/// A well-formed txid for previews and reports.
const String fakeTxid =
    'f1e2d3c4b5a60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// A signed-looking preview: one input from a watched wallet, one
/// payment, one change output, a modest fee.
TxPreview makePreview({
  bool ready = true,
  TxSource source = TxSource.psbt,
  Network network = Network.mainnet,
  List<TxWarning> warnings = const [],
  int? feeSats = 1000,
  double? feeRate = 7.1,
  List<TxInputPreview>? inputs,
  List<TxOutputPreview>? outputs,
}) {
  return TxPreview(
    txid: fakeTxid,
    source: source,
    network: network,
    inputs:
        inputs ??
        const [
          TxInputPreview(
            txid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
            vout: 1,
            valueSats: 100000,
            address: 'bc1qspentfromcoldstorage',
            signed: true,
            wallet: WalletRef(id: 'w1', name: 'Cold storage'),
          ),
        ],
    outputs:
        outputs ??
        const [
          TxOutputPreview(
            index: 0,
            valueSats: 90000,
            address: 'bc1qexternalpayee',
          ),
          TxOutputPreview(
            index: 1,
            valueSats: 9000,
            address: 'bc1qchangeback',
            wallet: WalletRef(id: 'w1', name: 'Cold storage'),
            change: true,
          ),
        ],
    feeSats: feeSats,
    feeRateSatVb: feeRate,
    vsize: 141,
    weight: 561,
    size: 222,
    version: 2,
    locktime: 0,
    rbf: true,
    ready: ready,
    warnings: warnings,
    hex: ready ? '0200000001deadbeef' : null,
  );
}
