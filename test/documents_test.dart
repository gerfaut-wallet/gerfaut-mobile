import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('gerfaut/files');

  /// The activity answering every save with one refusal.
  void refuseWith(String code, String message) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: code, message: message);
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<DocumentSaveException> refusal() async {
    try {
      await const SystemDocumentSaver().save(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'a.gerfaut',
        mimeType: 'application/octet-stream',
      );
    } on DocumentSaveException catch (error) {
      return error;
    }
    fail('the save was not refused');
  }

  group('the save channel', () {
    test('a write that failed happened behind a dialog', () async {
      refuseWith('write_failed', 'the document could not be opened');
      final error = await refusal();
      expect(error.message, 'the document could not be opened');
      expect(error.dialogOpened, isTrue);
    });

    test('a save refused as busy leaves the first dialog its return', () async {
      // The dialog up is an earlier call's, and the lock was told about
      // that trip: taking the announcement back here would lock the app
      // when that dialog closes.
      refuseWith('busy', 'a save is already under way');
      final error = await refusal();
      expect(error.dialogOpened, isTrue);
    });

    test('a phone with nothing to save a file opened no dialog', () async {
      refuseWith('unavailable', 'no app on this device can save a file');
      final error = await refusal();
      expect(error.message, 'no app on this device can save a file');
      expect(error.dialogOpened, isFalse);
    });

    test('a refusal this build does not know opened no dialog', () async {
      refuseWith('something_new', 'refused');
      expect((await refusal()).dialogOpened, isFalse);
    });
  });
}
