// The app lock: what stands between an unlocked phone and the wallets.
//
// The vault is encrypted whatever happens; the lock is the curtain in
// front of it. The secret never leaves the core, which hashes it and
// slows repeated guesses down; this file holds only whether the screen
// is showing and when it should show again.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';
import 'state.dart';

/// Whether coming back after `away` should ask for the secret again.
///
/// `null` never locks on return — the lock is then a launch-time
/// question only. Zero locks the moment Gerfaut leaves the screen.
bool shouldLock({required Duration away, required int? autoLockSecs}) {
  if (autoLockSecs == null) return false;
  if (autoLockSecs == 0) return true;
  return away.inSeconds >= autoLockSecs;
}

/// The phone's own prompt, behind an interface so no test ever reaches
/// the platform. The core never sees a biometric: the system answers,
/// and only a yes skips the secret.
abstract class BiometricGate {
  /// Whether this device can put the question at all.
  Future<bool> canCheck();

  /// Runs the prompt; false covers a refusal and a cancellation alike.
  Future<bool> authenticate(String reason);
}

class SystemBiometricGate implements BiometricGate {
  SystemBiometricGate([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canCheck() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      // A device that cannot answer is a device without biometrics.
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        // The prompt survives the app going to the background, which
        // some launchers do while the sensor reads.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricGateProvider = Provider<BiometricGate>(
  (ref) => SystemBiometricGate(),
);

/// Whether the phone can put the biometric question at all.
///
/// Asked apart from the lock itself on purpose: a platform that takes
/// its time must never hold the lock screen back. Until it answers,
/// the offer is simply not made.
final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(biometricGateProvider).canCheck();
  } catch (_) {
    return false;
  }
});

/// Where the lock stands.
@immutable
class LockState {
  const LockState({this.lock, this.locked = false, this.loaded = false});

  /// The lock the vault holds, without its hash; null when none is set.
  final AppLock? lock;

  /// The lock screen is showing and nothing else is reachable.
  final bool locked;

  /// The vault has been asked; before that the app shows its startup
  /// screen rather than guessing.
  final bool loaded;

  LockState copyWith({
    AppLock? lock,
    bool clearLock = false,
    bool? locked,
    bool? loaded,
  }) {
    return LockState(
      lock: clearLock ? null : (lock ?? this.lock),
      locked: locked ?? this.locked,
      loaded: loaded ?? this.loaded,
    );
  }
}

class LockController extends Notifier<LockState> {
  /// When Gerfaut left the screen, so returning knows how long it was
  /// away. Null while it is in front.
  DateTime? _leftAt;

  @override
  LockState build() => const LockState();

  /// Reads the lock the vault holds. A lock present means the app
  /// starts locked: the first thing it asks is the secret.
  Future<void> load() async {
    try {
      final lock = await ref.read(bridgeProvider).appLock();
      state = LockState(lock: lock, locked: lock != null, loaded: true);
    } catch (_) {
      // A vault that cannot say has no lock to show: the startup error
      // screen is the one that speaks, not a lock nobody can pass.
      state = const LockState(loaded: true);
    }
  }

  /// Reloads after the settings changed the lock, keeping the screen as
  /// it is: turning a lock on does not lock the user out at once.
  Future<void> refresh() async {
    try {
      final lock = await ref.read(bridgeProvider).appLock();
      state = state.copyWith(lock: lock, clearLock: lock == null, loaded: true);
    } catch (_) {
      // Keep what is on screen: a failed read is not an unlock.
    }
  }

  /// Tries the secret. The verdict carries the delay the core imposes
  /// after repeated failures; the screen shows it counting down.
  Future<LockVerdict> unlock(String secret) async {
    final verdict = await ref.read(bridgeProvider).verifyAppLock(secret);
    if (verdict.unlocked) state = state.copyWith(locked: false);
    return verdict;
  }

  /// Asks the phone instead of the secret. False leaves the screen up.
  Future<bool> unlockWithBiometrics() async {
    if (!(state.lock?.biometric ?? false)) return false;
    final passed = await ref
        .read(biometricGateProvider)
        .authenticate('Unlock Gerfaut');
    if (passed) state = state.copyWith(locked: false);
    return passed;
  }

  void lockNow() {
    if (state.lock != null) state = state.copyWith(locked: true);
  }

  /// Gerfaut left the screen: the clock starts.
  void noteHidden() => _leftAt = DateTime.now();

  /// Gerfaut is back: lock again if it was away long enough.
  void noteResumed() {
    final left = _leftAt;
    _leftAt = null;
    final lock = state.lock;
    if (lock == null || left == null || state.locked) return;
    if (shouldLock(
      away: DateTime.now().difference(left),
      autoLockSecs: lock.autoLockSecs,
    )) {
      state = state.copyWith(locked: true);
    }
  }
}

final lockProvider = NotifierProvider<LockController, LockState>(
  LockController.new,
);
