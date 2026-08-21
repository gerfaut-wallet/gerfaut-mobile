import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../theme/tokens.dart';

/// Data freshness, always visible. While syncing, the last known sync
/// stays on screen, never a spinner alone, never a shimmer. A failed
/// sync is stated with its reason: silence would look like health.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({
    super.key,
    required this.stamp,
    required this.syncing,
    this.error,
  });

  final SyncStamp? stamp;
  final bool syncing;

  /// Last sync failure; long-press shows the full reason.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    if (syncing) {
      return Text(
        stamp == null
            ? 'Syncing…'
            : 'Syncing… last sync ${relativeTime(stamp!.at)}',
        style: tokens.label.copyWith(color: tokens.textMuted),
        overflow: TextOverflow.ellipsis,
      );
    }
    if (error != null) {
      return Tooltip(
        message: error!,
        triggerMode: TooltipTriggerMode.longPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.triangleAlert, size: 13, color: tokens.pending),
            const SizedBox(width: GerfautSpacing.xs),
            Flexible(
              child: Text(
                stamp == null
                    ? 'Sync failed · no data yet'
                    : 'Sync failed · showing data from '
                          '${relativeTime(stamp!.at)}',
                style: tokens.label.copyWith(color: tokens.pending),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      stamp == null
          ? 'Never synced'
          : 'Synced ${relativeTime(stamp!.at)} · ${stamp!.backend}',
      style: tokens.label.copyWith(color: tokens.textMuted),
      overflow: TextOverflow.ellipsis,
    );
  }
}
