import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/notifications.dart';
import '../../theme/tokens.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/section_card.dart';

/// The settings card for what Gerfaut says on its own: a notice when a
/// sync finds a transaction, and how often to look while the app is
/// closed. Both are off until asked for.
class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final on = ref.watch(notifyNewTxProvider);
    final refused = ref.watch(notificationsRefusedProvider);
    final cadence = ref.watch(backgroundCheckProvider);

    return SectionCard(
      icon: LucideIcons.bell,
      title: 'Notifications',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New transactions',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    'A notification when a sync finds a transaction you '
                    'have not seen. Amounts follow the display unit and '
                    'stay hidden while balances are masked.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Switch(
              value: on,
              onChanged: (next) =>
                  ref.read(notifyNewTxProvider.notifier).set(next),
            ),
          ],
        ),
        if (refused) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'Notifications are off for Gerfaut in the system settings.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        ChoiceGroup<BackgroundCheck>(
          label: 'Check in the background',
          value: cadence,
          options: [
            for (final check in BackgroundCheck.values)
              ChoiceOption(
                value: check,
                label: check.label,
                // Nothing to schedule while nothing would be said.
                enabled: on,
              ),
          ],
          onChanged: (check) =>
              ref.read(backgroundCheckProvider.notifier).set(check),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Syncs with your configured backend even when Gerfaut is '
          'closed: the same servers, nothing else. Android checks at most '
          'every 15 minutes and may delay it to save battery.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
