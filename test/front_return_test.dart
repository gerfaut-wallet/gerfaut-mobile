import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/share.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('the share is over when the app is back from the sheet', () async {
    final back = FrontReturn(patience: const Duration(hours: 1));
    var done = false;
    unawaited(back.wait().then((_) => done = true));
    // The sheet comes up: the app loses the focus, then goes behind it.
    back.lifecycle(AppLifecycleState.inactive);
    back.lifecycle(AppLifecycleState.hidden);
    await _settle();
    expect(done, isFalse);
    back.lifecycle(AppLifecycleState.inactive);
    back.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(done, isTrue);
    back.dispose();
  });

  test('a resume before the app left is not the return', () async {
    final back = FrontReturn(patience: const Duration(hours: 1));
    var done = false;
    back.lifecycle(AppLifecycleState.resumed);
    unawaited(back.wait().then((_) => done = true));
    await _settle();
    expect(done, isFalse);
    back.lifecycle(AppLifecycleState.inactive);
    back.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(done, isTrue);
    back.dispose();
  });

  test('the app leaving before the answer is not missed', () async {
    // The platform answers after the sheet already took the focus.
    final back = FrontReturn(patience: const Duration(milliseconds: 1));
    back.lifecycle(AppLifecycleState.inactive);
    var done = false;
    unawaited(back.wait().then((_) => done = true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Left already: the patience never ran, and the return is awaited.
    expect(done, isFalse);
    back.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(done, isTrue);
    back.dispose();
  });

  test('a sheet that never came up frees the wait', () async {
    final back = FrontReturn(patience: const Duration(milliseconds: 1));
    await back.wait();
    back.dispose();
  });
}
