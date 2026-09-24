import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/clipboard.dart';
import '../src/premium.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/notice.dart';
import 'confirm_identity.dart';

/// Opens the change of key. It cannot be swiped away: once the new key
/// is on screen, "Done" is the only way out, and only once the box
/// says it was saved.
Future<void> showChangeKeySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const ChangeKeySheet(),
  );
}

/// A new key for the account, in two steps on one sheet: what it does
/// and the button that does it, then the key itself, shown the one time
/// it is worth writing down.
///
/// The old key stops working everywhere the moment the server answers,
/// and every other device is disconnected: an owner who fears the key
/// leaked changes it, and whoever took it is left with nothing. The
/// press is confirmed by who holds the phone first, and never sent
/// twice: the button is held from the first tap.
class ChangeKeySheet extends ConsumerStatefulWidget {
  const ChangeKeySheet({super.key});

  @override
  ConsumerState<ChangeKeySheet> createState() => _ChangeKeySheetState();
}

class _ChangeKeySheetState extends ConsumerState<ChangeKeySheet> {
  bool _busy = false;
  BridgeException? _error;

  /// The key the server drew, once it has.
  String? _newKey;
  bool _copied = false;
  bool _saved = false;
  bool _closing = false;

  Future<void> _change() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await confirmIdentity(context, ref)) return;
      final key = await ref.read(bridgeProvider).premiumChangeKey();
      if (!mounted) return;
      setState(() => _newKey = key);
      // The other devices are gone, and the key in the vault is new:
      // the section reads it all again behind the sheet.
      invalidatePremium(ref);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String key) async {
    await ref.read(sensitiveClipboardProvider).copy(key);
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _done() async {
    if (!_saved || _closing) return;
    setState(() => _closing = true);
    try {
      await ref.read(bridgeProvider).premiumSetKeySaved(true);
    } on BridgeException {
      // The checklist asks again; the key itself is changed and kept.
    }
    if (!mounted) return;
    ref.invalidate(premiumStateProvider);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final newKey = _newKey;
    return PopScope(
      // Back and the scrim leave the question, never the key: it is
      // shown here once, and "Done" says it was kept.
      canPop: newKey == null && !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          left: GerfautSpacing.md,
          right: GerfautSpacing.md,
          top: GerfautSpacing.md,
          bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
        ),
        child: SingleChildScrollView(
          child: newKey == null
              ? _asking(tokens)
              : _revealed(tokens, newKey),
        ),
      ),
    );
  }

  Widget _asking(GerfautTokens tokens) {
    final error = _error;
    final failure = error == null ? null : premiumFailure(error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Change your Premium key', style: tokens.h2),
        ),
        const SizedBox(height: GerfautSpacing.md),
        // Amber: nothing on chain is touched, and the words say what is
        // lost — the old key, and every other device's access.
        const GerfautNotice(
          tone: NoticeTone.info,
          message:
              'A new key replaces this one. The old key stops working at '
              'once, on the website too. Every other device is disconnected: '
              'enter the new key there, then approve it here.',
        ),
        if (failure != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          GerfautNotice(
            tone: NoticeTone.info,
            message: failure.message,
            hint: failure.hint,
            detail: failure.detail,
            liveRegion: true,
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        ConfirmActions(
          cancel: GhostButton(
            label: 'Cancel',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          confirm: DangerButton(
            label: _busy ? 'Changing…' : 'Change key',
            onPressed: _busy ? null : _change,
          ),
        ),
      ],
    );
  }

  Widget _revealed(GerfautTokens tokens, String newKey) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text('Your new key', style: tokens.h2),
        ),
        const SizedBox(height: GerfautSpacing.md),
        // The one large identifier of the app: read and compared symbol
        // by symbol, so mono, selectable, and never cut short. At a
        // large text size it breaks at a dash, between two groups.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.md,
            vertical: GerfautSpacing.sm + GerfautSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          child: SelectableText(
            newKey,
            key: const Key('change_key.value'),
            textAlign: TextAlign.center,
            style: tokens.data.copyWith(
              fontSize: 22,
              height: 1.4,
              color: tokens.text,
            ),
          ),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryButton(
            label: _copied ? 'Copied' : 'Copy',
            icon: _copied ? LucideIcons.check : LucideIcons.copy,
            onPressed: () => _copy(newKey),
          ),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Text(
          'Save it in your password manager now. This device keeps it, but '
          'nothing else does.',
          style: tokens.bodySmall,
        ),
        const SizedBox(height: GerfautSpacing.sm),
        _SavedBox(
          value: _saved,
          onChanged: _closing ? null : (on) => setState(() => _saved = on),
        ),
        const SizedBox(height: GerfautSpacing.md),
        PrimaryButton(
          label: 'Done',
          expand: true,
          onPressed: _saved && !_closing ? _done : null,
        ),
      ],
    );
  }
}

/// "I saved my new key": the one thing standing between the key on
/// screen and the sheet closing on it.
class _SavedBox extends StatelessWidget {
  const _SavedBox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final onChanged = this.onChanged;
    // One stop for a screen reader: the box and its words go together.
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Checkbox(
                value: value,
                activeColor: tokens.primary,
                checkColor: tokens.onPrimary,
                side: BorderSide(color: tokens.border, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                onChanged: onChanged == null
                    ? null
                    : (ticked) => onChanged(ticked ?? false),
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Expanded(
                child: Text('I saved my new key', style: tokens.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
