// What the platform lets others see of Gerfaut's window: screenshots,
// screen recordings, the task switcher's thumbnail.
//
// The lock screen replaces the app rather than covering it, and that
// is still not enough on its own: Android takes the thumbnail for the
// task switcher as the app leaves the screen, before the lock has
// drawn, and that picture is readable without unlocking anything.
// Marking the window secure blanks it there, along with screenshots
// and recordings.
//
// It is done only while a lock exists, and not while the disguise has
// the calculator on screen: a blank "Calculator" card in the switcher
// would give the game away, and a calculator has nothing to hide.
// Without a lock, the wallets are open to anyone holding the phone
// anyway, and the user keeps the right to capture their own screen: to
// show it to someone, or for the emulator tests, which read the screen
// the same way.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Marks the window secure or plain. Behind an interface so no test
/// ever reaches the platform.
abstract class WindowGuard {
  Future<void> setSecure(bool secure);
}

/// The real guard: a method channel the Android activity answers.
class SystemWindowGuard implements WindowGuard {
  const SystemWindowGuard();

  static const MethodChannel _channel = MethodChannel('gerfaut/window');

  @override
  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } on PlatformException {
      // A window that cannot be marked stays as it is; the lock still
      // stands in front of the wallets.
    } on MissingPluginException {
      // A platform without the channel, such as a widget test.
    }
  }
}

/// The guard in use. Widget tests override this with a fake.
final windowGuardProvider = Provider<WindowGuard>(
  (ref) => const SystemWindowGuard(),
);
