import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/clipboard.dart';
import '../../src/models.dart';
import '../../src/premium.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';
import '../../widgets/section_card.dart';
import '../settings.dart';

/// Where each of the three steps stands.
typedef ProtectSteps = ({bool secondDevice, bool appLock, bool keySaved});

/// The steps, from what the app already knows: the devices with full
/// access, the lock in the vault, and the box the user ticked.
ProtectSteps protectSteps({
  required PremiumView view,
  required List<PremiumDevice> devices,
  required AppLock? lock,
}) {
  final full = devices.where((device) => device.fullAccess).length;
  return (
    secondDevice: full >= 2,
    appLock: lock != null,
    keySaved: view.keySaved,
  );
}

/// Whether the card shows: on a device with full access, until it is
/// hidden or all three steps are done.
bool protectCardShows(PremiumView view, ProtectSteps steps) {
  if (view.checklistHidden) return false;
  return !(steps.secondDevice && steps.appLock && steps.keySaved);
}

/// "Protect your Premium account": the three things that keep a stolen
/// key or a stolen phone from taking the account. A second device keeps
/// full access if this one is lost; the app lock stops whoever holds
/// this one unlocked from approving a stranger; the key in a password
/// manager is the only copy that survives this phone.
///
/// Each step checks itself from what the app knows; the card goes once
/// all three are done, or when it is hidden.
class ProtectAccountCard extends ConsumerStatefulWidget {
  const ProtectAccountCard({
    super.key,
    required this.view,
    required this.steps,
  });

  final PremiumView view;
  final ProtectSteps steps;

  @override
  ConsumerState<ProtectAccountCard> createState() => _ProtectAccountCardState();
}

/// The two things the card writes to the vault.
enum _Write { hide, keySaved }

class _ProtectAccountCardState extends ConsumerState<ProtectAccountCard> {
  /// A write to the vault is under way: its button is held.
  bool _busy = false;

  /// The last "Copy key" did not reach the clipboard.
  bool _copyFailed = false;

  /// The write the vault last refused, said under its button until the
  /// next press.
  _Write? _failed;

  /// A write that fails leaves the card as it was, to press again, and
  /// says so under the button that asked: a card that stays put after
  /// "Hide" reads as a button that does nothing.
  Future<void> _write(
    _Write what,
    Future<void> Function(GerfautBridge bridge) call,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await call(ref.read(bridgeProvider));
      ref.invalidate(premiumStateProvider);
    } catch (_) {
      if (mounted) setState(() => _failed = what);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyKey() async {
    final key = widget.view.keyDisplay ?? widget.view.key;
    if (key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sensitiveClipboardProvider).copy(key);
    } catch (_) {
      // Said under the step, where it was asked, and it stays.
      if (mounted) setState(() => _copyFailed = true);
      return;
    }
    if (!mounted) return;
    setState(() => _copyFailed = false);
    messenger.showSnackBar(const SnackBar(content: Text('Key copied')));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final steps = widget.steps;
    return SectionCard(
      icon: LucideIcons.shieldCheck,
      iconColor: tokens.premium,
      title: 'Protect your Premium account',
      trailing: GhostButton(
        label: 'Hide',
        onPressed: _busy
            ? null
            : () => _write(
                _Write.hide,
                (bridge) => bridge.premiumHideChecklist(),
              ),
      ),
      children: [
        // "Hide" sits in the header: its failure right under it.
        if (_failed == _Write.hide) ...[
          const GerfautNotice(
            tone: NoticeTone.info,
            liveRegion: true,
            message: 'Could not hide the card.',
          ),
          const SizedBox(height: GerfautSpacing.md),
        ],
        _Step(
          done: steps.secondDevice,
          title: 'Connect a second device',
          body:
              'Enter this key in Gerfaut on your computer or another phone, '
              'then approve it here. If this device is lost, the other keeps '
              'full access.',
        ),
        _Step(
          done: steps.appLock,
          title: 'Turn on the app lock',
          body:
              "Anyone holding this device unlocked could approve a stranger's "
              'device. A PIN stops them.',
          actions: [
            GhostButton(
              label: 'Set up',
              icon: LucideIcons.lock,
              onPressed: () => SettingsScreen.open(
                context,
                section: SettingsSection.security,
              ),
            ),
          ],
        ),
        _Step(
          done: steps.keySaved,
          title: 'Save your key in a password manager',
          body:
              'Your key is the whole account. Nobody can send it to you '
              'again.',
          last: true,
          actions: [
            // Not while a key change waits for its answer: the key here
            // may already be dead, and the licence says how to finish.
            if (!widget.view.keyChangePending)
              GhostButton(
                label: 'Copy key',
                icon: LucideIcons.copy,
                onPressed: _copyKey,
              ),
            GhostButton(
              label: 'Mark as done',
              icon: LucideIcons.check,
              onPressed: _busy
                  ? null
                  : () => _write(
                      _Write.keySaved,
                      (bridge) => bridge.premiumSetKeySaved(true),
                    ),
            ),
          ],
        ),
        if (_copyFailed &&
            !steps.keySaved &&
            !widget.view.keyChangePending) ...[
          const SizedBox(height: GerfautSpacing.sm),
          const GerfautNotice(
            tone: NoticeTone.info,
            liveRegion: true,
            message: 'Could not copy the key.',
          ),
        ],
        if (_failed == _Write.keySaved && !steps.keySaved) ...[
          const SizedBox(height: GerfautSpacing.sm),
          const GerfautNotice(
            tone: NoticeTone.info,
            liveRegion: true,
            message: 'Could not mark the key as saved.',
          ),
        ],
      ],
    );
  }
}

/// One step: a ring that fills with a check once it is done, what to do
/// and why, and the buttons that do it while it is not done yet.
class _Step extends StatelessWidget {
  const _Step({
    required this.done,
    required this.title,
    required this.body,
    this.actions = const [],
    this.last = false,
  });

  final bool done;
  final String title;
  final String body;
  final List<Widget> actions;

  /// No gap under the last step: the card's own padding closes it.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final titleStyle = tokens.bodySmall.copyWith(
      color: done ? tokens.textMuted : tokens.text,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    const indent = 18.0 + GerfautSpacing.sm + GerfautSpacing.xs;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : GerfautSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One stop for a screen reader: where the step stands, what it
          // is and why, read together; its buttons are stops of their own.
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FirstLine(
                  style: titleStyle,
                  child: Icon(
                    done ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 18,
                    color: done ? tokens.premium : tokens.textMuted,
                    semanticLabel: done ? 'Done' : 'To do',
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!done && actions.isNotEmpty) ...[
            const SizedBox(height: GerfautSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: indent),
              child: Wrap(
                spacing: GerfautSpacing.xs,
                runSpacing: GerfautSpacing.xs,
                children: actions,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
