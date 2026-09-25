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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'disguise.dart';
import 'models.dart';
import 'state.dart';
import 'window.dart';

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

/// How long a trip to a system screen Gerfaut opened itself may last
/// and still not count as leaving the app.
const Duration excursionAllowance = Duration(minutes: 10);

class LockController extends Notifier<LockState> {
  /// Gerfaut has been out of sight since the last time it came back.
  bool _away = false;

  /// When Gerfaut last sent the user to a system screen of its own;
  /// null when no such trip is under way.
  DateTime? _excursionAt;

  /// The clock the trips are timed with. Tests move it.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// What the window was last asked to be; null before the first ask.
  bool? _secure;

  @override
  LockState build() {
    // The disguise decides what a locked app shows, so the window
    // follows it as it follows the lock.
    ref.listen(disguiseProvider, (_, _) => _guardWindow());
    return const LockState();
  }

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
    _guardWindow();
  }

  /// Keeps the window in step with what is on screen.
  ///
  /// Secure while a lock exists and the app wears its own face: the
  /// task switcher photographs the app on its way out, before the lock
  /// screen draws, so the lock alone would leave a balance readable
  /// there. Disguised and locked, what shows is the calculator, and a
  /// blank card titled "Calculator" in the switcher would say the app
  /// has something to hide: that face is left plain. The wallet is
  /// still never photographed, since it only ever shows unlocked, and
  /// the flag is back before it draws. Without a lock nothing is
  /// hidden, and screenshots stay possible.
  void _guardWindow() {
    if (!state.loaded) return;
    final disguised = ref.read(disguiseProvider).disguised;
    final secure = state.lock != null && !(disguised && state.locked);
    if (secure == _secure) return;
    _secure = secure;
    unawaited(ref.read(windowGuardProvider).setSecure(secure));
  }

  /// Tries the secret. The verdict carries the delay the core imposes
  /// after repeated failures; the screen shows it counting down.
  Future<LockVerdict> unlock(String secret) async {
    final verdict = await ref.read(bridgeProvider).verifyAppLock(secret);
    if (verdict.unlocked) {
      state = state.copyWith(locked: false);
      _guardWindow();
    }
    return verdict;
  }

  /// Asks the phone instead of the secret. False leaves the screen up.
  ///
  /// Never while disguised: the phone's prompt names the app, and the
  /// calculator has nothing to say about a fingerprint.
  Future<bool> unlockWithBiometrics() async {
    if (!(state.lock?.biometric ?? false)) return false;
    if (ref.read(disguiseProvider).disguised) return false;
    final passed = await ref
        .read(biometricGateProvider)
        .authenticate('Unlock Gerfaut');
    if (passed) {
      state = state.copyWith(locked: false);
      _guardWindow();
    }
    return passed;
  }

  void lockNow() {
    if (state.lock == null) return;
    state = state.copyWith(locked: true);
    _guardWindow();
  }

  /// Gerfaut left the screen. A flag and not a clock, because the
  /// framework walks the whole chain back on the way in as well: the
  /// hidden state lands again a beat before the resume that reads it.
  void noteHidden() => _away = true;

  /// Gerfaut is about to open a system screen of its own — a file
  /// picker, a save dialog, a share sheet. Coming back from one is not
  /// coming back from the background, so the next return does not lock.
  ///
  /// Announced as late as it can be, against the call that opens the
  /// screen and nothing earlier, and taken back with [forgetExcursion]
  /// the moment it turns out no screen came up. A return spends it,
  /// picked or waved away alike; but a screen that never opens produces
  /// no return, and an announcement nobody takes back then waits to be
  /// spent by the next real absence, which is the one that had to lock.
  /// It waits no longer than [excursionAllowance], which is also as
  /// long as any trip may last.
  void expectExcursion() => _excursionAt = clock();

  /// The announced screen did not open: no app on the phone can show
  /// it, a save was already under way, the platform has none to give.
  /// Nothing went anywhere, so the next return counts again.
  ///
  /// Only for the branches where nothing came up. A trip that did
  /// happen can report its failure while the app is still away — the
  /// system hands the result back before Flutter says `resumed` — and
  /// forgetting the excursion there would put the lock in front of
  /// someone who never left.
  void forgetExcursion() => _excursionAt = null;

  /// Gerfaut is back: having been away is the whole rule, unless the
  /// trip was one Gerfaut sent the user on, and a short one. Picking a
  /// file takes a minute; a phone that came back an hour after its
  /// picker opened was put down on the way, and whoever holds it now
  /// meets the lock. So does one whose clock went back during the trip:
  /// setting the date back would otherwise make any trip look short.
  void noteResumed() {
    final away = _away;
    final at = _excursionAt;
    final elapsed = at == null ? null : clock().difference(at);
    final excursion =
        elapsed != null && !elapsed.isNegative && elapsed <= excursionAllowance;
    _away = false;
    _excursionAt = null;
    if (!away || excursion || state.locked) return;
    lockNow();
  }
}

final lockProvider = NotifierProvider<LockController, LockState>(
  LockController.new,
);
