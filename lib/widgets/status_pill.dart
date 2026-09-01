import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../theme/tokens.dart';

/// The glyph of a chain state: a check once it is in a block, a clock
/// while it waits. One convention for the whole app, desktop included.
///
/// A shape, not a coloured dot: the two states then differ for someone
/// who cannot tell green from amber, in a black and white screenshot,
/// and at the size where a label no longer fits.
IconData iconOfStatus(TxStatus status) =>
    status.confirmed ? LucideIcons.check : LucideIcons.clock;

/// What that glyph is called, for assistive technology and for the
/// label of the pill.
String labelOfStatus(TxStatus status, {int? confirmations}) {
  if (!status.confirmed) return 'Pending';
  if (confirmations != null && confirmations < 6) return '$confirmations conf';
  return 'Confirmed';
}

/// The state alone, without its label: for a dense list row where the
/// date and the amount need the width more than the word does.
class StatusGlyph extends StatelessWidget {
  const StatusGlyph({super.key, required this.status});

  final TxStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Icon(
      iconOfStatus(status),
      size: 14,
      color: status.confirmed ? tokens.confirmed : tokens.pending,
      semanticLabel: labelOfStatus(status),
    );
  }
}

/// The colour of a pill: the two chain tones, plus a neutral for a
/// state that is neither good nor pressing — a far-off timelock, a
/// wallet with no coins to count yet.
enum PillTone { confirmed, pending, neutral }

/// Confirmed / pending pill: the state glyph plus the label, never
/// color alone. Tinted surface + dark text + 25% border in the light
/// theme; the dark tokens map the tinted surfaces to the card surface,
/// which yields the "colored text, no tint" dark rule with the same code.
///
/// [StatusPill.tone] is the same shape for any other state — a branch
/// of a spending policy, a timelock's countdown — so a new state never
/// forks the pill.
class StatusPill extends StatelessWidget {
  StatusPill({super.key, required TxStatus status, int? confirmations})
    : tone = status.confirmed ? PillTone.confirmed : PillTone.pending,
      icon = iconOfStatus(status),
      label = labelOfStatus(status, confirmations: confirmations),
      semanticLabel = null;

  /// Any state in the pill's shape: a tone, a 12px glyph, its label.
  const StatusPill.tone({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    this.semanticLabel,
  });

  final PillTone tone;
  final IconData icon;
  final String label;

  /// Read in place of the label, for a pill whose words alone would
  /// not say what they are the state of.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final color = switch (tone) {
      PillTone.confirmed => tokens.confirmed,
      PillTone.pending => tokens.pending,
      PillTone.neutral => tokens.textMuted,
    };
    final surface = switch (tone) {
      PillTone.confirmed => tokens.confirmedSurface,
      PillTone.pending => tokens.pendingSurface,
      PillTone.neutral => tokens.surfaceSunken,
    };

    final pill = Container(
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
          Icon(icon, size: 12, color: color),
          const SizedBox(width: GerfautSpacing.xs + 2),
          // Flexible, so a long state — a per-coin count and its next
          // unlock — wraps inside the pill instead of running out of it.
          Flexible(
            child: Text(label, style: tokens.label.copyWith(color: color)),
          ),
        ],
      ),
    );
    final semanticLabel = this.semanticLabel;
    if (semanticLabel == null) return pill;
    return Semantics(label: semanticLabel, excludeSemantics: true, child: pill);
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
