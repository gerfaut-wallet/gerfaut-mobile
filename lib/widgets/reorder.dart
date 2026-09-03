import 'package:flutter/material.dart';

/// Marks the copy of a list item that follows the finger while it is
/// dragged. The item reads it and paints itself as the one thing on the
/// screen that really floats: on its own surface, with the overlay
/// shadow. Nothing else changes about it, so what lands is what was
/// lifted.
///
/// A `proxyDecorator` cannot hand the item a flag, and cannot draw the
/// shadow itself without shading the gutter under the item too: the
/// item owns its margin, so the item has to own its lift.
class LiftedItem extends InheritedWidget {
  const LiftedItem({super.key, required super.child});

  /// Whether the widget at [context] is being dragged right now.
  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LiftedItem>() != null;
  }

  @override
  bool updateShouldNotify(LiftedItem oldWidget) => false;
}

/// The `proxyDecorator` of every reorderable list in the app.
Widget liftedProxy(Widget child, int index, Animation<double> animation) {
  return Material(
    color: Colors.transparent,
    child: LiftedItem(child: child),
  );
}
