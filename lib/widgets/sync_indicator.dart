import 'package:flutter/material.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../theme/tokens.dart';

/// Data freshness, always visible. While syncing, the last known sync
/// stays on screen — never a spinner alone, never a shimmer.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.stamp, required this.syncing});

  final SyncStamp? stamp;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final String text;
    if (syncing) {
      text = stamp == null
          ? 'Syncing…'
          : 'Syncing… · last sync ${relativeTime(stamp!.at)}';
    } else if (stamp == null) {
      text = 'Never synced';
    } else {
      text = 'Synced ${relativeTime(stamp!.at)} · ${stamp!.backend}';
    }
    return Text(
      text,
      style: tokens.label.copyWith(color: tokens.textMuted),
      overflow: TextOverflow.ellipsis,
    );
  }
}
