import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// How loud the note is allowed to be. One question decides it, and it
/// is never re-argued case by case:
///
/// - [alert] — red. **Only** when the user can lose funds or lose
///   privacy: an unexpected outflow, a server certificate that changed,
///   a link that hands their IP to an explorer operator, an unsigned
///   transaction they believe is ready. Red is the most expensive colour
///   of the system; every use too many makes it inaudible the day it
///   counts.
/// - [info] — amber. Everything else worth reading: information, a
///   convention, a benign consequence. A key that does not carry its
///   script type, an OP_RETURN in a transaction, a gap limit raised that
///   only applies to the next sync. Nothing is at risk; something is
///   simply good to know before going on.
///
/// A precision that changes no decision needs no panel at all: it is a
/// hint under the field, in the muted colour.
enum NoticeTone { alert, info }

/// A note about something else, in its own panel.
///
/// **A notice never lives inside the card it comments on.** A card
/// states what was recognized; a notice states what is not known.
/// Stacked in one frame they read as a single block of facts of equal
/// weight — which is how "This key carries no script type" once slipped
/// under "First address" in the same grey. Apart, one is scanned and the
/// other stops the eye.
///
/// Same anatomy in both tones: tinted surface, 1px border in the text
/// colour at 25%, radius 8, a 16px icon on the first line of text, the
/// message in `bodySmall` in the tone's colour. The tone is never the
/// only carrier: the text always says what is at stake on its own.
class GerfautNotice extends StatelessWidget {
  const GerfautNotice({
    super.key,
    required this.tone,
    required this.message,
    this.hint,
    this.icon,
    this.action,
  });

  final NoticeTone tone;

  /// Wraps to as many lines as it needs.
  final String message;

  /// A quieter second line, when the note needs to say what to do about
  /// it as well as what it is. Muted, so the coloured line stays the
  /// one that is read first.
  final String? hint;

  /// A glyph in place of the tone's own, for a panel that names a
  /// specific kind of caution — the broadcast warnings pick one per
  /// kind. It never changes the tone: the colour still says how much
  /// this matters, the glyph only says what it is about.
  final IconData? icon;

  /// What to do about it, if anything: a ghost button, a link. Centred
  /// on the panel because it answers the whole note, not its first line.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color ink, Color tint, IconData glyph, String role) = switch (tone) {
      NoticeTone.alert => (
        tokens.alert,
        tokens.alertSurface,
        icon ?? LucideIcons.triangleAlert,
        'Warning',
      ),
      NoticeTone.info => (
        tokens.pending,
        tokens.pendingSurface,
        icon ?? LucideIcons.info,
        'Note',
      ),
    };
    final style = tokens.bodySmall.copyWith(color: ink);

    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
      decoration: BoxDecoration(
        // Dark theme: coloured text on the card surface, no tint. A
        // tinted flat on Nuit polaire reads as a second card, and the
        // colour of the words is enough there.
        color: dark ? tokens.surface : tint,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: ink.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FirstLine(
                  style: style,
                  child: Icon(glyph, size: 16, color: ink, semanticLabel: role),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Expanded(
                  // One line stays one Text: a paragraph in a Column
                  // would report an overflow the plain text never had.
                  child: hint == null
                      ? Text(message, style: style)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // With a second line under it, the first one
                            // carries the weight that says which is which.
                            Text(
                              message,
                              style: style.copyWith(
                                fontWeight: FontWeight.w500,
                                fontVariations: const [
                                  FontVariation('wght', 500),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hint!,
                              style: tokens.bodySmall.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: GerfautSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Puts its child on the first line of a paragraph in [style], however
/// many lines that paragraph runs to.
///
/// The box is exactly one line tall, and the child is centred in it. The
/// theme distributes a line's spare leading evenly, so the centre of a
/// line box is the optical centre of its glyphs: centring the icon there
/// puts the two optical centres on each other, at any text scale. That
/// is why this is a measurement and not a two-pixel nudge — a nudge is
/// right for one font size and wrong for every other.
class _FirstLine extends StatelessWidget {
  const _FirstLine({required this.style, required this.child});

  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: scaler.scale(style.fontSize!) * style.height!,
      child: Center(child: child),
    );
  }
}
