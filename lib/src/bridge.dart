// Typed facade over the Rust bridge. The generated bindings speak JSON
// strings; this layer decodes them into the models and turns `{"error"}`
// payloads into [BridgeException]s. Screens depend on [GerfautBridge]
// only, so tests can substitute a fake without touching native code.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show BaseHandler, NormalTask, PanicException, RustStreamSink, SyncTask;

import 'models.dart';
import 'rust/api.dart' as rust;

/// Error surfaced by the core, with a stable machine-readable kind.
///
/// A failure of the core comes under the core's own code (`ErrorCode`
/// in gerfaut-core), the one the desktop app reads too:
/// unrecognized_input, private_material, invalid_input, too_many_parts,
/// network_mismatch, wallet_not_found, duplicate_wallet, wrong_key,
/// vault_in_use, vault, unreadable_backup, newer_format, sync,
/// false_proof, broadcast, backend_unavailable, tor, descriptor, internal. The
/// bridge adds its own: not_initialized, bad_key, bad_json, random and
/// live_running.
class BridgeException implements Exception {
  const BridgeException(this.kind, this.message);

  final String kind;
  final String message;

  @override
  String toString() => message;
}

/// What a screen says when the core failed in a way it has no words
/// for: a panic, caught at the bridge.
const String internalFailure =
    'Something went wrong inside Gerfaut. Try again; if it happens again, '
    'restart the app.';

/// A panic in the core reaches Dart as an error of the bridge's own,
/// outside every `{"error": ...}`: the screens, which catch a
/// [BridgeException], would let it through and say nothing, the button
/// set free and nobody told. It comes back as one, with a sentence fit
/// for a screen; the panic's own words are a backtrace.
Future<T> guardPanics<T>(Future<T> call) async {
  try {
    return await call;
  } on PanicException {
    throw const BridgeException('internal', internalFailure);
  }
}

/// The one place a panic of the core is caught: every call to the core
/// goes through the handler given to `RustLib.init`, the streams of
/// Live included, so no call can be left out of it.
///
/// A call answers its caller with the [BridgeException] of
/// [guardPanics]. A stream cannot carry the panic: the generated code
/// drops the call behind it, and the stream merely ends. The end of
/// that call is kept against the stream instead, for
/// [endsWithItsCall] to raise once the stream is done.
class PanicGuard extends BaseHandler {
  @override
  Future<S> executeNormal<S, E extends Object>(NormalTask<S, E> task) {
    // The call has set its sinks up by the time this returns: each one
    // has its stream.
    final call = super.executeNormal(task);
    return guardCall(
      call,
      streams: [
        for (final arg in task.argValues)
          if (arg is RustStreamSink) arg.stream,
      ],
    );
  }

  @override
  S executeSync<S, E extends Object, WireSyncType>(
    SyncTask<S, E, WireSyncType> task,
  ) {
    try {
      return super.executeSync(task);
    } on PanicException {
      throw const BridgeException('internal', internalFailure);
    }
  }
}

/// How each stream of the core ended on the Rust side: null, or the
/// failure that cut it short.
final Expando<Future<Object?>> _callEnds = Expando('the call of a stream');

/// [PanicGuard] for one call, given the streams it feeds.
@visibleForTesting
Future<S> guardCall<S>(
  Future<S> call, {
  List<Stream<Object?>> streams = const [],
}) {
  final guarded = guardPanics(call);
  if (streams.isEmpty) return guarded;
  // Listening here is also what keeps a failure nobody awaits from
  // reaching the zone as an uncaught error.
  final end = guarded.then<Object?>(
    (_) => null,
    onError: (Object failure) => failure,
  );
  for (final stream in streams) {
    _callEnds[stream] = end;
  }
  return guarded;
}

/// [stream], then the failure its call ended with, if any: a stream of
/// the core that a panic cut short ends on a [BridgeException] rather
/// than as if it had simply finished.
Stream<T> endsWithItsCall<T>(Stream<T> stream) async* {
  yield* stream;
  final failure = await _callEnds[stream];
  if (failure != null) throw failure;
}

/// Said when a sync stopped on a server whose proof of a confirmation
/// did not hold. The core alone names such a failure (`false_proof`);
/// its own words name a server and a layer, these say what happened.
const String falseProofMessage =
    'This server sent a false proof of a confirmation. Gerfaut stopped '
    'trusting it and asked another.';

/// What a wallet's freshness line says of a failed sync: the core's own
/// words, except for a false proof, which has a sentence of its own.
String syncFailure(Object error) =>
    error is BridgeException && error.kind == 'false_proof'
    ? falseProofMessage
    : '$error';

/// The same, for a failure the core hands over as data, by its code and
/// in its words: a wallet a sync of all of them could not sync, or a
/// sync the live watch ran.
String reportedFailure(String kind, String message) =>
    syncFailure(BridgeException(kind, message));

