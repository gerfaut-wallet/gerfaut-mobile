// The contract of the bridge, from this side: every reference JSON of
// gerfaut-core (core_fixtures.dart) decoded by the model of this app
// that receives it, or matched by what this app sends in its place. A
// key the core sends and the model never reads fails here, as does a
// decode that throws, a variant this app does not know or reads as
// another, a key the model reads that the core sends nowhere, and a
// variant of this app the core never sends.
//
// The list of types is this test's, not the folder's: a type the core
// starts to write fails here until it is given a decoder or a reason
// to stay out, and a type it stops writing fails too.

import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/format.dart' show AmountUnit;
import 'package:gerfaut/src/models.dart';

import 'core_fixtures.dart';
import 'fakes.dart' show kPreferences, kPriceTable;

// --- what a model reads ------------------------------------------------------

/// The key paths of one case a decoder looked at, `[]` standing for
/// every item of a list: the ones the case holds, and the ones it does
/// not.
class _Reads {
  final Set<String> held = {};
  final Set<String> absent = {};
}

String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

/// A JSON object that notes which of its keys a decoder looks at.
class _TrackedMap extends MapBase<String, dynamic> {
  _TrackedMap(this._map, this._path, this._reads);

  final Map<String, dynamic> _map;
  final String _path;
  final _Reads _reads;

  void _note(Object? key) {
    if (key is! String) return;
    final path = _join(_path, key);
    (_map.containsKey(key) ? _reads.held : _reads.absent).add(path);
  }

  @override
  dynamic operator [](Object? key) {
    _note(key);
    return _track(_map[key], _join(_path, '$key'), _reads);
  }

  @override
  bool containsKey(Object? key) {
    _note(key);
    return _map.containsKey(key);
  }

  @override
  Iterable<String> get keys => _map.keys;

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('a decoder writes into the JSON');

  @override
  void clear() => throw UnsupportedError('a decoder clears the JSON');

  @override
  dynamic remove(Object? key) =>
      throw UnsupportedError('a decoder removes from the JSON');
}

class _TrackedList extends ListBase<dynamic> {
  _TrackedList(this._list, this._path, this._reads);

  final List<dynamic> _list;
  final String _path;
  final _Reads _reads;

  @override
  int get length => _list.length;

  @override
  set length(int value) => throw UnsupportedError('a decoder resizes the JSON');

  @override
  dynamic operator [](int index) => _track(_list[index], '$_path[]', _reads);

  @override
  void operator []=(int index, dynamic value) =>
      throw UnsupportedError('a decoder writes into the JSON');
}

dynamic _track(dynamic value, String path, _Reads reads) => switch (value) {
  Map<String, dynamic> map => _TrackedMap(map, path, reads),
  List<dynamic> list => _TrackedList(list, path, reads),
  _ => value,
};

/// Calls [visit] on every key of [value], with the object it sits in.
void _eachKey(
  dynamic value,
  String path,
  void Function(String path, Map<String, dynamic> parent) visit,
) {
  if (value is Map<String, dynamic>) {
    value.forEach((key, item) {
      final at = _join(path, key);
      visit(at, value);
      _eachKey(item, at, visit);
    });
  } else if (value is List) {
    for (final item in value) {
      _eachKey(item, '$path[]', visit);
    }
  }
}

/// [value] without the keys that hold null: the core reads a key left
/// out the way it reads a null one.
dynamic _withoutNulls(dynamic value) => switch (value) {
  Map<String, dynamic> map => {
    for (final entry in map.entries)
      if (entry.value != null) entry.key: _withoutNulls(entry.value),
  },
  List<dynamic> list => [for (final item in list) _withoutNulls(item)],
  _ => value,
};

// --- how this app takes each type ----------------------------------------

sealed class _Entry {
  const _Entry();
}

/// Decoded by a model of this app, which must read every key of every
/// case; [encode] is what this app sends back of it, when it does,
/// which must be the case again.
class _Decoded extends _Entry {
  const _Decoded(this.decode, {this.encode});

