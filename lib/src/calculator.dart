// A pocket calculator, and nothing of a wallet.
//
// This is the arithmetic behind the calculator screen, the face Gerfaut
// wears while disguised. It is a real calculator: four operations,
// percent, sign, decimals, one line of history. Precedence is the one
// a scientific pocket calculator has: × and ÷ bind before + and −, and
// equal operators run left to right, so 2 + 3 × 4 is 14 and 10 − 2 − 3
// is 5. Percent turns the number under entry into a fraction: of the
// pending left operand after + or − (200 + 10 % is 220), of one
// otherwise (50 % is 0.5, 200 × 10 % is 20). Division by zero shows
// "Error" until the next digit or a clear.
//
// The digits are kept exactly as typed, leading zeros included: the
// screen reads them back as a PIN when = is pressed on a bare number,
// and 0042 is not 42 to a lock.

/// The four operations, with the glyph each shows.
enum CalcOp {
  add('+'),
  subtract('−'),
  multiply('×'),
  divide('÷');

  const CalcOp(this.symbol);

  final String symbol;
}

class Calculator {
  /// The number under entry, as typed: an optional leading '-', digits,
  /// at most one '.'. Empty when the display shows a result or nothing.
  String _entry = '';

  /// Whether [_entry] was typed key by key rather than produced by a
  /// percent or a sign change of a result. A produced number is taken
  /// whole by the next digit or backspace, the way a result is.
  bool _typed = false;

  /// The expression so far, numbers and operators alternating. While a
  /// number is being typed it ends with the operator waiting for it.
  final List<Object> _tokens = [];

  /// The value of the last expression, shown while nothing is typed.
  double? _result;

  bool _error = false;
  String _history = '';

  /// Keys are ignored past this many characters of entry.
  static const int maxEntryLength = 15;

  /// What the main line shows.
  String get display {
    if (_error) return 'Error';
    if (_entry.isNotEmpty) return formatEntry(_entry);
    if (_result != null) return formatValue(_result!);
    return '0';
  }

  /// The line above the display: the expression under way while there
  /// is one, otherwise the last expression evaluated, with its =.
  String get history {
    if (_tokens.isNotEmpty) return _render(_tokens);
    return _history;
  }

  bool get hasError => _error;

  /// The typed digits when the entry is a bare number — digits only, no
  /// sign, no decimal point, no operator before it — and null otherwise.
  /// This is what the screen tries as a PIN.
  String? get bareDigits {
    if (_tokens.isNotEmpty || !_typed) return null;
    return RegExp(r'^\d+$').hasMatch(_entry) ? _entry : null;
  }

  void digit(int digit) {
    if (_error) _reset();
    if (!_typed) {
      // A result, or a number percent produced, gives way to a new one.
      _entry = '';
      _result = null;
    }
    if (_entry.length >= maxEntryLength) return;
    _entry += '$digit';
    _typed = true;
  }

  void decimal() {
    if (_error) _reset();
    if (!_typed || _entry.isEmpty) {
      _entry = '0.';
      _result = null;
      _typed = true;
      return;
    }
    if (_entry.contains('.')) return;
    _entry += '.';
  }

  void operator(CalcOp op) {
    if (_error) return;
    if (_entry.isNotEmpty) {
      _tokens
        ..add(_value(_entry))
        ..add(op);
      _entry = '';
      _typed = false;
    } else if (_tokens.isNotEmpty) {
      // Two operators in a row: the second one is meant.
      _tokens[_tokens.length - 1] = op;
    } else {
      // An operator on a result carries the result on; on nothing, 0.
      _tokens
        ..add(_result ?? 0)
        ..add(op);
    }
    _result = null;
  }

  void percent() {
    if (_error) return;
    final double value;
    if (_entry.isNotEmpty) {
      value = _value(_entry);
    } else if (_result != null) {
      value = _result!;
    } else {
      return;
    }
    var base = 1.0;
    if (_tokens.isNotEmpty) {
      final op = _tokens.last as CalcOp;
      if (op == CalcOp.add || op == CalcOp.subtract) {
        base = _evaluate(_tokens.sublist(0, _tokens.length - 1));
      }
    }
    _produce(base * value / 100);
  }

  void negate() {
    if (_error) return;
    if (_entry.isNotEmpty) {
      _entry = _entry.startsWith('-') ? _entry.substring(1) : '-$_entry';
      return;
    }
    if (_result != null) _produce(-_result!);
  }

  /// Clears everything, the history line included.
  void clear() {
    _reset();
    _history = '';
  }

