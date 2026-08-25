// Hands a built CSV to the system share sheet. Kept behind a small
// interface so widget tests substitute a fake instead of touching the
// path_provider and share_plus plugins.

import 'dart:io';

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
