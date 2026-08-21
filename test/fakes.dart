// A configurable in-memory bridge so widget tests never touch native
// code. Screens observe the same contract as the real bridge, including
// BridgeException errors.

import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';

WalletMeta makeMeta({
  String id = 'w1',
  String name = 'Cold storage',
  Network network = Network.mainnet,
  int totalSats = 0,
  SyncStamp? lastSync,
}) {
  return WalletMeta(
    id: id,
    name: name,
    network: network,
    recognizedAs: RecognizedKind.multipathDescriptor,
    createdAt: 1755000000,
    gapLimit: 20,
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
}) {
  return WalletSnapshot(
    meta: meta ?? makeMeta(totalSats: totalSats),
    balance: makeBalance(totalSats),
    txs: txs,
    tipHeight: tipHeight,
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
}) {
  return ParsedInput(
    kind: kind,
    networks: networks,
    payload: payload,
    warnings: warnings,
    rawJson: '{}',
  );
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
    this.onParse,
  }) : wallets = wallets ?? [],
       snapshots = snapshots ?? {},
       utxoMap = utxos ?? {},
       txDetails = txDetails ?? {},
       addresses = addresses ?? {};

  List<WalletMeta> wallets;
  Settings settings;
  Map<String, WalletSnapshot> snapshots;
  Map<String, List<UtxoInfo>> utxoMap;

  /// Keyed by `'$walletId:$txid'`.
  Map<String, TxDetail> txDetails;
  Map<String, List<AddressEntry>> addresses;

  /// Classification hook; throw a [BridgeException] to simulate a
  /// rejection (private material, unrecognized input, ...).
  ParsedInput Function(String input)? onParse;

  /// Every `set_app_pref` write, for assertions.
  final Map<String, String> appPrefs = {};

  /// Every backend save, for assertions.
  final Map<Network, BackendConfig> savedBackends = {};

  int addWalletCalls = 0;
  int syncWalletCalls = 0;
  int syncAllCalls = 0;
  Network? lastActiveNetworkSet;

  @override
  Future<ParsedInput> parseInput(String input) async {
    final parse = onParse;
    if (parse == null) {
      throw const BridgeException('unrecognized_input', 'no parser configured');
    }
    return parse(input);
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

  @override
  Future<List<AddressEntry>> receiveAddresses(String id, int lookahead) async {
    return addresses[id] ??
        const [AddressEntry(index: 0, address: 'tb1qexample', used: false)];
  }

  @override
  Future<SyncReport> syncWallet(String id) async {
    syncWalletCalls += 1;
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
  Future<SyncAllReport> syncAll([Network? network]) async {
    syncAllCalls += 1;
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

  @override
  Future<void> setActiveNetwork(Network network) async {
    lastActiveNetworkSet = network;
    settings = Settings(
      activeNetwork: network,
      backends: settings.backends,
      appPrefs: settings.appPrefs,
    );
  }

  @override
  Future<void> setBackend(Network network, BackendConfig config) async {
    savedBackends[network] = config;
    settings = Settings(
      activeNetwork: settings.activeNetwork,
      backends: {...settings.backends, network: config},
      appPrefs: settings.appPrefs,
    );
  }

  @override
  Future<void> setAppPref(String key, String value) async {
    appPrefs[key] = value;
  }
}
