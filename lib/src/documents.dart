// Writes a file where the user points: the system's save dialog on a
// new document, then the bytes into whatever place it names. This is
// what "Save file" promises; the share sheet, which can also end in a
// file, stays a separate action under its own name.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The save could not be carried out, in words fit for the screen.
class DocumentSaveException implements Exception {
  const DocumentSaveException(this.message, {this.dialogOpened = true});

  final String message;

  /// Whether a save dialog is up, or was: this call's, or the one an
  /// earlier call opened and that still owes its return.
  ///
  /// False when the save was refused before any could open: Gerfaut
  /// never left the screen, nothing is coming back, and the app lock
  /// has to be told so or it will spend the trip it was promised on
  /// the next real absence instead.
  final bool dialogOpened;

  @override
  String toString() => message;
}

/// Saves bytes under a name the user may change, wherever they choose.
/// Behind an interface so widget tests substitute a fake instead of
/// reaching the platform.
abstract class DocumentSaver {
  /// True once the file is written; false when the dialog was
  /// dismissed. Throws [DocumentSaveException] when the write failed.
  Future<bool> save({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  });
}

/// The real saver: a method channel the Android activity answers with
/// the system's create-document dialog.
class SystemDocumentSaver implements DocumentSaver {
  const SystemDocumentSaver();

  static const MethodChannel _channel = MethodChannel('gerfaut/files');

  @override
  Future<bool> save({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('createDocument', {
        'filename': filename,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      return saved ?? false;
    } on PlatformException catch (error) {
      // `write_failed` is the far side of the trip: the dialog named a
      // place and the bytes did not make it. `busy` is a dialog still
      // up, the one an earlier call opened: the lock was told about
      // that trip and is still owed its return, and reading the
      // refusal as no dialog would take the announcement back under
      // the dialog, then lock the app the moment it closes. Every
      // other refusal comes from before any launch — no app on the
      // phone that can save a file — and a code this build does not
      // know is counted with them, since being told to lock too often
      // costs a PIN and being told too rarely costs the lock.
      throw DocumentSaveException(
        error.message ?? 'The file could not be saved.',
        dialogOpened: error.code == 'write_failed' || error.code == 'busy',
      );
    } on MissingPluginException {
      throw const DocumentSaveException(
        'Saving a file is not available on this platform.',
        dialogOpened: false,
      );
    }
  }
}

/// The saver in use. Widget tests override this with a fake.
final documentSaverProvider = Provider<DocumentSaver>(
  (ref) => const SystemDocumentSaver(),
);
