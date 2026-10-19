import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'tap_target.dart';

// Every labelled button is filled: a word alone, with no fill and no
// edge, does not read as something to press.
//
// - [PrimaryButton]: an action that stands on its own, the action of a
//   card, a form that saves, the yes of a dialog. Every one of them,
//   not one per screen; when two sit side by side, the one people come
//   for is primary and the other secondary.
// - [SecondaryButton]: the way out beside a primary (Cancel, Back,
//   Later, Skip), one of several equal choices, and the actions a list
//   repeats on every row.
// - [DangerButton]: the yes of a confirmation that erases, never the
//   button that opens it.
// - [DisclosureButton]: shows or hides the part of the page under it.
//   It does nothing, it shows, so it is the one labelled button left
//   without a fill.
//
// Every button here is drawn [GerfautTouch.control] tall and answers the
// finger over [GerfautTouch.target]: the extra height is invisible
// padding, so a tap just above or below the button still presses it.

/// An action that stands on its own: Glacier fill, a darker Glacier
/// under the finger.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;

  /// Null switches the button off: half its strength, nothing on press.
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Fills the available width: the thumb-reachable bottom action.
  final bool expand;

  /// Working on it: a spinner takes the icon's place and the button
  /// keeps its full colour, since it is not off but busy. Presses are
  /// ignored. The label says what is going on ("Saving…").
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: tokens.primary,
      pressedFill: tokens.primaryPressed,
      ink: tokens.onPrimary,
    );
  }
}

/// The second choice, which is still a button: Givre fill, no border.
///
/// On a tinted panel (a notice, see [TintedSurface]) the Givre would
/// read as a dirty grey in the light theme, so it takes the card white
/// with a hairline instead. The dark theme keeps its fill there, the
/// panel being the card surface.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// As [PrimaryButton.busy].
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onTint = !dark && TintedSurface.of(context);
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: onTint ? tokens.surface : tokens.surfaceSunken,
      // Brume at 60% over the fill, as the desktop's hover; on a tint,
      // the page canvas under the white.
      pressedFill: onTint
          ? tokens.background
          : Color.alphaBlend(
              tokens.border.withValues(alpha: 0.6),
              tokens.surfaceSunken,
            ),
      ink: tokens.text,
      edge: onTint ? tokens.border : null,
    );
  }
}

/// The yes of a confirmation that erases, and nothing else: the
/// primary's form in the alert colour. The button that opens the
/// confirmation stays a [SecondaryButton]; red appears at the yes.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  /// As [PrimaryButton.busy].
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return _FilledAction(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expand: expand,
      busy: busy,
      fill: tokens.alert,
      pressedFill: tokens.alertPressed,
      ink: tokens.onAlert,
    );
  }
}

