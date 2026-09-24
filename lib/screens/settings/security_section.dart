import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/disguise.dart';
import '../../src/identity.dart';
import '../../src/lock.dart';
import '../../src/models.dart';
import '../../src/notifications.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/notice.dart';
import '../../widgets/password_field.dart';
import '../../widgets/section_card.dart';
import '../confirm_identity.dart';

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
    if (kind == null && !await _mayChooseFirstLock()) return;
    if (!mounted) return;
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

  /// Whether whoever holds the phone may choose its first app lock.
  ///
  /// With a Premium key here, the app lock is what proves the owner
  /// before a device is approved, the key changed or the account
  /// deleted; until one is set, the phone's own screen lock does. A
  /// first lock chosen by whoever holds the phone unlocked would hand
  /// them that proof, so the phone's screen lock is asked first. A phone
  /// without one has no owner's secret to ask for, and without a key
  /// there is nothing the lock would stand in front of: the lock is set
  /// as it always was.
  ///
  /// A first connection whose answer was lost counts as a key: the
  /// vault holds it only once the server answers, but the core sends it
  /// again on its own, and the account may already be this phone's.
  Future<bool> _mayChooseFirstLock() async {
    final PremiumView premium;
    try {
      premium = await ref.read(bridgeProvider).premiumState();
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    }
    if (!premium.hasKey && !premium.connectPending) return true;
    final outcome = await ref
        .read(screenLockGateProvider)
        .confirm(confirmItsYouTitle);
    // Refused: a change of mind, or not the owner. The phone said why,
    // if anything needed saying.
    return outcome != ScreenLockOutcome.refused;
  }

  Future<void> _turnOff(LockKind kind) async {
    // A disguise has no meaning without the PIN that opens it, so
    // removing the lock takes the disguise off first, and the sheet
    // says so before the secret is asked.
    final disguised = ref.read(disguiseProvider).disguised;
    final current = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSecretSheet(
        kind: kind,
        title: 'Turn off the app lock',
        action: 'Turn off',
        note: disguised
            ? 'This also turns the disguise off: the calculator goes, and '
                  'Gerfaut is back in the launcher.'
            : null,
      ),
    );
    if (current == null) return;
    setState(() => _error = null);
    try {
      await ref.read(bridgeProvider).clearAppLock(current);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    }
    // Only once the core accepts: the launcher face is restored after
    // the lock is gone, never before it is agreed.
    if (disguised) await _swapFace(false);
    _afterChange();
  }

  /// Puts the disguise on behind a confirmation, or takes it off at
  /// once. The switch only offers "on" where a PIN lock stands.
  Future<void> _setDisguise(bool on) async {
    setState(() => _error = null);
    if (!on) {
      await _swapFace(false);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DisguiseSheet(
        liveOn: ref.read(backgroundCheckProvider) == BackgroundCheck.live,
      ),
    );
    if (confirmed != true) return;
    await _swapFace(true);
  }

  /// Asks the platform for the other launcher face. A package manager
  /// that refuses is reported under the card; the switch stays where it
  /// was, since the state only moves once the platform has.
  Future<void> _swapFace(bool disguised) async {
    try {
      await ref.read(disguiseProvider.notifier).set(disguised);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.message ?? 'The launcher entry could not be changed.',
        );
      }
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
    final disguised = ref.watch(disguiseProvider).disguised;
    final pinLock = lock?.kind == LockKind.pin;

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
          const SizedBox(height: GerfautSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Disguise the app',
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    Text(
                      'Shows a calculator in the launcher. Open the wallet by '
                      'typing your PIN, then =.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              Switch(
                value: disguised,
                // A password is not something you type into a calculator:
                // the disguise needs a PIN lock.
                onChanged: pinLock ? _setDisguise : null,
              ),
            ],
          ),
          if (!pinLock) ...[
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Needs a PIN lock: the PIN is what you type into the '
              'calculator.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
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
    this.note,
  });

  final LockKind kind;
  final String title;
  final String action;

  /// A line under the title, when turning the lock off does more than
  /// that — taking a disguise off with it.
  final String? note;

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
          if (widget.note != null) ...[
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              widget.note!,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ],
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

/// The confirmation for turning the disguise on: what changes and what
/// stays, said once as plain facts, and the one consequence that bites
/// in a note of its own. Five amber panels in a row read as a wall of
/// warnings, and a wall is skipped; one panel is read.
class _DisguiseSheet extends StatelessWidget {
  const _DisguiseSheet({this.liveOn = false});

  /// Live watch is what looks for transactions right now: the sheet
  /// says it is about to stop.
  final bool liveOn;

  /// What stops with the disguise when Live is on. Its permanent
  /// notification is headed with the app's name, so it cannot stay.
  static const String liveFact =
      'Live watch is turned off, and the check for transactions goes back '
      'to every 15 minutes.';

  static const List<String> facts = [
    'The launcher will show a calculator named "Calculator".',
    'Open the wallet by typing your PIN into it, then =.',
    'Settings → Apps and the app store still list "Gerfaut".',
    'Notifications and home-screen widgets are turned off while disguised.',
    'Clear your recent apps once: Android may still show an older Gerfaut '
        'thumbnail.',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
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
            Text('Disguise the app', style: tokens.h2),
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              'Gerfaut hides behind a working calculator. What that means:',
              style: tokens.body,
            ),
            const SizedBox(height: GerfautSpacing.sm),
            for (final fact in [...facts, if (liveOn) liveFact])
              Padding(
                padding: const EdgeInsets.only(bottom: GerfautSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FirstLine(
                      style: muted,
                      child: Icon(
                        LucideIcons.dot,
                        size: 16,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(child: Text(fact, style: muted)),
                  ],
                ),
              ),
            const SizedBox(height: GerfautSpacing.sm),
            const GerfautNotice(
              tone: NoticeTone.info,
              message:
                  'Forget the PIN and the app cannot be opened: it is the '
                  'only way in.',
            ),
            const SizedBox(height: GerfautSpacing.md),
            PrimaryButton(
              label: 'Turn on the disguise',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            GhostButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
