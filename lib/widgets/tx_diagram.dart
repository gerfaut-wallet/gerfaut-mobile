// A transaction as a picture: which coins came in, where they went,
// and what the fee took. The rows carry the reading, the curves only
// say how much at a glance. The transaction detail and the broadcast
// preview both feed it, so neither one owns the shape.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/state.dart';
import '../theme/tokens.dart';

/// What a branch is, which fixes its icon and its ink. These are the
/// roles the input and output lists already use: a diagram and a list
/// that name the same thing two ways have to be learned twice.
enum TxBranchRole {
  /// Spent from the watched wallet.
  walletInput,

  /// Spent from somewhere the wallet does not know.
  externalInput,

  /// The coinbase input of a block reward: it spends nothing.
  coinbase,

  /// Change coming back to the watched wallet.
  change,

  /// Received by the watched wallet.
  walletOutput,

  /// Leaving for somewhere else.
  externalOutput,

  /// A data output: a payload, no spendable coins.
  opReturn,

  /// The tail the diagram folded into one row. Built here, never
  /// passed in.
  folded,
}

/// One line of the diagram: what the branch is, what names it on the
/// chain, and what it carries. Platform-neutral on purpose — the
/// transaction detail and the broadcast preview each build these from
/// their own model, and the diagram knows neither.
@immutable
class TxBranch {
  const TxBranch({
    required this.role,
    required this.label,
    this.sats,
    this.mine = false,
  });

  final TxBranchRole role;

  /// The outpoint of an input, the address of an output, whole: the
  /// diagram truncates it to the width it was given.
  final String label;

  /// What the branch carries; null when nothing on the page knows it.
  final int? sats;

  /// The branch touches the watched wallet, which colors its curve.
  final bool mine;
}

/// Rows per side before the tail folds into one. DESIGN.md allows
/// eight in the desktop modal; a phone gets five.
const int _rowsPerSide = 5;

/// Dot radii: the square root of the share, so a small branch stays
/// visible next to one that dwarfs it.
const double _minDot = 2;
const double _maxDot = 7;

/// Width of the connector column, and the narrower one a small phone
/// gets. It has to hold the node plus a span of curve on either side:
/// a connector shorter than the node it reaches reads as a nick, not
/// as a branch.
const double _gutter = 84;
const double _tightGutter = 64;

/// Under this, the connector column takes the narrow width: the sides
/// need the room more than the curves do.
const double _tightSide = 130;

/// A side wide enough for an identifier and a full-size figure side by
/// side. Under it — every phone, in practice — the amount moves under
/// the label rather than shrink to something nobody can read. The
/// three columns and their convergence never change.
const double _oneLineSide = 190;

/// Kept clear on the inner edge of each side, so a dot never lands on
/// a figure.
const double _dotLane = 10;

/// Between two rows, and between the node and the fee under it.
const double _rowGap = 2;
const double _feeGap = 18;

/// Stroke of every connector, DESIGN.md.
const double _wire = 1.5;

/// How much of the accent a wire touching the wallet carries.
const double _walletWire = 0.55;

/// Size of the identifier and the figure on a row, and the line they
/// sit on: tight enough that a row carrying two lines stays close to
/// the height of one.
const double _rowText = 11;
const double _rowLine = 1.25;

/// The transaction, drawn: inputs left, outputs right, a `TX` node
/// between them, and the fee hanging below it.
class TxDiagram extends ConsumerStatefulWidget {
  const TxDiagram({
    super.key,
    required this.inputs,
    required this.outputs,
    this.feeSats,
    this.maxRows = _rowsPerSide,
  });

  final List<TxBranch> inputs;
  final List<TxBranch> outputs;

  /// The fee, when it is known: a third branch leaving the node
  /// downward. Null or zero draws none.
  final int? feeSats;

  /// Rows kept per side before the rest folds into "+N more".
  final int maxRows;

  @override
  ConsumerState<TxDiagram> createState() => _TxDiagramState();
}