  final Object? Function(Map<String, dynamic> json, String raw) decode;
  final Map<String, dynamic> Function(Object decoded)? encode;
}

_Decoded _reads(
  Object? Function(Map<String, dynamic> json) decode, {
  Map<String, dynamic> Function(Object decoded)? encode,
}) => _Decoded((json, _) => decode(json), encode: encode);

/// Decoded inside another type, never alone: each case takes the place
/// of what sits at [path] in the first case of [parent].
class _Inside extends _Entry {
  const _Inside(this.parent, this.path);

  final String parent;
  final List<Object> path;
}

/// An enumeration: every id the core sends decodes to the value of that
/// id, and every value of this app is one the core sends, but [own].
class _Enum extends _Entry {
  const _Enum(this.ids, this.decode, {this.own = const {}});

  final List<String> ids;
  final String? Function(String id) decode;

  /// Values of this app the core never sends, with the reason.
  final Map<String, String> own;
}

_Enum _enum<T>(
  List<T> values,
  String Function(T value) id,
  T? Function(String id) fromId, {
  Map<String, String> own = const {},
}) => _Enum(
  [for (final value in values) id(value)],
  (text) => switch (fromId(text)) {
    final value? => id(value),
    null => null,
  },
  own: own,
);

/// Kept as the text the core sends: [known] holds the values a screen
/// tells apart, when one does.
class _Text extends _Entry {
  const _Text(this.reason, {this.known});

  final String reason;
  final Set<String>? known;
}

/// Built and sent by this app: each case of the core, as this app
/// writes it.
class _Sent extends _Entry {
  const _Sent(this.cases);

  final Map<String, Map<String, dynamic> Function()> cases;
}

/// A failure of the core, `{"kind", "message"}`, as the bridge hands it
/// over inside `{"error": …}`.
class _Failure extends _Entry {
  const _Failure();
}

/// A code of the core, the kind of a failure.
class _Code extends _Entry {
  const _Code();
}

/// Never received nor sent by this app.
class _Away extends _Entry {
  const _Away(this.reason);

  final String reason;
}

const String _savings = '3f1c2a64-8b7e-4d21-9c5a-6e0f7b2d9a13';
const int _now = 1750000000;
const String _noChart = 'this app draws no price chart';

