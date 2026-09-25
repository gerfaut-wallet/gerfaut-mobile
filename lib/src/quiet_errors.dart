// What an uncaught error says in a release build: nothing.
//
// Flutter prints an uncaught error to the system log in every build, the
// release one included, and the message is whatever the error says. A
// failure from the core can quote an address, a descriptor or a server;
// the system log is read by `adb logcat` on any phone with debugging on,
// and by bug-report tools. Gerfaut has no crash reporting to feed, so in
// a release build the message goes nowhere. A debug build keeps it: that
// is where it is read.

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Silences uncaught errors when [release] is true. Called first in
/// each entry point: the app, the Live service and the periodic task
/// each run in an isolate of their own, with handlers of their own.
void quietErrorsInRelease({bool release = kReleaseMode}) {
  if (!release) return;
  FlutterError.onError = (_) {};
  PlatformDispatcher.instance.onError = (_, _) => true;
}
