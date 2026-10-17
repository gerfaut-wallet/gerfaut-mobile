// Hands a built CSV or a sealed backup to the system share sheet. Kept
// behind small interfaces so widget tests substitute fakes instead of
// touching the platform.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'documents.dart' show filesChannel;

/// Offers [bytes] to the share sheet as a file named [filename], and
/// answers once the app is back in front: the sheet itself is all the
/// feedback a share gets, and a screen that waits for this answer takes
/// no second tap meanwhile, which would open a second sheet over a
/// second copy. The file is written into a folder of its own under the
/// cache, so no two shares share an address, and only the app picked in
/// the sheet is granted a read of it, for as long as it holds it: no app
/// could reach it before the choice, nor a later file through an old
/// grant. It stays [sharedCopyLifetime], then [sharedCopies] deletes it
/// (SharedFiles.kt).
Future<void> _share(Uint8List bytes, String filename, String mimeType) async {
  await sharedCopies.sweep();
  // Listened to before the sheet is asked for: the app may leave the
  // front before the platform has even answered.
  final back = FrontReturn();
  final listener = AppLifecycleListener(onStateChange: back.lifecycle);
  try {
    await filesChannel.invokeMethod<void>('share', {
      'bytes': bytes,
      'filename': filename,
      'mimeType': mimeType,
    });
    await back.wait();
  } finally {
    listener.dispose();
    back.dispose();
    // The copy just written is too young to go: this sets the hour.
    unawaited(sharedCopies.sweepQuietly());
  }
}

/// The app's return to the front after a screen of the system's it
/// opened. Done at the first `resumed` after the app was seen out of
/// focus; and, should it never leave within [patience] of [wait], no
/// screen came up after all, and that is done too.
class FrontReturn {
  FrontReturn({this.patience = const Duration(seconds: 3)});

  final Duration patience;
  final Completer<void> _done = Completer<void>();
  bool _left = false;
  Timer? _patience;

  void lifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_left) _finish();
    } else {
      _left = true;
      _patience?.cancel();
    }
  }

  /// Done once the app is back, or right after [patience] if it never
  /// left.
  Future<void> wait() {
    if (!_left && !_done.isCompleted) {
      _patience = Timer(patience, () {
        if (!_left) _finish();
      });
    }
    return _done.future;
  }

  void dispose() => _patience?.cancel();

  void _finish() {
    _patience?.cancel();
    if (!_done.isCompleted) _done.complete();
  }
}

/// Offers a CSV to the system share sheet under `filename`.
abstract class CsvSharer {
  Future<void> shareCsv({required String csv, required String filename});

  /// Deletes what earlier shares left in the cache: the histories, and
  /// the backups shared from their own screen.
  Future<void> forgetCopies();
}

/// The real sharer. A history left in the cache, amounts, txids and
/// labels in the clear, would outlive the wallet it came from and the
/// vault that keeps it sealed: the share sheet needs a file, and that
/// copy goes once [sharedCopyLifetime] has passed, by [sharedCopies],
/// not right after the sheet closes, when the app it went to may still
/// be reading it.
class SystemCsvSharer implements CsvSharer {
  const SystemCsvSharer();

  @override
  Future<void> forgetCopies() => sharedCopies.sweepQuietly();

  @override
  Future<void> shareCsv({required String csv, required String filename}) =>
      _share(Uint8List.fromList(utf8.encode(csv)), filename, 'text/csv');
}

/// How long a shared copy stays before it may go. The app a file went
/// to reads it within minutes, an upload or a mail attachment included;
/// an hour leaves room for a slow network or a draft left open, and a
/// file younger than that may still be on its way.
const sharedCopyLifetime = Duration(hours: 1);

/// What one sweep did: how many copies went, and how long until the
/// youngest one it kept is old enough to go; null when it kept none.
typedef SharedSweep = ({int gone, Duration? next});

/// Deletes the histories and backups left in the cache to share them,
/// once older than `lifetime`. Only the places that hold them are read,
/// not the whole cache, which this runs over at every start: its top,
/// where earlier builds wrote histories, the folders right under it,
/// where share_plus kept what earlier builds shared through it, and the
/// folders under those, one for each share in Gerfaut's own `shared`. A
/// folder emptied here goes too.
///
/// Sweeps may overlap (the start, a share, the hour coming): a file or a
/// folder another one took is skipped, and the rest is still read, so
/// every younger copy is still counted in [SharedSweep.next].
Future<SharedSweep> sweepSharedCopies({
  Directory? cache,
  Duration lifetime = sharedCopyLifetime,
}) async {
  final dir = cache ?? await getTemporaryDirectory();
  final sweep = _Sweep(DateTime.now(), lifetime);
  await for (final entry in _entries(dir)) {
    if (entry is File) {
      await sweep.file(entry);
    } else if (entry is Directory) {
      await sweep.folder(entry);
    }
  }
  return (gone: sweep.gone, next: sweep.next);
}