/// Every type the core writes a reference file for, by its name in the
/// core, and how this app takes it.
final Map<String, _Entry> _contract = {
  'AbsoluteLock': _reads(AbsoluteLock.fromJson),
  'AddressEntry': _reads(AddressEntry.fromJson),
  'AddressList': _reads(AddressList.fromJson),
  'AddressRow': _reads(AddressRow.fromJson),
  'AppLock': _reads(AppLock.fromJson),
  'BackendConfig': _reads(
    BackendConfig.fromJson,
    encode: (config) => (config as BackendConfig).toJson(),
  ),
  'BackupBackendPreview': _reads(BackupBackend.fromJson),
  'BackupBundle': _reads(BackupBundle.fromJson),
  'BackupOptions': _Sent({
    'everything': () => const BackupOptions().toJson(),
    'chosen': () => const BackupOptions(
      walletIds: [_savings],
      includeSettings: true,
    ).toJson(),
  }),
  'BackupPreview': _reads(BackupPreview.fromJson),
  'BackupWalletPreview': _reads(BackupWalletPreview.fromJson),
  'BalanceSnapshot': _reads(BalanceSnapshot.fromJson),
  'BranchRole': _enum(BranchRole.values, (v) => v.id, BranchRole.fromId),
  'BranchState': _reads(BranchState.fromJson),
  'BranchTone': _enum(BranchTone.values, (v) => v.id, BranchTone.fromId),
  'BroadcastReport': _reads(BroadcastReport.fromJson),
  'BroadcastStatus': _reads(BroadcastStatus.fromJson),
  'CachedTotals': const _Inside('WalletMeta', ['cached']),
  'CertificateReport': _reads(CertificateReport.fromJson),
  'CertificateStatus': _reads(CertificateStatus.fromJson),
  'Condition': _reads(PolicyCondition.fromJson),
  'Context': _Sent({
    'told': () => const NoticeContext(
      names: {_savings: 'Savings'},
      unit: AmountUnit.btc,
      masked: false,
      details: true,
    ).toJson(),
    'discreet': () => const NoticeContext(
      names: {},
      unit: AmountUnit.sats,
      masked: true,
      details: false,
    ).toJson(),
  }),
  'CoreError': const _Failure(),
  'Coverage': _enum(Coverage.values, (v) => v.id, Coverage.fromId),
  'CurrencyEntry': _reads(CurrencyEntry.fromJson),
  'CurrencyReach': _enum(
    CurrencyReach.values,
    (v) => v.id,
    CurrencyReach.fromId,
  ),
  'DerivationChoice': _reads(
    DerivationChoice.fromJson,
    encode: (choice) => (choice as DerivationChoice).toJson(),
  ),
  'ErrorCode': const _Code(),
  'ExportDirection': _enum(
    ExportDirection.values,
    (v) => v.id,
    (id) => ExportDirection.values.where((v) => v.id == id).firstOrNull,
  ),
  'ExportOptions': _Sent({
    'everything': () => const ExportOptions().toJson(),
    'filtered': () => const ExportOptions(
      from: _now - 86400 * 31,
      to: _now,
      direction: ExportDirection.incoming,
      includePending: false,
    ).toJson(),
  }),
  'ExportResult': _reads(ExportResult.fromJson),
  'FiatCurrency': const _Text(
    "the list of currencies is the core's: the settings offer what its "
    'table lists',
  ),
  'ImportChoices': _Sent({
    'everything': () => const ImportChoices().toJson(),
    'chosen': () =>
        const ImportChoices(indexes: [0], applySettings: true).toJson(),
  }),
  'ImportOptions': _Sent({
    'as_read': () => const ImportOptions().toJson(),
    'chosen': () => const ImportOptions(
      script: ScriptKind.segwit,
      derivation: DerivationChoice(
        receive: '0/*',
        change: '1/*',
        origin: "[73c5da0a/84'/0'/0']",
      ),
      network: Network.mainnet,
    ).toJson(),
  }),
  'ImportReport': _reads(ImportReport.fromJson),
  'InputWarning': _enum(InputWarning.values, (v) => v.id, InputWarning.fromId),
  'Keychain': const _Text('kept as the core spells it; no screen reads it'),
  'LeftOut': _reads(LiveLeftOut.fromJson),
  'LeftOutReason': _enum(
    LeftOutReason.values,
    (v) => v.id,
    LeftOutReason.fromId,
  ),
  // `{"type":"stopped"}`, which the model reads too, is the mobile
  // bridge's own (rust/src/api/mod.rs): what it says once the core's
  // last event is out.
  'LiveEvent': _reads(LiveEvent.fromJson),
  'LiveTx': _reads(LiveTx.fromJson, encode: (tx) => (tx as LiveTx).toJson()),
  'LockKind': _enum(LockKind.values, (v) => v.id, LockKind.fromId),
  'LockState': _reads(LockState.fromJson),
  'LockVerdict': _reads(LockVerdict.fromJson),
  'Network': _enum(Network.values, (v) => v.id, Network.fromId),
  'NewTx': _reads(NewTx.fromJson),
  'Notice': _reads(TxNotice.fromJson),
  'NoticeId': const _Inside('Notice', ['id']),
  'NoticeKind': _enum(NoticeKind.values, (v) => v.id, NoticeKind.fromId),
  'OpReturnData': _reads(OpReturnData.fromJson),
  'ParsedInput': _Decoded((json, raw) => ParsedInput.fromJson(json, raw)),
  'ParsedPayload': _reads(ParsedPayload.fromJson),
  'PolicyBranch': _reads(PolicyBranch.fromJson),
  'PolicyKey': _reads(PolicyKey.fromJson),
  'PolicyKind': _enum(PolicyKind.values, (v) => v.id, PolicyKind.fromId),
  'PolicySnapshot': _reads(PolicySnapshot.fromJson),
  'Preferences': _reads(Preferences.fromJson),
  'PreferencesChange': _Sent({
    'nothing': () => const PreferencesChange().toJson(),
    'currency': () =>
        const PreferencesChange(fiatCurrency: FiatCurrency('usd')).toJson(),
    'everything': () => const PreferencesChange(
      unit: AmountUnit.sats,
      masked: true,
      fiat: true,
      fiatCurrency: FiatCurrency('chf'),
      priceSource: PriceSource.kraken,
      notifyNewTx: true,
      explorerAck: true,
    ).toJson(),
  }),
  'PriceHistory': const _Away(_noChart),
  'PricePoint': const _Away(_noChart),
  'PriceQuote': _reads(PriceQuote.fromJson),
  'PriceRange': const _Away(_noChart),
  'PriceSource': _enum(PriceSource.values, (v) => v.id, PriceSource.fromId),
  'PriceTable': _reads(PriceTable.fromJson),
  'PublicServer': _reads(PublicServer.fromJson),
  'QrFormat': _enum(QrFormat.values, (v) => v.id, QrFormat.fromId),
  'QrProgress': _reads(QrProgress.fromJson),
  'RecentBroadcast': _reads(RecentBroadcast.fromJson),
  'RecognizedKind': _enum(
    RecognizedKind.values,
    (v) => v.id,
    RecognizedKind.fromId,
  ),
  'RelativeLock': _reads(RelativeLock.fromJson),
  'Remaining': _reads(Remaining.fromJson),
  'Remedy': _reads(LiveRemedy.fromJson),
  'ScannedBackend': _reads(ScannedBackend.fromJson),
  'ScannedBackendKind': const _Text(
    'the backend form tells Esplora from Electrum by it',
    known: {'electrum', 'esplora'},
  ),
  'ScriptKind': _enum(ScriptKind.values, (v) => v.id, ScriptKind.fromId),
  'ServerProtocol': _enum(
    ServerProtocol.values,
    (v) => v.id,
    ServerProtocol.fromId,
  ),
  'ServerSoftware': _enum(
    ServerSoftware.values,
    (v) => v.id,
    ServerSoftware.fromId,
  ),
  'Settings': _reads(Settings.fromJson),
  'SourceEntry': const _Inside('PriceTable', ['sources', 0]),
  'SyncAllReport': _reads(SyncAllReport.fromJson),
  'SyncFailure': _reads(SyncFailure.fromJson),
  'SyncReport': _reads(SyncReport.fromJson),
  'SyncStamp': _reads(SyncStamp.fromJson),
  'TimeBasis': _enum(TimeBasis.values, (v) => v.id, TimeBasis.fromId),
  'Timelock': _reads(PolicyTimelock.fromJson),
  'TimelockRef': _reads(TimelockRef.fromJson),
  'TorMode': _enum(TorMode.values, (v) => v.id, TorMode.fromId),
  'TorRoute': _reads(TorRoute.fromJson),
  'TorSettings': _reads(
    TorSettings.fromJson,
    encode: (settings) => (settings as TorSettings).toJson(),
  ),
  'TorStatus': _reads(TorStatus.fromJson),
  'TorVia': _enum(TorVia.values, (v) => v.id, TorVia.fromId),
  'TxDetail': _reads(TxDetail.fromJson),
  'TxExtras': _reads(TxExtras.fromJson),
  'TxInputPreview': _reads(TxInputPreview.fromJson),
  'TxIo': _reads(TxIo.fromJson),
  'TxOutputPreview': _reads(TxOutputPreview.fromJson),
  'TxPreview': _reads(TxPreview.fromJson),
  'TxReadiness': _enum(TxReadiness.values, (v) => v.id, TxReadiness.fromId),
  'TxSeverity': _enum(TxSeverity.values, (v) => v.id, TxSeverity.fromId),
  'TxSource': _enum(TxSource.values, (v) => v.id, TxSource.fromId),
  'TxStage': _enum(TxStage.values, (v) => v.id, TxStage.fromId),
  'TxStatus': _reads(TxStatus.fromJson),
  'TxSummary': _reads(TxSummary.fromJson),
  'TxWarning': _reads(TxWarning.fromJson),
  'TxWarningKind': _enum(
    TxWarningKind.values,
    (v) => v.id,
    TxWarningKind.fromId,
    own: {'other': 'what this build reads a kind it does not know as'},
  ),
  'Unit': _enum(AmountUnit.values, (v) => v.id, AmountUnit.fromId),
  'UpdateStatus': _reads(UpdateStatus.fromJson),
  'UtxoInfo': _reads(UtxoInfo.fromJson),
  'WalletCoverage': _reads(WalletCoverage.fromJson),
  'WalletIcon': _enum(WalletIcon.values, (v) => v.id, WalletIcon.fromId),
  'WalletKind': _reads(WalletKind.fromJson),
  'WalletMeta': _reads(WalletMeta.fromJson),
  'WalletRef': _reads(WalletRef.fromJson),
  'WalletSnapshot': _reads(WalletSnapshot.fromJson),
  'WatchLimits': _reads(WatchLimits.fromJson),
  'WatchLimitsChoice': _reads(WatchLimitsChoice.fromJson),
  'WatchState': _enum(WatchState.values, (v) => v.id, WatchState.fromId),
  'WatchStatus': _reads(LiveWatchStatus.fromJson),
  'WatchTransport': _enum(
    WatchTransport.values,
    (v) => v.id,
    WatchTransport.fromId,
  ),
};

