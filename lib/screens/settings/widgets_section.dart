import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/home_widgets.dart';
import '../../theme/tokens.dart';
import '../../widgets/section_card.dart';

/// The settings card for the home-screen widgets: whether they may show
/// balances, and how to place one. The widgets themselves are added
/// from the launcher, not from here.
class WidgetsSection extends ConsumerWidget {
  const WidgetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final on = ref.watch(widgetBalancesProvider);

    return SectionCard(
      icon: LucideIcons.layoutGrid,
      title: 'Widgets',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Show balances on widgets',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    'A widget is read over the shoulder: balances stay '
                    'masked until this is on, and whenever amounts are '
                    'hidden in the app.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Switch(
              value: on,
              onChanged: (next) =>
                  ref.read(widgetBalancesProvider.notifier).set(next),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.md),
        Text(
          'To add one, hold an empty spot on your home screen and pick '
          'Gerfaut under Widgets.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
