// The calculator: what the app is while it is disguised, and its lock
// screen.
//
// This screen is the one deliberate exception to the design system. It
// has to pass for any calculator on any phone, so it shares nothing
// with Gerfaut: no Toundra colour, no Bricolage or Instrument face, no
// lucide glyph, no falcon. Its palette lives in this file and nowhere
// else, its type is the platform's own, its keys are plain Material.
//
// Why a calculator stands in for the lock screen at all: on Android 10
// and later an app that hides its launcher icon is not gone from the
// launcher — the system shows a synthesized entry named after the app
// in its place. A disguise therefore has to be another launcher entry,
// and whoever opens that entry must find what it promised. So the
// calculator is real. Typing the PIN and = is what opens the wallet. A
// wrong PIN, or one tried during the delay the core imposes after three
// failures, shows the number, the way any calculator would: no message,
// no hint, no vibration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/calculator.dart';
import '../src/lock.dart';

class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  /// The bounds of a PIN, the ones the lock sheet enforces. A bare
  /// number outside them is arithmetic, never a guess: asking the core
  /// about it would only wind its delay up.
  static const int minPinLength = 4;
  static const int maxPinLength = 12;

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final _calc = Calculator();

  /// The core is being asked about a number; = waits its turn.
  bool _checking = false;

  Future<void> _equals() async {
    if (_checking) return;
    final digits = _calc.bareDigits;
    if (digits != null &&
        digits.length >= CalculatorScreen.minPinLength &&
        digits.length <= CalculatorScreen.maxPinLength) {
      setState(() => _checking = true);
      try {
        final verdict = await ref.read(lockProvider.notifier).unlock(digits);
        // Unlocked, the gate replaces this screen with the app.
        if (verdict.unlocked) return;
      } catch (_) {
        // No lock to open, or a core that would not answer: a calculator.
      } finally {
        if (mounted) setState(() => _checking = false);
      }
      if (!mounted) return;
    }
    setState(_calc.equals);
  }

  void _press(void Function() key) => setState(key);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = dark ? _Palette.dark : _Palette.light;
    // A theme of its own, without the app's font: the platform's type is
    // the one every other calculator on this phone is set in.
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final display = _Display(
                  history: _calc.history,
                  value: _calc.display,
                  palette: palette,
                );
                final keypad = _Keypad(
                  palette: palette,
                  onDigit: (d) => _press(() => _calc.digit(d)),
                  onDecimal: () => _press(_calc.decimal),
                  onOperator: (op) => _press(() => _calc.operator(op)),
                  onPercent: () => _press(_calc.percent),
                  onNegate: () => _press(_calc.negate),
                  onClear: () => _press(_calc.clear),
                  onBackspace: () => _press(_calc.backspace),
                  onEquals: _equals,
                );
                // Landscape puts the keys beside the display: five rows
                // still have to be 48dp each on a phone turned sideways.
                if (constraints.maxWidth > constraints.maxHeight) {
                  return Row(
                    children: [
                      Expanded(child: display),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: keypad),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 2, child: display),
                    const SizedBox(height: 16),
                    Expanded(flex: 5, child: keypad),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The history line and the number, right-aligned at the bottom of the
/// space they are given. A long number shrinks rather than wraps.
class _Display extends StatelessWidget {
  const _Display({
    required this.history,
    required this.value,
    required this.palette,
  });

  final String history;
  final String value;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          history,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 20, color: palette.muted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                color: palette.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.palette,
    required this.onDigit,
    required this.onDecimal,
    required this.onOperator,
    required this.onPercent,
    required this.onNegate,
    required this.onClear,
    required this.onBackspace,
    required this.onEquals,
  });

  final _Palette palette;
  final void Function(int) onDigit;
  final VoidCallback onDecimal;
  final void Function(CalcOp) onOperator;
  final VoidCallback onPercent;
  final VoidCallback onNegate;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final VoidCallback onEquals;

  @override
  Widget build(BuildContext context) {
    _Key digit(int d) => _Key('$d', onTap: () => onDigit(d));
    _Key op(CalcOp o, String name) => _Key(
      o.symbol,
      semantics: name,
      role: _KeyRole.function,
      onTap: () => onOperator(o),
    );
    final rows = <List<_Key>>[
      [
        _Key('C', semantics: 'Clear', role: _KeyRole.function, onTap: onClear),
        _Key(
          '⌫',
          semantics: 'Backspace',
          role: _KeyRole.function,
          onTap: onBackspace,
        ),
        _Key(
          '%',
          semantics: 'Percent',
          role: _KeyRole.function,
          onTap: onPercent,
        ),
        op(CalcOp.divide, 'Divide'),
      ],
      [digit(7), digit(8), digit(9), op(CalcOp.multiply, 'Multiply')],
      [digit(4), digit(5), digit(6), op(CalcOp.subtract, 'Minus')],
      [digit(1), digit(2), digit(3), op(CalcOp.add, 'Plus')],
      [
        _Key('±', semantics: 'Change sign', onTap: onNegate),
        digit(0),
        _Key('.', semantics: 'Decimal point', onTap: onDecimal),
        _Key('=', semantics: 'Equals', role: _KeyRole.equals, onTap: onEquals),
      ],
    ];
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _KeyButton(data: key, palette: palette),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _KeyRole { digit, function, equals }

class _Key {
  const _Key(
    this.label, {
    required this.onTap,
    this.semantics,
    this.role = _KeyRole.digit,
  });

  final String label;
  final String? semantics;
  final _KeyRole role;
  final VoidCallback onTap;
}

/// One key: a rounded Material surface, ink on tap, a large glyph.
class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.data, required this.palette});

  final _Key data;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final (Color surface, Color ink) = switch (data.role) {
      _KeyRole.digit => (palette.digitKey, palette.digitText),
      _KeyRole.function => (palette.functionKey, palette.functionText),
      _KeyRole.equals => (palette.equalsKey, palette.onEquals),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              data.label,
              semanticsLabel: data.semantics,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w400,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The calculator's own colours. Material greys and an indigo, the way a
/// stock calculator looks; nothing from the Toundra palette, on purpose.
class _Palette {
  const _Palette({
    required this.background,
    required this.text,
    required this.muted,
    required this.digitKey,
    required this.digitText,
    required this.functionKey,
    required this.functionText,
    required this.equalsKey,
    required this.onEquals,
  });

  final Color background;
  final Color text;
  final Color muted;
  final Color digitKey;
  final Color digitText;
  final Color functionKey;
  final Color functionText;
  final Color equalsKey;
  final Color onEquals;

  static const light = _Palette(
    background: Color(0xFFF5F5F5),
    text: Color(0xFF212121),
    muted: Color(0xFF757575),
    digitKey: Color(0xFFFFFFFF),
    digitText: Color(0xFF212121),
    functionKey: Color(0xFFE0E0E0),
    functionText: Color(0xFF424242),
    equalsKey: Color(0xFF3F51B5),
    onEquals: Color(0xFFFFFFFF),
  );

  static const dark = _Palette(
    background: Color(0xFF121212),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFF9E9E9E),
    digitKey: Color(0xFF2A2A2A),
    digitText: Color(0xFFFFFFFF),
    functionKey: Color(0xFF3A3A3A),
    functionText: Color(0xFFE0E0E0),
    equalsKey: Color(0xFF5C6BC0),
    onEquals: Color(0xFFFFFFFF),
  );
}