class _TxDiagramState extends ConsumerState<TxDiagram> {
  final _geometry = _DiagramGeometry();

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    final inputs = _fold(widget.inputs, widget.maxRows);
    final outputs = _fold(widget.outputs, widget.maxRows);
    final feeSats = (widget.feeSats ?? 0) > 0 ? widget.feeSats : null;

    // The largest branch sets the scale. Masked, every dot is the same
    // size: a drawing must not give away the proportions the figures
    // are covering up.
    var largest = feeSats ?? 0;
    for (final branch in [...inputs, ...outputs]) {
      largest = math.max(largest, branch.sats ?? 0);
    }
    List<_Dot> dotsOf(List<TxBranch> branches) => [
      for (final branch in branches)
        _Dot(
          radius: masked
              ? (_minDot + _maxDot) / 2
              : _radius(branch.sats, largest),
          color: branch.mine
              ? tokens.primary.withValues(alpha: _walletWire)
              : tokens.border,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = (constraints.maxWidth - _gutter) / 2 >= _tightSide;
        final gutter = wide ? _gutter : _tightGutter;
        final stacked = (constraints.maxWidth - gutter) / 2 < _oneLineSide;

        List<Widget> rowsOf(List<TxBranch> branches, {required bool input}) => [
          for (final branch in branches)
            _BranchRow(
              branch: branch,
              input: input,
              stacked: stacked,
              masked: masked,
              unit: unit,
              tokens: tokens,
            ),
        ];

        return Stack(
          children: [
            Positioned.fill(
              // The strokes say nothing a row does not already say.
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _WirePainter(
                    geometry: _geometry,
                    gutter: gutter,
                    inputs: dotsOf(inputs),
                    outputs: dotsOf(outputs),
                    fee: feeSats != null ? tokens.border : null,
                  ),
                ),
              ),
            ),
            Column(
              // The diagram is as tall as its rows, wherever it is put:
              // a Column left to its own devices would claim the whole
              // height of a bounded parent.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _RowsColumn(
                        spacing: _rowGap,
                        onLaidOut: (centres, height) => _geometry.setSide(
                          input: true,
                          centres: centres,
                          height: height,
                        ),
                        children: rowsOf(inputs, input: true),
                      ),
                    ),
                    SizedBox(
                      width: gutter,
                      child: Center(
                        child: _Measured(
                          onLaidOut: _geometry.setNode,
                          child: _NodeBox(
                            tokens: tokens,
                            child: Text(
                              'TX',
                              style: tokens.data.copyWith(
                                fontSize: _rowText,
                                color: tokens.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _RowsColumn(
                        spacing: _rowGap,
                        onLaidOut: (centres, height) => _geometry.setSide(
                          input: false,
                          centres: centres,
                          height: height,
                        ),
                        children: rowsOf(outputs, input: false),
                      ),
                    ),
                  ],
                ),
                if (feeSats != null) ...[
                  const SizedBox(height: _feeGap),
                  Center(
                    child: _Measured(
                      onLaidOut: _geometry.setFee,
                      child: _NodeBox(
                        tokens: tokens,
                        // The amount alone: the sat/vB rate is a fact of
                        // the card below, and repeating it here muddies
                        // the one thing this node has to say.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Fee',
                              style: tokens.label.copyWith(
                                fontSize: _rowText,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(width: GerfautSpacing.sm - 2),
                            Text(
                              masked ? maskedValue : formatAmount(feeSats, unit),
                              style: tokens.figureOf(
                                size: _rowText,
                                weight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Radius of a branch's dot: the square root of its share of the
/// largest branch, so the small ones keep a body. An amount nobody
/// knows gets the floor — it cannot claim a size.
double _radius(int? sats, int largest) {
  if (sats == null || sats <= 0 || largest <= 0) return _minDot;
  return _minDot + (_maxDot - _minDot) * math.sqrt(sats / largest);
}

/// Keeps the first rows and folds the tail into one "+N more", whose
/// dot carries the sum of what it stands for. A diagram that overflows
/// is no longer a diagram, and the full list sits right underneath.
List<TxBranch> _fold(List<TxBranch> branches, int maxRows) {
  if (branches.length <= maxRows || maxRows < 2) return branches;
  final rest = branches.sublist(maxRows - 1);
  int? total = 0;
  for (final branch in rest) {
    final sats = branch.sats;
    if (sats == null) {
      total = null;
      break;
    }
    total = total! + sats;
  }
  return [
    ...branches.take(maxRows - 1),
    TxBranch(
      role: TxBranchRole.folded,
      label: '+${rest.length} more',
      sats: total,
      mine: rest.any((branch) => branch.mine),
    ),
  ];
}

/// One line of a side: the role as an icon, what names the branch on
/// the chain, and what it carries.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.input,
    required this.stacked,
    required this.masked,
    required this.unit,
    required this.tokens,
  });

  final TxBranch branch;
  final bool input;

  /// Too narrow for one line: the amount moves under the label.
  final bool stacked;
  final bool masked;
  final AmountUnit unit;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    final role = _roleOf(branch.role, tokens);
    final sats = branch.sats;
    final amount = sats == null
        ? 'n/a'
        : masked
        ? maskedValue
        : formatAmount(sats, unit);
    final folded = branch.role == TxBranchRole.folded;

    final labelStyle = tokens.data.copyWith(
      fontSize: _rowText,
      height: _rowLine,
      color: tokens.textMuted,
    );
    // The cut is *measured*, never guessed from a character count: a
    // count has to assume an advance, a fallback glyph for the ellipsis
    // and a text scale, and being one character out costs the `:0` of
    // the outpoint — exactly the half that names the input.
    final label = LayoutBuilder(
      builder: (context, constraints) => Text(
        folded
            ? branch.label
            : _shortenToFit(
                branch.label,
                constraints.maxWidth,
                labelStyle,
                MediaQuery.textScalerOf(context),
              ),
        style: folded
            ? tokens.bodySmall.copyWith(
                fontSize: _rowText,
                height: _rowLine,
                color: tokens.textMuted,
              )
            : labelStyle,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
    // A figure gives way by scaling down, never by clipping.
    final figure = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        amount,
        style: tokens
            .figureOf(
              size: _rowText,
              weight: FontWeight.w500,
              color: sats == null ? tokens.textMuted : null,
            )
            .copyWith(height: _rowLine),
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.right,
      ),
    );
    final icon = Icon(role.icon, size: 13, color: role.ink);

    return Semantics(
      label: '${role.name}, ${branch.label}, $amount',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: input ? 0 : _dotLane,
          right: input ? _dotLane : 0,
          top: GerfautSpacing.xs + 2,
          bottom: GerfautSpacing.xs + 2,
        ),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: GerfautSpacing.xs),
                      Expanded(child: label),
                    ],
                  ),
                  figure,
                ],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: GerfautSpacing.xs),
                  // An even split keeps the amounts of every row in one
                  // column, which is the whole point of tabular figures.
                  Expanded(child: label),
                  const SizedBox(width: GerfautSpacing.xs),
                  Expanded(child: figure),
                ],
              ),
      ),
    );
  }
}

