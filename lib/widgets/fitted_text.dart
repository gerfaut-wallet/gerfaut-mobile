import 'package:flutter/widgets.dart';

import '../src/format.dart';

/// Width one line of [text] takes in the style it will be drawn in, at
/// the reader's text scale.
double textWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The longest middle truncation of [value] that fits [room], both ends
/// kept: it drops a whole character from the longer end until it does.
/// Under an unbounded width the asked-for truncation stands. It stops
/// at [floor] characters kept in all: below that there is nothing left
/// worth comparing.
String fitMiddle(
  String value,
  double room,
  TextStyle style,
  TextScaler scaler, {
  required int head,
  required int tail,
  int floor = 8,
}) {
  var shown = truncateMiddle(value, head: head, tail: tail);
  if (!room.isFinite) return shown;
  // A pixel of margin: a measurement that lands a hair under the paint
  // fades the last glyph, and half a character of an address is worse
  // than one character fewer.
  while (textWidth(shown, style, scaler) > room - 1 && head + tail > floor) {
    if (head > tail) {
      head--;
    } else {
      tail--;
    }
    shown = truncateMiddle(value, head: head, tail: tail);
  }
  return shown;
}
