import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Gives [child] a hit area of [GerfautTouch.target] both ways without
/// drawing it any larger: the child keeps its size, centred in the box,
/// and a tap in the margin lands on it as if it had hit its middle.
///
/// Material pads its own buttons the same way, to its own figure. This
/// one is for what Gerfaut draws itself, held to the app's target. The
/// box is one node for a screen reader, sized as the finger finds it.
class TapTarget extends SingleChildRenderObjectWidget {
  const TapTarget({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapTarget();
}

class _RenderTapTarget extends RenderShiftedBox {
  _RenderTapTarget() : super(null);

  static const double _min = GerfautTouch.target;

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(child?.getMinIntrinsicWidth(height) ?? 0, _min);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(child?.getMaxIntrinsicWidth(height) ?? 0, _min);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(child?.getMinIntrinsicHeight(width) ?? 0, _min);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(child?.getMaxIntrinsicHeight(width) ?? 0, _min);

  Size _around(BoxConstraints constraints, Size child) => constraints.constrain(
    Size(math.max(child.width, _min), math.max(child.height, _min)),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _around(constraints, child.getDryLayout(constraints));
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = this.child;
    if (child == null) return null;
    final result = child.getDryBaseline(constraints, baseline);
    if (result == null) return null;
    final childSize = child.getDryLayout(constraints);
    final size = _around(constraints, childSize);
    return result + Alignment.center.alongOffset(size - childSize as Offset).dy;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = _around(constraints, child.size);
    (child.parentData! as BoxParentData).offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null) return false;
    // In the margin: the tap goes to the middle of what is drawn.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, _) => child.hitTest(result, position: center),
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = true;
  }
}
