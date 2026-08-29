import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/background.dart';
import 'src/vault_key.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The scheduler only has to know how to wake the app; whether it ever
  // does is the background-check preference, applied from the settings.
  unawaited(initBackgroundChecks());
  runApp(const ProviderScope(child: GerfautApp(bootstrap: bootstrapGerfaut)));
}
