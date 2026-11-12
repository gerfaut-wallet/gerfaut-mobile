// What the Android manifest and its backup rules promise, read from the
// files the build packs. Comments are dropped first: they describe the
// rules, and a rule written only in a comment is not one.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The text of the file at [path] without its XML comments.
String _withoutComments(String path) =>
    File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// The opening tag of the element named [name] in [xml].
String _openingTag(String xml, String element, String name) {
  final tag = RegExp(
    '<$element\\s[^>]*android:name="${RegExp.escape(name)}"[^>]*>',
  ).firstMatch(xml);
  expect(tag, isNotNull, reason: '$element $name is declared');
  return tag![0]!;
}

void main() {
  group('backup and transfer rules', () {
    final rules = _withoutComments(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    );

    // Android copies an app's data domain by domain, and `root` holds
    // none of the others: excluding it alone still lets shared_prefs/,
    // files/ and databases/ travel. Every domain is named, the
    // device-protected ones too.
    const domains = [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ];

    for (final section in ['cloud-backup', 'device-transfer']) {
      test('$section excludes every domain and includes none', () {
        final body = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules);
        expect(body, isNotNull, reason: '$section is declared');
        final text = body![1]!;
        for (final domain in domains) {
          expect(
            text,
            matches(RegExp('<exclude\\s+domain="$domain"\\s*/>')),
            reason: '$section excludes $domain',
          );
        }
        expect(text, isNot(contains('<include')));
      });
    }

    test('the manifest turns backup off on every version', () {
      final manifest = _withoutComments(
        'android/app/src/main/AndroidManifest.xml',
      );
      final application = RegExp(r'<application\s[^>]*>')
          .firstMatch(manifest)![0]!;
      expect(application, contains('android:allowBackup="false"'));
      expect(application, contains('android:fullBackupContent="false"'));
      expect(
        application,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });
  });

  group('launch entries', () {
    final manifest = _withoutComments(
      'android/app/src/main/AndroidManifest.xml',
    );

    // Another app reaches the activity only through the launcher
    // entries, and those carry nothing but MAIN and LAUNCHER.
    test('the activity itself is not exported', () {
      expect(
        _openingTag(manifest, 'activity', '.MainActivity'),
        contains('android:exported="false"'),
      );
    });

    test('both launcher entries still are', () {
      for (final alias in ['.Launcher', '.Calculator']) {
        final tag = _openingTag(manifest, 'activity-alias', alias);
        expect(tag, contains('android:exported="true"'));
        expect(tag, contains('android:targetActivity=".MainActivity"'));
      }
    });
  });
}
