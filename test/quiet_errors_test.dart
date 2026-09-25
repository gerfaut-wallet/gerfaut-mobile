import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/quiet_errors.dart';

void main() {
  test('a release build says nothing of an uncaught error', () {
    final flutter = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutter;
      PlatformDispatcher.instance.onError = platform;
    });
    final printed = <String?>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = print);

    quietErrorsInRelease(release: true);
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: Exception('sync failed for tb1q6rz28mcfaxtmd6v789l9rrl'),
      ),
    );
    expect(printed, isEmpty);
    expect(
      PlatformDispatcher.instance.onError!(Exception('x'), StackTrace.empty),
      isTrue,
    );
  });

  test('a debug build keeps the handlers it had', () {
    final flutter = FlutterError.onError;
    quietErrorsInRelease(release: false);
    expect(FlutterError.onError, same(flutter));
  });
}
