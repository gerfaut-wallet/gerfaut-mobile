import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../theme/tokens.dart';
import 'buttons.dart';

/// A page whose data could not be read: what failed, in the core's
/// words when it gave any, and a way to ask again. The bare line it
/// replaces gave no reason and no way out but leaving the page, and a
/// failed list of UTXOs read as a wallet holding none.
class LoadFailure extends StatelessWidget {
  const LoadFailure({
    super.key,
    required this.what,
    required this.error,
    required this.onRetry,
    this.centered = true,
  });

  /// The sentence's subject: "This wallet", "The UTXOs".
  final String what;
  final Object? error;
  final VoidCallback onRetry;

  /// In the middle of an empty page; false for a part of a page.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final error = this.error;
    // The core's sentence is ours to show; anything else is a raw
    // exception, and says nothing a reader can act on.
    final reason = error is BridgeException ? error.message : null;
    final body = Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            '$what could not be loaded.',
            style: tokens.bodySmall,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              reason,
              style: tokens.label.copyWith(color: tokens.textMuted),
              textAlign: centered ? TextAlign.center : TextAlign.start,
            ),
          ],
          const SizedBox(height: GerfautSpacing.sm),
          GhostButton(
            label: 'Try again',
            icon: LucideIcons.refreshCw,
            onPressed: onRetry,
          ),
        ],
      ),
    );
    if (!centered) return body;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        child: body,
      ),
    );
  }
}