/// What the page says when the core refuses wallet material handed to
/// it: pasted, scanned, read from a file or from a backup.
///
/// The core's own words, verbatim, except for two refusals whose words
/// name a layer instead of the thing refused. A private key is refused
/// wherever it comes from, and the sentence says what to bring instead.
/// A descriptor the wallet engine will not take is said to be that,
/// with the engine's reason after it.
String materialRefusal(BridgeException error, {bool backup = false}) {
  return switch (error.kind) {
    'private_material' when backup =>
      'A wallet in this backup holds a private key, and Gerfaut only '
          'watches: nothing was restored.',
    'private_material' =>
      'This holds a private key, and Gerfaut only watches: nothing was '
          'saved. Bring the public descriptor or extended public key '
          'instead.',
    'descriptor' =>
      'This descriptor could not be used: '
          '${error.message.replaceFirst('descriptor error: ', '')}',
    _ => error.message,
  };
}

/// Every operation the app can ask of the core.
abstract class GerfautBridge {
  /// Classifies wallet material. `script` is the user's script type
  /// choice for a lone extended key; the core ignores it otherwise.
  Future<ParsedInput> parseInput(String input, {ScriptKind? script});

  /// Assembles the distinct QR frames scanned so far (plain text, UR,
  /// BBQr). Feed the growing list until [QrProgress.complete], then
  /// hand [QrProgress.text] to [parseInput]. The scanner uses a scan the
  /// core holds instead: [openQrScan], [pushQrFrame], [closeQrScan].
  Future<QrProgress> assembleQr(List<String> frames);

  /// Opens a scan the core holds while the scanner is up, and gives the
  /// number its frames go under.
  Future<int> openQrScan();

  /// Sends one new frame to an open scan: where it stands after it, as
  /// [assembleQr] says of every frame so far. Once it answers with its
  /// text or a refusal, the core starts the scan again empty.
  Future<QrProgress> pushQrFrame(int scan, String frame);

  /// Lets the core drop a scan; one already closed stays closed.
  Future<void> closeQrScan(int scan);

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

  /// Puts a wallet ahead of the others in Live, or back among them: when
  /// Live cannot follow every address, pinned wallets come first.
  Future<void> setWalletLivePinned(String id, bool pinned);

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

  /// Stores one preference of this app alone.
  Future<void> setAppPref(String key, String value);

  /// Changes some of the preferences both apps keep, and answers them
  /// all as the vault stored them: the currency wins, the source
  /// follows.
  Future<Preferences> setPreferences(PreferencesChange change);

  /// The currencies and price sources on offer, and how often the price
  /// is asked.
  Future<PriceTable> priceTable();

  /// The current BTC price, in the currency and from the source of the
  /// preferences.
  Future<PriceQuote> fetchPrice();

  /// What to say about releases to someone running [currentVersion].
  /// Reads only.
  Future<UpdateStatus> updateStatus(String currentVersion);

  /// The wallets came on screen, unlocked and not disguised: the core
  /// asks for the latest release if a check is due.
  Future<UpdateStatus> updateSession(String currentVersion);

  /// The button in About: asks for the latest release now, due or not.
  Future<UpdateStatus> checkUpdate(String currentVersion);

  /// Closes the notice on the release it announced.
  Future<void> dismissUpdate(String version);

  /// Turns the daily check on or off.
  Future<void> setUpdateAutomatic(bool automatic);

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

  /// The last transactions sent on [network], newest first, as the
  /// vault keeps them.
  Future<List<RecentBroadcast>> recentBroadcasts(Network network);

  /// Drops the vault's record of a broadcast; the transaction itself is
  /// on the network and untouched.
  Future<void> forgetBroadcast(String txid);

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

  /// Starts the live watch of the active network and yields everything
  /// it says to this one caller, until [LiveStopped]. Each
  /// [LiveTransaction] has been taken off the core's record: the caller
  /// announces it, or it is never said. One caller at a time; another
  /// one gets a `live_running` error and nothing else.
  Stream<LiveEvent> liveRun();

  /// Stops the live watch and closes its connection. Idempotent.
  Future<void> liveStop();

  /// Checks the connection now. The timers of a sleeping phone do not
  /// run, so an alarm and every change of network call this.
  Future<void> liveTick();

  /// Where the watch stands; off when none runs.
  Future<LiveWatchStatus> liveStatus();

  /// What the watch takes on any server and on the user's own node, for
  /// the words under "This is my node".
  Future<WatchLimitsChoice> liveLimits();

  /// What the running watch says for the screens: its status, the
  /// wallets it synced, blocks, its end. Never a transaction to
  /// announce: those go to the caller of [liveRun] alone. Any number of
  /// isolates may listen.
  Stream<LiveEvent> liveEvents();

