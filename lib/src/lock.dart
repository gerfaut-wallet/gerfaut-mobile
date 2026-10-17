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

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'disguise.dart';
import 'models.dart';
import 'state.dart';
import 'window.dart';

/// What the phone offers to stand in for the secret.
enum BiometricSupport {
  /// A strong biometric (Android's class 3) is set up: it may unlock.
  strong,

  /// Only a weak one is (class 2, most face unlocks that read a plain
  /// camera): it can be fooled, and the secret stays the way in.
  weakOnly,

  /// None is set up, or the phone has no sensor.
  none,

  /// A strong one may be there but cannot answer right now: the sensor
  /// busy or held, an update due. A passing state: it turns nothing off
  /// and greys nothing out.
  unavailable;

  /// No strong biometric can be had on this phone, for good: biometrics
  /// standing on in the vault have nothing left to open it.
  bool get lacksStrong => this == weakOnly || this == none;
}

/// How a biometric prompt ended.
enum BiometricOutcome {
  passed,

  /// Cancelled, or not answered.
  refused,

  /// The key no longer opens: a fingerprint or a face was added or
  /// removed on the phone since biometrics were turned on. The secret is
  /// asked, and biometrics have to be turned on again.
  reset,

  /// There never was a key: biometrics were turned on by a build from
  /// before keys. Nothing is asked of the phone; the secret is, and
  /// biometrics have to be turned on again.
  missing,
}

/// Why biometrics stand on in the vault and can no longer open it.
enum BiometricLapse {
  /// The phone's biometrics changed since the key was made.
  changed,

  /// No key was ever made for this vault.
  missing,
}

/// The phone's own prompt, behind an interface so no test ever reaches
/// the platform. The core never sees a biometric: the system answers,
/// and only a yes skips the secret.
///
/// On Android only a strong biometric answers, through a key of the
/// Keystore that it alone unlocks: see StrongBiometrics.kt.
abstract class BiometricGate {
  /// What this phone can offer.
  Future<BiometricSupport> support();

  /// Makes the key the prompt unlocks and puts the prompt on it, for
  /// turning biometrics on. True once the phone confirmed; otherwise no
  /// key is kept.
  Future<bool> enroll(String reason);

  /// Puts the prompt on the key made by [enroll].
  Future<BiometricOutcome> authenticate(String reason);

  /// Whether the key made by [enroll] is there, without any prompt.
  Future<bool> hasKey();

  /// Drops the key: biometrics are off.
  Future<void> forget();
}

class SystemBiometricGate implements BiometricGate {
  const SystemBiometricGate([this._channel = _biometricsChannel]);

  final MethodChannel _channel;

  /// What the prompt offers instead of a biometric: going back to the
  /// secret field.
  static const String _cancel = 'Cancel';

  @override
  Future<BiometricSupport> support() async {
    try {
      return switch (await _channel.invokeMethod<String>('support')) {
        'strong' => BiometricSupport.strong,
        'weak' => BiometricSupport.weakOnly,
        'none' => BiometricSupport.none,
        _ => BiometricSupport.unavailable,
      };
    } catch (_) {
      // A phone that cannot answer now may answer later.
      return BiometricSupport.unavailable;
    }
  }

  /// One prompt, and how it ended, as StrongBiometrics.kt says it.
  Future<PromptEnd> _prompt(String reason) async {
    try {
      final answer = await _channel.invokeMethod<String>('prompt', {
        'title': reason,
        'cancel': _cancel,
      });
      return PromptEnd.parse(answer);
    } catch (_) {
      return PromptEnd.refused;
    }
  }