/// Shows or hides the part of the page under it: a chevron, then the
/// label in Ardoise, Givre under the finger. Not an action, so no fill;
/// a fill would make it pass for one. Read out with whether it is open.
class DisclosureButton extends StatelessWidget {
  const DisclosureButton({
    super.key,
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;

  /// Whether what it folds is shown: the chevron points up, and a screen
  /// reader says "expanded".
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // One node: the button, and whether what it folds is open.
    return MergeSemantics(
      child: Semantics(
        expanded: open,
        child: TapTarget(
          child: SizedBox(
            height: GerfautTouch.control,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: tokens.textMuted,
                overlayColor: tokens.surfaceSunken,
                padding: const EdgeInsets.symmetric(
                  horizontal: GerfautSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GerfautRadius.md),
                ),
                textStyle: _labelStyle(tokens),
              ),
              onPressed: onPressed,
              child: _Content(
                label: label,
                leading: Icon(
                  open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: _glyph,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks a tinted panel, a notice, for the buttons inside it: a
/// [SecondaryButton] there takes white and a hairline instead of Givre.
/// The panel sets it once, so no caller has to remember.
class TintedSurface extends InheritedWidget {
  const TintedSurface({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TintedSurface>() != null;

  @override
  bool updateShouldNotify(TintedSurface oldWidget) => false;
}

/// The two buttons that close a confirmation: the way out and the deed,
/// in that order, the deed at the end where the thumb expects the last
/// word.
///
/// A Wrap and not a Row: at a large text size two labels do not share
/// a line on a phone, and the deed then goes to a line of its own under
/// the way out rather than past the edge of the panel. Aligned to the
/// end whichever column it sits in.
class ConfirmActions extends StatelessWidget {
  const ConfirmActions({
    super.key,
    required this.cancel,
    required this.confirm,
  });

  final Widget cancel;
  final Widget confirm;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: GerfautSpacing.sm,
        runSpacing: GerfautSpacing.sm,
        children: [cancel, confirm],
      ),
    );
  }
}

/// The glyph before a label, and the spinner that takes its place.
const double _glyph = 16;

TextStyle _labelStyle(GerfautTokens tokens) => tokens.bodySmall.copyWith(
  fontWeight: FontWeight.w500,
  fontVariations: const [FontVariation('wght', 500)],
);

/// The one filled button the three variants draw: geometry, press,
/// busy, off and focus in one place, so no screen styles its own.
class _FilledAction extends StatefulWidget {
  const _FilledAction({
    required this.label,
    required this.onPressed,
    required this.icon,
    required this.expand,
    required this.busy,
    required this.fill,
    required this.pressedFill,
    required this.ink,
    this.edge,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool busy;
  final Color fill;
  final Color pressedFill;
  final Color ink;

  /// A hairline around the fill, for the secondary on a tint.
  final Color? edge;

  @override
  State<_FilledAction> createState() => _FilledActionState();
}

class _FilledActionState extends State<_FilledAction>
    with SingleTickerProviderStateMixin {
  /// A finger is down on it: the button gives a little.
  bool _pressed = false;

  /// Focused from a keyboard: the ring shows.
  bool _focused = false;

  /// One turn of the spinner a second, while busy.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _turn();
  }

  @override
  void didUpdateWidget(_FilledAction old) {
    super.didUpdateWidget(old);
    if (old.busy != widget.busy) _turn();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  /// The spinner turns while busy, unless the phone asks for less
  /// motion: then it stands still and the label carries the state.
  void _turn() {
    if (widget.busy && !MediaQuery.disableAnimationsOf(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final still = MediaQuery.disableAnimationsOf(context);
    final busy = widget.busy;
    final off = widget.onPressed == null && !busy;
    final radius = BorderRadius.circular(GerfautRadius.md);
    final edge = widget.edge;

    final style =
        FilledButton.styleFrom(
          foregroundColor: widget.ink,
          // Busy keeps its colour, and off fades as a whole below: the
          // fill never turns into another button's grey.
          disabledBackgroundColor: widget.fill,
          disabledForegroundColor: widget.ink,
          elevation: 0,
          // Under the finger the fill itself darkens; no ripple on top.
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: edge == null ? BorderSide.none : BorderSide(color: edge),
          ),
          textStyle: _labelStyle(tokens),
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? widget.pressedFill
                : widget.fill,
          ),
        );

    final Widget? leading = busy
        ? RotationTransition(
            turns: _spin,
            child: const Icon(LucideIcons.loaderCircle, size: _glyph),
          )
        : widget.icon == null
        ? null
        : Icon(widget.icon, size: _glyph);

    final live = !busy && widget.onPressed != null;
    void press(bool down) {
      if (_pressed != down) setState(() => _pressed = down);
    }

    // Pressed, the button gives a little (0.96, never less); focused
    // from a keyboard, it gets the 2px Glacier ring, 2px out, which
    // stands clear of a filled button in both themes. Only in the
    // keyboard's highlight mode: a touch never shows a ring.
    final ring =
        _focused &&
        live &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    Widget button = CustomPaint(
      foregroundPainter: ring
          ? _FocusRing(color: tokens.primary, radius: GerfautRadius.md)
          : null,
      child: Listener(
        onPointerDown: live ? (_) => press(true) : null,
        onPointerUp: (_) => press(false),
        onPointerCancel: (_) => press(false),
        child: AnimatedScale(
          scale: _pressed && live && !still ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: FilledButton(
            style: style,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            onPressed: live ? widget.onPressed : null,
            child: _Content(label: widget.label, leading: leading),
          ),
        ),
      ),
    );

    if (off) button = Opacity(opacity: 0.5, child: button);

    return TapTarget(
      child: SizedBox(
        height: GerfautTouch.control,
        width: widget.expand ? double.infinity : null,
        child: button,
      ),
    );
  }
}

/// The glyph, if any, then the label. The height is fixed, so a label
/// wider than the phone at a large text size gives ground at its end
/// rather than running past the button.
class _Content extends StatelessWidget {
  const _Content({required this.label, required this.leading});

  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    if (leading == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: GerfautSpacing.sm),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The keyboard focus ring, drawn outside the button so it does not
/// move the layout.
class _FocusRing extends CustomPainter {
  const _FocusRing({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _width = 2;
  static const double _gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final out = _gap + _width / 2;
    final rect = (Offset.zero & size).inflate(out);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + out)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width,
    );
  }

  @override
  bool shouldRepaint(_FocusRing old) =>
      old.color != color || old.radius != radius;
}

/// Tertiary action: transparent, muted text. A deletion is this plus an
/// explicit confirmation — never a red button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// For a button that folds a part of the page in and out: whether it
  /// is open, said to a screen reader with the button. Null for any
  /// other button.
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final expanded = this.expanded;
    final button = _button(context);
    if (expanded == null) return button;
    // One node: the button, and whether what it folds is open.
    return MergeSemantics(
      child: Semantics(expanded: expanded, child: button),
    );
  }

  Widget _button(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return TapTarget(
      child: SizedBox(
        height: GerfautTouch.control,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: tokens.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GerfautRadius.md),
            ),
            textStyle: tokens.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
              fontVariations: const [FontVariation('wght', 500)],
            ),
          ),
          onPressed: onPressed,
          child: icon == null
              ? Text(label)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: GerfautSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

