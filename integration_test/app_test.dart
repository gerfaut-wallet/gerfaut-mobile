// The real app on a real platform: the Rust core loaded through the
// bridge, the vault created on disk, its key kept by the system's
// secure storage. CI runs it on the iOS simulator, where nothing else
// proves that the native side links and starts:
//
//   flutter test integration_test -d <simulator id>
//
// It needs no network: an empty vault syncs nothing. It expects a first
// launch, as on CI's fresh simulator; run again on the same one, after
// `xcrun simctl uninstall <simulator id> com.gerfautwallet.gerfaut`
// and `xcrun simctl keychain <simulator id> reset`.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gerfaut/app.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/src/vault_key.dart';

/// Pumps frames until [finder] matches, or fails after [timeout]. The
/// app keeps animating while it starts, so `pumpAndSettle` could wait
/// for ever.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('not on screen after $timeout: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a first launch opens a new vault and reaches the home screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        retry: noRetry,
        child: GerfautApp(bootstrap: bootstrapGerfaut),
      ),
    );

    await pumpUntilFound(tester, find.text('Watch, never spend'));
    await tester.tap(find.text('Skip'));
    await pumpUntilFound(tester, find.text('No wallets yet'));

    // The vault the core sealed is on disk, and the key that opens it
    // is in the secure storage, where the next launch will look.
    final dir = await getApplicationDocumentsDirectory();
    expect(
      File('${dir.path}${Platform.pathSeparator}$vaultFileName').existsSync(),
      isTrue,
    );
    final key = await const SecureVaultKeyStore().read();
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$', caseSensitive: false)));

    // And the core answers through the bridge.
    final settings = await const RustBridge().getSettings();
    expect(settings.preferences.notifyNewTx, isFalse);
  });
}
