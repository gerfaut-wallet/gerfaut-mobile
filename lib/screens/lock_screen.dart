import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/lock.dart';
import '../src/models.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/buttons.dart';
import '../widgets/pinned_action_form.dart';

/// The screen that stands in front of everything while the app is
/// locked. Nothing of the wallet is behind it: it replaces the app,
/// it does not cover it.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _controller = TextEditingController();
  bool _hidden = true;
  bool _checking = false;
  String? _message;

  /// Seconds left before the core will even look at a secret again.
  int _wait = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    // A phone that unlocks by face should not make the user reach for
    // the keyboard first: the prompt comes up on its own.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The offer is made once the phone has said it can answer; until
  /// then the secret is the way in, which it always is.
  bool get _offersBiometrics =>
      (ref.watch(lockProvider).lock?.biometric ?? false) &&
      (ref.watch(biometricsAvailableProvider).valueOrNull ?? false);

  Future<void> _tryBiometrics() async {
    if (!(ref.read(lockProvider).lock?.biometric ?? false)) return;
    // Awaited, not read: the sensor answers a moment after the screen
    // is up, and the prompt is worth waiting for.
    final can = await ref.read(biometricsAvailableProvider.future);
    if (!can || !mounted) return;
    await ref.read(lockProvider.notifier).unlockWithBiometrics();
    // A refusal says nothing: the secret field is right there.
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

  Future<void> _unlock() async {
    if (_checking || _wait > 0 || _controller.text.isEmpty) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final verdict = await ref
          .read(lockProvider.notifier)
          .unlock(_controller.text);
      if (!mounted || verdict.unlocked) return;
      final kind = ref.read(lockProvider).lock?.kind ?? LockKind.pin;
      setState(() {
        _controller.clear();
        _message = verdict.retryAfterSecs > 0
            ? null
            : 'Wrong ${kind == LockKind.pin ? 'PIN' : 'password'}';
      });
      if (verdict.retryAfterSecs > 0) _startCountdown(verdict.retryAfterSecs);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final kind = ref.watch(lockProvider).lock?.kind ?? LockKind.pin;
    final pin = kind == LockKind.pin;
    final blocked = _wait > 0;
    final note = blocked
        ? 'Too many attempts. Try again in $_wait s'
        : _message;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: PinnedActionForm(
            action: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_offersBiometrics) ...[
                  GhostButton(
                    label: 'Use fingerprint or face',
                    icon: LucideIcons.fingerprint,
                    onPressed: _tryBiometrics,
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                ],
                PrimaryButton(
                  label: _checking ? 'Unlocking…' : 'Unlock',
                  expand: true,
                  onPressed: blocked || _checking ? null : _unlock,
                ),
              ],
            ),
            children: [
              const SizedBox(height: GerfautSpacing.xl),
              Center(
                child: GerfautMark(
                  color: tokens.primary,
                  height: 40,
                  semanticLabel: 'Gerfaut',
                ),
              ),
              const SizedBox(height: GerfautSpacing.lg),
              Center(child: Text('Locked', style: tokens.h2)),
              const SizedBox(height: GerfautSpacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: _hidden,
                enabled: !blocked,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: pin ? TextInputType.number : TextInputType.text,
                inputFormatters: pin
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ]
                    : null,
                style: tokens.body,
                textAlign: pin ? TextAlign.center : TextAlign.start,
                onChanged: (_) => setState(() => _message = null),
                onSubmitted: (_) => _unlock(),
                decoration: InputDecoration(
                  hintText: pin ? 'PIN' : 'Password',
                  hintStyle: tokens.body.copyWith(color: tokens.textMuted),
                  filled: true,
                  fillColor: tokens.surfaceSunken,
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
                  suffixIcon: pin
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
                // A refused secret is a fact, not an alarm: Alerte is
                // kept for coins moving.
                Text(
                  note,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
