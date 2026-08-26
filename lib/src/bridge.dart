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
/// vault, sync, backend_unavailable, descriptor, internal — plus the
/// bridge-level not_initialized, bad_key, bad_json.
class BridgeException implements Exception {
  const BridgeException(this.kind, this.message);

  final String kind;
  final String message;

  @override
  String toString() => message;
}

/// Every operation the app can ask of the core.
abstract class GerfautBridge {
  /// Classifies wallet material. `script` is the user's script type
  /// choice for a lone extended key; the core ignores it otherwise.
  Future<ParsedInput> parseInput(String input, {ScriptKind? script});

  /// Assembles the distinct QR frames scanned so far (plain text, UR,
  /// BBQr). Feed the growing list until [QrProgress.complete], then
  /// hand [QrProgress.text] to [parseInput].
  Future<QrProgress> assembleQr(List<String> frames);
  Future<WalletMeta> addWallet(
    String name,
    ParsedInput parsed,
    Network network,
  );
  Future<List<WalletMeta>> listWallets([Network? network]);
  Future<WalletSnapshot> walletSnapshot(String id);
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
  Future<void> removeWallet(String id);
  Future<Settings> getSettings();
  Future<void> setActiveNetwork(Network network);

  /// Sets the global gap limit (1..=500), applied on the next sync.
  Future<void> setGapLimit(int gapLimit);
  Future<void> setBackend(Network network, BackendConfig config);
  Future<void> setAppPref(String key, String value);
  Future<PriceQuote> fetchPrice(PriceSource source, FiatCurrency currency);
  Future<UpdateCheck> checkUpdate(String currentVersion);
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
}
