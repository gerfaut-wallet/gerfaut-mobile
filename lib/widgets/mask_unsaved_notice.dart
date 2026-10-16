import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/state.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'notice.dart';

/// Says that balances hidden in the app are hidden there only, on every
/// screen for as long as it runs: the vault refused to keep them hidden,
/// and the home screen widget and the notifications posted in the
/// background read the vault. Nothing tries again on its own, so the
/// note says what happens until the change is saved and offers the try.
/// Red: amounts may be shown where the user asked for none, which is
/// privacy lost.
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
        message: 'Balances are hidden in the app only.',
        hint:
            'Gerfaut could not save the change. Until it is saved, the '
            'widget and notifications may still show amounts.',
        actionsBelow: true,
        action: GhostButton(
          label: 'Try again',
          onPressed: () => ref.read(maskedProvider.notifier).retry(),
        ),
      ),
    );
  }
}
