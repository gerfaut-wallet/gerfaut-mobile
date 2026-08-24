import 'package:flutter/material.dart';

import '../src/models.dart';
import '../theme/tokens.dart';

/// Confirmed / pending pill: a leading 6px dot plus the label, never
/// color alone. Tinted surface + dark text + 25% border in the light
/// theme; the dark tokens map the tinted surfaces to the card surface,
/// which yields the "colored text, no tint" dark rule with the same code.
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
      padding: const EdgeInsets.only(
        left: GerfautSpacing.sm,
        right: GerfautSpacing.sm + 2,
        top: 2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: GerfautSpacing.xs + 2),
          Text(label, style: tokens.label.copyWith(color: color)),
        ],
      ),
    );
  }
}
