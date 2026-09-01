// Writes a file where the user points: the system's save dialog on a
// new document, then the bytes into whatever place it names. This is
// what "Save file" promises; the share sheet, which can also end in a
// file, stays a separate action under its own name.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The save could not be carried out, in words fit for the screen.
class DocumentSaveException implements Exception {
  const DocumentSaveException(this.message);

  final String message;

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
      throw DocumentSaveException(
        error.message ?? 'The file could not be saved.',
      );
    } on MissingPluginException {
      throw const DocumentSaveException(
        'Saving a file is not available on this platform.',
      );
    }
  }
}

/// The saver in use. Widget tests override this with a fake.
final documentSaverProvider = Provider<DocumentSaver>(
  (ref) => const SystemDocumentSaver(),
);
