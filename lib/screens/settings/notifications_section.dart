import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/disguise.dart';
import '../../src/live.dart';
import '../../src/lock.dart';
import '../../src/models.dart';
import '../../src/notifications.dart';
import '../../src/premium.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/facts.dart';
import '../../widgets/section_card.dart';
import '../../widgets/select_field.dart';
import '../../widgets/setting_switch.dart';
import 'live_sheet.dart';

/// The settings card for what Gerfaut says on its own: a notice when a
/// sync finds a transaction, and how often to look while the app is
/// closed. Both are off until asked for.
class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  /// Live is explained before it is turned on, and only turned on from
  /// the sheet that explains it. Every other choice applies at once.
  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    BackgroundCheck check,
  ) async {
    final current = ref.read(backgroundCheckProvider);
    if (check == BackgroundCheck.live) {
      if (current != BackgroundCheck.live) await showLiveSheet(context);
      return;
    }
    await ref.read(backgroundCheckProvider.notifier).set(check);
  }

  /// Gerfaut's page in the system settings, where its notifications
  /// are turned back on. A trip out of the app the user asked for: the
  /// lock does not land on the way back.
  Future<void> _openSystemSettings(WidgetRef ref) async {
    final platform = ref.read(livePlatformProvider);
    await ref
        .read(lockProvider.notifier)
        .excursion(platform.openAppSettings, shown: (opened) => opened);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final on = ref.watch(notifyNewTxProvider);
    final refused = ref.watch(notificationsRefusedProvider);
    final cadence = ref.watch(backgroundCheckProvider);
    final disguised = ref.watch(disguiseProvider).disguised;
    // Premium alerts come from the server, not from this phone: they
    // are what still arrives while the app is disguised.
    final premium =
        ref.watch(premiumStateProvider).valueOrNull?.connected ?? false;

    return SectionCard(
      icon: LucideIcons.bell,
      title: 'Notifications',
      children: [
        // Disguised, nothing of the app's own is posted: a notification
        // is headed with its name. Both settings keep their value for
        // when the disguise comes off, greyed meanwhile, and the line
        // under the first says why.
        SettingSwitch(
          title: 'New transactions',
          hint: disguised
              ? disguisedNotificationsHint(premium: premium)
              : 'A notification when a sync finds a transaction you have '
                    'not seen. Amounts follow the display unit and stay '
                    'hidden while balances are masked.',
          value: on,
          onChanged: disguised
              ? null
              : (next) => ref.read(notifyNewTxProvider.notifier).set(next),
        ),
        if (refused && !disguised) ...[
          const SizedBox(height: GerfautSpacing.sm),
          // Amber: the setting says on, and nothing reaches the user.
          Semantics(
            liveRegion: true,
            child: Text(
              'Notifications are off for Gerfaut in the system settings.',
              style: tokens.bodySmall.copyWith(color: tokens.pending),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GhostButton(
              label: 'Open system settings',
              icon: LucideIcons.externalLink,
              onPressed: () => _openSystemSettings(ref),
            ),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        FieldLabel('Check for transactions', tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        GerfautSelect<BackgroundCheck>.items(
          label: 'Check for transactions',
          value: cadence,
          items: [
            for (final check in BackgroundCheck.values)
              GerfautSelectItem(
                value: check,
                title: check.label,
                subtitle: switch (check) {
                  BackgroundCheck.live =>
                    'A connection kept open, told within seconds',
                  BackgroundCheck.off => 'Only while Gerfaut is open',
                  _ => null,
                },
                // Nothing to schedule while nothing would be said.
                enabled: on,
              ),
          ],
          onChanged: disguised ? null : (check) => _choose(context, ref, check),
        ),
        // While the notices are blocked, Live waits for them: the line
        // above says why, and a status would only say it is stopped.
        if (on &&
            cadence == BackgroundCheck.live &&
            !disguised &&
            !refused) ...[
          const SizedBox(height: GerfautSpacing.sm),
          const _LiveStatus(),
        ],
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          cadence == BackgroundCheck.live
              ? 'Live talks to your configured backend and to nothing '
                    'else. A check every 15 minutes stays scheduled under '
                    'it, for whenever Android stops Live.'
              : 'Syncs with your configured backend even when Gerfaut is '
                    'closed: the same servers, nothing else. Android checks '
                    'at most every 15 minutes and may delay it to save '
                    'battery.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// Why the notification settings are greyed while the app is disguised,
/// and what still arrives: Premium alerts, which the server sends to
/// the user's channels without this phone posting anything.
String disguisedNotificationsHint({required bool premium}) {
  const silent =
      'Off while the app is disguised: a notification would show the name '
      'Gerfaut. Live stops, and background checks post nothing.';
  return premium ? '$silent Premium alerts still reach your channels.' : silent;
}

/// Where Live stands, always on screen while Live is chosen: how the
/// connection fares, a way to restart a service Android stopped, and
/// whether the battery exemption is missing.
class _LiveStatus extends ConsumerStatefulWidget {
  const _LiveStatus();

  @override
  ConsumerState<_LiveStatus> createState() => _LiveStatusState();
}

class _LiveStatusState extends ConsumerState<_LiveStatus> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(liveProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final live = ref.watch(liveProvider);
    final line = liveStatusLine(live);
    if (line == null) return const SizedBox.shrink();
    final stopped = !live.serviceRunning;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final note = stopped
        ? null
        : liveCoverageNote(
            live.status,
            ownNode: switch (settings?.backendFor(settings.activeNetwork)) {
              CustomEsplora(:final ownNode) ||
              CustomElectrum(:final ownNode) => ownNode,
              _ => false,
            },
          );
    final connected =
        !stopped &&
        (live.status.state == WatchState.connected ||
            live.status.state == WatchState.polling);
    final color = connected ? tokens.text : tokens.pending;
    final icon = stopped
        ? LucideIcons.circlePause
        : connected
        ? LucideIcons.radio
        : LucideIcons.refreshCw;
    final row = Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: GerfautSpacing.sm),
        Expanded(
          child: Text(line, style: tokens.bodySmall.copyWith(color: color)),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          button: stopped,
          child: stopped
              ? InkWell(
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                  onTap: () => ref.read(liveProvider.notifier).restart(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: row,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: GerfautSpacing.xs,
                  ),
                  child: row,
                ),
        ),
        if (note != null) ...[
          const SizedBox(height: GerfautSpacing.xs),
          // Amber words, no panel: Live works, only not for everything,
          // and the line sits with the status it qualifies.
          Text(
            note.fact,
            style: tokens.bodySmall.copyWith(color: tokens.pending),
          ),
          if (note.remedy != null)
            Text(
              note.remedy!,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          const SizedBox(height: GerfautSpacing.xs),
        ],
        if (!live.batteryExempt)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Battery: restricted. Android may stop Live and will '
                  'not let it restart by itself.',
                  style: tokens.bodySmall.copyWith(color: tokens.pending),
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              GhostButton(
                label: 'Fix',
                onPressed: () =>
                    ref.read(liveProvider.notifier).requestBatteryExemption(),
              ),
            ],
          ),
      ],
    );
  }
}
