// Hands a built CSV or a sealed backup to the system share sheet. Kept
// behind small interfaces so widget tests substitute fakes instead of
// touching the path_provider and share_plus plugins.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Offers a CSV to the system share sheet under `filename`.
abstract class CsvSharer {
  Future<void> shareCsv({required String csv, required String filename});

  /// Deletes the histories earlier shares left in the cache.
  Future<void> forgetCopies();
}

/// The real sharer: the text goes straight to the share sheet, as a
/// backup does, never written by Gerfaut to a file of its own. A history
/// left in the cache, amounts, txids and labels in the clear, would
/// outlive the wallet it came from and the vault that keeps it sealed.
///
/// The share sheet still needs a file, and share_plus writes one into a
/// folder of its own under the cache, which it never deletes. That copy
/// goes at the next share, and each time the app starts: not right
/// after the sheet closes, when the app it went to may still be reading
/// it.
class SystemCsvSharer implements CsvSharer {
  const SystemCsvSharer();

  @override
  Future<void> forgetCopies() async {
    try {
      await forgetCsvCopies();
    } catch (_) {
      // No cache to reach, as in a test: nothing to delete.
    }
  }

  @override
  Future<void> shareCsv({required String csv, required String filename}) async {
    await forgetCsvCopies();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
            name: filename,
          ),
        ],
        fileNameOverrides: [filename],
      ),
    );
  }
}

/// Deletes the histories left in the cache to share them: at its top,
/// where earlier builds wrote them, and in the folder share_plus makes
/// for each file it is handed, which goes too once empty. Answers how
/// many histories went.
Future<int> forgetCsvCopies([Directory? cache]) async {
  final dir = cache ?? await getTemporaryDirectory();
  var gone = 0;
  final emptied = <Directory>{};
  try {
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File && entry.path.endsWith('-transactions.csv')) {
        await entry.delete();
        gone++;
        if (entry.parent.path != dir.path) emptied.add(entry.parent);
      }
    }
    for (final folder in emptied) {
      if (await folder.list().isEmpty) await folder.delete();
    }
  } on FileSystemException {
    // A cache that cannot be listed holds nothing to delete here.
  }
  return gone;
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
