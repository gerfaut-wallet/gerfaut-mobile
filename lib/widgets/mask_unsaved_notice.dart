import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/state.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'notice.dart';

/// Says that balances hidden on screen are hidden there only: the vault
/// refused to keep them hidden, and the home screen widget and the
/// notifications posted in the background read the vault. Red: amounts
/// may be shown where the user asked for none, which is privacy lost.
class MaskUnsavedNotice extends ConsumerWidget {
  const MaskUnsavedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(maskUnsavedProvider) || !ref.watch(maskedProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GerfautSpacing.md,
        GerfautSpacing.sm,
        GerfautSpacing.md,
        0,
      ),
      child: GerfautNotice(
        tone: NoticeTone.alert,
        liveRegion: true,
        message: 'Balances are hidden on this screen only.',
        hint:
            'Gerfaut could not save the change. Until it does, the widget '
            'and notifications may still show amounts.',
        actionsBelow: true,
        action: GhostButton(
          label: 'Try again',
          onPressed: () => ref.read(maskedProvider.notifier).retry(),
        ),
      ),
    );
  }
}
