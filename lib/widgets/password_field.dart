import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// A secret typed once and typed again elsewhere: hidden by default,
/// revealed on demand.
///
/// The eye is not a convenience. A backup password has to be retyped on
/// another device, and there is no way to recover it: whoever sets one
/// must be able to read what they typed before they commit to it.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  /// Caption above the field, also what assistive technology reads.
  final String label;
  final TextEditingController controller;

  /// Set when the screen has to put the caret here itself.
  final FocusNode? focusNode;
  final VoidCallback? onChanged;

  /// Keyboard action; null leaves the key inert.
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: tokens.label.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _hidden,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          // 16px, or the field zooms on some keyboards.
          style: tokens.body,
          onChanged: (_) => widget.onChanged?.call(),
          onSubmitted: (_) => widget.onSubmitted?.call(),
          textInputAction: widget.onSubmitted == null
              ? TextInputAction.next
              : TextInputAction.done,
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: GerfautSpacing.md,
              vertical: GerfautSpacing.sm + GerfautSpacing.xs,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GerfautRadius.sm),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GerfautRadius.sm),
              borderSide: BorderSide(color: tokens.primary, width: 2),
            ),
            suffixIcon: IconButton(
              tooltip: _hidden
                  ? 'Show ${widget.label}'
                  : 'Hide ${widget.label}',
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(
                _hidden ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 18,
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
