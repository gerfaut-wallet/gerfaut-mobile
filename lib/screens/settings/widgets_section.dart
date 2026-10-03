import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/disguise.dart';
import '../../src/home_widgets.dart';
import '../../theme/tokens.dart';
import '../../widgets/section_card.dart';
import '../../widgets/setting_switch.dart';

/// The settings card for the home-screen widgets: whether they may show
/// balances, and how to place one. The widgets themselves are added
/// from the launcher, not from here.
class WidgetsSection extends ConsumerWidget {
  const WidgetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final on = ref.watch(widgetBalancesProvider);
    final disguised = ref.watch(disguiseProvider).disguised;

    return SectionCard(
      icon: LucideIcons.layoutGrid,
      title: 'Widgets',
      children: [
        SettingSwitch(
          title: 'Show balances on widgets',
          hint:
              'A widget is read over the shoulder: balances stay masked '
              'until this is on, and whenever amounts are hidden in the app.',
          value: on,
          onChanged: (next) =>
              ref.read(widgetBalancesProvider.notifier).set(next),
        ),
        const SizedBox(height: GerfautSpacing.md),
        // Disguised, the providers are disabled and the launcher offers
        // none: telling someone to look for Gerfaut under Widgets would
        // send them looking for a thing that is not there.
        Text(
          disguised
              ? 'Widgets are off while the app is disguised.'
              : 'To add one, hold an empty spot on your home screen and '
                    'pick Gerfaut under Widgets.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
