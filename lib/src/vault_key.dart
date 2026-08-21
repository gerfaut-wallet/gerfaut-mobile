// Vault key bootstrap: a 32-byte key generated on first launch, kept in
// the platform secure storage, and handed to the Rust core to open the
// encrypted vault.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'rust/api.dart' as rust_api;
import 'rust/frb_generated.dart';

const _vaultKeyName = 'vault-key';

bool _isValidKeyHex(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

/// Returns the vault key as 64 hex characters, generating and storing a
/// fresh 32-byte key on first launch and reusing it afterwards.
Future<String> obtainVaultKeyHex({FlutterSecureStorage? storage}) async {
  final store = storage ?? const FlutterSecureStorage();
  final existing = await store.read(key: _vaultKeyName);
  if (existing != null) {
    if (_isValidKeyHex(existing)) {
      return existing;
    }
    // Never overwrite a stored key, even a malformed one: replacing it
    // would silently make the existing vault undecryptable forever.
    throw StateError('stored vault key is malformed; refusing to replace it');
  }
  final rng = Random.secure();
  final hex = List<String>.generate(
    32,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await store.write(key: _vaultKeyName, value: hex);
  return hex;
}

/// Loads the Rust bridge and opens the encrypted vault in the app's
/// documents directory. Runs once before the home screen shows.
Future<void> bootstrapGerfaut() async {
  await RustLib.init();
  final dir = await getApplicationDocumentsDirectory();
  final keyHex = await obtainVaultKeyHex();
  final result = await rust_api.initManager(dataDir: dir.path, keyHex: keyHex);
  final decoded = jsonDecode(result);
  if (decoded is Map<String, dynamic> && decoded['error'] != null) {
    final error = decoded['error'] as Map<String, dynamic>;
    throw StateError(
      'vault init failed (${error['kind']}): ${error['message']}',
    );
  }
}