/// The icon, the ink and the plain words of a role. The words are what
/// a screen reader gets in place of the picture.
({IconData icon, Color ink, String name}) _roleOf(
  TxBranchRole role,
  GerfautTokens tokens,
) {
  return switch (role) {
    TxBranchRole.walletInput => (
      icon: LucideIcons.wallet,
      ink: tokens.primary,
      name: 'Spent from this wallet',
    ),
    TxBranchRole.externalInput => (
      icon: LucideIcons.arrowUpRight,
      ink: tokens.textMuted,
      name: 'External input',
    ),
    TxBranchRole.coinbase => (
      icon: LucideIcons.pickaxe,
      ink: tokens.textMuted,
      name: 'Newly minted coins',
    ),
    TxBranchRole.change => (
      icon: LucideIcons.undo2,
      ink: tokens.primary,
      name: 'Change back to this wallet',
    ),
    TxBranchRole.walletOutput => (
      icon: LucideIcons.arrowDownLeft,
      ink: tokens.primary,
      name: 'Received by this wallet',
    ),
    TxBranchRole.externalOutput => (
      icon: LucideIcons.arrowUpRight,
      ink: tokens.textMuted,
      name: 'External output',
    ),
    TxBranchRole.opReturn => (
      icon: LucideIcons.scrollText,
      ink: tokens.pending,
      name: 'Data output',
    ),
    TxBranchRole.folded => (
      icon: LucideIcons.ellipsis,
      ink: tokens.textMuted,
      name: 'The rest of the list',
    ),
  };
}