  /// What the syncs of [walletId] found that nobody has announced yet,
  /// taken off the core's record. Called after every sync the app runs
  /// of that wallet, whatever its report lists; whoever calls it says
  /// what it returns or drops it on purpose, since nothing returned is
  /// ever returned again.
  Future<List<LiveTx>> claimAnnouncements(String walletId);

  /// What [txs] amount to, as notifications ready to post, in order:
  /// the core composes the words, the desktop app's, from what [context]
  /// lets them say, and counts them against the budget it keeps for the
  /// whole process, twenty a minute. Ask only for what is about to be
  /// posted.
  Future<List<TxNotice>> liveNotices(List<LiveTx> txs, NoticeContext context);

  /// Whether anything this app sends has to go through Tor.
  Future<bool> usesTor();
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
      );
    }
    return decoded;
  }

  /// The same, for the test that reads the core's failures the way
  /// the bridge hands them over.
  @visibleForTesting
  static dynamic decode(String raw) => _decode(raw);

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
  Future<int> openQrScan() => rust.openQrScan();

  @override
  Future<QrProgress> pushQrFrame(int scan, String frame) async {
    final raw = await rust.pushQrFrame(scan: scan, frame: frame);
    return QrProgress.fromJson(_object(raw));
  }

  @override
  Future<void> closeQrScan(int scan) => rust.closeQrScan(scan: scan);

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
  Future<void> setWalletLivePinned(String id, bool pinned) async {
    _ok(await rust.setWalletLivePinned(id: id, pinned: pinned));
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
  Future<Preferences> setPreferences(PreferencesChange change) async {
    final raw = await rust.setPreferences(
      changeJson: jsonEncode(change.toJson()),
    );
    return Preferences.fromJson(_object(raw));
  }

  @override
  Future<PriceTable> priceTable() async {
    return PriceTable.fromJson(_object(await rust.priceTable()));
  }

  @override
  Future<PriceQuote> fetchPrice() async {
    return PriceQuote.fromJson(_object(await rust.fetchPrice()));
  }

  @override
  Future<UpdateStatus> updateStatus(String currentVersion) async {
    final raw = await rust.updateStatus(currentVersion: currentVersion);
    return UpdateStatus.fromJson(_object(raw));
  }

  @override
  Future<UpdateStatus> updateSession(String currentVersion) async {
    final raw = await rust.updateSession(currentVersion: currentVersion);
    return UpdateStatus.fromJson(_object(raw));
  }

  @override
  Future<UpdateStatus> checkUpdate(String currentVersion) async {
    final raw = await rust.checkUpdate(currentVersion: currentVersion);
    return UpdateStatus.fromJson(_object(raw));
  }

  @override
  Future<void> dismissUpdate(String version) async {
    _ok(await rust.dismissUpdate(version: version));
  }

  @override
  Future<void> setUpdateAutomatic(bool automatic) async {
    _ok(await rust.setUpdateAutomatic(automatic: automatic));
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
  Future<List<RecentBroadcast>> recentBroadcasts(Network network) async {
    final raw = await rust.recentBroadcasts(network: network.id);
    return _list(raw).map(RecentBroadcast.fromJson).toList();
  }

  @override
  Future<void> forgetBroadcast(String txid) async {
    _ok(await rust.forgetBroadcast(txid: txid));
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
  Stream<LiveEvent> liveRun() {
    // Read now, in the caller's turn: a stop it asks after this call
    // ends the run, even one carried out before the run itself starts.
    final stopsSeen = rust.liveStops();
    return _liveRun(stopsSeen);
  }

  Stream<LiveEvent> _liveRun(int stopsSeen) async* {
    final payloads = rust.liveRun(stopsSeen: stopsSeen);
    await for (final raw in endsWithItsCall(payloads)) {
      final Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        // One event that does not read must not end the stream.
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      // A refusal to start comes as the only payload: it ends the run.
      if (decoded['error'] is Map<String, dynamic>) _decode(raw);
      final event = LiveEvent.fromJson(decoded);
      if (event != null) yield event;
    }
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
  Future<WatchLimitsChoice> liveLimits() async {
    return WatchLimitsChoice.fromJson(_object(await rust.liveLimits()));
  }

  @override
  Stream<LiveEvent> liveEvents() async* {
    await for (final raw in endsWithItsCall(rust.liveEvents())) {
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
  Future<List<LiveTx>> claimAnnouncements(String walletId) async {
    final raw = await rust.claimAnnouncements(walletId: walletId);
    return _list(raw).map(LiveTx.fromJson).toList();
  }

  @override
  Future<List<TxNotice>> liveNotices(
    List<LiveTx> txs,
    NoticeContext context,
  ) async {
    final raw = await rust.liveNotices(
      txsJson: jsonEncode([for (final tx in txs) tx.toJson()]),
      contextJson: jsonEncode(context.toJson()),
    );
    return _list(raw).map(TxNotice.fromJson).toList();
  }

  @override
  Future<bool> usesTor() async {
    return _decode(await rust.usesTor()) as bool;
  }
}
