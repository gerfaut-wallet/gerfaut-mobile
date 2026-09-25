// Vault key bootstrap: a 32-byte key generated on first launch, kept in
// the platform secure storage, and handed to the Rust core to open the
// encrypted vault.
//
// The key and the vault are two things kept by two systems, and only
// one of them travels: a phone restored from a backup, moved to a new
// device or reset comes back with the vault file and without the key
// that opens it. Nothing here ever makes a new key while a vault
// exists. A vault that cannot be opened is reported as such, and left
// exactly where it is.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'rust/api.dart' as rust_api;
import 'rust/frb_generated.dart';

const _vaultKeyName = 'vault-key';

/// The vault's file name under the data directory, as the core names it.
const String vaultFileName = 'gerfaut.vault';

bool _isValidKeyHex(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

/// Where the vault key is kept. Behind an interface so a test can stand
/// in for the platform's secure storage.
abstract class VaultKeyStore {
  /// The stored value, or null when nothing is stored under the key's
  /// name. Throws when the storage cannot answer.
  Future<String?> read();

  Future<void> write(String value);
}

/// The Android Keystore, through flutter_secure_storage.
///
/// `resetOnError` is off on purpose. The plugin's default wipes the
/// entry on any error reading it and answers as if nothing had ever
/// been stored, which turns a passing Keystore fault into a vault
/// nobody can open, silently. An error is an error here: it is
/// reported, and the entry stays.
class SecureVaultKeyStore implements VaultKeyStore {
  const SecureVaultKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  @override
  Future<String?> read() => _storage.read(key: _vaultKeyName);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _vaultKeyName, value: value);
}

/// The vault is on disk, but the key that opens it is not to be had:
/// absent from the secure storage, unreadable there, or replaced by
/// something that is not a key. The vault is not touched.
class VaultKeyMissingException implements Exception {
  const VaultKeyMissingException(this.detail);

  /// What was found in the key's place, for the startup screen's
  /// second line.
  final String detail;

  @override
  String toString() => 'the vault is here but its key is gone: $detail';
}

/// Another open holds the vault: a second copy of the app, or a second
/// opener in this one. Nothing was read, and nothing is wrong with the
/// vault: it is never set aside for this, and a background run that
/// meets it simply skips its turn.
class VaultInUseException implements Exception {
  const VaultInUseException();

  @override
  String toString() => 'the vault is already open in another Gerfaut process';
}

File _vaultFile(String dataDir) =>
    File('$dataDir${Platform.pathSeparator}$vaultFileName');

/// Returns the vault key as 64 hex characters, generating and storing a
/// fresh 32-byte key on first launch and reusing it afterwards.
///
/// A first launch is a directory with no vault in it, and nothing else:
/// with a vault on disk, a key that is not there is never replaced,
/// since the new one would open nothing and the old one might still
/// turn up. [VaultKeyMissingException] says so instead.
Future<String> obtainVaultKeyHex({
  required String dataDir,
  VaultKeyStore store = const SecureVaultKeyStore(),
}) async {
  final vaultExists = await _vaultFile(dataDir).exists();
  final String? existing;
  try {
    existing = await store.read();
  } catch (error) {
    if (vaultExists) {
      throw VaultKeyMissingException(
        'the secure storage did not give it up: $error',
      );
    }
    rethrow;
  }
  if (existing != null && _isValidKeyHex(existing)) {
    return existing;
  }
  if (vaultExists) {
    throw VaultKeyMissingException(
      existing == null
          ? 'nothing is stored under its name'
          : 'what is stored under its name is not a key',
    );
  }
  // No vault to open: a first launch, or a vault set aside. A value
  // that is not a key would open nothing anyway, so a fresh one takes
  // its place.
  final rng = Random.secure();
  final hex = List<String>.generate(
    32,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await store.write(hex);
  return hex;
}

/// Moves the vault file out of the way, under a name that says what it
/// is and when it was set aside, so the next bootstrap starts an empty
/// one. Nothing is deleted. Answers the new path, or null when there
/// was no vault to move.
Future<String?> setVaultAsideIn(String dataDir) async {
  final vault = _vaultFile(dataDir);
  if (!await vault.exists()) return null;
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final aside = await vault.rename('${vault.path}.unopenable-$stamp');
  return aside.path;
}

/// [setVaultAsideIn] on the app's own data directory.
Future<void> setVaultAside() async {
  final dir = await getApplicationDocumentsDirectory();
  await setVaultAsideIn(dir.path);
}

/// A debug build can be pointed at another Premium server, a local one
/// for an end-to-end run, with
/// `--dart-define=GERFAUT_PREMIUM_URL=http://10.0.2.2:8080` and
/// `--dart-define=GERFAUT_PREMIUM_PUBLIC_KEY=<hex>`, the key that server
/// signs its certificates with.
const String _debugPremiumUrl = String.fromEnvironment('GERFAUT_PREMIUM_URL');
const String _debugPremiumPublicKey = String.fromEnvironment(
  'GERFAUT_PREMIUM_PUBLIC_KEY',
);

/// Hands the core the server a debug build was pointed at, before the
/// vault opens and before any Premium call. A release build compiles
/// this out, and its core would not listen either.
void pointAtDebugPremiumServer() {
  if (!kDebugMode) return;
  if (_debugPremiumUrl.isEmpty && _debugPremiumPublicKey.isEmpty) return;
  rust_api.premiumDebugEndpoint(
    baseUrl: _debugPremiumUrl,
    publicKey: _debugPremiumPublicKey,
  );
}

/// Loads the Rust bridge and opens the encrypted vault in the app's
/// documents directory. Runs once before the home screen shows, and
/// again after a vault was set aside: the bridge is only loaded the
/// first time.
Future<void> bootstrapGerfaut() async {
  if (!RustLib.instance.initialized) await RustLib.init();
  pointAtDebugPremiumServer();
  final dir = await getApplicationDocumentsDirectory();
  final keyHex = await obtainVaultKeyHex(dataDir: dir.path);
  final result = await rust_api.initManager(dataDir: dir.path, keyHex: keyHex);
  final decoded = jsonDecode(result);
  if (decoded is Map<String, dynamic> && decoded['error'] != null) {
    final error = decoded['error'] as Map<String, dynamic>;
    if (error['kind'] == 'vault_in_use') throw const VaultInUseException();
    throw StateError(
      'vault init failed (${error['kind']}): ${error['message']}',
    );
  }
}
