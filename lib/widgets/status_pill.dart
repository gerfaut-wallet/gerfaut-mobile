import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../theme/tokens.dart';

/// Confirmed / pending pill: always icon + text, never color alone.
/// Tinted surface + dark text + 25% border in the light theme; the dark
/// tokens map the tinted surfaces to the card surface, which yields the
/// "colored text, no tint" dark rule with the same code.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.confirmations});

  final TxStatus status;
  final int? confirmations;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final confirmed = status.confirmed;
    final color = confirmed ? tokens.confirmed : tokens.pending;
    final surface = confirmed ? tokens.confirmedSurface : tokens.pendingSurface;
    final label = confirmed
        ? (confirmations != null && confirmations! < 6
              ? '$confirmations conf'
              : 'Confirmed')
        : 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confirmed ? LucideIcons.circleCheck : LucideIcons.clock3,
            size: 12,
            color: color,
          ),
          const SizedBox(width: GerfautSpacing.xs),
          Text(label, style: tokens.label.copyWith(color: color)),
        ],
      ),
    );
  }
}
