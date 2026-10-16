// The reference JSON of gerfaut-core: what the core sends for every type
// that crosses the bridge, in tests/bridge/<Type>.json of the checkout
// beside this repository (the one rust/Cargo.toml builds against, at
// reproducible/gerfaut-core.rev in CI). Each file maps a case name to
// one value.

import 'dart:convert';
import 'dart:io';

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
