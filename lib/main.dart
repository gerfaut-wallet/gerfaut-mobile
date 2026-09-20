import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/background.dart';
import 'src/live.dart';
import 'src/vault_key.dart';

/// The entry point the Android Live service runs in an engine of its
/// own, without a view. Top level, here, and annotated: the service
/// looks it up by name in the root library, and the tree shaker would
/// drop it from a release build otherwise.
@pragma('vm:entry-point')
void liveMain() => unawaited(runLiveService());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The scheduler only has to know how to wake the app; whether it ever
  // does is the background-check preference, applied from the settings.
  unawaited(initBackgroundChecks());
  runApp(const ProviderScope(child: GerfautApp(bootstrap: bootstrapGerfaut)));
}