/// Keys the core sends that this app leaves unread on purpose, as
/// `Type.key`, with the reason. A key is excused wherever it sits in an
/// object shaped like a case of that type: in the type's own file, and
/// nested in the others.
const Map<String, String> _ignored = {
  'CurrencyEntry.code':
      'the ISO code of a currency is its identifier in capitals, which '
      'FiatCurrency.code spells wherever a currency is shown without its '
      'entry of the table',
  'SourceEntry.ranges': _noChart,
  'SyncStamp.server':
      'where the core starts the next sync of the wallet; the screens name '
      'the backend, which the stamp carries too',
  'TxPreview.ready':
      'the same as `readiness` being ready, which the page reads',
  'WalletMeta.complete_at':
      "when a sync last read every script: the core's own schedule of full "
      'reads',
  'WalletMeta.labels': 'no screen of this app shows the labels of a wallet',
};

// --- the checks ----------------------------------------------------------

/// The key sets of the cases of [type]: what an object of it looks like.
Set<String> _shapes(String type) => {
  for (final value in coreCases(type).values)
    if (value is Map<String, dynamic>) (value.keys.toList()..sort()).join(','),
};

String _shape(Map<String, dynamic> object) =>
    (object.keys.toList()..sort()).join(',');

/// Every key any reference file holds, at any depth.
Set<String> _vocabulary() {
  final keys = <String>{};
  for (final type in coreFixtureTexts.keys) {
    _eachKey(coreCases(type), '', (path, parent) {
      keys.add(path.split('.').last.replaceAll('[]', ''));
    });
  }
  return keys;
}