/// An identifier cut to the room there is, both ends kept: the head and
/// the tail are what a person compares, and the tail of an outpoint is
/// its index.
///
/// The candidate is painted and measured at each length, shortest work
/// first, so what comes back is the longest form that actually fits the
/// style it will be drawn in — no assumption about the font's advance,
/// the glyph the ellipsis falls back to, or the device's text scale.
String _shortenToFit(
  String value,
  double width,
  TextStyle style,
  TextScaler scaler,
) {
  if (!width.isFinite || width <= 0) return value;
  double widthOf(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final measured = painter.width;
    painter.dispose();
    return measured;
  }

  if (widthOf(value) <= width) return value;
  // A ceiling no monospaced face can breach: the widest of them advances
  // well under 0.68 em, and JetBrains Mono is 0.6. Painting a candidate
  // measures narrower than the device draws it — seen on a phone, where
  // an eighteen-character outpoint fitted on paper and lost its `:0` to
  // the fade on screen — so the count starts under a bound that cannot
  // be wrong, and the measurement below only ever shortens it further.
  final ceiling = (width / (_rowText * scaler.scale(1) * 0.68)).floor();
  // Longest first: the first form that fits is the one to keep.
  for (var chars = math.min(value.length - 1, ceiling); chars >= 5; chars--) {
    final tail = math.min(6, math.max(2, (chars - 4) ~/ 2));
    final head = math.max(2, chars - 3 - tail);
    if (head + tail + 3 >= value.length) continue;
    final candidate = truncateMiddle(value, head: head, tail: tail);
    if (widthOf(candidate) <= width) return candidate;
  }
  return truncateMiddle(value, head: 2, tail: 2);
}

/// The crossroads, and the stop the fee makes: a hairline box on the
/// card surface. Not a card of facts — a junction.
class _NodeBox extends StatelessWidget {
  const _NodeBox({required this.tokens, required this.child});

  final GerfautTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm - 2,
        vertical: GerfautSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }
}

/// A dot on the inner edge of a side: how big, and in what ink.
@immutable
class _Dot {
  const _Dot({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _Dot && other.radius == radius && other.color == color;

  @override
  int get hashCode => Object.hash(radius, color);
}

/// What layout actually produced, handed to the painter so the curves
/// meet the rows instead of a height written down twice.
class _DiagramGeometry extends ChangeNotifier {
  List<double> inputCentres = const [];
  List<double> outputCentres = const [];
  double inputsHeight = 0;
  double outputsHeight = 0;
  Size node = Size.zero;
  Size fee = Size.zero;

  void setSide({
    required bool input,
    required List<double> centres,
    required double height,
  }) {
    final settled = input ? inputCentres : outputCentres;
    final was = input ? inputsHeight : outputsHeight;
    if (height == was && _same(settled, centres)) return;
    if (input) {
      inputCentres = centres;
      inputsHeight = height;
    } else {
      outputCentres = centres;
      outputsHeight = height;
    }
    notifyListeners();
  }

  void setNode(Size size) {
    if (node == size) return;
    node = size;
    notifyListeners();
  }

  void setFee(Size size) {
    if (fee == size) return;
    fee = size;
    notifyListeners();
  }
}

bool _same(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The connectors and their dots. Every curve is a cubic with control
/// points at a fifth and four fifths of the span and flat tangents at
/// both ends, so it leaves the dot and reaches the node level, never
/// at an angle.
class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.geometry,
    required this.gutter,
    required this.inputs,
    required this.outputs,
    required this.fee,
  }) : super(repaint: geometry);

  final _DiagramGeometry geometry;
  final double gutter;
  final List<_Dot> inputs;
  final List<_Dot> outputs;

