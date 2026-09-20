// Typed facade over the Rust bridge. The generated bindings speak JSON
// strings; this layer decodes them into the models and turns `{"error"}`
// payloads into [BridgeException]s. Screens depend on [GerfautBridge]
// only, so tests can substitute a fake without touching native code.

import 'dart:convert';

import 'models.dart';
import 'rust/api.dart' as rust;

/// Error surfaced by the core, with a stable machine-readable kind.
///
/// Kinds match the desktop app: unrecognized_input, private_material,
/// invalid_input, network_mismatch, wallet_not_found, duplicate_wallet,
/// vault, sync, backend_unavailable, broadcast, descriptor, tor,
/// internal — plus the bridge-level not_initialized, bad_key, bad_json,
/// and the premium server's, which are [premiumErrorKinds].
class BridgeException implements Exception {
  const BridgeException(this.kind, this.message, {this.retryAfter});

  final String kind;
  final String message;

  /// Seconds the premium server asked to wait, with
  /// `premium_rate_limited` when it named a wait.
  final int? retryAfter;

  @override
  String toString() => message;
}

/// Every kind a premium call can fail with, and the whole of it.
///
/// Seven, where the core has ten: the bridge folds what a screen cannot
/// act on differently, the way the desktop app does. An answer that
/// does not decode goes under `premium_unreachable` — on a phone that
/// is a hotel's login page, not something to read out — and a
/// certificate or a heartbeat that does not check out is
/// `premium_invalid`, whichever of the two it was.
///
/// This list is what holds the screens to a sentence for each: a kind
/// added here and left unanswered fails the test that walks it.
const List<String> premiumErrorKinds = [
  'premium_no_key',
  'premium_unknown_key',
  'premium_no_paid_time',
  'premium_rejected',
  'premium_rate_limited',
  'premium_unreachable',
  'premium_invalid',
];

/// Every operation the app can ask of the core.
abstract class GerfautBridge {
  /// Classifies wallet material. `script` is the user's script type
  /// choice for a lone extended key; the core ignores it otherwise.
  Future<ParsedInput> parseInput(String input, {ScriptKind? script});

  /// Assembles the distinct QR frames scanned so far (plain text, UR,
  /// BBQr). Feed the growing list until [QrProgress.complete], then
  /// hand [QrProgress.text] to [parseInput].
  Future<QrProgress> assembleQr(List<String> frames);

  /// Reads a server address scanned or pasted into the backend form:
  /// the Electrum one-liner `host:port:s|t` node dashboards print, an
  /// `ssl://`/`tcp://` address, or an `http(s)://` Esplora endpoint.
  /// What comes back fills the fields; nothing is saved.
  Future<ScannedBackend> parseBackend(String input);
  Future<WalletMeta> addWallet(
    String name,
    ParsedInput parsed,
    Network network,
  );
  Future<List<WalletMeta>> listWallets([Network? network]);
  Future<WalletSnapshot> walletSnapshot(String id);

  /// The wallet's descriptor read as a spending policy: keys, branches
  /// and every timelock evaluated against the chain tip and the coins.
  /// A watched address yields a snapshot with no keys and no branches.
  Future<PolicySnapshot> walletPolicy(String id);
  Future<TxDetail> txDetail(String id, String txid);
  Future<List<UtxoInfo>> utxos(String id);
  Future<List<AddressEntry>> receiveAddresses(String id, int lookahead);

  /// Revealed addresses by keychain, with usage and the balance on
  /// each. Capped by the core to 200 rows per keychain.
  Future<AddressList> addressList(String id);

  /// Builds the CSV export of this wallet's transactions, filtered.
  /// Everything stays on this device.
  Future<ExportResult> exportTransactions(String id, ExportOptions options);
  Future<SyncReport> syncWallet(String id);

  /// Fetches an older round of history for a watched address and
  /// returns how many transactions were added. Zero means the history
  /// is complete.
  Future<int> loadMoreHistory(String id);
  Future<SyncAllReport> syncAll([Network? network]);
  Future<void> renameWallet(String id, String name);

  /// Changes the glyph a wallet shows next to its name.
  Future<void> setWalletIcon(String id, WalletIcon icon);

