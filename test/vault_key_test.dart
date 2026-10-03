import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/vault_key.dart';

/// Stands in for the secure storage: what it holds, and whether it
/// answers at all.
class _FakeStore implements VaultKeyStore {
  _FakeStore({this.value, this.failure});

  String? value;

  /// Thrown by every read, the way a Keystore fault surfaces once the
  /// plugin no longer wipes the entry over it.
  Object? failure;

  final List<String> written = [];

  @override
  Future<String?> read() async {
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<void> write(String value) async {
    written.add(value);
    this.value = value;
  }
}

const String goodKey =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// What the core draws for a first launch, here a key of sevens.
final String drawnKey = '07' * 32;

/// The core's draw, counted: once a process, whoever asks.
class _Draw {
  int calls = 0;

  Future<String> call() async {
    calls += 1;
    return drawnKey;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gerfaut-vault-key');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> writeVault() =>
      File('${dir.path}${Platform.pathSeparator}$vaultFileName')
          .writeAsBytes([0x47, 0x46, 0x56, 0x41, 0x55, 0x4c, 0x54, 0x31]);

  group('obtaining the key', () {
    test('a first launch stores the key the core draws', () async {
      final store = _FakeStore();
      final draw = _Draw();
      final hex = await obtainVaultKeyHex(
        dataDir: dir.path,
        store: store,
        drawKey: draw.call,
      );
      expect(hex, drawnKey);
      expect(store.written, [drawnKey]);
      expect(draw.calls, 1);
    });

    test('isolates starting together store one and the same key', () async {
      // Each isolate holds a storage handle of its own onto the same
      // entry; the core hands every one of them the key it drew.
      final store = _FakeStore();
      final draw = _Draw();
      final keys = await Future.wait([
        for (var i = 0; i < 3; i++)
          obtainVaultKeyHex(
            dataDir: dir.path,
            store: store,
            drawKey: draw.call,
          ),
      ]);
      expect(keys, [drawnKey, drawnKey, drawnKey]);
      expect(store.value, drawnKey);
    });

    test('a key drawn wrong is never stored', () async {
      final store = _FakeStore();
      await expectLater(
        obtainVaultKeyHex(
          dataDir: dir.path,
          store: store,
          drawKey: () async => 'not a key',
        ),
        throwsStateError,
      );
      expect(store.written, isEmpty);
    });

    test('a stored key is never drawn again', () async {
      final store = _FakeStore(value: goodKey);
      final draw = _Draw();
      final hex = await obtainVaultKeyHex(
        dataDir: dir.path,
        store: store,
        drawKey: draw.call,
      );
      expect(hex, goodKey);
      expect(draw.calls, 0);
    });

    test('a stored key is reused as it is', () async {
      final store = _FakeStore(value: goodKey);
      await writeVault();
      final hex = await obtainVaultKeyHex(
        dataDir: dir.path,
        store: store,
        drawKey: _Draw().call,
      );
      expect(hex, goodKey);
      expect(store.written, isEmpty);
    });

    test(
      'a vault without its key is reported, never given a new one',
      () async {
        await writeVault();
        final store = _FakeStore();
        await expectLater(
          obtainVaultKeyHex(
            dataDir: dir.path,
            store: store,
            drawKey: _Draw().call,
          ),
          throwsA(
            isA<VaultKeyMissingException>().having(
              (e) => e.detail,
              'detail',
              'nothing is stored under its name',
            ),
          ),
        );
        expect(store.written, isEmpty);
      },
    );

    test('a value that is not a key counts as a key gone', () async {
      // What the plugin answers after it wiped the storage over an error.
      await writeVault();
      final store = _FakeStore(value: 'Data has been reset');
      await expectLater(
        obtainVaultKeyHex(
          dataDir: dir.path,
          store: store,
          drawKey: _Draw().call,
        ),
        throwsA(
          isA<VaultKeyMissingException>().having(
            (e) => e.detail,
            'detail',
            'what is stored under its name is not a key',
          ),
        ),
      );
      expect(store.written, isEmpty);
      expect(store.value, 'Data has been reset');
    });

    test('a storage that will not answer leaves the vault alone', () async {
      await writeVault();
      final store = _FakeStore(failure: StateError('keystore unavailable'));
      await expectLater(
        obtainVaultKeyHex(
          dataDir: dir.path,
          store: store,
          drawKey: _Draw().call,
        ),
        throwsA(
          isA<VaultKeyMissingException>().having(
            (e) => e.detail,
            'detail',
            contains('keystore unavailable'),
          ),
        ),
      );
      expect(store.written, isEmpty);
    });

    test('without a vault, a storage failure is a plain failure', () async {
      final store = _FakeStore(failure: StateError('keystore unavailable'));
      await expectLater(
        obtainVaultKeyHex(
          dataDir: dir.path,
          store: store,
          drawKey: _Draw().call,
        ),
        throwsStateError,
      );
      expect(store.written, isEmpty);
    });

    test('without a vault, a value that is not a key is replaced', () async {
      final store = _FakeStore(value: 'Data has been reset');
      final hex = await obtainVaultKeyHex(
        dataDir: dir.path,
        store: store,
        drawKey: _Draw().call,
      );
      expect(hex, drawnKey);
      expect(store.value, hex);
    });
  });

  group('setting the vault aside', () {
    test('renames the file and keeps its bytes', () async {
      final vault = await writeVault();
      final before = await vault.readAsBytes();
      final aside = await setVaultAsideIn(dir.path);
      expect(aside, isNotNull);
      expect(await vault.exists(), isFalse);
      expect(aside, contains('$vaultFileName.unopenable-'));
      expect(await File(aside!).readAsBytes(), before);

      // The next bootstrap is a first launch again.
      final store = _FakeStore();
      final hex = await obtainVaultKeyHex(
        dataDir: dir.path,
        store: store,
        drawKey: _Draw().call,
      );
      expect(store.written, [hex]);
    });

    test('does nothing without a vault', () async {
      expect(await setVaultAsideIn(dir.path), isNull);
    });
  });
}
