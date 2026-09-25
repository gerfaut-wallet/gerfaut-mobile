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

  group('the open channel', () {
    void answer(Object? Function(MethodCall call) reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => reply(call));
    }

    test('asks for no more than the limit, of the types given', () async {
      MethodCall? asked;
      answer((call) {
        asked = call;
        return {
          'name': 'wallet.json',
          'size': 3,
          'bytes': Uint8List.fromList([1, 2, 3]),
        };
      });
      final file = await openBoundedFile(
        maxBytes: 64,
        mimeTypes: const ['text/plain'],
      );
      expect(asked!.method, 'openDocument');
      expect(asked!.arguments, {
        'mimeTypes': ['text/plain'],
        'maxBytes': 64,
      });
      expect(file!.name, 'wallet.json');
      expect(await file.length(), 3);
      expect(await file.readAsBytes(), [1, 2, 3]);
    });

    test('a file past the limit comes as its size alone', () async {
      answer((_) => {'name': 'holiday.mp4', 'size': 314572800, 'bytes': null});
      final file = await openBoundedFile(maxBytes: 64);
      expect(await file!.length(), 314572800);
      expect(await file.readAsBytes(), isEmpty);
    });

    test('a dismissed dialog picks nothing', () async {
      answer((_) => null);
      expect(await openBoundedFile(maxBytes: 64), isNull);
    });

    test('a file that could not be read says so', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'read_failed', message: 'EIO');
          });
      expect(openBoundedFile(maxBytes: 64), throwsA(isA<FileReadException>()));
    });

    test('no dialog to open is left to the caller', () async {
      refuseWith('unavailable', 'no app on this device can open a file');
      expect(openBoundedFile(maxBytes: 64), throwsA(isA<PlatformException>()));
    });
  });
}
