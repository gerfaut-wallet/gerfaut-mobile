// Hands a built CSV or a sealed backup to the system share sheet. Kept
// behind small interfaces so widget tests substitute fakes instead of
// touching the path_provider and share_plus plugins.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes a CSV somewhere temporary and offers it to the system share
/// sheet under `filename`.
abstract class CsvSharer {
  Future<void> shareCsv({required String csv, required String filename});
}

/// The real sharer: a file in the app's temporary directory, then the
/// platform share sheet. The file never leaves the device unless the
/// user picks a target that sends it.
class SystemCsvSharer implements CsvSharer {
  const SystemCsvSharer();

  @override
  Future<void> shareCsv({required String csv, required String filename}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]),
    );
  }
}

/// The sharer in use. Widget tests override this with a fake.
final csvSharerProvider = Provider<CsvSharer>((ref) => const SystemCsvSharer());

/// Offers a sealed backup to the system share sheet under `filename`.
abstract class BackupSharer {
  Future<void> shareBackup({
    required Uint8List bytes,
    required String filename,
  });
}

/// The real sharer: the bytes go straight to the share sheet, which
/// writes them to a temporary file of its own. The name override is
/// what names that file: an in-memory [XFile] drops its name on Android.
class SystemBackupSharer implements BackupSharer {
  const SystemBackupSharer();

  @override
  Future<void> shareBackup({
    required Uint8List bytes,
    required String filename,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/octet-stream',
            name: filename,
          ),
        ],
        fileNameOverrides: [filename],
      ),
    );
  }
}

/// The backup sharer in use. Widget tests override this with a fake.
final backupSharerProvider = Provider<BackupSharer>(
  (ref) => const SystemBackupSharer(),
);
