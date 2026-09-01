// A configurable in-memory bridge so widget tests never touch native
// code. Screens observe the same contract as the real bridge, including
// BridgeException errors.

import 'dart:async';
import 'dart:typed_data';

import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/disguise.dart';
import 'package:gerfaut/src/documents.dart';
import 'package:gerfaut/src/electrum.dart';
import 'package:gerfaut/src/home_widgets.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/screen.dart';
import 'package:gerfaut/src/window.dart';
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

/// Records what the window was asked to be instead of touching the
/// activity.
class FakeWindowGuard implements WindowGuard {
  final List<bool> calls = [];

  /// The last state asked for; null when nothing was asked yet.
  bool? get secure => calls.isEmpty ? null : calls.last;

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

/// Remembers which face the launcher shows instead of touching the
/// package manager.
class FakeDisguise implements Disguise {
  FakeDisguise({this.disguised = false});

  bool disguised;
  bool widgetsEnabled = true;

  /// Every call, in order, for assertions.
  final List<String> calls = [];

  @override
  Future<bool> isDisguised() async => disguised;

  @override
  Future<void> setDisguised(bool disguised) async {
    calls.add('disguise:$disguised');
    this.disguised = disguised;
  }

  @override
  Future<void> setWidgetsEnabled(bool enabled) async {
    calls.add('widgets:$enabled');
    widgetsEnabled = enabled;
  }
}

/// Counts what the screen was asked instead of touching the platform.
class FakeScreenKeeper implements ScreenKeeper {
  int holds = 0;
  int releases = 0;

  /// Whether the screen is being kept on right now.
  bool get on => holds > releases;

  @override
  Future<void> keepOn() async => holds++;

  @override
  Future<void> release() async => releases++;
}

/// Holds what the widgets would read, and counts the redraws, instead
/// of reaching the launcher.
class FakeWidgetBoard implements WidgetBoard {
  FakeWidgetBoard({Set<String> installed = const {}})
    : installed = {...installed};

  /// The provider names the fake reports as placed on a home screen.
  Set<String> installed;

  /// What the store holds right now: a removed key is gone from here.
  final Map<String, String> data = {};

  /// Every redraw asked for, in order.
  final List<String> updates = [];

  /// How many times the set of placed widgets was asked for.
  int installedAsks = 0;

  @override
  Future<void> saveWidgetData(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> updateWidget(String name) async => updates.add(name);

  @override
  Future<Set<String>> installedWidgets() async {
    installedAsks++;
    return {...installed};
  }
}

/// Records what would have been written instead of opening the
/// system's save dialog.
class FakeDocumentSaver implements DocumentSaver {
  FakeDocumentSaver({this.answer = true});

  /// What the dialog answers: true for a place picked, false for a
  /// dialog waved away.
  bool answer;

  /// A failure to raise instead of answering.
  DocumentSaveException? failure;

  final List<({Uint8List bytes, String filename, String mimeType})> saved = [];

