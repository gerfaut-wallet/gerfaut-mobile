// Keeps the phone awake while something on the screen has to be read
// by another device: an animated backup code, or the camera pointed at
// one. A screen that goes dark halfway through a loop interrupts the
// transfer, and with a lock set it takes the whole flow down with it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Holds the screen on and lets it go. Behind an interface so widget
/// tests substitute a fake instead of reaching the platform.
abstract class ScreenKeeper {
  /// Keeps the screen from dimming and sleeping until [release].
  Future<void> keepOn();

  /// Hands the screen back to the phone's own timeout.
  Future<void> release();
}

/// The real keeper: the window flag the platform offers for exactly
/// this, through the wakelock plugin. No permission is involved.
class SystemScreenKeeper implements ScreenKeeper {
  const SystemScreenKeeper();

  @override
  Future<void> keepOn() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // A platform without the plugin keeps its own timeout.
    }
  }

  @override
  Future<void> release() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Nothing was held.
    }
  }
}

/// The keeper in use. Widget tests override this with a fake.
final screenKeeperProvider = Provider<ScreenKeeper>(
  (ref) => const SystemScreenKeeper(),
);
