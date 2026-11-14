import 'dart:math';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Keeps a screen's content at [GerfautLayout.readableWidth], centred,
/// when the window is wider: on the inner display of a foldable or on
/// a tablet, a form, a row or a full-width button stays the size a hand
/// and an eye expect, instead of running from one edge to the other.
///
/// A window no wider than that is left as it is: every phone held
/// upright lays out as before.
///
/// Goes inside the screen's [SafeArea], around its body; the app bar
/// keeps the full width, as a navigation bar does on a tablet.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spare = constraints.hasBoundedWidth
            ? max(0.0, constraints.maxWidth - GerfautLayout.readableWidth)
            : 0.0;
        // Always the same Padding, zero below the limit: a window that
        // crosses it, a foldable opened or a phone turned sideways,
        // keeps the screen's state, its page, its scroll, its tab. A
        // child that came and went in a Padding would be rebuilt from
        // scratch. Padding rather than a centred box: the child gets
        // the same tight constraints it had, only narrower.
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spare / 2),
          child: child,
        );
      },
    );
  }
}
