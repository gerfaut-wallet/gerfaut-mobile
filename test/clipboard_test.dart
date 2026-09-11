import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/clipboard.dart';

const _channel = MethodChannel('gerfaut/window');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> sensitive;
  late List<MethodCall> plain;

  /// Answers the activity's channel with [handler], and always records
  /// what the plain clipboard was asked for.
  void install(Future<Object?>? Function(MethodCall call)? handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      sensitive.add(call);
      return handler == null ? null : await handler(call);
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plain.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  setUp(() {
    sensitive = [];
    plain = [];
  });

  test('a secret goes to the activity, not to the plain clipboard', () async {
    install(null);
    await const SystemSensitiveClipboard().copy('wsh(or_d(pk(A),older(52560)))');

    expect(sensitive.single.method, 'copySensitive');
    expect(sensitive.single.arguments, 'wsh(or_d(pk(A),older(52560)))');
    // The point of the flag: the clip the system previews and keeps in
    // its history is never the one that carries this.
    expect(plain, isEmpty);
  });

  test('a platform without the channel still copies', () async {
    // A widget test, or a platform that has no activity to ask. The
    // flag asks the system to hide a clip from its preview; it never
    // decided who may read the clipboard. So the copy still happens,
    // exactly as it did before the flag existed.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plain.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await const SystemSensitiveClipboard().copy('topic-abcdefghijklmnopqrst');
    expect(sensitive, isEmpty);
    expect(
      (plain.single.arguments as Map)['text'],
      'topic-abcdefghijklmnopqrst',
    );
  });

  test('an activity that refuses still copies', () async {
    install((_) async => throw PlatformException(code: 'failed'));
    await const SystemSensitiveClipboard().copy('gerf-aut1-2345-6789');

    expect(sensitive.single.method, 'copySensitive');
    expect((plain.single.arguments as Map)['text'], 'gerf-aut1-2345-6789');
  });
}
