// Who is holding the phone, asked again before an action that changes
// who can use the Premium account or what it watches.
//
// An unlocked phone in the wrong hands is the case this answers: the
// app lock keeps a stranger out of the wallets, and the same secret, or
// the phone's own screen lock where the app has none, keeps them from
// approving their own device, changing the key, or taking the watch
// down. The secret is judged by the core, which counts the failures the
// way the lock screen does; the phone's prompt is the system's, and
// only its yes counts.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// What the phone's own prompt answered.
enum ScreenLockOutcome {
  /// The owner passed it: a fingerprint, a face, the phone's PIN.
  confirmed,

  /// Cancelled, refused, or locked out for now: nothing happens.
  refused,

  /// The phone has no screen lock to ask with.
  unavailable,
}

/// The phone's screen lock, behind an interface so no test reaches the
/// platform: biometrics, or the PIN, pattern or password the phone
/// unlocks with.
abstract class ScreenLockGate {
  Future<ScreenLockOutcome> confirm(String reason);
}

class SystemScreenLockGate implements ScreenLockGate {
  SystemScreenLockGate([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<ScreenLockOutcome> confirm(String reason) async {
    try {
      // A phone with no lock at all says so before any prompt: there
      // is nothing to ask the owner with.
      if (!await _auth.isDeviceSupported()) {
        return ScreenLockOutcome.unavailable;
      }
      final passed = await _auth.authenticate(
        localizedReason: reason,
        // The phone's code stands in for a finger: what counts is that
        // the owner of the phone is the one holding it.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return passed ? ScreenLockOutcome.confirmed : ScreenLockOutcome.refused;
    } on LocalAuthException catch (error) {
      return error.code == LocalAuthExceptionCode.noCredentialsSet
          ? ScreenLockOutcome.unavailable
          : ScreenLockOutcome.refused;
    } catch (_) {
      // A prompt that could not be put is not a yes.
      return ScreenLockOutcome.refused;
    }
  }
}

final screenLockGateProvider = Provider<ScreenLockGate>(
  (ref) => SystemScreenLockGate(),
);
