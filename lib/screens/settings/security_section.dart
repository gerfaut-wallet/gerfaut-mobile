import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/lock.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/password_field.dart';
import '../../widgets/section_card.dart';

/// The settings card that turns the lock on and changes its secret.
class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key});

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  String? _error;

  /// The vault is the source of truth: invalidating the settings is
  /// what tells the lock screen, through the gate that watches them.
  void _afterChange() => ref.invalidate(settingsProvider);

  Future<void> _setLock({LockKind? kind}) async {
    final chosen = await showModalBottomSheet<_NewSecret>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SetLockSheet(kind: kind, asksCurrent: kind != null),
    );
    if (chosen == null) return;
    setState(() => _error = null);
    try {
      // Replacing a secret needs the one in place: an unlocked phone in
      // the wrong hands must not be able to set a new PIN.
      await ref
          .read(bridgeProvider)
          .setAppLock(chosen.kind, chosen.secret, current: chosen.current);
      _afterChange();
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _turnOff(LockKind kind) async {
    final current = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSecretSheet(
        kind: kind,
        title: 'Turn off the app lock',
        action: 'Turn off',
      ),
    );
    if (current == null) return;
    setState(() => _error = null);
    try {
      await ref.read(bridgeProvider).clearAppLock(current);
      _afterChange();
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  /// Asks for the secret in place and hands it back, or null when the
  /// sheet was dismissed.
  Future<String?> _askSecret(LockKind kind, String title) {
    setState(() => _error = null);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSecretSheet(kind: kind, title: title),
    );
  }

  Future<void> _setBiometric(bool on, LockKind kind) async {
    // The secret first: whoever has their own finger enrolled on this
    // phone must not be able to make it a key to this vault.
    final current = await _askSecret(kind, 'Unlock with biometrics');
    if (current == null) return;
    // Then prove the phone answers, before storing a promise it
    // cannot keep.
    if (on) {
      final passed = await ref
          .read(biometricGateProvider)
          .authenticate('Unlock Gerfaut');
      if (!passed) {
        if (mounted) {
          setState(
            () => _error = 'The phone did not confirm. Nothing changed.',
          );
        }
        return;
      }
    }
    try {
      await ref.read(bridgeProvider).setBiometricUnlock(on, current);
      _afterChange();
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // The vault is the source of truth for what is set; the lock
    // provider only knows whether the screen is up right now.
    final lock = ref.watch(settingsProvider).valueOrNull?.appLock;
    final canBiometrics =
        ref.watch(biometricsAvailableProvider).valueOrNull ?? false;

    return SectionCard(
      icon: LucideIcons.lock,
      title: 'Security',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App lock',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    'Asked when Gerfaut opens and every time it comes back '
                    'from the background. The vault is encrypted either way; '
                    'the lock is what stops someone holding your unlocked '
                    'phone.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Switch(
              value: lock != null,
              onChanged: (on) => on ? _setLock() : _turnOff(lock!.kind),
            ),
          ],
        ),
        if (lock != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Row(
            children: [
              GhostButton(
                label: lock.kind == LockKind.pin
                    ? 'Change PIN'
                    : 'Change password',
                icon: LucideIcons.pencil,
                onPressed: () => _setLock(kind: lock.kind),
              ),
              GhostButton(
                label: 'Lock now',
                icon: LucideIcons.lock,
                onPressed: ref.read(lockProvider.notifier).lockNow,
              ),
            ],
          ),
          if (canBiometrics) ...[
            const SizedBox(height: GerfautSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Unlock with biometrics',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                ),
                Switch(
                  value: lock.biometric,
                  onChanged: (on) => _setBiometric(on, lock.kind),
                ),
              ],
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }
}

/// What a set-lock sheet comes back with.
typedef _NewSecret = ({LockKind kind, String secret, String? current});

/// Asks for a new secret, and for the current one when there is a lock
/// to replace.
class _SetLockSheet extends StatefulWidget {
  const _SetLockSheet({this.kind, this.asksCurrent = false});

  /// Fixed when changing an existing lock, chosen when turning it on.
  final LockKind? kind;
  final bool asksCurrent;

  @override
  State<_SetLockSheet> createState() => _SetLockSheetState();
}

class _SetLockSheetState extends State<_SetLockSheet> {
  late LockKind _kind = widget.kind ?? LockKind.pin;
  final _currentController = TextEditingController();
  final _secretController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _currentController.dispose();
    _secretController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// What is wrong with the pair, in the core's own terms so the screen
  /// never promises something the core would refuse.
  String? _check() {
    final secret = _secretController.text;
    if (_kind == LockKind.pin) {
      if (secret.length < 4 || secret.length > 12) {
        return 'A PIN is 4 to 12 digits.';
      }
    } else if (secret.length < 8) {
      return 'A password is at least 8 characters.';
    }
    if (_confirmController.text != secret) return 'The two entries differ.';
    return null;
  }

  void _submit() {
    final problem = _check();
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop((
      kind: _kind,
      secret: _secretController.text,
      current: widget.asksCurrent ? _currentController.text : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: GerfautSpacing.md,
        right: GerfautSpacing.md,
        top: GerfautSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.asksCurrent
                  ? 'Change the app lock'
                  : 'Turn on the app lock',
              style: tokens.h2,
            ),
            const SizedBox(height: GerfautSpacing.md),
            if (widget.kind == null) ...[
              ChoiceGroup<LockKind>(
                label: 'Kind',
                value: _kind,
                options: const [
                  ChoiceOption(value: LockKind.pin, label: 'PIN'),
                  ChoiceOption(value: LockKind.password, label: 'Password'),
                ],
                onChanged: (kind) => setState(() {
                  _kind = kind;
                  _problem = null;
                }),
              ),
              const SizedBox(height: GerfautSpacing.xs),
              Text(
                _kind == LockKind.pin
                    ? '4 to 12 digits'
                    : 'At least 8 characters',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.md),
            ],
            if (widget.asksCurrent) ...[
              PasswordField(
                key: const Key('lock.current'),
                label: _kind == LockKind.pin
                    ? 'Current PIN'
                    : 'Current password',
                controller: _currentController,
                onChanged: () => setState(() => _problem = null),
              ),
              const SizedBox(height: GerfautSpacing.md),
            ],
            PasswordField(
              key: const Key('lock.secret'),
              label: _kind == LockKind.pin ? 'New PIN' : 'New password',
              controller: _secretController,
              onChanged: () => setState(() => _problem = null),
            ),
            const SizedBox(height: GerfautSpacing.md),
            PasswordField(
              key: const Key('lock.confirm'),
              label: 'Confirm',
              controller: _confirmController,
              onChanged: () => setState(() => _problem = null),
              onSubmitted: _submit,
            ),
            if (_problem != null) ...[
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                _problem!,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
            const SizedBox(height: GerfautSpacing.md),
            PrimaryButton(
              label: widget.asksCurrent ? 'Change' : 'Turn on',
              expand: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks only for the secret in place: turning the lock off is an unlock
/// like any other.
class _ConfirmSecretSheet extends StatefulWidget {
  const _ConfirmSecretSheet({
    required this.kind,
    required this.title,
    this.action = 'Confirm',
  });

  final LockKind kind;
  final String title;
  final String action;

  @override
  State<_ConfirmSecretSheet> createState() => _ConfirmSecretSheetState();
}

class _ConfirmSecretSheetState extends State<_ConfirmSecretSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: GerfautSpacing.md,
        right: GerfautSpacing.md,
        top: GerfautSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: tokens.h2),
          const SizedBox(height: GerfautSpacing.md),
          PasswordField(
            key: const Key('lock.current'),
            label: widget.kind == LockKind.pin ? 'PIN' : 'Password',
            controller: _controller,
            autofocus: true,
            onSubmitted: () => Navigator.of(context).pop(_controller.text),
          ),
          const SizedBox(height: GerfautSpacing.md),
          PrimaryButton(
            label: widget.action,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_controller.text),
          ),
        ],
      ),
    );
  }
}