  void backspace() {
    if (_error) {
      _reset();
      return;
    }
    if (_entry.isNotEmpty) {
      if (!_typed) {
        _entry = '';
        return;
      }
      _entry = _entry.substring(0, _entry.length - 1);
      if (_entry == '-') _entry = '';
      return;
    }
    if (_result != null) {
      _result = null;
      return;
    }
    if (_tokens.isNotEmpty) {
      // Taking back an operator hands its left operand back to the entry.
      _tokens.removeLast();
      _produce(_tokens.removeLast() as double);
    }
  }

  void equals() {
    if (_error) return;
    if (_entry.isNotEmpty) {
      _tokens.add(_value(_entry));
    } else if (_tokens.isNotEmpty) {
      // "5 + =" is 5: an operator with nothing after it is dropped.
      _tokens.removeLast();
    } else {
      return;
    }
    final expression = _tokens.toList();
    final value = _evaluate(expression);
    _history = '${_render(expression)} =';
    _entry = '';
    _typed = false;
    _tokens.clear();
    if (value.isNaN || value.isInfinite) {
      _error = true;
      _result = null;
    } else {
      _result = value;
    }
  }

  void _reset() {
    _entry = '';
    _typed = false;
    _tokens.clear();
    _result = null;
    _error = false;
  }

  /// Puts a computed number in the entry, as a result would sit there:
  /// shown, carried into the next operator, replaced by the next digit.
  void _produce(double value) {
    if (value.isNaN || value.isInfinite) {
      _reset();
      _error = true;
      return;
    }
    _entry = _plain(value);
    _typed = false;
    _result = null;
  }

  static double _value(String entry) {
    var text = entry;
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    if (text.isEmpty || text == '-') return 0;
    return double.parse(text);
  }

  /// × and ÷ first, left to right, then + and −, left to right.
  static double _evaluate(List<Object> tokens) {
    if (tokens.isEmpty) return 0;
    final values = <double>[tokens.first as double];
    final ops = <CalcOp>[];
    for (var i = 1; i < tokens.length; i += 2) {
      final op = tokens[i] as CalcOp;
      final right = tokens[i + 1] as double;
      if (op == CalcOp.multiply || op == CalcOp.divide) {
        values[values.length - 1] = _apply(op, values.last, right);
      } else {
        ops.add(op);
        values.add(right);
      }
    }
    var total = values.first;
    for (var i = 0; i < ops.length; i++) {
      total = _apply(ops[i], total, values[i + 1]);
    }
    return total;
  }

  static double _apply(CalcOp op, double left, double right) => switch (op) {
    CalcOp.add => left + right,
    CalcOp.subtract => left - right,
    CalcOp.multiply => left * right,
    CalcOp.divide => left / right,
  };

  static String _render(List<Object> tokens) => tokens
      .map((t) => t is CalcOp ? t.symbol : formatValue(t as double))
      .join(' ');

  /// A value as an entry string: what [_value] parses and [formatEntry]
  /// shows, without grouping.
  static String _plain(double value) {
    if (value == value.truncateToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    return _trim(value.toStringAsPrecision(12));
  }

  /// An entry the way the display shows it: leading zeros dropped,
  /// thousands grouped, the decimal part exactly as typed.
  static String formatEntry(String entry) {
    final negative = entry.startsWith('-');
    final body = negative ? entry.substring(1) : entry;
    final dot = body.indexOf('.');
    var integer = dot < 0 ? body : body.substring(0, dot);
    integer = integer.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (integer.isEmpty) integer = '0';
    final fraction = dot < 0 ? '' : body.substring(dot);
    return '${negative ? '-' : ''}${_group(integer)}$fraction';
  }

  /// A result the way the display shows it: twelve significant digits
  /// at most, trailing zeros gone, thousands grouped. Very large and
  /// very small values fall back to a short exponent form.
  static String formatValue(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';
    if (value == 0) return '0';
    final magnitude = value.abs();
    if (magnitude >= 1e15 || magnitude < 1e-9) {
      return _trim(value.toStringAsExponential(6));
    }
    var text = value.toStringAsPrecision(12);
    if (text.contains('e')) text = value.toStringAsFixed(10);
    text = _trim(text);
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    final parts = body.split('.');
    final integer = _group(parts.first);
    final fraction = parts.length > 1 ? '.${parts[1]}' : '';
    return '${negative ? '-' : ''}$integer$fraction';
  }

  /// Drops the trailing zeros of a decimal part, and the point with them
  /// when nothing is left; leaves an exponent, if any, in place.
  static String _trim(String text) {
    final e = text.indexOf('e');
    var mantissa = e < 0 ? text : text.substring(0, e);
    final exponent = e < 0 ? '' : text.substring(e);
    if (mantissa.contains('.')) {
      mantissa = mantissa
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '$mantissa$exponent';
  }

  static String _group(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final left = digits.length - i;
      if (i > 0 && left % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