  /// Puts the listed wallets in that order. Wallets left out keep their
  /// slots, so the list of one network reorders without moving another
  /// network's wallets.
  Future<void> reorderWallets(List<String> ids);
  Future<void> removeWallet(String id);
  Future<Settings> getSettings();
  Future<void> setActiveNetwork(Network network);

  /// Sets the global gap limit (1..=500), applied on the next sync.
  Future<void> setGapLimit(int gapLimit);
  Future<void> setBackend(Network network, BackendConfig config);

  /// Public servers offered for a network, in settings order. Empty on
  /// regtest, which has no public server.
  Future<List<PublicServer>> publicServers(Network network);

  /// What an Electrum server's certificate amounts to right now, seen
  /// through the handshake a sync would open.
  Future<CertificateReport> inspectCertificate(String url);

  /// Remembers the certificate the user accepted for this server. That
  /// host must present exactly this one from then on.
  Future<void> trustCertificate(String url, String fingerprint);

  /// Drops an accepted certificate, keyed by `host:port`: the next
  /// connection to that host asks again.
  Future<void> forgetCertificate(String host);
  Future<void> setAppPref(String key, String value);
  Future<PriceQuote> fetchPrice(PriceSource source, FiatCurrency currency);
  Future<UpdateCheck> checkUpdate(String currentVersion);

  /// Decodes a transaction somebody else signed (PSBT as base64, hex or
  /// a binary file passed as hex; raw transaction as hex; a UR or BBQr
  /// envelope) and previews what it does on [network]. Nothing is
  /// signed, nothing is sent.
  Future<TxPreview> previewTransaction(String input, Network network);

  /// Hands a fully signed transaction to the backend of [network]. A
  /// refusal comes back as a [BridgeException] carrying the node's
  /// message verbatim.
  Future<BroadcastReport> broadcastTransaction(Network network, String hex);

  /// Where a broadcast transaction stands as the backend sees it.
  Future<BroadcastStatus> transactionStatus(Network network, String hex);

  /// Classifies wallet material with the advanced choices (script type,
  /// derivation paths). Inputs that fix their own ignore them.
  Future<ParsedInput> parseInputWithOptions(
    String input,
    ImportOptions options,
  );

  /// Scans a wallet again from its first address with the current gap
  /// limit, for funds an incremental sync can no longer see.
  Future<SyncReport> rescanWallet(String id);

  /// The lock in place, without its hash; null when there is none.
  Future<AppLock?> appLock();

  /// Sets a lock, or replaces its secret; replacing needs the current one.
  Future<void> setAppLock(LockKind kind, String secret, {String? current});
  Future<void> clearAppLock(String current);

  /// Tries a secret. The verdict carries the delay after repeated
  /// failures: while it runs, even the right secret is not looked at.
  Future<LockVerdict> verifyAppLock(String secret);

  Future<void> setBiometricUnlock(bool enabled, String current);

  /// Seals the chosen wallets under a password: a file and QR frames.
  Future<BackupBundle> exportBackup(BackupOptions options, String password);

  /// Opens a backup (base64 of the file, or the text a scan yields) and
  /// lists what it holds, before anything is added.
  Future<BackupPreview> previewBackup(String source, String password);
  Future<ImportReport> importBackup(
    String source,
    String password,
    ImportChoices choices,
  );

  /// Where Tor stands for `.onion` backends.
  Future<TorStatus> torStatus();
  Future<void> setTorSettings(TorSettings settings);

  /// Resolves the route now, bootstrapping the built-in client if that
  /// is the path. Up to a minute and a half on a first run.
  Future<TorRoute> torConnect();

  // --- live watch --------------------------------------------------------

  /// Starts the live watch of the active network. Idempotent across
  /// isolates: a watch already running is left as it is.
  Future<LiveWatchStatus> liveStart();

  /// Stops the live watch and closes its connection. Idempotent.
  Future<void> liveStop();

  /// Checks the connection now. The timers of a sleeping phone do not
  /// run, so an alarm and every change of network call this.
  Future<void> liveTick();

  /// Where the watch stands; off when none runs.
  Future<LiveWatchStatus> liveStatus();

  /// What the running watch says, for this isolate. Any number of
  /// isolates may listen; the core's single receiver is consumed in
  /// Rust and fanned out from there.
  Stream<LiveEvent> liveEvents();

