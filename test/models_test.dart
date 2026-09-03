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

    test('reads the icon by its serde name', () {
      final json = _metaJson()..['icon'] = 'piggy_bank';
      expect(WalletMeta.fromJson(json).icon, WalletIcon.piggyBank);
      expect(WalletIcon.fromId('map_pin'), WalletIcon.mapPin);
      expect(WalletIcon.piggyBank.id, 'piggy_bank');
    });

    test('falls back to the wallet glyph when the icon is missing or '
        'unknown', () {
      // A vault written before icons existed carries none.
      expect(WalletMeta.fromJson(_metaJson()).icon, WalletIcon.wallet);
      // A newer core may name one this build has never heard of.
      final json = _metaJson()..['icon'] = 'telescope';
      expect(WalletMeta.fromJson(json).icon, WalletIcon.wallet);
    });

    test('copyWith changes the name or the icon and nothing else', () {
      final meta = WalletMeta.fromJson(_metaJson());
      final renamed = meta.copyWith(name: 'Savings');
      expect(renamed.name, 'Savings');
      expect(renamed.icon, meta.icon);
      expect(renamed.id, meta.id);
      expect(renamed.scanGap, meta.scanGap);
      final iconed = meta.copyWith(icon: WalletIcon.snowflake);
      expect(iconed.icon, WalletIcon.snowflake);
      expect(iconed.name, meta.name);
    });
  });

  group('FiatCurrency', () {
    test('offers thirty currencies, the seven common ones first', () {
      expect(FiatCurrency.values, hasLength(30));
      final common = FiatCurrency.values
          .where((c) => c.reach == CurrencyReach.every)
          .toList();
      expect(common, hasLength(7));
      expect(FiatCurrency.values.take(7), common);
      expect(common.map((c) => c.code), [
        'EUR',
        'USD',
        'GBP',
        'CHF',
        'JPY',
        'CAD',
        'AUD',
      ]);
    });

    test('every currency carries a distinct identifier, code and name', () {
      expect(
        FiatCurrency.values.map((c) => c.id).toSet(),
        hasLength(FiatCurrency.values.length),
      );
      for (final currency in FiatCurrency.values) {
        expect(currency.id, currency.code.toLowerCase());
        expect(currency.label, isNotEmpty);
        expect(FiatCurrency.fromId(currency.id), currency);
      }
      // The Turkish lira keeps the identifier the core stores, whatever
      // Dart makes of the word `try`.
      expect(FiatCurrency.fromId('try'), FiatCurrency.tryLira);
      expect(FiatCurrency.fromId('xxx'), isNull);
    });

    test('only CoinGecko quotes past the common seven', () {
      for (final source in PriceSource.values) {
        expect(source.supportsCurrency(FiatCurrency.jpy), isTrue);
      }
      expect(PriceSource.coingecko.supportsCurrency(FiatCurrency.ngn), isTrue);
      expect(PriceSource.kraken.supportsCurrency(FiatCurrency.ngn), isFalse);
      expect(
        PriceSource.mempoolSpace.supportsCurrency(FiatCurrency.ngn),
        isFalse,
      );
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
      // A public authority vouches for this one.
      expect(server.selfSigned, isFalse);
      expect(
        PublicServer.fromJson(const {
          'id': 'electrum:bitcoin.lu.ke',
          'label': 'bitcoin.lu.ke:50002',
          'protocol': 'electrum',
          'url': 'ssl://bitcoin.lu.ke:50002',
          'self_signed': true,
        }).selfSigned,
        isTrue,
      );
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

  group('TxWarning.fromJson', () {
    test('reads the tone the core sent rather than deriving one', () {
      final alert = TxWarning.fromJson(const {
        'kind': 'unsigned',
        'message': '1 of 1 inputs carry no signature.',
        'severity': 'alert',
      });
      expect(alert.kind, TxWarningKind.unsigned);
      expect(alert.severity, TxSeverity.alert);

      final info = TxWarning.fromJson(const {
        'kind': 'spends_watched',
        'message': 'Spends coins of Cold storage.',
        'severity': 'info',
      });
      expect(info.severity, TxSeverity.info);
    });

    test('a kind added by a newer core still arrives with its tone', () {
      // The whole point of carrying severity on the wire: a kind this
      // build cannot name no longer falls through a hand-written table.
      final warning = TxWarning.fromJson(const {
        'kind': 'something_this_build_never_heard_of',
        'message': 'Worth reading all the same.',
        'severity': 'alert',
      });
      expect(warning.kind, TxWarningKind.other);
      expect(warning.severity, TxSeverity.alert);
    });

    test('a tone it cannot name reads as info', () {
      // Quiet is the safe way to be wrong about a tone: the red is a
      // budget, and it must not be spent by a string nobody parsed.
      expect(
        TxWarning.fromJson(const {
          'kind': 'other',
          'message': 'Something.',
          'severity': 'catastrophic',
        }).severity,
        TxSeverity.info,
      );
      expect(
        TxWarning.fromJson(const {'kind': 'other', 'message': 'Something.'})
            .severity,
        TxSeverity.info,
      );
    });
  });

  group('certificates', () {
    test('every status the core can report is read back', () {
      const fingerprint =
          '11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:'
          '11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00';

      final trusted = CertificateReport.fromJson(const {
        'host': 'electrum.blockstream.info:50002',
        'status': 'trusted',
      });
      expect(trusted.host, 'electrum.blockstream.info:50002');
      expect(trusted.status, isA<TrustedCertificate>());

      expect(
        CertificateReport.fromJson(const {
          'host': 'node.local:50001',
          'status': 'not_tls',
        }).status,
        isA<NotTlsCertificate>(),
      );
      expect(
        CertificateReport.fromJson(const {
          'host': 'abcdefgh.onion:50002',
          'status': 'tor',
        }).status,
        isA<TorCertificate>(),
      );

      final pinned = CertificateReport.fromJson({
        'host': 'node.local:50002',
        'status': 'pinned',
        'fingerprint': fingerprint,
      }).status;
      expect((pinned as PinnedCertificate).fingerprint, fingerprint);

      final unknown = CertificateReport.fromJson({
        'host': 'node.local:50002',
        'status': 'unknown',
        'fingerprint': fingerprint,
        'reason':
            'self-signed, or signed by an authority this machine '
            'does not know',
        'subject': 'CN=node.local',
        'expires': 1893456000,
      }).status;
      expect((unknown as UnknownCertificate).fingerprint, fingerprint);
      expect(unknown.subject, 'CN=node.local');
      expect(unknown.expires, 1893456000);
      expect(unknown.reason, startsWith('self-signed'));

      // What the certificate says about itself is optional; the
      // fingerprint is what gets trusted.
      final bare = CertificateReport.fromJson({
        'host': 'node.local:50002',
        'status': 'unknown',
        'fingerprint': fingerprint,
        'reason': 'expired',
        'subject': null,
        'expires': null,
      }).status;
      expect((bare as UnknownCertificate).subject, isNull);
      expect(bare.expires, isNull);

      final changed = CertificateReport.fromJson({
        'host': 'node.local:50002',
        'status': 'changed',
        'stored': fingerprint,
        'presented': 'AA:$fingerprint',
      }).status;
      expect((changed as ChangedCertificate).stored, fingerprint);
      expect(changed.presented, 'AA:$fingerprint');

      final unreachable = CertificateReport.fromJson(const {
        'host': 'node.local:50002',
        'status': 'unreachable',
        'detail': 'connection refused',
      }).status;
      expect(
        (unreachable as UnreachableCertificate).detail,
        'connection refused',
      );
    });

    test('a status this build does not know is refused, not guessed', () {
      expect(
        () => CertificateReport.fromJson(const {
          'host': 'node.local:50002',
          'status': 'revoked',
        }),
        throwsFormatException,
      );
    });

    test('accepted certificates ride along in the settings', () {
      final settings = Settings.fromJson(const {
        'active_network': 'mainnet',
        'backends': <String, dynamic>{},
        'app_prefs': <String, dynamic>{},
        'gap_limit': 20,
        'electrum_certs': {'node.local:50002': 'AB:CD'},
      });
      expect(settings.electrumCerts, {'node.local:50002': 'AB:CD'});

      // A vault written before the map existed reads as empty.
      expect(
        Settings.fromJson(const {
          'active_network': 'mainnet',
          'backends': <String, dynamic>{},
          'app_prefs': <String, dynamic>{},
        }).electrumCerts,
        isEmpty,
      );
    });
  });
}
