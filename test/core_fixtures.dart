// The reference JSON of gerfaut-core: what the core sends for every type
// that crosses the bridge, in tests/bridge/<Type>.json of the checkout
// beside this repository (the one rust/Cargo.toml builds against, at
// reproducible/gerfaut-core.rev in CI). Each file maps a case name to
// one value.

import 'dart:convert';
import 'dart:io';

import 'package:gerfaut/src/bridge.dart';

/// Where the files are read from, relative to this package, where
/// `flutter test` runs.
const String coreFixturesDir = '../gerfaut-core/tests/bridge';

/// The text of every file, by type name, in name order.
final Map<String, String> coreFixtureTexts = _readAll();

Map<String, String> _readAll() {
  final dir = Directory(coreFixturesDir);
  if (!dir.existsSync()) return const {};
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      file.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''): file
          .readAsStringSync(),
  };
}

/// The cases of a type, decoded afresh, in the order the core wrote
/// them.
Map<String, dynamic> coreCases(String type) {
  final text = coreFixtureTexts[type];
  if (text == null) {
    throw StateError(
      'no $type.json in $coreFixturesDir: check out gerfaut-core beside '
      'this repository',
    );
  }
  return jsonDecode(text) as Map<String, dynamic>;
}

/// One case of a type, as the bridge hands it over: its JSON text.
String coreCaseJson(String type, String name) {
  final cases = coreCases(type);
  if (!cases.containsKey(name)) {
    throw StateError('$type.json has no case $name');
  }
  return jsonEncode(cases[name]);
}

/// The failure the core sends under [kind] (`CoreError.json`), read the
/// way the bridge reads it. The fakes raise these: a code the core no
/// longer sends fails the test that raises it, instead of standing in
/// for a failure that can never come. [message] takes the place of the
/// core's words where a test needs words of its own; the code is the
/// core's either way.
BridgeException coreFailure(String kind, [String? message]) {
  final sent = coreCases('CoreError').values.whereType<Map<String, dynamic>>();
  final error = sent.where((error) => error['kind'] == kind).firstOrNull;
  if (error == null) {
    throw StateError(
      'the core sends no failure of kind $kind (CoreError.json)',
    );
  }
  try {
    RustBridge.decode(
      jsonEncode({
        'error': {...error, 'message': ?message},
      }),
    );
  } on BridgeException catch (failure) {
    return failure;
  }
  throw StateError('CoreError.json#$kind is not read as a failure');
}
