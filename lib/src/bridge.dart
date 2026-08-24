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
  Future<ParsedInput> parseInput(String input);
  Future<WalletMeta> addWallet(String name, ParsedInput parsed, Network network);
  Future<List<WalletMeta>> listWallets([Network? network]);
  Future<WalletSnapshot> walletSnapshot(String id);
  Future<TxDetail> txDetail(String id, String txid);
  Future<List<UtxoInfo>> utxos(String id);
  Future<List<AddressEntry>> receiveAddresses(String id, int lookahead);
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
  Future<ParsedInput> parseInput(String input) async {
    final raw = await rust.parseInput(input: input);
    return ParsedInput.fromJson(_object(raw), raw);
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
