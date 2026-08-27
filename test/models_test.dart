import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/models.dart';

const _descriptors = {
  'type': 'descriptors',
  'external': 'wpkh(tpub.../0/*)#checksum',
  'internal': 'wpkh(tpub.../1/*)#checksum',
  'script': 'segwit',
};

Map<String, dynamic> _metaJson({bool withScanGap = true}) => {
  'id': 'w1',
  'name': 'Cold storage',
  'network': 'signet',
  'kind': _descriptors,
  'recognized_as': 'extended_key',
  'created_at': 1755000000,
  'gap_limit': 20,
  if (withScanGap) 'scan_gap': 50,
  'last_sync': null,
  'cached': {
    'balance': {
      'confirmed': 0,
      'trusted_pending': 0,
      'untrusted_pending': 0,
      'immature': 0,
      'total': 0,
    },
    'tx_count': 0,
  },
};

void main() {
  group('ParsedInput.fromJson', () {
    test('reads the script options and the preview address', () {
      final json = {
        'kind': 'extended_key',
        'networks': ['signet', 'testnet4', 'regtest'],
        'payload': _descriptors,
        'warnings': ['assumed_segwit'],
        'script_options': ['legacy', 'nested_segwit', 'segwit', 'taproot'],
        'preview_address': 'tb1qexample',
      };
      final raw = jsonEncode(json);
      final parsed = ParsedInput.fromJson(json, raw);

      expect(parsed.kind, RecognizedKind.extendedKey);
      expect(parsed.scriptOptions, [
        ScriptKind.legacy,
        ScriptKind.nestedSegwit,
        ScriptKind.segwit,
        ScriptKind.taproot,
      ]);
      expect(parsed.previewAddress, 'tb1qexample');
      expect(parsed.warnings, [InputWarning.assumedSegwit]);
      expect(parsed.rawJson, raw);
    });

    test('tolerates a core answer without the new fields', () {
      final json = {
        'kind': 'descriptor',
        'networks': ['mainnet'],
        'payload': _descriptors,
        'warnings': <String>[],
      };
      final parsed = ParsedInput.fromJson(json, jsonEncode(json));

      expect(parsed.scriptOptions, isEmpty);
      expect(parsed.previewAddress, isNull);
    });

    test('recognizes a BSMS record', () {
      final json = {
        'kind': 'bsms',
        'networks': ['mainnet'],
        'payload': _descriptors,
        'warnings': <String>[],
      };
      final parsed = ParsedInput.fromJson(json, jsonEncode(json));

      expect(parsed.kind, RecognizedKind.bsms);
      expect(RecognizedKind.fromId('bsms'), RecognizedKind.bsms);
      expect(RecognizedKind.bsms.label, 'BSMS record');
    });

    test('reads an explicit null preview address', () {
      final json = {
        'kind': 'address',
        'networks': ['mainnet'],
        'payload': {'type': 'address', 'address': 'bc1qexample'},
        'warnings': <String>[],
        'script_options': <String>[],
        'preview_address': null,
      };
      final parsed = ParsedInput.fromJson(json, jsonEncode(json));

      expect(parsed.scriptOptions, isEmpty);
      expect(parsed.previewAddress, isNull);
    });
  });

  group('WalletMeta.fromJson', () {
    test('reads the scan gap', () {
      final meta = WalletMeta.fromJson(_metaJson());
      expect(meta.scanGap, 50);
      expect(meta.gapLimit, 20);
    });

    test('defaults the scan gap on older metadata', () {
      final meta = WalletMeta.fromJson(_metaJson(withScanGap: false));
      expect(meta.scanGap, 20);
    });
  });

  group('BackendConfig', () {
    test('an automatic public backend keeps its stored shape', () {
      final stored = BackendConfig.fromJson({'type': 'public_esplora'});
      expect(stored, isA<PublicEsplora>());
      expect((stored as PublicEsplora).server, isNull);
      // The key must not appear at all: the core reads the exact shape
      // every vault written before the choice existed already carries.
      expect(jsonEncode(stored.toJson()), '{"type":"public_esplora"}');
    });

    test('a chosen operator rides along in the same tag', () {
      final config = BackendConfig.fromJson({
        'type': 'public_esplora',
        'server': 'blockstream.info',
      });
      expect((config as PublicEsplora).server, 'blockstream.info');
      expect(
        jsonEncode(config.toJson()),
        '{"type":"public_esplora","server":"blockstream.info"}',
      );
    });

    test('reads a public server entry', () {
      final server = PublicServer.fromJson(const {
        'id': 'electrum:frigate.2140.dev',
        'label': 'frigate.2140.dev:50002',
        'protocol': 'electrum',
        'url': 'ssl://frigate.2140.dev:50002',
      });
      expect(server.id, 'electrum:frigate.2140.dev');
      expect(server.label, 'frigate.2140.dev:50002');
      expect(server.protocol, ServerProtocol.electrum);
      expect(server.protocol.label, 'Electrum');
      expect(server.url, 'ssl://frigate.2140.dev:50002');
      expect(
        PublicServer.fromJson(const {
          'id': 'mempool.space',
          'label': 'mempool.space',
          'protocol': 'esplora',
          'url': 'https://mempool.space/api',
        }).protocol,
        ServerProtocol.esplora,
      );
    });

    test('settings fall back to the automatic public backend', () {
      const settings = Settings(
        activeNetwork: Network.mainnet,
        backends: {},
        appPrefs: {},
      );
      final config = settings.backendFor(Network.mainnet);
      expect((config as PublicEsplora).server, isNull);
    });
  });
}
