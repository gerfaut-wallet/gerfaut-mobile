import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';

/// A field for an identifier: a host, a port, a URL, a count. Mono, so
/// a `0` and an `O` never trade places, at the body size so the phone
/// never zooms the page to read it.
class MonoField extends StatelessWidget {
  const MonoField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.tokens,
    this.numeric = false,
    this.focusNode,
    this.onSubmitted,
  });

  /// What a screen reader calls the field. The caption above it is a
  /// widget of its own, and the hint is an example: read alone, a field
  /// is "node.example.org, edit box", which names nothing.
  final String label;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final GerfautTokens tokens;
  final bool numeric;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  /// The width a field needs to show [characters] whole at the text
  /// size in force: that many digits measured in the field's own style,
  /// plus its padding and the caret, and never under [atLeast]. A width
  /// fixed at one text size cut the value at a larger one ("50005" at
  /// twice the size).
  static double widthFor(
    BuildContext context,
    GerfautTokens tokens, {
    required int characters,
    double atLeast = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: '0' * characters, style: _style(tokens)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * (GerfautSpacing.md + _gap) + _caretRoom;
    painter.dispose();
    return width < atLeast ? atLeast : width;
  }

  /// The caret and the gap it keeps after the last character.
  static const double _caretRoom = 6;

  /// What Material adds inside an outlined field, each side, past the
  /// content padding: the border's gap, given here so it is known.
  static const double _gap = 4;

  static TextStyle _style(GerfautTokens tokens) =>
      tokens.data.copyWith(fontSize: tokens.body.fontSize);

  @override
  Widget build(BuildContext context) {
    return Semantics(label: label, child: _field());
  }

  Widget _field() {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autocorrect: false,
      enableSuggestions: false,
      // Often the user's own node: not a word for the keyboard to keep.
      enableIMEPersonalizedLearning: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.url,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: _style(tokens),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _style(tokens).copyWith(color: tokens.textMuted),
        filled: true,
        fillColor: tokens.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GerfautSpacing.md,
          vertical: GerfautSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide.none,
          gapPadding: _gap,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide(color: tokens.primary, width: 2),
          gapPadding: _gap,
        ),
      ),
    );
  }
}