  @override
  Future<bool> enroll(String reason) async {
    try {
      if (await _channel.invokeMethod<bool>('prepareKey') != true) {
        return false;
      }
    } catch (_) {
      return false;
    }
    // One prompt, never brought back: leaving the app locks it, and the
    // switch that asked is no longer on screen.
    final passed = await _prompt(reason) == PromptEnd.passed;
    if (!passed) await forget();
    return passed;
  }

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    final binding = WidgetsBinding.instance;
    final session = PromptSession(
      () => _prompt(reason),
      focused: binding.lifecycleState == AppLifecycleState.resumed,
    );
    final listener = AppLifecycleListener(onStateChange: session.lifecycle);
    try {
      return await session.run();
    } finally {
      listener.dispose();
    }
  }

  @override
  Future<bool> hasKey() async {
    try {
      return await _channel.invokeMethod<bool>('hasKey') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> forget() async {
    try {
      await _channel.invokeMethod<void>('forget');
    } catch (_) {
      // Nothing to drop where there is no platform.
    }
  }
}

/// How one prompt of the phone ended, before anyone decides what that
/// means.
enum PromptEnd {
  passed,
  missing,
  reset,

  /// Turned down on purpose ("Cancel"), or kept from opening.
  refused,

  /// Closed by a cancel that may be the user's (back, a touch outside
  /// it) or the system's as the app goes (the home gesture, which
  /// Android 16 reports as the user's): what the app does next tells.
  cancelled,

  /// Not put up at all: the app was on its way out of sight.
  unshown;

  /// What StrongBiometrics.kt answers, read. Error codes are androidx's
  /// BiometricPrompt ones: 13 is the prompt's own "Cancel" button, 10 a
  /// cancel by the user, 5 one by the system.
  static PromptEnd parse(String? answer) => switch (answer) {
    'passed' => passed,
    'missing' => missing,
    'reset' => reset,
    'unshown' => unshown,
    'error:10' || 'error:5' => cancelled,
    _ => refused,
  };
}

/// One unlock by the phone's prompt, from the ask to its single answer.
///
/// A cancel alone does not say whose it is. The app's lifecycle does,
/// with no timer: an app that goes out of sight (hidden, paused) was
/// taken away, and the prompt comes back when it is in front again; an
/// app that is back in focus with nothing having left (resumed) saw its
/// user wave the prompt off, and that is a refusal, for good. Every
/// other end answers at once.
class PromptSession {
  PromptSession(this._attempt, {this.focused = true});

  /// Puts one prompt up and says how it ended.
  final Future<PromptEnd> Function() _attempt;

  final Completer<BiometricOutcome> _answer = Completer<BiometricOutcome>();
  _Phase _phase = _Phase.idle;

  /// The app has the focus: nothing of the system's is over it. Given
  /// as it stands when the unlock is asked for.
  @visibleForTesting
  bool focused;

  /// The app went out of sight since the prompt was last put up.
  bool _left = false;

  /// How many prompts were put up: the first, and one per return.
  @visibleForTesting
  int attempts = 0;

  /// The single answer, once one is due.
  Future<BiometricOutcome> run() {
    if (_phase == _Phase.idle) _show();
    return _answer.future;
  }

  void _show() {
    _phase = _Phase.showing;
    _left = false;
    attempts++;
    _attempt().then(
      _ended,
      onError: (Object _) => _finish(BiometricOutcome.refused),
    );
  }

  void _ended(PromptEnd end) {
    if (_phase != _Phase.showing) return;
    switch (end) {
      case PromptEnd.passed:
        _finish(BiometricOutcome.passed);
      case PromptEnd.missing:
        _finish(BiometricOutcome.missing);
      case PromptEnd.reset:
        _finish(BiometricOutcome.reset);
      case PromptEnd.refused:
        _finish(BiometricOutcome.refused);
      case PromptEnd.unshown:
        if (_left) {
          _phase = _Phase.away;
        } else {
          _finish(BiometricOutcome.refused);
        }
      case PromptEnd.cancelled:
        if (_left) {
          _phase = _Phase.away;
        } else if (focused) {
          // Back in focus already, nothing having left: the user's.
          _finish(BiometricOutcome.refused);
        } else {
          _phase = _Phase.cancelled;
        }
    }
  }

  /// What the app goes through while the prompt is asked for.
  void lifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        focused = true;
        switch (_phase) {
          case _Phase.away:
            _show();
          case _Phase.cancelled:
            _finish(BiometricOutcome.refused);
          case _Phase.idle || _Phase.showing || _Phase.done:
            break;
        }
      case AppLifecycleState.inactive:
        focused = false;
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        focused = false;
        _left = true;
        if (_phase == _Phase.cancelled) _phase = _Phase.away;
      case AppLifecycleState.detached:
        _finish(BiometricOutcome.refused);
    }
  }

  void _finish(BiometricOutcome outcome) {
    if (_phase == _Phase.done) return;
    _phase = _Phase.done;
    _answer.complete(outcome);
  }
}

enum _Phase {
  /// Not asked yet.
  idle,

  /// A prompt is up, or on its way.
  showing,

  /// The prompt was cancelled, and whose cancel it was is not known yet.
  cancelled,

  /// The app was taken away with the prompt: it comes back with the app.
  away,

  /// Answered.
  done,
}

const MethodChannel _biometricsChannel = MethodChannel('gerfaut/biometrics');

final biometricGateProvider = Provider<BiometricGate>(
  (ref) => const SystemBiometricGate(),
);

/// What the phone can offer for the lock.
///
/// Asked apart from the lock itself on purpose: a platform that takes
/// its time must never hold the lock screen back. Until it answers,
/// the offer is simply not made.
final biometricSupportProvider = FutureProvider<BiometricSupport>((ref) async {
  try {
    return await ref.watch(biometricGateProvider).support();
  } catch (_) {
    return BiometricSupport.none;
  }
});

