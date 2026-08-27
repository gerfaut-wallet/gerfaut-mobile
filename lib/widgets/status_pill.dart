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

/// Address state on the audit list: Used or Fresh, two pills of the
/// same shape read side by side in one column, neither carrying its
/// meaning by colour alone.
///
/// "Used" is the documented exception to the alert reserve: on an audit
/// page an address the chain has already seen is the one fact that
/// calls for a decision — do not hand it out again. In the dark theme
/// the tinted alert surface is the card surface itself, so the fill
/// becomes the alert colour at 10% and the text stays alert.
class AddressStatePill extends StatelessWidget {
  const AddressStatePill({super.key, required this.used});

  final bool used;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = used ? tokens.alert : tokens.primary;
    final fill = used && !dark
        ? tokens.alertSurface
        : color.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        used ? 'Used' : 'Fresh',
        style: tokens.label.copyWith(fontSize: 11, color: color),
      ),
    );
  }
}
