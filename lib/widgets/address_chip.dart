import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../theme/tokens.dart';

/// Address or txid shown inline: Givre surface, mono 13px, truncated in
/// the middle only. Tap copies the full value with explicit feedback —
/// the icon flips to a check for 1.5 s and the word `Copied` appears.
///
/// The chip keeps the width it had while that word is showing. It sits
/// in a [Wrap] on the transaction detail, and a chip that grows pushes
/// the date beside it onto the next line and back again a second and a
/// half later. The word takes its room from the identifier instead —
/// already truncated, and not what anyone is reading at the moment they
/// have just copied it.
///
/// The truncation is fitted to the room, never faded: a chip too narrow
/// for `bc1q…306fyu` used to draw `bc1q…306fy` and half a `u` under the
/// copy icon, which is a different address. It drops a character from
/// the ends instead, so what is on screen is always exactly what is
/// there.
class AddressChip extends StatefulWidget {
  const AddressChip({
    super.key,
    required this.value,
    this.head = 6,
    this.tail = 4,
    this.emphasis = false,
    this.kind,
    this.spoken,
  });

  final String value;
  final int head;
  final int tail;

  /// What the value is, said before it to a screen reader: "address",
  /// "outpoint". Null says the value alone.
  final String? kind;

  /// What a screen reader says in place of the whole value, when the
  /// whole of it is noise rather than something to check: the 64 hex
  /// characters of a txid, read one by one. An address is always said
  /// in full, since hearing it is how it is checked.
  final String? spoken;

  /// Wallet-owned address: primary wash and full-strength medium text,
  /// so "mine" reads against the muted external gray (desktop mirror).
  final bool emphasis;

  @override
  State<AddressChip> createState() => _AddressChipState();
}

class _AddressChipState extends State<AddressChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  /// The longest truncation of the value that fits [room], both ends
  /// kept. Under an unbounded width — a chip in a [Wrap] — the asked-for
  /// truncation stands. Below the floor there is nothing left worth
  /// comparing, so the fade takes over.
  String _fitted(double room, TextStyle style, TextScaler scaler) {
    var head = widget.head;
    var tail = widget.tail;
    var shown = truncateMiddle(widget.value, head: head, tail: tail);
    if (!room.isFinite) return shown;
    // A pixel of margin: a measurement that lands a hair under the paint
    // fades the last glyph, and half a character of an address is worse
    // than one character fewer.
    while (_widthOf(shown, style, scaler) > room - 1 && head + tail > 8) {
      if (head > tail) {
        head--;
      } else {
        tail--;
      }
      shown = truncateMiddle(widget.value, head: head, tail: tail);
    }
    return shown;
  }

  /// Width one line of text takes in the style it will be drawn in,
  /// at the reader's text scale.
  static double _widthOf(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final scaler = MediaQuery.textScalerOf(context);
    final shown = truncateMiddle(
      widget.value,
      head: widget.head,
      tail: widget.tail,
    );
    final valueStyle = widget.emphasis
        ? tokens.data.copyWith(
            color: tokens.text,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          )
        : tokens.data.copyWith(color: tokens.textMuted);
    final copiedStyle = tokens.label.copyWith(color: tokens.confirmed);
    // What the word and its own gap will occupy, given back by the
    // identifier so the chip's outer width never moves.
    final valueWidth = _widthOf(shown, valueStyle, scaler);
    // Only while the word is showing: capping at the measured width the
    // rest of the time buys nothing and costs a glyph, since a measured
    // width lands a hair under the painted one.
    final maxValueWidth = _copied
        ? math.max(
            0.0,
            valueWidth -
                _widthOf('Copied', copiedStyle, scaler) -
                GerfautSpacing.xs,
          )
        : double.infinity;
    return Semantics(
      button: true,
      label: [
        'Copy',
        if (widget.kind != null) widget.kind!,
        widget.spoken ?? widget.value,
      ].join(' '),
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        onTap: _copy,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.sm,
            vertical: GerfautSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.emphasis
                ? tokens.primary.withValues(alpha: 0.10)
                : tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible on the outside so a narrow parent can still
              // squeeze the chip; the cap on the inside is what keeps
              // the confirmation from widening it.
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxValueWidth),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Text(
                      _fitted(constraints.maxWidth, valueStyle, scaler),
                      style: valueStyle,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Icon(
                _copied ? LucideIcons.check : LucideIcons.copy,
                size: 14,
                color: _copied ? tokens.confirmed : tokens.textMuted,
              ),
              if (_copied) ...[
                const SizedBox(width: GerfautSpacing.xs),
                Text('Copied', style: copiedStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
