import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/disguise.dart';
import '../src/identity.dart';
import '../src/lock.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'settings.dart';

/// The title of every identity check, and the reason the phone's own
/// prompt gives.
const String confirmItsYouTitle = "Confirm it's you";

/// What a phone with neither an app lock nor a screen lock is told.
const String appLockNeededMessage =
    'Changing who can use your Premium account needs an app lock on this '
    'device, so that nobody holding it unlocked can do it.';

/// Asks whoever holds the phone to prove they own it, before an action
/// that changes who can use the Premium account or what it watches.
/// True only on a yes.
///
/// With an app lock, its secret, judged by the core with the lock
/// screen's own count of failures, or the phone's biometrics when the
/// lock accepts them. Without one, the phone's screen lock. A phone
/// with neither gets the way to set an app lock, and a no: the action
/// waits until one exists.
Future<bool> confirmIdentity(BuildContext context, WidgetRef ref) async {
  final AppLock? lock;
  try {
    // The vault's answer, not the settings in hand: a lock turned off a
    // moment ago must not be asked for, nor one just set be skipped.
    lock = await ref.read(bridgeProvider).appLock();
  } on BridgeException {
    return false;
  }
  if (!context.mounted) return false;
  if (lock != null) {
    final yes = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConfirmItsYouSheet(lock: lock!),
    );
    return yes ?? false;
  }
  final outcome = await ref
      .read(screenLockGateProvider)
      .confirm(confirmItsYouTitle);
  switch (outcome) {
    case ScreenLockOutcome.confirmed:
      return true;
    case ScreenLockOutcome.refused:
      // The phone said why, if anything needed saying: a cancelled
      // prompt is a change of mind.
      return false;
    case ScreenLockOutcome.unavailable:
      if (context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const AppLockNeededSheet(),
        );
      }
      return false;
  }
}

/// The app lock's secret, asked again: the same field as the lock
/// screen, judged by the same core, the same failures counted and the
/// same wait imposed. The phone's biometrics stand in when the lock
/// accepts them, never while the app is disguised.
class ConfirmItsYouSheet extends ConsumerStatefulWidget {
  const ConfirmItsYouSheet({super.key, required this.lock});

  final AppLock lock;

  @override
  ConsumerState<ConfirmItsYouSheet> createState() => _ConfirmItsYouSheetState();
}

class _ConfirmItsYouSheetState extends ConsumerState<ConfirmItsYouSheet> {
  final _controller = TextEditingController();
  bool _hidden = true;
  bool _checking = false;
  String? _message;

  /// Seconds left before the core looks at a secret again.
  int _wait = 0;
  Timer? _countdown;

  bool get _pin => widget.lock.kind == LockKind.pin;

  @override
  void initState() {
    super.initState();
    // The finger is the shorter way: offered at once when the lock
    // takes it, the secret field waiting underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _offersBiometrics =>
      widget.lock.biometric &&
      !ref.watch(disguiseProvider).disguised &&
      (ref.watch(biometricsAvailableProvider).valueOrNull ?? false);

  Future<void> _tryBiometrics() async {
    if (!widget.lock.biometric || ref.read(disguiseProvider).disguised) return;
    final can = await ref.read(biometricsAvailableProvider.future);
    if (!can || !mounted) return;
    final passed = await ref
        .read(biometricGateProvider)
        .authenticate(confirmItsYouTitle);
    if (passed && mounted) Navigator.of(context).pop(true);
  }

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    setState(() => _wait = seconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _wait -= 1);
      if (_wait <= 0) {
        timer.cancel();
        setState(() => _message = null);
      }
    });
  }

  Future<void> _confirm() async {
    if (_checking || _wait > 0 || _controller.text.isEmpty) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final verdict = await ref
          .read(bridgeProvider)
          .verifyAppLock(_controller.text);
      if (!mounted) return;
      if (verdict.unlocked) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _controller.clear();
        _message = verdict.retryAfterSecs > 0
            ? null
            : 'Wrong ${_pin ? 'PIN' : 'password'}';
      });
      if (verdict.retryAfterSecs > 0) _startCountdown(verdict.retryAfterSecs);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final blocked = _wait > 0;
    final note = blocked
        ? 'Too many attempts. Try again in $_wait s'
        : _message;
    final label = _pin ? 'PIN' : 'Password';
    return Padding(
      padding: EdgeInsets.only(
        left: GerfautSpacing.md,
        right: GerfautSpacing.md,
        top: GerfautSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
      ),
      // Clear of the gesture bar, as every sheet's last button must be.
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(confirmItsYouTitle, style: tokens.h2),
              ),
              const SizedBox(height: GerfautSpacing.md),
              // The field names itself, as on the lock screen: one word in
              // the box, heard by a screen reader on the box itself.
              TextField(
                key: const Key('identity.secret'),
                controller: _controller,
                autofocus: true,
                obscureText: _hidden,
                enabled: !blocked,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: _pin ? TextInputType.number : TextInputType.text,
                inputFormatters: _pin
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ]
                    : null,
                style: tokens.body,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _message = null),
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  // The caption above is what the eye reads; the hint is
                  // what a screen reader hears on the field itself.
                  hintText: label,
                  hintStyle: tokens.body.copyWith(color: tokens.textMuted),
                  filled: true,
                  fillColor: tokens.surfaceSunken,
                  constraints: const BoxConstraints(minHeight: 44),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: GerfautSpacing.md,
                    vertical: GerfautSpacing.sm + GerfautSpacing.xs,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    borderSide: BorderSide(color: tokens.primary, width: 2),
                  ),
                  suffixIcon: _pin
                      ? null
                      : IconButton(
                          tooltip: _hidden ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(
                            _hidden ? LucideIcons.eye : LucideIcons.eyeOff,
                            size: 18,
                            color: tokens.textMuted,
                          ),
                        ),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: GerfautSpacing.sm),
                // A refused secret is a fact, not an alarm: muted, as on
                // the lock screen.
                Semantics(
                  liveRegion: true,
                  child: Text(
                    note,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ),
              ],
              const SizedBox(height: GerfautSpacing.md),
              if (_offersBiometrics) ...[
                GhostButton(
                  label: 'Use fingerprint or face',
                  icon: LucideIcons.fingerprint,
                  onPressed: _checking ? null : _tryBiometrics,
                ),
                const SizedBox(height: GerfautSpacing.sm),
              ],
              PrimaryButton(
                label: _checking ? 'Checking…' : 'Confirm',
                expand: true,
                onPressed: blocked || _checking ? null : _confirm,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              GhostButton(
                label: 'Cancel',
                onPressed: _checking
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone that can prove nothing: no app lock, no screen lock. The
/// action waits, and the way to an app lock is one tap away.
class AppLockNeededSheet extends StatelessWidget {
  const AppLockNeededSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(GerfautSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(confirmItsYouTitle, style: tokens.h2),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Text(appLockNeededMessage, style: tokens.body),
            const SizedBox(height: GerfautSpacing.md),
            PrimaryButton(
              label: 'Set an app lock',
              icon: LucideIcons.lock,
              expand: true,
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const SettingsScreen(section: SettingsSection.security),
                  ),
                );
              },
            ),
            const SizedBox(height: GerfautSpacing.sm),
            GhostButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
