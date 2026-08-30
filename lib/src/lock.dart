// The app lock: what stands between an unlocked phone and the wallets.
//
// The vault is encrypted whatever happens; the lock is the curtain in
// front of it. The secret never leaves the core, which hashes it and
// slows repeated guesses down; this file holds only whether the screen
// is showing.
//
// There is no delay to sit out. The secret is asked when Gerfaut opens
// and again every time it comes back from the background. The one trip
// that does not count is the one Gerfaut sends the user on itself — a
// file picker, a save dialog, a share sheet.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';
import 'state.dart';

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
  /// Gerfaut has been out of sight since the last time it came back.
  bool _away = false;

  /// The next return comes from a system screen Gerfaut opened itself.
  bool _excursion = false;

  @override
  LockState build() => const LockState();

  /// Takes the lock from the settings the vault just handed over.
  ///
  /// The vault is the single source of truth; this notifier only knows
  /// whether the screen is up right now. Reading it separately would
  /// mean a failed read could open the app on a guess — and the
  /// settings are loaded before anything shows anyway.
  ///
  /// Only the first reading with a lock in it locks: a later one never
  /// does, so turning a lock on does not shut the user out of the
  /// screen they are standing on.
  void syncFromSettings(AppLock? lock) {
    final first = !state.loaded;
    state = LockState(
      lock: lock,
      loaded: true,
      locked: first ? lock != null : state.locked,
    );
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

  /// Gerfaut left the screen. A flag and not a clock, because the
  /// framework walks the whole chain back on the way in as well: the
  /// hidden state lands again a beat before the resume that reads it.
  void noteHidden() => _away = true;

  /// Gerfaut is about to open a system screen of its own — a file
  /// picker, a save dialog, a share sheet. Coming back from one is not
  /// coming back from the background, so the next return does not lock.
  ///
  /// The next return spends it whether the excursion happened or not:
  /// a picker waved away, or a permission the phone never asked about,
  /// must not leave the door open for a real absence later.
  void expectExcursion() => _excursion = true;

  /// Gerfaut is back: having been away is the whole rule, unless the
  /// trip was one Gerfaut sent the user on.
  void noteResumed() {
    final away = _away;
    final excursion = _excursion;
    _away = false;
    _excursion = false;
    if (!away || excursion || state.locked) return;
    lockNow();
  }
}

final lockProvider = NotifierProvider<LockController, LockState>(
  LockController.new,
);