  @override
  Future<bool> save({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (failure != null) throw failure!;
    if (answer) {
      saved.add((bytes: bytes, filename: filename, mimeType: mimeType));
    }
    return answer;
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

BalanceSnapshot makeBalance(int totalSats, {int? pendingNetSats}) {
  return BalanceSnapshot(
    confirmed: totalSats,
    trustedPending: 0,
    untrustedPending: 0,
    immature: 0,
    total: totalSats,
    pendingNetSats: pendingNetSats,
  );
}

WalletSnapshot makeSnapshot({
  WalletMeta? meta,
  int totalSats = 0,
  int? pendingNetSats,
  List<TxSummary> txs = const [],
  int tipHeight = 0,
  bool truncated = false,
}) {
  return WalletSnapshot(
    meta: meta ?? makeMeta(totalSats: totalSats),
    balance: makeBalance(totalSats, pendingNetSats: pendingNetSats),
    txs: txs,
    tipHeight: tipHeight,
    truncated: truncated,
  );
}

/// One key of a policy fixture, with a stand-in for the key material.
PolicyKey makePolicyKey(int index, {String? fingerprint, String? originPath}) {
  final letter = String.fromCharCode(0x41 + index);
  return PolicyKey(
    id: 'k$index',
    label: 'Key $letter',
    fingerprint: fingerprint ?? '0000000$index',
    originPath: originPath ?? "m/84'/1'/0'",
    keyShort: 'tpubKey$letter…$index$index$index$index',
  );
}

/// A single-key policy: one primary branch, open now. The default the
/// fake bridge hands out for any wallet nobody configured.
PolicySnapshot makePolicy({
  PolicyKind kind = PolicyKind.singleKey,
  ScriptKind script = ScriptKind.segwit,
  String descriptor = 'wpkh(tpub.../0/*)#checksum',
  String policy = 'pk(Key A)',
  List<PolicyKey>? keys,
  List<PolicyBranch>? branches,
  int tipHeight = 800000,
  int computedAt = 1750000000,
  int coins = 0,
  bool hasTimelocks = false,
}) {
  return PolicySnapshot(
    kind: kind,
    script: script,
    descriptor: descriptor,
    policy: policy,
    keys: keys ?? [makePolicyKey(0)],
    branches:
        branches ??
        const [
          PolicyBranch(
            id: 'b0',
            role: BranchRole.primary,
            label: 'Primary',
            summary: 'Key A',
            condition: KeyCondition(keyId: 'k0'),
            timelocks: [],
            state: SpendableNow(),
            spendableNow: true,
          ),
        ],
    tipHeight: tipHeight,
    computedAt: computedAt,
    timeBasis: TimeBasis.wallClock,
    coins: coins,
    hasTimelocks: hasTimelocks,
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
  DerivationChoice? derivation,
  bool derivationEditable = false,
}) {
  return ParsedInput(
    kind: kind,
    networks: networks,
    payload: payload,
    warnings: warnings,
    rawJson: '{}',
    scriptOptions: scriptOptions,
    previewAddress: previewAddress,
    derivation:
        derivation ?? (derivationEditable ? DerivationChoice.standard : null),
    derivationEditable: derivationEditable,
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

  /// Server address hook; the default refuses everything the way the
  /// core refuses what is not an address. Return a [ScannedBackend] to
  /// stand in for a QR code a node printed.
  ScannedBackend Function(String input)? onParseBackend;

  /// Every address handed to parseBackend, for assertions.
  final List<String> parsedBackends = [];

  @override
  Future<ScannedBackend> parseBackend(String input) async {
    parsedBackends.add(input);
    final parse = onParseBackend;
    if (parse == null) {
      throw const BridgeException('server', 'nothing to read');
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

  /// Policies by wallet id; a wallet with none gets a single-key one.
  final Map<String, PolicySnapshot> policies = {};

  /// Policy hook; throw a [BridgeException] to simulate a descriptor
  /// the core cannot read, or return a future that never completes to
  /// hold the screen in its loading state. Takes precedence over
  /// [policies] when set.
  FutureOr<PolicySnapshot> Function(String id)? onWalletPolicy;

  @override
  Future<PolicySnapshot> walletPolicy(String id) async {
    final policy = onWalletPolicy;
    if (policy != null) return await policy(id);
    return policies[id] ?? makePolicy();
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

  /// Holds a sync in flight, for a test that looks at what the screen
  /// does while one runs. Completed, the sync finishes.
  Completer<void>? syncGate;

  @override
  Future<SyncReport> syncWallet(String id) async {
    syncWalletCalls += 1;
    await syncGate?.future;
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

  /// Held open by a test that wants the screen to go away while a
  /// rename is still in flight.
  Completer<void>? renameGate;

  @override
  Future<void> renameWallet(String id, String name) async {
    final gate = renameGate;
    if (gate != null) await gate.future;
    wallets = [
      for (final wallet in wallets)
        if (wallet.id == id) makeMeta(id: id, name: name) else wallet,
    ];
    // The core keeps one record per wallet: the snapshot carries the new
    // name too, not only the list.
    final snapshot = snapshots[id];
    if (snapshot == null) return;
    final meta = snapshot.meta;
    snapshots[id] = WalletSnapshot(
      meta: WalletMeta(
        id: meta.id,
        name: name,
        network: meta.network,
        kind: meta.kind,
        recognizedAs: meta.recognizedAs,
        createdAt: meta.createdAt,
        gapLimit: meta.gapLimit,
        scanGap: meta.scanGap,
        lastSync: meta.lastSync,
        cachedBalance: meta.cachedBalance,
        cachedTxCount: meta.cachedTxCount,
      ),
      balance: snapshot.balance,
      txs: snapshot.txs,
      tipHeight: snapshot.tipHeight,
      truncated: snapshot.truncated,
    );
  }

  @override
  Future<void> removeWallet(String id) async {
    wallets = wallets.where((w) => w.id != id).toList();
    snapshots.remove(id);
  }

  @override
  Future<Settings> getSettings() async {
    // The vault carries the lock: the settings screen reads it there,
    // the same place the core keeps it.
    return Settings(
      activeNetwork: settings.activeNetwork,
      backends: settings.backends,
      appPrefs: settings.appPrefs,
      gapLimit: settings.gapLimit,
      electrumCerts: settings.electrumCerts,
      appLock: lock,
      tor: settings.tor,
    );
  }

  /// Rewrites the stored settings one field at a time, the way the
  /// vault does: everything left out stays as it was.
  void _store({
    Network? activeNetwork,
    Map<Network, BackendConfig>? backends,
    int? gapLimit,
    Map<String, String>? electrumCerts,
    TorSettings? tor,
  }) {
    settings = Settings(
      activeNetwork: activeNetwork ?? settings.activeNetwork,
      backends: backends ?? settings.backends,
      appPrefs: settings.appPrefs,
      gapLimit: gapLimit ?? settings.gapLimit,
      electrumCerts: electrumCerts ?? settings.electrumCerts,
      appLock: settings.appLock,
      tor: tor ?? settings.tor,
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

  /// Fee hook; the default answers a plausible market on every network
  /// but regtest. Return null for a network with no fee market, throw a
  /// [BridgeException] for a source that did not answer.
  FutureOr<FeeEstimates?> Function(Network network)? onFetchFees;

  /// Every network handed to fetchFees, for assertions.
  final List<Network> feeCalls = [];

  @override
  Future<FeeEstimates?> fetchFees(Network network) async {
    feeCalls.add(network);
    final fetch = onFetchFees;
    if (fetch != null) return fetch(network);
    if (network == Network.regtest) return null;
    return const FeeEstimates(
      fastest: 12,
      halfHour: 8.5,
      hour: 4,
      economy: 2,
      minimum: 1,
      at: 1755000000,
    );
  }

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

  /// Advanced import hook; the default routes to [parseInput] with the
  /// script of the options, so screens keep their existing fakes.
  FutureOr<ParsedInput> Function(String input, ImportOptions options)?
  onParseWithOptions;

  /// The options of every parseInputWithOptions call, for assertions.
  final List<ImportOptions> parseOptions = [];

  @override
  Future<ParsedInput> parseInputWithOptions(
    String input,
    ImportOptions options,
  ) async {
    parseOptions.add(options);
    final parse = onParseWithOptions;
    if (parse != null) return parse(input, options);
    return parseInput(input, script: options.script);
  }

  int rescanCalls = 0;

  /// Rescan hook; the default behaves like a sync.
  FutureOr<SyncReport> Function(String id)? onRescan;

  @override
  Future<SyncReport> rescanWallet(String id) async {
    rescanCalls += 1;
    final rescan = onRescan;
    if (rescan != null) return rescan(id);
    return syncWallet(id);
  }

  /// The lock in place; null when none. Tests set it directly.
  AppLock? lock;

  /// The secret behind [lock]; every verify compares against it.
  String lockSecret = '1234';
  int lockFailures = 0;

  /// Every lock operation, in order, for assertions.
  final List<String> lockCalls = [];

  @override
  Future<AppLock?> appLock() async => lock;

  @override
  Future<void> setAppLock(
    LockKind kind,
    String secret, {
    String? current,
  }) async {
    lockCalls.add('set:${kind.id}');
    if (lock != null && current != lockSecret) {
      throw const BridgeException('lock', 'wrong PIN or password');
    }
    lockSecret = secret;
    lock = AppLock(kind: kind, biometric: lock?.biometric ?? false);
  }

  @override
  Future<void> clearAppLock(String current) async {
    lockCalls.add('clear');
    if (current != lockSecret) {
      throw const BridgeException('lock', 'wrong PIN or password');
    }
    lock = null;
  }

  @override
  Future<LockVerdict> verifyAppLock(String secret) async {
    lockCalls.add('verify');
    if (lock == null) throw const BridgeException('lock', 'no lock is set');
    if (secret == lockSecret) {
      lockFailures = 0;
      return const LockVerdict(unlocked: true, failures: 0, retryAfterSecs: 0);
    }
    lockFailures += 1;
    return LockVerdict(
      unlocked: false,
      failures: lockFailures,
      retryAfterSecs: lockFailures >= 3 ? 5 : 0,
    );
  }

  @override
  Future<void> setBiometricUnlock(bool enabled, String current) async {
    lockCalls.add('biometric:$enabled');
    final existing = lock;
    if (existing == null) throw const BridgeException('lock', 'no lock is set');
    if (current != lockSecret) {
      throw const BridgeException('lock', 'wrong PIN or password');
    }
    lock = AppLock(kind: existing.kind, biometric: enabled);
  }

  /// Backup hooks. The defaults seal nothing: a bundle with one frame
  /// per wallet, and a preview listing the fake's wallets.
  FutureOr<BackupBundle> Function(BackupOptions options, String password)?
  onExportBackup;
  FutureOr<BackupPreview> Function(String source, String password)?
  onPreviewBackup;
  FutureOr<ImportReport> Function(
    String source,
    String password,
    ImportChoices choices,
  )?
  onImportBackup;
  final List<BackupOptions> backupExportCalls = [];
  final List<ImportChoices> importCalls = [];

  @override
  Future<BackupBundle> exportBackup(
    BackupOptions options,
    String password,
  ) async {
    backupExportCalls.add(options);
    final export = onExportBackup;
    if (export != null) return export(options, password);
    final ids = options.walletIds;
    final chosen = ids == null
        ? wallets
        : wallets.where((w) => ids.contains(w.id)).toList();
    return BackupBundle(
      data: 'R0ZCQUNLVVA=',
      frames: [
        for (var i = 0; i < chosen.length; i++)
          'ur:bytes/${i + 1}-${chosen.length}/fake',
      ],
      walletCount: chosen.length,
      sizeBytes: 512,
    );
  }

  @override
  Future<BackupPreview> previewBackup(String source, String password) async {
    final preview = onPreviewBackup;
    if (preview != null) return preview(source, password);
    return BackupPreview(
      createdAt: 1755000000,
      hasSettings: false,
      wallets: [
        for (final (i, w) in wallets.indexed)
          BackupWalletPreview(
            index: i,
            name: w.name,
            network: w.network,
            kind: w.kind,
            alreadyWatched: true,
          ),
      ],
    );
  }

  @override
  Future<ImportReport> importBackup(
    String source,
    String password,
    ImportChoices choices,
  ) async {
    importCalls.add(choices);
    final import = onImportBackup;
    if (import != null) return import(source, password, choices);
    return const ImportReport(added: [], skipped: 0, settingsApplied: false);
  }

  /// Tor hooks. The default status reports the settings' mode with
  /// nothing running; connect answers a system route.
  TorStatus Function(TorSettings settings)? onTorStatus;
  FutureOr<TorRoute> Function()? onTorConnect;
  final List<TorSettings> torSettingsCalls = [];

  @override
  Future<TorStatus> torStatus() async {
    final status = onTorStatus;
    if (status != null) return status(settings.tor);
    return TorStatus(
      mode: settings.tor.mode,
      socksProxy: settings.tor.socksProxy ?? '127.0.0.1:9050',
      via: null,
      socks: null,
      running: false,
      bootstrapped: false,
      bootstrapPercent: 0,
      error: null,
      embeddedAvailable: true,
    );
  }

  @override
  Future<void> setTorSettings(TorSettings tor) async {
    torSettingsCalls.add(tor);
    settings = Settings(
      activeNetwork: settings.activeNetwork,
      backends: settings.backends,
      appPrefs: settings.appPrefs,
      gapLimit: settings.gapLimit,
      electrumCerts: settings.electrumCerts,
      appLock: settings.appLock,
      tor: tor,
    );
  }

  @override
  Future<TorRoute> torConnect() async {
    final connect = onTorConnect;
    if (connect != null) return connect();
    return const TorRoute(socks: '127.0.0.1:9050', via: TorVia.system);
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
