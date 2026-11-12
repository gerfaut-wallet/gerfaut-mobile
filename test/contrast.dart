// The contrast ratio the colour tests hold the tokens to.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2 contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final (hi, lo) = (luminance(a), luminance(b));
  return (math.max(hi, lo) + 0.05) / (math.min(hi, lo) + 0.05);
}