/// Where the lock stands.
@immutable
class LockState {
  const LockState({
    this.lock,
    this.locked = false,
    this.loaded = false,
    this.biometricLapse,
  });

  /// The lock the vault holds, without its hash; null when none is set.
  final AppLock? lock;

  /// The lock screen is showing and nothing else is reachable.
  final bool locked;

  /// The vault has been asked; before that the app shows its startup
  /// screen rather than guessing.
  final bool loaded;

  /// The last prompt found no key to unlock, and why; null while there
  /// is nothing to say. The lock screen says what to do, and the next
  /// unlock with the secret turns biometrics off, for the user to turn
  /// on again.
  final BiometricLapse? biometricLapse;

  LockState copyWith({
    AppLock? lock,
    bool? locked,
    bool? loaded,
    BiometricLapse? biometricLapse,
    bool clearLapse = false,
  }) {
    return LockState(
      lock: lock ?? this.lock,
      locked: locked ?? this.locked,
      loaded: loaded ?? this.loaded,
      biometricLapse: clearLapse ? null : biometricLapse ?? this.biometricLapse,
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
      biometricLapse: (lock?.biometric ?? false) ? state.biometricLapse : null,
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
      if (await _biometricsLapsed()) await _retireBiometrics(secret);
    }
    return verdict;
  }

  /// Whether biometrics stand on in the vault and can no longer open
  /// it: the key changed, or was never made (a vault from before keys),
  /// or the phone has no strong biometric any more, for good. A sensor
  /// that cannot answer for now is no reason to turn anything off.
  Future<bool> _biometricsLapsed() async {
    if (!(state.lock?.biometric ?? false)) return false;
    if (state.biometricLapse != null) return true;
    final gate = ref.read(biometricGateProvider);
    try {
      final support = await gate.support();
      if (support.lacksStrong) return true;
      return support == BiometricSupport.strong && !await gate.hasKey();
    } catch (_) {
      return false;
    }
  }

  /// Biometrics can no longer open the vault: it stops offering them,
  /// with the secret just given, any key left goes, and the settings say
  /// they are off. Turning them on again makes a new key, behind the
  /// secret and a prompt, as the first time.
  Future<void> _retireBiometrics(String secret) async {
    try {
      await ref.read(bridgeProvider).setBiometricUnlock(false, secret);
      await ref.read(biometricGateProvider).forget();
      state = state.copyWith(clearLapse: true);
      ref.invalidate(settingsProvider);
    } catch (_) {
      // Asked again at the next unlock; the prompt finds no key
      // meanwhile, so nothing opens by it.
    }
  }

  /// Asks the phone instead of the secret. False leaves the screen up.
  ///
  /// Never while disguised: the phone's prompt names the app, and the
  /// calculator has nothing to say about a fingerprint.
  Future<bool> unlockWithBiometrics() async {
    if (!(state.lock?.biometric ?? false)) return false;
    if (ref.read(disguiseProvider).disguised) return false;
    final outcome = await ref
        .read(biometricGateProvider)
        .authenticate('Unlock Gerfaut');
    switch (outcome) {
      case BiometricOutcome.passed:
        state = state.copyWith(locked: false);
        _guardWindow();
        return true;
      case BiometricOutcome.reset:
        state = state.copyWith(biometricLapse: BiometricLapse.changed);
        return false;
      case BiometricOutcome.missing:
        state = state.copyWith(biometricLapse: BiometricLapse.missing);
        return false;
      case BiometricOutcome.refused:
        return false;
    }
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

  /// Opens a system screen of Gerfaut's own with [open] — a picker, a
  /// save dialog, a share sheet, a page of the system settings — as an
  /// excursion: announced against the call, and taken back the moment
  /// it is clear no screen came up. That is every failure of [open]
  /// unless [cameUp] says the screen had opened before it failed (a
  /// file picked then not read, a save refused once its dialog was up),
  /// and a result [shown] says brought nothing up (a settings page that
  /// would not open). What [open] answers or throws is handed back.
  ///
  /// The one place the rule lives: a screen that announced a trip and
  /// forgot to take it back would leave the next real absence unlocked.
  Future<T> excursion<T>(
    Future<T> Function() open, {
    bool Function(Object error)? cameUp,
    bool Function(T result)? shown,
  }) async {
    expectExcursion();
    final T result;
    try {
      result = await open();
    } catch (error) {
      if (!(cameUp?.call(error) ?? false)) forgetExcursion();
      rethrow;
    }
    if (!(shown?.call(result) ?? true)) forgetExcursion();
    return result;
  }

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