  /// Of what a sync found, what nobody has announced yet, recorded as
  /// announced from now on. Every path that notifies from a sync of its
  /// own asks here first, so a transaction is said once per stage
  /// whoever saw it first.
  Future<List<LiveTx>> claimAnnouncements(SyncReport report);

  /// Whether anything this app sends has to go through Tor.
  Future<bool> usesTor();

  // --- premium -----------------------------------------------------------

  /// The premium account as the vault keeps it, the certificate's
  /// claims verified offline by the core. Never touches the network.
  Future<PremiumView> premiumState();

  /// Enters an account key: the core checks its shape, fetches the
  /// licence, verifies the certificate and stores both. Kinds:
  /// premium_unreachable, premium_unknown_key, premium_no_paid_time.
  Future<PremiumLicence> premiumActivate(String key);

  /// Fetches the certificate again with the stored key, for the time a
  /// renewal added, and stores it.
  Future<PremiumLicence> premiumRefreshLicence();

  /// Drops the key and its certificate from this device. The server
  /// goes on watching; the consents stay.
  Future<void> premiumForgetKey();

  /// Keeps the "watch is offline" banner quiet until [untilUnix], or
  /// lets it show again with null.
  Future<void> premiumAcknowledgeOffline(int? untilUnix);

  /// Paid time, counts and the network the server watches.
  Future<PremiumAccount> premiumAccount();

  /// The wallets the server watches for this key.
  Future<List<WalletWatch>> premiumWallets();

  /// Records the user's yes for [id] and hands the wallet to the server:
  /// its descriptors as the vault holds them, or its address when the
  /// wallet is a single address.
  Future<void> premiumWatchWallet(String id);

  /// Tells the server to stop watching [id]. The consent stays.
  Future<void> premiumUnwatchWallet(String id);
  Future<List<PremiumChannel>> premiumChannels();

  /// Adds a channel. [target] is the e-mail address or the webhook URL;
  /// nothing for Telegram, and nothing for ntfy, whose topic the core
  /// draws and returns once with the URL to subscribe to.
  Future<CreatedChannel> premiumCreateChannel(
    ChannelKind kind, {
    String? target,
    String? secret,
  });

  /// Confirms a channel with the code the server sent to it. Answers
  /// the channel, linked. A code that is wrong, expired or tried too
  /// often comes back as premium_rejected, in the server's words.
  Future<PremiumChannel> premiumConfirmChannel(String id, String code);
  Future<void> premiumDeleteChannel(String id);

  /// Sends a test message through a channel. A provider's refusal comes
  /// back as premium_rejected, in the server's words.
  Future<void> premiumTestChannel(String id);

  /// The last events of the account, newest first, at most twenty.
  Future<List<PremiumEvent>> premiumRecentEvents();

  /// The server's signed heartbeat, verified by the core against the
  /// embedded key and this device's clock. Any failure counts as a
  /// missed beat.
  Future<HeartbeatReport> premiumHeartbeat();

  /// Deletes the account on the server — the key, the wallets it
  /// watched, the channels, the log — and then forgets it here.
  /// Nothing local is dropped unless the server confirmed. There is no
  /// way back.
  Future<void> premiumDeleteAccount();
}

/// The real bridge, backed by the generated Rust bindings.
class RustBridge implements GerfautBridge {
  const RustBridge();