class _Check {
  final List<String> failures = [];
  final Set<String> ignoredUsed = {};
  final Set<String> vocabulary = _vocabulary();
  late final Map<String, Set<String>> _ignoredShapes = {
    for (final id in _ignored.keys) id: _shapes(id.split('.').first),
  };

  void fail(String at, String message) => failures.add('$at: $message');

  /// Whether [key] of an object shaped like [parent] is left unread on
  /// purpose.
  bool _excused(Map<String, dynamic> parent, String key) {
    for (final entry in _ignoredShapes.entries) {
      if (entry.key.split('.').last == key &&
          entry.value.contains(_shape(parent))) {
        ignoredUsed.add(entry.key);
        return true;
      }
    }
    return false;
  }

  /// Decodes [value] with [entry], noting what it reads. Null when the
  /// decode failed.
  _Reads? _decode(_Decoded entry, dynamic value, String at) {
    if (value is! Map<String, dynamic>) {
      fail(at, 'not an object');
      return null;
    }
    final reads = _Reads();
    final Object? decoded;
    try {
      decoded = entry.decode(_TrackedMap(value, '', reads), jsonEncode(value));
    } catch (error) {
      final missing = reads.absent.isEmpty
          ? ''
          : ', reading ${reads.absent.join(', ')}, absent from this case';
      fail(at, 'the model throws: $error$missing');
      return null;
    }
    if (decoded == null) {
      fail(at, 'the model reads nothing out of it');
      return null;
    }
    if (entry.encode case final encode?) {
      final sent = jsonEncode(_withoutNulls(encode(decoded)));
      if (sent != jsonEncode(_withoutNulls(value))) {
        fail(at, 'sent back as $sent');
      }
    }
    for (final path in reads.absent) {
      final key = path.split('.').last;
      if (!vocabulary.contains(key)) {
        fail('$at.$path', 'read by this app, sent by the core nowhere');
      }
    }
    return reads;
  }

