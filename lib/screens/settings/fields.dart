import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';

/// A field for an identifier: a host, a port, a URL, a count. Mono, so
/// a `0` and an `O` never trade places, at the body size so the phone
/// never zooms the page to read it.
class MonoField extends StatelessWidget {
  const MonoField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.tokens,
    this.numeric = false,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final GerfautTokens tokens;
  final bool numeric;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.url,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: tokens.data.copyWith(
          fontSize: tokens.body.fontSize,
          color: tokens.textMuted,
        ),
        filled: true,
        fillColor: tokens.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GerfautSpacing.md,
          vertical: GerfautSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GerfautRadius.sm),
          borderSide: BorderSide(color: tokens.primary, width: 2),
        ),
      ),
    );
  }
}
