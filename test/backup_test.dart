import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/screens/backup_export.dart';
import 'package:gerfaut/screens/backup_qr.dart';
import 'package:gerfaut/screens/backup_restore.dart';
import 'package:gerfaut/screens/scan.dart';
import 'package:gerfaut/src/bridge.dart';
import 'package:gerfaut/src/documents.dart';
import 'package:gerfaut/src/lock.dart';
import 'package:gerfaut/src/models.dart';
import 'package:gerfaut/src/screen.dart';
import 'package:gerfaut/src/share.dart';
import 'package:gerfaut/src/state.dart';
import 'package:gerfaut/theme/tokens.dart';
import 'package:gerfaut/widgets/buttons.dart';
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

Widget screen(
  FakeBridge bridge,
  Widget home, {
  BackupSharer? sharer,
  DocumentSaver? saver,
  ScreenKeeper? keeper,
}) {
  return ProviderScope(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      if (sharer != null) backupSharerProvider.overrideWithValue(sharer),
      if (saver != null) documentSaverProvider.overrideWithValue(saver),
      if (keeper != null) screenKeeperProvider.overrideWithValue(keeper),
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

    testWidgets('the password field says what it stands in front of', (
      tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        screen(FakeBridge(wallets: [makeMeta()]), const BackupExportScreen()),
      );
      await tester.pumpAndSettle();

      // The eight-character floor is what the core takes, not advice:
      // a file guessed offline needs length, and the screen says so
      // where the password is chosen.
      expect(
        find.text(
          'This file can be copied and guessed offline: use a long '
          'passphrase, several words.',
        ),
        findsOneWidget,
      );
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
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Show QR code'), findsOneWidget);
      // The backup is made: leaving is the one primary action left, and
      // it reads as a button, full width, not as a line of text.
      final done = find.widgetWithText(PrimaryButton, 'Done');
      expect(done, findsOneWidget);
      expect(tester.widget<PrimaryButton>(done).expand, isTrue);
      expect(
        tester.getRect(done).width,
        closeTo(
          tester
              .getRect(find.widgetWithText(SecondaryButton, 'Show QR code'))
              .width,
          1,
        ),
      );

      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byType(BackupExportScreen), findsNothing);
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

    testWidgets('saving writes the decoded bytes where the user points', (
      tester,
    ) async {
      useTallSurface(tester);
      final saver = FakeDocumentSaver();
      final sharer = FakeBackupSharer();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(
          bridge,
          const BackupExportScreen(),
          sharer: sharer,
          saver: saver,
        ),
      );
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      // A file, literally: the system's save dialog, not a share sheet
      // that happens to offer a drive among mail apps.
      expect(saver.saved, hasLength(1));
      expect(saver.saved.single.bytes, base64Decode('R0ZCQUNLVVA='));
      expect(saver.saved.single.filename, endsWith('.gerfaut'));
      expect(saver.saved.single.mimeType, 'application/octet-stream');
      expect(sharer.shared, isEmpty);
      expect(find.text('Saved'), findsOneWidget);

      // Flush the snackbar timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a save dialog waved away says nothing', (tester) async {
      useTallSurface(tester);
      final saver = FakeDocumentSaver(answer: false);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(bridge, const BackupExportScreen(), saver: saver),
      );
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      expect(saver.saved, isEmpty);
      expect(find.text('Saved'), findsNothing);
      // The backup is still on screen, ready for another try.
      expect(find.text('Save file'), findsOneWidget);
    });

    testWidgets('a write that fails is said in the words of the platform', (
      tester,
    ) async {
      useTallSurface(tester);
      final saver = FakeDocumentSaver()
        ..failure = const DocumentSaveException('The drive is full.');
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(bridge, const BackupExportScreen(), saver: saver),
      );
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      expect(find.text('The drive is full.'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('sharing hands the decoded bytes to the system sheet', (
      tester,
    ) async {
      useTallSurface(tester);
      final saver = FakeDocumentSaver();
      final sharer = FakeBackupSharer();
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(
          bridge,
          const BackupExportScreen(),
          sharer: sharer,
          saver: saver,
        ),
      );
      await tester.pumpAndSettle();

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      // The share sheet stays, under its own name, for a backup bound
      // straight for another app or device.
      expect(sharer.shared, hasLength(1));
      expect(sharer.shared.single.bytes, base64Decode('R0ZCQUNLVVA='));
      expect(sharer.shared.single.filename, endsWith('.gerfaut'));
      expect(saver.saved, isEmpty);
    });

    testWidgets('coming back from the save dialog or the sheet does not lock', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge(wallets: [makeMeta()]);
      await tester.pumpWidget(
        screen(
          bridge,
          const BackupExportScreen(),
          sharer: FakeBackupSharer(),
          saver: FakeDocumentSaver(answer: false),
        ),
      );
      await tester.pumpAndSettle();
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(BackupExportScreen)),
      ).read(lockProvider.notifier);
      lock
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();
      // Android pauses Gerfaut behind the dialog and resumes it after.
      lock
        ..noteHidden()
        ..noteResumed();

      // The backup is still on screen, with its QR code still to show.
      expect(lock.state.locked, isFalse);
      expect(find.text('Show QR code'), findsOneWidget);

      // The share sheet is a screen of the system's just the same.
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      lock
        ..noteHidden()
        ..noteResumed();
      expect(lock.state.locked, isFalse);
      expect(find.text('Show QR code'), findsOneWidget);
    });

    testWidgets('a dialog that never opened does not cover a later trip', (
      tester,
    ) async {
      useTallSurface(tester);
      // The save was refused before the dialog could come up: no app on
      // the phone can save a file. Gerfaut never left the screen, so
      // nothing ever comes back to spend the trip it announced — and
      // the next absence, whenever it comes, has to lock.
      final saver = FakeDocumentSaver()
        ..failure = const DocumentSaveException(
          'no app on this device can save a file',
          dialogOpened: false,
        );
      await tester.pumpWidget(
        screen(
          FakeBridge(wallets: [makeMeta()]),
          const BackupExportScreen(),
          sharer: FakeBackupSharer(),
          saver: saver,
        ),
      );
      await tester.pumpAndSettle();
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(BackupExportScreen)),
      ).read(lockProvider.notifier);
      lock
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      // The refusal is on screen and the backup is still here.
      expect(
        find.text('no app on this device can save a file'),
        findsOneWidget,
      );
      expect(lock.state.locked, isFalse);

      // The phone is put down and picked up again: that is a real
      // absence, and the announcement must not have covered it.
      lock
        ..noteHidden()
        ..noteHidden()
        ..noteResumed();
      expect(lock.state.locked, isTrue);
    });

    testWidgets('a write that failed after the dialog keeps its return', (
      tester,
    ) async {
      useTallSurface(tester);
      // The other side of the same trip: the dialog named a place and
      // the bytes did not make it. Android hands that answer back
      // before Flutter says the app resumed, so the trip is still owed
      // a return, and taking the announcement back here would put the
      // lock in front of someone who never left.
      final saver = FakeDocumentSaver()
        ..failure = const DocumentSaveException(
          'the document could not be opened for writing',
        );
      await tester.pumpWidget(
        screen(
          FakeBridge(wallets: [makeMeta()]),
          const BackupExportScreen(),
          sharer: FakeBackupSharer(),
          saver: saver,
        ),
      );
      await tester.pumpAndSettle();
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(BackupExportScreen)),
      ).read(lockProvider.notifier);
      lock
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await typePasswords(tester, 'correct horse', 'correct horse');
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();
      expect(
        find.text('the document could not be opened for writing'),
        findsOneWidget,
      );

      // The return the dialog owes, arriving after its answer.
      lock
        ..noteHidden()
        ..noteResumed();
      expect(lock.state.locked, isFalse);
      expect(find.text('Show QR code'), findsOneWidget);
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

    testWidgets('the screen is kept on for the loop, then let go', (
      tester,
    ) async {
      useTallSurface(tester);
      final keeper = FakeScreenKeeper();
      await tester.pumpWidget(
        screen(
          FakeBridge(),
          const BackupQrScreen(
            frames: ['ur:bytes/1-2/aaa', 'ur:bytes/2-2/bbb'],
          ),
          keeper: keeper,
        ),
      );
      await tester.pump();
      expect(keeper.on, isTrue);
      expect(keeper.holds, 1);

      // Leaving the screen hands the phone its timeout back.
      await tester.pumpWidget(
        screen(FakeBridge(), const SizedBox.shrink(), keeper: keeper),
      );
      expect(keeper.on, isFalse);
      expect(keeper.releases, 1);
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

    /// Pushes the restore screen the way the settings page pushes it, so
    /// what it says on its way out has a route to land on. The scanner's
    /// camera is a button that hands one frame over.
    Future<void> pushRestore(
      WidgetTester tester,
      FakeBridge bridge, {
      BackupFilePicker? filePicker,
    }) async {
      await tester.pumpWidget(
        screen(
          bridge,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BackupRestoreScreen(
                      filePicker: filePicker,
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
    }

    /// Drives the screen to the preview step through a scanned code.
    Future<void> openBackup(WidgetTester tester, FakeBridge bridge) async {
      await pushRestore(tester, bridge);
      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('frame'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
    }

    /// Whether the caret sits in the password field — the only one on
    /// this step, and what a phone raises its keyboard for.
    bool passwordHasFocus(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .hasFocus;

    testWidgets('a scanned backup lands on the page, and takes the caret', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await pushRestore(tester, bridge);
      expect(find.textContaining('Backup read from'), findsNothing);

      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('frame'));
      await tester.pumpAndSettle();

      // The scanner closing over the page used to be all the person saw:
      // the page now states what it holds and where the next step is.
      expect(find.byType(ScanScreen), findsNothing);
      expect(find.text('Backup read from the QR code'), findsOneWidget);
      expect(find.text('Type its password to open it.'), findsOneWidget);
      expect(passwordHasFocus(tester), isTrue);
    });

    testWidgets('a file lands the same way, under its own name', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await pushRestore(
        tester,
        bridge,
        // On this platform an XFile takes its name from its path.
        filePicker: () async =>
            XFile.fromData(base64Decode('R0ZCQUNLVVA='), path: 'phone.gerfaut'),
      );

      await tester.tap(find.text('Open a file'));
      await tester.pumpAndSettle();

      expect(find.text('Backup read from phone.gerfaut'), findsOneWidget);
      expect(find.text('Type its password to open it.'), findsOneWidget);
      expect(passwordHasFocus(tester), isTrue);
    });

    testWidgets('coming back from the file picker does not lock the app', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await pushRestore(
        tester,
        bridge,
        // On this platform an XFile takes its name from its path.
        filePicker: () async =>
            XFile.fromData(base64Decode('R0ZCQUNLVVA='), path: 'phone.gerfaut'),
      );
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(BackupRestoreScreen)),
      ).read(lockProvider.notifier);
      // A lock that is already open: loaded first without one, so
      // learning about it does not shut the screen on the spot.
      lock
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await tester.tap(find.text('Open a file'));
      await tester.pumpAndSettle();
      // Android pauses Gerfaut behind the picker and resumes it after.
      lock
        ..noteHidden()
        ..noteResumed();

      // Being sent to a screen of the system's by Gerfaut itself is not
      // leaving: the flow is still there to go on with.
      expect(lock.state.locked, isFalse);
      expect(find.text('Backup read from phone.gerfaut'), findsOneWidget);
    });

    testWidgets('a picker that never opened does not cover a later trip', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      await pushRestore(
        tester,
        bridge,
        // No app on the phone answers the intent: the picker throws
        // instead of showing, and Gerfaut never leaves the screen.
        filePicker: () async =>
            throw PlatformException(code: 'ActivityNotFoundException'),
      );
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(BackupRestoreScreen)),
      ).read(lockProvider.notifier);
      lock
        ..syncFromSettings(null)
        ..syncFromSettings(const AppLock(kind: LockKind.pin, biometric: false));

      await tester.tap(find.text('Open a file'));
      await tester.pumpAndSettle();
      expect(
        find.text('No app on this phone can open a file to restore.'),
        findsOneWidget,
      );
      expect(lock.state.locked, isFalse);

      // A real absence afterwards still locks: the announcement was
      // taken back rather than left to cover it.
      lock
        ..noteHidden()
        ..noteHidden()
        ..noteResumed();
      expect(lock.state.locked, isTrue);
    });

    testWidgets('what was read holds at 340dp and twice the text size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(340, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        screen(
          FakeBridge(),
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: BackupRestoreScreen(
                filePicker: () async => XFile.fromData(
                  base64Decode('R0ZCQUNLVVA='),
                  path: 'gerfaut-backup-2026-08-30.gerfaut',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open a file'));
      await tester.pumpAndSettle();

      // A file name is as long as its owner made it, and the panel has
      // to carry the longest one on the narrowest phone.
      expect(tester.takeException(), isNull);
      expect(
        find.text('Backup read from gerfaut-backup-2026-08-30.gerfaut'),
        findsOneWidget,
      );
    });

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

    testWidgets('a watched wallet cannot be tapped into the restore', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => preview(alreadyWatched: true);
      bridge.onImportBackup = (_, _, _) => ImportReport(
        added: [makeMeta(network: Network.signet)],
        skipped: 1,
        settingsApplied: false,
      );
      await openBackup(tester, bridge);

      // The whole row, not only its box: the line reads as tappable and
      // must answer the same way the box does.
      await tester.tap(find.text('Savings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Restore 1 wallet'), findsOneWidget);

      await tester.tap(find.text('Restore 1 wallet'));
      await tester.pumpAndSettle();

      // The core would skip it anyway; it is never even asked for.
      expect(bridge.importCalls.single.indexes, [0]);
    });

    testWidgets('a backup that holds nothing new leaves nothing to restore', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => BackupPreview(
        createdAt: 1755000000,
        hasSettings: false,
        wallets: [
          for (final wallet in preview(alreadyWatched: true).wallets)
            BackupWalletPreview(
              index: wallet.index,
              name: wallet.name,
              network: wallet.network,
              kind: wallet.kind,
              alreadyWatched: true,
            ),
        ],
      );
      await openBackup(tester, bridge);

      // Every wallet stays on the list, said to be watched already:
      // showing what will not be done reads better than a backup that
      // seems to have lost its wallets.
      expect(find.text('Cold storage'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
      expect(find.textContaining('Already watched'), findsNWidgets(2));
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((box) => box.value == false && box.onChanged == null),
        isTrue,
      );

      // And the action leads nowhere: there is nothing left to ask for.
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(bridge.importCalls, isEmpty);
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

    testWidgets('the node settings say what they would put in place', (
      tester,
    ) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => BackupPreview(
        createdAt: 1755000000,
        hasSettings: true,
        wallets: preview().wallets,
        backends: const [
          BackupBackend(network: Network.mainnet, backend: 'node.example.org'),
          BackupBackend(network: Network.signet, backend: 'signet.example.org'),
        ],
        electrumHosts: const ['node.example.org:50002'],
      );
      await openBackup(tester, bridge);

      expect(
        find.text(
          'Replaces your backend choice, accepted certificates and gap '
          "limit with the backup's.",
        ),
        findsOneWidget,
      );
      // What would take their place, named: the machine every address
      // is asked for, and the certificate this phone would then trust
      // without asking again.
      expect(find.text('NODES'), findsOneWidget);
      expect(find.text('Mainnet'), findsOneWidget);
      expect(find.text('node.example.org'), findsOneWidget);
      expect(find.text('Signet'), findsOneWidget);
      expect(find.text('signet.example.org'), findsOneWidget);
      expect(find.text('PINNED CERTIFICATES'), findsOneWidget);
      expect(find.text('node.example.org:50002'), findsOneWidget);
    });

    testWidgets('a backup that names no node lists nothing', (tester) async {
      useTallSurface(tester);
      final bridge = FakeBridge();
      bridge.onPreviewBackup = (_, _) => preview(settings: true);
      await openBackup(tester, bridge);

      // The toggle stands; there is simply nothing to list under it.
      expect(find.text('Apply node settings'), findsOneWidget);
      expect(find.text('NODES'), findsNothing);
      expect(find.text('PINNED CERTIFICATES'), findsNothing);
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