/// The folder of the cache each share writes its file into, one folder
/// per share under it: the one res/xml/shared_paths.xml names.
const String sharedFolder = 'shared';

String _name(FileSystemEntity entity) =>
    entity.uri.pathSegments.where((part) => part.isNotEmpty).last;

/// What a folder holds, past any entry that cannot be read; nothing when
/// the folder itself cannot be, or is gone.
Stream<FileSystemEntity> _entries(Directory dir) => dir
    .list(followLinks: false)
    .handleError((_) {}, test: (error) => error is FileSystemException);

class _Sweep {
  _Sweep(this.now, this.lifetime);

  final DateTime now;
  final Duration lifetime;
  int gone = 0;
  Duration? next;

  /// The shared files in one folder, and for Gerfaut's own `shared` in
  /// the folders right under it, one per share, where every file is a
  /// share whatever its name; a folder goes once they have left it
  /// empty.
  Future<void> folder(
    Directory folder, {
    bool top = true,
    bool share = false,
  }) async {
    final before = gone;
    final shares = top && _name(folder) == sharedFolder;
    await for (final entry in _entries(folder)) {
      if (entry is File) {
        await file(entry, anyName: share);
      } else if (entry is Directory && shares) {
        await this.folder(entry, top: false, share: true);
      }
    }
    if (gone == before) return;
    try {
      if (await folder.list().isEmpty) await folder.delete();
    } on FileSystemException {
      // Gone already, or filled again meanwhile: left as it is.
    }
  }

  /// A history is named after its wallet, a backup carries the extension
  /// every Gerfaut backup has: nothing else in the cache ends that way.
  /// In a folder of Gerfaut's own shares, [anyName]: every file there is
  /// one, whatever it was called. Each goes once `lifetime` old; a
  /// younger one says when it will be.
  Future<void> file(File file, {bool anyName = false}) async {
    final path = file.path;
    final ours =
        anyName ||
        path.endsWith('-transactions.csv') ||
        path.endsWith('.gerfaut');
    if (!ours) return;
    try {
      final left = (await file.lastModified()).add(lifetime).difference(now);
      if (left > Duration.zero) {
        if (next == null || left < next!) next = left;
        return;
      }
      await file.delete();
      gone++;
    } on FileSystemException {
      // Taken by another sweep: nothing left to do.
    }
  }
}

/// Sweeps the shared copies, and again the moment the youngest one kept
/// comes of age, for as long as the app lives. A process that dies first
/// leaves it to the sweep of the next start.
class SharedCopySweeper {
  SharedCopySweeper({this.cache, this.lifetime = sharedCopyLifetime});

  /// The folder swept; null for the app's cache.
  final Directory? cache;
  final Duration lifetime;

  Timer? _timer;
  DateTime? _due;

  /// One sweep now, and the next one set for the youngest copy kept.
  /// Answers how many copies went.
  Future<int> sweep() async {
    final result = await sweepSharedCopies(cache: cache, lifetime: lifetime);
    final next = result.next;
    if (next != null) _wakeIn(next);
    return result.gone;
  }

  /// [sweep] where nothing may fail: at start, and once a share is done.
  Future<void> sweepQuietly() async {
    try {
      await sweep();
    } catch (_) {
      // No cache to reach, as in a test: nothing to delete.
    }
  }

  /// Stops the sweep set for later.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _due = null;
  }

  void _wakeIn(Duration delay) {
    final due = DateTime.now().add(delay);
    // A sweep already set sooner sees this copy too, and sets the next.
    if (_timer?.isActive == true && !_due!.isAfter(due)) return;
    _timer?.cancel();
    _due = due;
    _timer = Timer(delay, () {
      _timer = null;
      _due = null;
      unawaited(sweepQuietly());
    });
  }
}

/// The sweeper of the app's cache, shared by the real sharers and the
/// sweep at start, so one copy is never waited for twice.
final sharedCopies = SharedCopySweeper();

/// The sharer in use. Widget tests override this with a fake.
final csvSharerProvider = Provider<CsvSharer>((ref) => const SystemCsvSharer());

/// Offers a sealed backup to the system share sheet under `filename`.
abstract class BackupSharer {
  Future<void> shareBackup({
    required Uint8List bytes,
    required String filename,
  });
}

/// The real sharer. Sealed as it is, the backup's file has no business
/// outliving the share: it goes the way a history's copy goes, once
/// [sharedCopyLifetime] has passed, never while the app it went to may
/// still read it.
class SystemBackupSharer implements BackupSharer {
  const SystemBackupSharer();

  @override
  Future<void> shareBackup({
    required Uint8List bytes,
    required String filename,
  }) => _share(bytes, filename, 'application/octet-stream');
}

/// The backup sharer in use. Widget tests override this with a fake.
final backupSharerProvider = Provider<BackupSharer>(
  (ref) => const SystemBackupSharer(),
);