  /// Ink of the fee branch; null when there is no fee to draw.
  final Color? fee;

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.width - gutter) / 2;
    final node = geometry.node;
    final band = math.max(
      node.height,
      math.max(geometry.inputsHeight, geometry.outputsHeight),
    );
    if (side <= 0 || band <= 0) return;

    final middle = size.width / 2;
    final centre = band / 2;

    _side(
      canvas,
      dots: inputs,
      centres: geometry.inputCentres,
      top: (band - geometry.inputsHeight) / 2,
      dotX: side,
      nodeX: middle - node.width / 2,
      nodeY: centre,
    );
    _side(
      canvas,
      dots: outputs,
      centres: geometry.outputCentres,
      top: (band - geometry.outputsHeight) / 2,
      dotX: size.width - side,
      nodeX: middle + node.width / 2,
      nodeY: centre,
    );

    final feeInk = fee;
    if (feeInk != null && geometry.fee.height > 0) {
      // The fee is not an output, it is what is left over: the branch
      // says so by leaving the node from underneath.
      final from = Offset(middle, centre + node.height / 2);
      final to = Offset(middle, band + _feeGap);
      final drop = to.dy - from.dy;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(
            from.dx,
            from.dy + drop * 0.2,
            to.dx,
            from.dy + drop * 0.8,
            to.dx,
            to.dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _wire
          ..color = feeInk,
      );
    }
  }

  void _side(
    Canvas canvas, {
    required List<_Dot> dots,
    required List<double> centres,
    required double top,
    required double dotX,
    required double nodeX,
    required double nodeY,
  }) {
    final count = math.min(dots.length, centres.length);
    for (var i = 0; i < count; i++) {
      final dot = dots[i];
      final y = top + centres[i];
      final span = nodeX - dotX;
      canvas.drawPath(
        Path()
          ..moveTo(dotX, y)
          ..cubicTo(dotX + span * 0.2, y, dotX + span * 0.8, nodeY, nodeX, nodeY),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _wire
          ..color = dot.color,
      );
      canvas.drawCircle(
        Offset(dotX, y),
        dot.radius,
        Paint()..color = dot.color,
      );
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.gutter != gutter ||
      old.fee != fee ||
      !_sameDots(old.inputs, inputs) ||
      !_sameDots(old.outputs, outputs);
}

bool _sameDots(List<_Dot> a, List<_Dot> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reports the size layout gave a box, so the painter never has to
/// assume one.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onLaidOut, required Widget super.child});

  final ValueChanged<Size> onLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onLaidOut);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.onLaidOut = onLaidOut;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onLaidOut);

  ValueChanged<Size> onLaidOut;

  @override
  void performLayout() {
    super.performLayout();
    onLaidOut(size);
  }
}

/// The rows of one side, stacked, reporting where each one landed. A
/// Column would hold them just as well, but the painter needs the
/// centre of every row, and a height written once in the widget and
/// once in the painter drifts apart the day a font changes.
class _RowsColumn extends MultiChildRenderObjectWidget {
  const _RowsColumn({
    required this.spacing,
    required this.onLaidOut,
    required super.children,
  });

  final double spacing;
  final void Function(List<double> centres, double height) onLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRowsColumn(spacing, onLaidOut);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRowsColumn renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..onLaidOut = onLaidOut;
  }
}

class _RowsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderRowsColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowsParentData> {
  _RenderRowsColumn(this._spacing, this.onLaidOut);

  double _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  void Function(List<double> centres, double height) onLaidOut;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowsParentData) {
      child.parentData = _RowsParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      height += child
          .getDryLayout(BoxConstraints.tightFor(width: width))
          .height;
      child = childAfter(child);
      if (child != null) height += _spacing;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final centres = <double>[];
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      (child.parentData! as _RowsParentData).offset = Offset(0, height);
      centres.add(height + child.size.height / 2);
      height += child.size.height;
      child = childAfter(child);
      if (child != null) height += _spacing;
    }
    size = constraints.constrain(Size(width, height));
    onLaidOut(centres, size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