  /// Fails every key of [value] under [prefix] that [reads] did not
  /// look at.
  void _unread(dynamic value, _Reads reads, String at, String prefix) {
    bool below(String path, String root) =>
        path == root || path.startsWith('$root.') || path.startsWith('$root[');
    // What sits under a key left unread is left unread with it.
    final unread = <String>[];
    _eachKey(value, '', (path, parent) {
      if (prefix.isNotEmpty && !below(path, prefix)) return;
      if (reads.held.contains(path)) return;
      if (unread.any((root) => below(path, root))) return;
      unread.add(path);
      if (!_excused(parent, path.split('.').last)) {
        fail('$at.$path', 'sent by the core, read by no model of this app');
      }
    });
  }

  void type(String name, _Entry entry, Map<String, dynamic> cases) {
    switch (entry) {
      case _Decoded():
        cases.forEach((label, value) {
          final at = '$name.json#$label';
          final reads = _decode(entry, value, at);
          if (reads != null) _unread(value, reads, at, '');
        });
      case _Inside(:final parent, :final path):
        final host = _contract[parent];
        if (host is! _Decoded) {
          fail(name, 'read inside $parent, which no model decodes');
          return;
        }
        final base = coreCases(parent).values.first;
        final prefix = [for (final step in path) step is int ? '[]' : '.$step']
            .join()
            .substring(1);
        cases.forEach((label, value) {
          final at = '$name.json#$label, inside $parent';
          final whole = jsonDecode(jsonEncode(base));
          dynamic slot = whole;
          for (final step in path.take(path.length - 1)) {
            slot = slot[step];
          }
          slot[path.last] = value;
          final reads = _decode(host, whole, at);
          if (reads != null) _unread(whole, reads, at, prefix);
        });
      case _Enum(:final ids, :final decode, :final own):
        final sent = <String>{};
        cases.forEach((label, value) {
          final at = '$name.json#$label';
          if (value is! String) return fail(at, 'not a string');
          sent.add(value);
          String? read;
          try {
            read = decode(value);
          } catch (_) {
            read = null;
          }
          if (read != value) {
            fail(at, 'read by this app as ${read ?? 'nothing'}');
          }
        });
        for (final id in ids) {
          if (!sent.contains(id) && !own.containsKey(id)) {
            fail('$name=$id', 'a value of this app the core never sends');
          }
        }
        for (final id in own.keys) {
          if (sent.contains(id)) {
            fail('$name=$id', 'said to be this app\'s own, sent by the core');
          }
        }
      case _Text(:final reason, :final known):
        expect(reason, isNotEmpty, reason: '$name is text without a reason');
        final sent = {
          for (final value in cases.values)
            if (value is String) value,
        };
        if (sent.length != cases.length) fail(name, 'a case is not a string');
        if (known != null &&
            (sent.length != known.length || !sent.containsAll(known))) {
          fail(name, 'the core sends $sent, this app tells apart $known');
        }
      case _Sent(cases: final samples):
        for (final label in {...cases.keys, ...samples.keys}) {
          final at = '$name.json#$label';
          final sample = samples[label];
          if (!cases.containsKey(label)) {
            fail(at, 'built by this test, written by the core no more');
          } else if (sample == null) {
            fail(at, 'written by the core, not built by this test');
          } else {
            final sent = jsonEncode(_withoutNulls(sample()));
            if (sent != jsonEncode(_withoutNulls(cases[label]))) {
              fail(at, 'this app sends $sent');
            }
          }
        }
      case _Failure():
        cases.forEach((label, value) {
          final at = '$name.json#$label';
          if (value is! Map<String, dynamic>) return fail(at, 'not an object');
          for (final key in value.keys) {
            if (key != 'kind' && key != 'message') {
              fail(
                '$at.$key',
                'sent by the core, read by no model of this app',
              );
            }
          }
          _failsAs(at, value, value['kind'], value['message']);
        });
      case _Code():
        cases.forEach((label, value) {
          _failsAs('$name.json#$label', {'kind': value}, value, null);
        });
      case _Away(:final reason):
        expect(reason, isNotEmpty, reason: '$name stays away without a reason');
    }
  }

