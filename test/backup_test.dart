import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/backup_export.dart';
import 'package:gerfaut/screens/backup_qr.dart';
import 'package:gerfaut/screens/backup_restore.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/share.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fakes.dart';

/// Records what would have been shared instead of touching the system.
class FakeBackupSharer implements BackupSharer {
  final List<({List<int> bytes, String filename})> shared = [];

  @override
  Future<void> shareBackup({
    required List<int> bytes,
    required String filename,
  }) async {
    shared.add((bytes: bytes, filename: filename));
  }
}

Widget screen(FakeBridge bridge, Widget home, {BackupSharer? sharer}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      if (sharer != null) backupSharerProvider.overrideWithValue(sharer),
    ],
    child: MaterialApp(
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      home: home,
    ),
  );
}

/// A surface tall enough to lay out a whole step without scrolling.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> typePasswords(
  WidgetTester tester,
  String password, [
  String? confirm,
]) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), password);
  if (confirm != null) await tester.enterText(fields.at(1), confirm);
  await tester.pumpAndSettle();
}

void main() {
  group('export', () {
    testWidgets('a password too short never reaches the core', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(screen(bridge, const BackupExportScreen()));
      await tester.pumpAndSettle();

      await typePasswords(tester, 'short', 'short');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(bridge.backupExportCalls, isEmpty);
    });

    testWidgets('two different passwords are refused', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(screen(bridge, const BackupExportScreen()));
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct hors');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(find.text('The two passwords differ.'), findsOneWidget);
      expect(bridge.backupExportCalls, isEmpty);
    });

    testWidgets('every wallet by default, and the settings when asked', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(bridge, const BackupExportScreen(), sharer: FakeBackupSharer()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(bridge.backupExportCalls, hasLength(1));
      // Null means every wallet on every network, not a filtered list.
      expect(bridge.backupExportCalls.single.walletIds, isNull);
      expect(bridge.backupExportCalls.single.includeSettings, isTrue);
      expect(find.textContaining('1 wallet'), findsWidgets);
      expect(find.text('Save file'), findsOneWidget);
      expect(find.text('Show QR code'), findsOneWidget);
    });

    testWidgets('the network scope sends only that network ids', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge(
        wallets: [
          makeMeta(id: 'w1', network: Network.signet),
          makeMeta(id: 'w2', name: 'Other', network: Network.mainnet),
        ],
        settings: const Settings(
          activeNetwork: Network.signet,
          backends: {},
          appPrefs: {},
        ),
      );
      await tester.pumpWidget(screen(bridge, const BackupExportScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Signet only (1)'));
      await tester.pumpAndSettle();
      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(bridge.backupExportCalls.single.walletIds, ['w1']);
    });

    testWidgets('saving hands the decoded bytes to the system sheet', (
      tester,
    ) async {
      useTallSurface(tester);
      final sharer = FakeBackupSharer();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(bridge, const BackupExportScreen(), sharer: sharer),
      );
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      expect(sharer.shared, hasLength(1));
      expect(sharer.shared.single.bytes, base64Decode('R0ZCQUNLVVA='));
      expect(sharer.shared.single.filename, endsWith('.gerfaut'));
    });
  });

  group('animated QR', () {
    /// The frame on screen, read the way a screen reader would.
    String? shownLabel(WidgetTester tester) =>
        tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel;

    testWidgets('the frames loop, uppercased, with their position', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        screen(
          FakeBridge(),
          const BackupQrScreen(
            frames: ['ur:bytes/1-2/aaa', 'ur:bytes/2-2/bbb'],
          ),
        ),
      );
      await tester.pump();

      expect(shownLabel(tester), 'Backup QR code, frame 1 of 2');
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.pump(frameInterval);
      expect(shownLabel(tester), 'Backup QR code, frame 2 of 2');
      expect(find.text('2 / 2'), findsOneWidget);

      // And back to the first: a receiver may join at any frame.
      await tester.pump(frameInterval);
      expect(shownLabel(tester), 'Backup QR code, frame 1 of 2');
    });

    testWidgets('a single frame stands still, with no counter', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        screen(FakeBridge(), const BackupQrScreen(frames: ['ur:bytes/aaa'])),
      );
      await tester.pump();

      expect(shownLabel(tester), 'Backup QR code');
      expect(find.text('1 / 1'), findsNothing);
      await tester.pump(frameInterval);
      expect(shownLabel(tester), 'Backup QR code');
    });
  });

  group('restore', () {
    BackupPreview preview({
      bool alreadyWatched = false,
      bool settings = false,
    }) {
      return BackupPreview(
        createdAt: 1755000000,
        hasSettings: settings,
        wallets: [
          const BackupWalletPreview(
            index: 0,
            name: 'Cold storage',
            network: Network.signet,
            kind: DescriptorsKind(
              external: 'wpkh(tpub.../0/*)#aaaaaaaa',
              internal: null,
              script: ScriptKind.segwit,
            ),
            alreadyWatched: false,
          ),
          BackupWalletPreview(
            index: 1,
            name: 'Savings',
            network: Network.signet,
            kind: const SingleAddressKind(address: 'tb1qexample'),
            alreadyWatched: alreadyWatched,
          ),
        ],
      );
    }

    /// Drives the screen to the preview step through a scanned code.
    /// The screen is pushed, as the settings push it, so what it says
    /// on its way out has a route to land on.
    Future<void> openBackup(WidgetTester tester, FakeBridge bridge) async {
      await tester.pumpWidget(
        screen(
          bridge,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BackupRestoreScreen(
                      cameraBuilder: (onFrame) => TextButton(
                        onPressed: () => onFrame('gerfaut-backup:R0ZCQUNLVVA='),
                        child: const Text('frame'),
                      ),
                    ),
                  ),
                ),
                child: const Text('open restore'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('frame'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
    }

    testWidgets('a wrong password says so in plain words', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) =>
          throw const BridgeException('vault', 'vault decryption failed');
      await openBackup(tester, bridge);

      expect(
        find.text('Wrong password, or the file is damaged.'),
        findsOneWidget,
      );
    });

    testWidgets('a watched wallet is listed but cannot be chosen', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => preview(alreadyWatched: true);
      await openBackup(tester, bridge);

      expect(find.text('Savings'), findsOneWidget);
      expect(find.textContaining('Already watched'), findsOneWidget);
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes, hasLength(2));
      expect(boxes[0].value, isTrue);
      expect(boxes[1].value, isFalse);
      expect(boxes[1].onChanged, isNull);
      expect(find.text('Restore 1 wallet'), findsOneWidget);
    });

    testWidgets('unchecking a wallet leaves it out of the restore', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => preview(settings: true);
      bridge.onImportBackup = (_, _, choices) => ImportReport(
        added: [makeMeta(network: Network.signet)],
        skipped: choices.indexes?.length == 1 ? 1 : 0,
        settingsApplied: choices.applySettings,
      );
      await openBackup(tester, bridge);

      expect(find.text('Restore 2 wallets'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Restore 1 wallet'), findsOneWidget);

      // Node settings travel only when the box is ticked.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore 1 wallet'));
      await tester.pumpAndSettle();

      expect(bridge.importCalls, hasLength(1));
      expect(bridge.importCalls.single.indexes, [0]);
      expect(bridge.importCalls.single.applySettings, isTrue);
    });

    testWidgets('a restore states what it added', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => preview();
      bridge.onImportBackup = (_, _, _) => ImportReport(
        added: [makeMeta(network: Network.signet)],
        skipped: 1,
        settingsApplied: false,
      );
      await openBackup(tester, bridge);
      await tester.tap(find.text('Restore 2 wallets'));
      await tester.pumpAndSettle();

      expect(find.text('1 wallet restored'), findsOneWidget);
    });
  });
}
