import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/load_failure.dart';

/// What a section shows in place of its controls until the vault's
/// settings are in, and when they cannot be read.
///
/// Controls drawn from settings that have not arrived show a false
/// state (a lock switch that reads off, a list of wallets that reads
/// empty), and a bare "Loading…" that never ends reads as a hang when
/// the read failed. A failure names itself and offers another try.
class SettingsPending extends ConsumerWidget {
  const SettingsPending({super.key, required this.what});

  /// The subject of the failure sentence: "The network settings".
  final String what;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider);
    // A retry is loading again with the old error still behind it.
    if (settings.hasError && !settings.isLoading) {
      return LoadFailure(
        what: what,
        error: settings.error,
        onRetry: () => ref.invalidate(settingsProvider),
        centered: false,
      );
    }
    return Text(
      'Loading…',
      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
    );
  }
}

/// A field for an identifier: a host, a port, a URL. Mono, so a `0` and
/// an `O` never trade places, at the body size so the phone never zooms
/// the page to read it.
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

  /// The width the field needs to show [characters] whole at the text
  /// size in force, and never under [atLeast].
  static double widthFor(
    BuildContext context,
    GerfautTokens tokens, {
    required int characters,
    double atLeast = 0,
  }) => _widthFor(
    context,
    _style(tokens),
    characters: characters,
    atLeast: atLeast,
  );

  static TextStyle _style(GerfautTokens tokens) =>
      tokens.data.copyWith(fontSize: tokens.body.fontSize);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: _SettingField(
        controller: controller,
        focusNode: focusNode,
        hint: hint,
        style: _style(tokens),
        tokens: tokens,
        numeric: numeric,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// A field for a count. A count is read, not checked character by
/// character: it is set in the interface face with tabular figures,
/// against the right edge, as a column of amounts is.
class CountField extends StatelessWidget {
  const CountField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.tokens,
    this.focusNode,
    this.onSubmitted,
  });

  /// What a screen reader calls the field.
  final String label;
  final TextEditingController controller;
  final String hint;
  final GerfautTokens tokens;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  /// The width the field needs to show [characters] whole at the text
  /// size in force, and never under [atLeast].
  static double widthFor(
    BuildContext context,
    GerfautTokens tokens, {
    required int characters,
    double atLeast = 0,
  }) => _widthFor(
    context,
    _style(tokens),
    characters: characters,
    atLeast: atLeast,
  );

  static TextStyle _style(GerfautTokens tokens) =>
      tokens.figureOf(size: tokens.body.fontSize!);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: _SettingField(
        controller: controller,
        focusNode: focusNode,
        hint: hint,
        style: _style(tokens),
        tokens: tokens,
        numeric: true,
        textAlign: TextAlign.end,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// The caret and the gap it keeps after the last character.
const double _caretRoom = 6;

/// What Material adds inside an outlined field, each side, past the
/// content padding: the border's gap, given here so it is known.
const double _gap = 4;

/// The width a field needs to show [characters] whole at the text size
/// in force: that many digits measured in the field's own style, plus
/// its padding and the caret, and never under [atLeast]. A width fixed
/// at one text size cut the value at a larger one ("50005" at twice the
/// size).
double _widthFor(
  BuildContext context,
  TextStyle style, {
  required int characters,
  required double atLeast,
}) {
  // What the field draws in: the theme's body style under its own, as
  // TextField merges them, letter spacing included.
  final drawn = Theme.of(context).textTheme.bodyLarge!.merge(style);
  final painter = TextPainter(
    text: TextSpan(text: '0' * characters, style: drawn),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width + 2 * (GerfautSpacing.md + _gap) + _caretRoom;
  painter.dispose();
  return width < atLeast ? atLeast : width;
}

/// The sunken field of the settings, whatever it is set in.
class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.controller,
    required this.hint,
    required this.style,
    required this.tokens,
    required this.numeric,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final TextStyle style;
  final GerfautTokens tokens;
  final bool numeric;
  final TextAlign textAlign;
  final FocusNode? focusNode;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
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
      style: style,
      textAlign: textAlign,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: style.copyWith(color: tokens.textMuted),
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