  /// Hands [error] over the way the bridge does and checks the failure
  /// comes out with [kind], and [message] when one is given.
  void _failsAs(
    String at,
    Map<String, dynamic> error,
    dynamic kind,
    dynamic message,
  ) {
    try {
      RustBridge.decode(jsonEncode({'error': error}));
      fail(at, 'not read as a failure');
    } on BridgeException catch (failure) {
      if (failure.kind != kind) {
        fail(at, 'read as a failure of ${failure.kind}');
      }
      if (message != null && failure.message != message) {
        fail(at, 'read with the words ${failure.message}');
      }
    }
  }
}

void main() {
  test('the stand-ins of fakes.dart hold what the core sends', () {
    final defaults = coreCases('Preferences')['default'];
    expect(
      kPreferences,
      Preferences.fromJson(defaults as Map<String, dynamic>),
      reason: 'kPreferences are the defaults of the core',
    );
    final table = PriceTable.fromJson(
      coreCases('PriceTable')['table'] as Map<String, dynamic>,
    );
    final order = [for (final entry in table.currencies) entry.currency];
    var last = -1;
    for (final entry in kPriceTable.currencies) {
      final core = table.entryOf(entry.currency);
      expect(core, isNotNull, reason: '${entry.currency} is in the table');
      final named = '${entry.currency} as the core lists it';
      expect(entry.name, core!.name, reason: named);
      expect(entry.reach, core.reach, reason: named);
      expect(entry.sources, core.sources, reason: named);
      final at = order.indexOf(entry.currency);
      expect(at, greaterThan(last), reason: 'kPriceTable keeps its order');
      last = at;
    }
    expect(
      [for (final s in kPriceTable.sources) (s.source, s.label)],
      [for (final s in table.sources) (s.source, s.label)],
    );
    expect(kPriceTable.refresh, table.refresh);
  });

  test('finds the reference files of the core', () {
    expect(
      coreFixtureTexts,
      isNotEmpty,
      reason:
          'no reference JSON in $coreFixturesDir: check out gerfaut-core '
          'beside this repository, at reproducible/gerfaut-core.rev',
    );
  });

  test('knows every type the core writes, and only those', () {
    final written = coreFixtureTexts.keys.toSet();
    expect(
      written.difference(_contract.keys.toSet()).toList()..sort(),
      isEmpty,
      reason:
          'types the core writes and this app does not list: give each a '
          'decoder, or a reason to stay away',
    );
    expect(
      _contract.keys.toSet().difference(written).toList()..sort(),
      isEmpty,
      reason: 'types this app lists and the core no longer writes',
    );
  });

  test('reads every case the core writes with the models of this app', () {
    final check = _Check();
    for (final name in coreFixtureTexts.keys) {
      final entry = _contract[name];
      if (entry != null) check.type(name, entry, coreCases(name));
    }
    expect(
      check.failures,
      isEmpty,
      reason: 'what the core sends and this app reads differently',
    );
    expect(
      _ignored.keys.where((id) => !check.ignoredUsed.contains(id)).toList(),
      isEmpty,
      reason: '_ignored names keys the core no longer sends',
    );
  });
}