  /// Decodes a bridge payload, throwing on `{"error": ...}`.
  static dynamic _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> &&
        decoded['error'] is Map<String, dynamic>) {
      final error = decoded['error'] as Map<String, dynamic>;
      throw BridgeException(
        error['kind'] as String? ?? 'internal',
        error['message'] as String? ?? 'unknown error',
        retryAfter: error['retry_after'] as int?,
      );
    }
    return decoded;
  }

  static Map<String, dynamic> _object(String raw) =>
      _decode(raw) as Map<String, dynamic>;

  static List<Map<String, dynamic>> _list(String raw) =>
      (_decode(raw) as List).cast<Map<String, dynamic>>();

  static void _ok(String raw) => _decode(raw);

  @override
  Future<ParsedInput> parseInput(String input, {ScriptKind? script}) async {
    final raw = await rust.parseInput(input: input, script: script?.id);
    return ParsedInput.fromJson(_object(raw), raw);
  }

  @override
  Future<QrProgress> assembleQr(List<String> frames) async {
    final raw = await rust.assembleQr(framesJson: jsonEncode(frames));
    return QrProgress.fromJson(_object(raw));
  }

  @override
  Future<ScannedBackend> parseBackend(String input) async {
    final raw = await rust.parseBackend(input: input);
    return ScannedBackend.fromJson(_object(raw));
  }

  @override
  Future<WalletMeta> addWallet(
    String name,
    ParsedInput parsed,
    Network network,
  ) async {
    final raw = await rust.addWallet(
      name: name,
      parsedJson: parsed.rawJson,
      network: network.id,
    );
    return WalletMeta.fromJson(_object(raw));
  }

  @override
  Future<List<WalletMeta>> listWallets([Network? network]) async {
    final raw = await rust.listWallets(network: network?.id);
    return _list(raw).map(WalletMeta.fromJson).toList();
  }

  @override
  Future<WalletSnapshot> walletSnapshot(String id) async {
    return WalletSnapshot.fromJson(_object(await rust.walletSnapshot(id: id)));
  }

  @override
  Future<PolicySnapshot> walletPolicy(String id) async {
    return PolicySnapshot.fromJson(_object(await rust.walletPolicy(id: id)));
  }

  @override
  Future<TxDetail> txDetail(String id, String txid) async {
    return TxDetail.fromJson(_object(await rust.txDetail(id: id, txid: txid)));
  }

  @override
  Future<List<UtxoInfo>> utxos(String id) async {
    return _list(await rust.utxos(id: id)).map(UtxoInfo.fromJson).toList();
  }

  @override
  Future<List<AddressEntry>> receiveAddresses(String id, int lookahead) async {
    final raw = await rust.receiveAddresses(id: id, lookahead: lookahead);
    return _list(raw).map(AddressEntry.fromJson).toList();
  }

  @override
  Future<AddressList> addressList(String id) async {
    return AddressList.fromJson(_object(await rust.addressList(id: id)));
  }

  @override
  Future<ExportResult> exportTransactions(
    String id,
    ExportOptions options,
  ) async {
    final raw = await rust.exportTransactions(
      id: id,
      optionsJson: jsonEncode(options.toJson()),
    );
    return ExportResult.fromJson(_object(raw)['ok'] as Map<String, dynamic>);
  }

  @override
  Future<SyncReport> syncWallet(String id) async {
    return SyncReport.fromJson(_object(await rust.syncWallet(id: id)));
  }

  @override
  Future<int> loadMoreHistory(String id) async {
    return _decode(await rust.loadMoreHistory(id: id)) as int;
  }

  @override
  Future<SyncAllReport> syncAll([Network? network]) async {
    return SyncAllReport.fromJson(
      _object(await rust.syncAll(network: network?.id)),
    );
  }

  @override
  Future<void> renameWallet(String id, String name) async {
    _ok(await rust.renameWallet(id: id, name: name));
  }

  @override
  Future<void> setWalletIcon(String id, WalletIcon icon) async {
    _ok(await rust.setWalletIcon(id: id, icon: icon.id));
  }

  @override
  Future<void> reorderWallets(List<String> ids) async {
    _ok(await rust.reorderWallets(ids: ids));
  }

  @override
  Future<void> removeWallet(String id) async {
    _ok(await rust.removeWallet(id: id));
  }

  @override
  Future<Settings> getSettings() async {
    return Settings.fromJson(_object(await rust.getSettings()));
  }

  @override
  Future<void> setActiveNetwork(Network network) async {
    _ok(await rust.setActiveNetwork(network: network.id));
  }

  @override
  Future<void> setGapLimit(int gapLimit) async {
    _ok(await rust.setGapLimit(gapLimit: gapLimit));
  }

  @override
  Future<void> setBackend(Network network, BackendConfig config) async {
    _ok(
      await rust.setBackend(
        network: network.id,
        configJson: jsonEncode(config.toJson()),
      ),
    );
  }

  @override
  Future<List<PublicServer>> publicServers(Network network) async {
    final raw = await rust.publicServers(network: network.id);
    return _list(raw).map(PublicServer.fromJson).toList();
  }

  @override
  Future<CertificateReport> inspectCertificate(String url) async {
    final raw = await rust.inspectCertificate(url: url);
    return CertificateReport.fromJson(_object(raw));
  }

  @override
  Future<void> trustCertificate(String url, String fingerprint) async {
    _ok(await rust.trustCertificate(url: url, fingerprint: fingerprint));
  }

  @override
  Future<void> forgetCertificate(String host) async {
    _ok(await rust.forgetCertificate(host: host));
  }

  @override
  Future<void> setAppPref(String key, String value) async {
    _ok(await rust.setAppPref(key: key, value: value));
  }

  @override
  Future<PriceQuote> fetchPrice(
    PriceSource source,
    FiatCurrency currency,
  ) async {
    final raw = await rust.fetchPrice(source: source.id, currency: currency.id);
    return PriceQuote.fromJson(_object(raw));
  }

  @override
  Future<UpdateCheck> checkUpdate(String currentVersion) async {
    final raw = await rust.checkUpdate(currentVersion: currentVersion);
    return UpdateCheck.fromJson(_object(raw));
  }

  @override
  Future<TxPreview> previewTransaction(String input, Network network) async {
    final raw = await rust.previewTransaction(
      input: input,
      network: network.id,
    );
    return TxPreview.fromJson(_object(raw));
  }

  @override
  Future<BroadcastReport> broadcastTransaction(
    Network network,
    String hex,
  ) async {
    final raw = await rust.broadcastTransaction(network: network.id, hex: hex);
    return BroadcastReport.fromJson(_object(raw));
  }

  @override
  Future<BroadcastStatus> transactionStatus(Network network, String hex) async {
    final raw = await rust.transactionStatus(network: network.id, hex: hex);
    return BroadcastStatus.fromJson(_object(raw));
  }

  @override
  Future<ParsedInput> parseInputWithOptions(
    String input,
    ImportOptions options,
  ) async {
    final raw = await rust.parseInputWithOptions(
      input: input,
      optionsJson: jsonEncode(options.toJson()),
    );
    return ParsedInput.fromJson(_object(raw), raw);
  }

  @override
  Future<SyncReport> rescanWallet(String id) async {
    return SyncReport.fromJson(_object(await rust.rescanWallet(id: id)));
  }

  @override
  Future<AppLock?> appLock() async {
    final decoded = _decode(await rust.appLock());
    if (decoded == null) return null;
    return AppLock.fromJson(decoded as Map<String, dynamic>);
  }

  @override
  Future<void> setAppLock(
    LockKind kind,
    String secret, {
    String? current,
  }) async {
    _ok(await rust.setAppLock(kind: kind.id, secret: secret, current: current));
  }

  @override
  Future<void> clearAppLock(String current) async {
    _ok(await rust.clearAppLock(current: current));
  }

  @override
  Future<LockVerdict> verifyAppLock(String secret) async {
    return LockVerdict.fromJson(
      _object(await rust.verifyAppLock(secret: secret)),
    );
  }

  @override
  Future<void> setBiometricUnlock(bool enabled, String current) async {
    _ok(await rust.setBiometricUnlock(enabled: enabled, current: current));
  }

  @override
  Future<BackupBundle> exportBackup(
    BackupOptions options,
    String password,
  ) async {
    final raw = await rust.exportBackup(
      optionsJson: jsonEncode(options.toJson()),
      password: password,
    );
    return BackupBundle.fromJson(_object(raw));
  }

  @override
  Future<BackupPreview> previewBackup(String source, String password) async {
    final raw = await rust.previewBackup(source: source, password: password);
    return BackupPreview.fromJson(_object(raw));
  }

  @override
  Future<ImportReport> importBackup(
    String source,
    String password,
    ImportChoices choices,
  ) async {
    final raw = await rust.importBackup(
      source: source,
      password: password,
      choicesJson: jsonEncode(choices.toJson()),
    );
    return ImportReport.fromJson(_object(raw));
  }

  @override
  Future<TorStatus> torStatus() async {
    return TorStatus.fromJson(_object(await rust.torStatus()));
  }

  @override
  Future<void> setTorSettings(TorSettings settings) async {
    _ok(await rust.setTorSettings(settingsJson: jsonEncode(settings.toJson())));
  }

  @override
  Future<TorRoute> torConnect() async {
    return TorRoute.fromJson(_object(await rust.torConnect()));
  }

  @override
  Future<LiveWatchStatus> liveStart() async {
    return LiveWatchStatus.fromJson(_object(await rust.liveStart()));
  }

  @override
  Future<void> liveStop() async {
    _ok(await rust.liveStop());
  }

  @override
  Future<void> liveTick() async {
    _ok(await rust.liveTick());
  }

  @override
  Future<LiveWatchStatus> liveStatus() async {
    return LiveWatchStatus.fromJson(_object(await rust.liveStatus()));
  }

  @override
  Stream<LiveEvent> liveEvents() async* {
    await for (final raw in rust.liveEvents()) {
      final LiveEvent? event;
      try {
        event = LiveEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // One event that does not read must not end the stream.
        continue;
      }
      if (event != null) yield event;
    }
  }

  @override
  Future<List<LiveTx>> claimAnnouncements(SyncReport report) async {
    final raw = await rust.claimAnnouncements(
      findingsJson: jsonEncode(report.toFindingsJson()),
    );
    return _list(raw).map(LiveTx.fromJson).toList();
  }

  @override
  Future<bool> usesTor() async {
    return _decode(await rust.usesTor()) as bool;
  }

  @override
  Future<PremiumView> premiumState() async {
    return PremiumView.fromJson(_object(await rust.premiumState()));
  }

  @override
  Future<PremiumLicence> premiumActivate(String key) async {
    return PremiumLicence.fromJson(
      _object(await rust.premiumActivate(key: key)),
    );
  }

  @override
  Future<PremiumLicence> premiumRefreshLicence() async {
    return PremiumLicence.fromJson(_object(await rust.premiumRefreshLicence()));
  }

  @override
  Future<void> premiumForgetKey() async {
    _ok(await rust.premiumForgetKey());
  }

  @override
  Future<void> premiumAcknowledgeOffline(int? untilUnix) async {
    _ok(await rust.premiumAcknowledgeOffline(until: untilUnix));
  }

  @override
  Future<PremiumAccount> premiumAccount() async {
    return PremiumAccount.fromJson(_object(await rust.premiumAccount()));
  }

  @override
  Future<List<WalletWatch>> premiumWallets() async {
    return _list(await rust.premiumWallets())
        .map(WalletWatch.fromJson)
        .toList();
  }

  @override
  Future<void> premiumWatchWallet(String id) async {
    _ok(await rust.premiumWatchWallet(id: id));
  }

  @override
  Future<void> premiumUnwatchWallet(String id) async {
    _ok(await rust.premiumUnwatchWallet(id: id));
  }

  @override
  Future<List<PremiumChannel>> premiumChannels() async {
    return _list(await rust.premiumChannels())
        .map(PremiumChannel.fromJson)
        .toList();
  }

  @override
  Future<CreatedChannel> premiumCreateChannel(
    ChannelKind kind, {
    String? target,
    String? secret,
  }) async {
    final raw = await rust.premiumCreateChannel(
      kind: kind.id,
      target: target,
      secret: secret,
    );
    return CreatedChannel.fromJson(_object(raw));
  }

  @override
  Future<PremiumChannel> premiumConfirmChannel(String id, String code) async {
    return PremiumChannel.fromJson(
      _object(await rust.premiumConfirmChannel(id: id, code: code)),
    );
  }

  @override
  Future<void> premiumDeleteChannel(String id) async {
    _ok(await rust.premiumDeleteChannel(id: id));
  }

  @override
  Future<void> premiumTestChannel(String id) async {
    _ok(await rust.premiumTestChannel(id: id));
  }

  @override
  Future<List<PremiumEvent>> premiumRecentEvents() async {
    return _list(await rust.premiumRecentEvents())
        .map(PremiumEvent.fromJson)
        .toList();
  }

  @override
  Future<HeartbeatReport> premiumHeartbeat() async {
    return HeartbeatReport.fromJson(_object(await rust.premiumHeartbeat()));
  }

  @override
  Future<void> premiumDeleteAccount() async {
    _ok(await rust.premiumDeleteAccount());
  }
}
