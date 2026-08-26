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
}
