// A transaction as a picture: which coins came in, where they went,
// and what the fee took. Every branch is a box, every box is joined to
// the square in the middle by a curve that leaves one edge and lands
// on another. The transaction detail and the broadcast preview both
// feed it, so neither one owns the shape.

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

  /// The tail the diagram folded into one box. Built here, never
  /// passed in.
  folded,
}

/// One box of the diagram: what the branch is, what names it on the
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

  /// The branch touches the watched wallet, which colors its box and
  /// its connector.
  final bool mine;
}

/// Boxes per side before the tail folds into one. DESIGN.md allows ten
/// in the desktop modal; a phone gets five — half the height for half
/// the width.
const int _rowsPerSide = 5;

/// The junction, which is a square and nothing else.
const double _square = 40;

/// Clear space between a side and the square, and the narrower one a
/// small frame gets. The bend turns in that space: any shorter and the
/// connector reads as a nick rather than as a branch.
const double _gutter = 48;
const double _tightGutter = 40;

/// Under this width the gutter narrows — the boxes need the room more
/// than the bend does.
const double _tightFrame = 340;

/// Between two boxes of a side, and between the columns and the fee.
const double _boxGap = GerfautSpacing.sm;
const double _feeGap = 18;

/// Stroke of every connector, DESIGN.md.
const double _wire = 1.5;

/// How much of the accent a connector touching the wallet carries, and
/// the wash its box takes: the very one the input and output lists
/// below the diagram use, so a branch is recognized the same way
/// whichever of the two the eye lands on.
const double _walletWire = 0.55;
const double _walletEdge = 0.4;
const double _walletFill = 0.04;

/// The two lines of a box, and the line box each of them sits in. The
/// role icon is centred in one of those and not in the box: on the
/// first line, where the label is.
const double _boxText = 11;
const double _boxLine = 16;

/// The word in the square.
const double _squareText = 13;

/// The role icon, which never shrinks: it is the one thing on a box
/// that stays legible once the label has been cut to the bone.
const double _iconSize = 14;

/// The transaction, drawn: inputs left, outputs right, a `TX` square
/// between them, and the fee hanging below it.
class TxDiagram extends ConsumerStatefulWidget {
  const TxDiagram({
    super.key,
    required this.inputs,
    required this.outputs,
    this.feeSats,
    this.feeNote,
    this.maxRows = _rowsPerSide,
  });

  final List<TxBranch> inputs;
  final List<TxBranch> outputs;

  /// The fee, when it is known: a third branch leaving the square
  /// downward. Null or zero draws none.
  final int? feeSats;

  /// A line under the fee's figure when the fee is not the chain's
  /// word — the broadcast preview marks a fee the PSBT states and no
  /// backend confirmed. Nothing when null.
  final String? feeNote;

  /// Boxes kept per side before the rest folds into "+N more".
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
    final inputs = _fold(widget.inputs, widget.maxRows, side: 'inputs');
    final outputs = _fold(widget.outputs, widget.maxRows, side: 'outputs');
    final feeSats = (widget.feeSats ?? 0) > 0 ? widget.feeSats : null;

    List<Color> inkOf(List<TxBranch> branches) => [
      for (final branch in branches)
        branch.mine
            ? tokens.primary.withValues(alpha: _walletWire)
            : tokens.border,
    ];
    List<Widget> boxesOf(List<TxBranch> branches) => [
      for (final branch in branches)
        _BranchBox(branch: branch, masked: masked, unit: unit, tokens: tokens),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = width.isFinite && width < _tightFrame
            ? _tightGutter
            : _gutter;
        // The middle column: the square, and a clear span each side of
        // it. A frame too narrow for the three of them gives up the
        // span first — the convergence is the picture, though a box
        // squeezed to nothing says nothing either.
        final centre = width.isFinite
            ? math.min(_square + gutter * 2, math.max(_square, width / 2))
            : _square + gutter * 2;

        return Semantics(
          // The picture is a section of the page, and it says so: found
          // by its name, a reader knows what the rows below belong to
          // instead of walking into a run of unattributed outpoints.
          label: 'Transaction diagram',
          explicitChildNodes: true,
          child: Stack(
            children: [
              Positioned.fill(
                // The strokes say nothing a box does not already say.
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _WirePainter(
                      geometry: _geometry,
                      centre: centre,
                      inputs: inkOf(inputs),
                      outputs: inkOf(outputs),
                      fee: feeSats != null ? tokens.border : null,
                    ),
                  ),
                ),
              ),
              Column(
                // The diagram is as tall as its boxes, wherever it is
                // put: a Column left to its own devices would claim the
                // whole height of a bounded parent.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        // Which side a box is on is the picture's doing,
                        // and a reader gets none of it: the column says
                        // its own name so the boxes under it mean
                        // something.
                        child: Semantics(
                          label: 'Inputs',
                          explicitChildNodes: true,
                          child: _RowsColumn(
                            spacing: _boxGap,
                            onLaidOut: (centres, height) => _geometry.setSide(
                              input: true,
                              centres: centres,
                              height: height,
                            ),
                            children: boxesOf(inputs),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: centre,
                        child: Center(child: _Square(tokens: tokens)),
                      ),
                      Expanded(
                        child: Semantics(
                          label: 'Outputs',
                          explicitChildNodes: true,
                          child: _RowsColumn(
                            spacing: _boxGap,
                            onLaidOut: (centres, height) => _geometry.setSide(
                              input: false,
                              centres: centres,
                              height: height,
                            ),
                            children: boxesOf(outputs),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (feeSats != null) ...[
                    const SizedBox(height: _feeGap),
                    Center(
                      child: _FeeBox(
                        sats: feeSats,
                        note: widget.feeNote,
                        masked: masked,
                        unit: unit,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Keeps the first boxes and folds the tail into one, carrying the sum
/// of what it stands for. A diagram that overflows is no longer a
/// diagram, and the full list sits right underneath.
///
/// The folded box names its own side: read alone, halfway down a
/// picture, `+7 more` does not say more of what.
List<TxBranch> _fold(
  List<TxBranch> branches,
  int maxRows, {
  required String side,
}) {
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
      label: '+${rest.length} more $side',
      sats: total,
      mine: rest.any((branch) => branch.mine),
    ),
  ];
}

/// One branch of the diagram, as a box: its role as an icon, what
/// names it on the chain, and what it carries, stacked. The two lines
/// never collapse into one — a label and a figure side by side is the
/// list below, and the diagram would then be a second, worse copy of
/// it.
class _BranchBox extends StatelessWidget {
  const _BranchBox({
    required this.branch,
    required this.masked,
    required this.unit,
    required this.tokens,
  });

  final TxBranch branch;
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
    final scaler = MediaQuery.textScalerOf(context);

    // An identifier is code and stays in the mono face; the folded box
    // says a sentence, and a sentence set in mono reads as a machine
    // talking.
    final labelStyle = folded
        ? tokens.bodySmall.copyWith(
            fontSize: _boxText,
            height: _boxLine / _boxText,
            color: tokens.textMuted,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          )
        : tokens.data.copyWith(
            fontSize: _boxText,
            height: _boxLine / _boxText,
            color: tokens.textMuted,
          );

    return Semantics(
      // The role is carried by an icon, and an icon is nothing to a
      // screen reader: it goes into the box's own name, or the reading
      // is an address and a number with no say in what they are.
      label: '${role.name}, ${branch.label}, $amount',
      excludeSemantics: true,
      child: _Box(
        tokens: tokens,
        mine: branch.mine,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              // One line high, so the glyph sits on the optical centre
              // of the label rather than of the whole box.
              height: scaler.scale(_boxText) * (_boxLine / _boxText),
              child: Center(
                child: Icon(role.icon, size: _iconSize, color: role.ink),
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The cut is *measured*, never guessed from a
                  // character count: a count has to assume an advance, a
                  // fallback glyph for the ellipsis and a text scale,
                  // and being one character out costs the `:0` of the
                  // outpoint — exactly the half that names the input.
                  LayoutBuilder(
                    builder: (context, constraints) => Text(
                      folded
                          ? branch.label
                          : _shortenToFit(
                              branch.label,
                              constraints.maxWidth,
                              labelStyle,
                              scaler,
                            ),
                      style: labelStyle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                  _Figure(text: amount, muted: sats == null, tokens: tokens),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The fee is not an output, it is what stays behind: its own box under
/// the transaction, carrying the amount alone — the sat/vB rate is a
/// fact of the card below, and repeating it here blurs the one thing
/// this box has to say. No role icon either: a fee has no role to name.
class _FeeBox extends StatelessWidget {
  const _FeeBox({
    required this.sats,
    required this.note,
    required this.masked,
    required this.unit,
    required this.tokens,
  });

  final int sats;

  /// A third line under the figure, or nothing.
  final String? note;
  final bool masked;
  final AmountUnit unit;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return _Box(
      tokens: tokens,
      mine: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Uppercase in the string: desktop gets it from CSS, and a
          // label that reads FEE on one platform and Fee on the other
          // is the same box drawn two ways.
          Text(
            'FEE',
            style: tokens.label.copyWith(
              fontSize: _boxText,
              height: _boxLine / _boxText,
              letterSpacing: _boxText * 0.04,
              color: tokens.textMuted,
            ),
            maxLines: 1,
            softWrap: false,
          ),
          _Figure(
            text: masked ? maskedValue : formatAmount(sats, unit),
            muted: false,
            tokens: tokens,
          ),
          if (note != null)
            Text(
              note!,
              style: tokens.label.copyWith(
                fontSize: _boxText,
                height: _boxLine / _boxText,
                letterSpacing: 0,
                color: tokens.textMuted,
              ),
              maxLines: 1,
              softWrap: false,
            ),
        ],
      ),
    );
  }
}

/// The second line of every box. A figure gives way by scaling down,
/// never by clipping: a truncated amount is a wrong amount.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.text,
    required this.muted,
    required this.tokens,
  });

  final String text;
  final bool muted;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: tokens
            .figureOf(
              size: _boxText,
              weight: FontWeight.w500,
              color: muted ? tokens.textMuted : null,
            )
            .copyWith(height: _boxLine / _boxText),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// The shell every node of the diagram shares: a hairline box on the
/// card surface, washed with the accent when it touches the wallet.
class _Box extends StatelessWidget {
  const _Box({required this.tokens, required this.mine, required this.child});

  final GerfautTokens tokens;
  final bool mine;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm + 2,
        vertical: GerfautSpacing.sm - 2,
      ),
      decoration: BoxDecoration(
        color: mine
            ? tokens.primary.withValues(alpha: _walletFill)
            : tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(
          color: mine
              ? tokens.primary.withValues(alpha: _walletEdge)
              : tokens.border,
        ),
      ),
      child: child,
    );
  }
}

/// The crossroads: a square that says where the branches meet, and
/// nothing else. Its size is fixed so the two sides keep their room at
/// any text scale, and the word inside gives way rather than break out
/// of it.
class _Square extends StatelessWidget {
  const _Square({required this.tokens});

  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _square,
      height: _square,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'TX',
          style: tokens.data.copyWith(
            fontSize: _squareText,
            height: 1,
            color: tokens.textMuted,
          ),
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
  final ceiling = (width / (_boxText * scaler.scale(1) * 0.68)).floor();
  // Only the txid of an outpoint is up for cutting: the index is put
  // back whole, so the budget leaves room for it rather than counting
  // it among the characters it may drop.
  final suffix = outpointSuffix(value);
  final body = value.substring(0, value.length - suffix.length);
  // Longest first: the first form that fits is the one to keep.
  for (
    var chars = math.min(body.length - 1, ceiling - suffix.length);
    chars >= 5;
    chars--
  ) {
    final tail = math.min(6, math.max(2, (chars - 4) ~/ 2));
    final head = math.max(2, chars - 3 - tail);
    if (head + tail + 3 >= body.length) continue;
    final candidate = shortenBranchLabel(value, head: head, tail: tail);
    if (widthOf(candidate) <= width) return candidate;
  }
  return shortenBranchLabel(value, head: 2, tail: 2);
}

/// What layout actually produced, handed to the painter so the curves
/// meet the boxes instead of a height written down twice.
class _DiagramGeometry extends ChangeNotifier {
  List<double> inputCentres = const [];
  List<double> outputCentres = const [];
  double inputsHeight = 0;
  double outputsHeight = 0;

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
}

bool _same(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The connectors, box edge to box edge. Every one of them is a cubic
/// whose two control points sit on the middle of the span, so it leaves
/// and arrives perfectly horizontal and turns in one move. Held closer
/// to the ends it grew a long flat middle that read as neither a line
/// nor a curve.
class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.geometry,
    required this.centre,
    required this.inputs,
    required this.outputs,
    required this.fee,
  }) : super(repaint: geometry);

  final _DiagramGeometry geometry;

  /// Width of the middle column: the square and its two clear spans.
  final double centre;

  final List<Color> inputs;
  final List<Color> outputs;

  /// Ink of the fee branch; null when there is no fee to draw.
  final Color? fee;

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.width - centre) / 2;
    final band = math.max(
      _square,
      math.max(geometry.inputsHeight, geometry.outputsHeight),
    );
    if (side <= 0) return;

    final middle = size.width / 2;
    final axis = band / 2;

    _span(
      canvas,
      inks: inputs,
      centres: geometry.inputCentres,
      top: (band - geometry.inputsHeight) / 2,
      boxEdge: side,
      squareEdge: middle - _square / 2,
      axis: axis,
    );
    _span(
      canvas,
      inks: outputs,
      centres: geometry.outputCentres,
      top: (band - geometry.outputsHeight) / 2,
      boxEdge: size.width - side,
      squareEdge: middle + _square / 2,
      axis: axis,
    );

    final feeInk = fee;
    if (feeInk == null) return;
    // What stays behind is nobody's branch: the drop keeps the neutral
    // ink even under a wallet the accent runs through.
    final from = axis + _square / 2;
    final to = band + _feeGap;
    final drop = to - from;
    canvas.drawPath(
      Path()
        ..moveTo(middle, from)
        ..cubicTo(
          middle,
          from + drop * 0.5,
          middle,
          to - drop * 0.5,
          middle,
          to,
        ),
      _paint(feeInk),
    );
  }

  /// Every box of one side joined to the square. The boxes stretch to
  /// their column, so each connector leaves from the same x and the
  /// branches read as one bundle instead of a fan.
  void _span(
    Canvas canvas, {
    required List<Color> inks,
    required List<double> centres,
    required double top,
    required double boxEdge,
    required double squareEdge,
    required double axis,
  }) {
    final count = math.min(inks.length, centres.length);
    final bend = (boxEdge + squareEdge) / 2;
    for (var i = 0; i < count; i++) {
      final y = top + centres[i];
      canvas.drawPath(
        Path()
          ..moveTo(boxEdge, y)
          ..cubicTo(bend, y, bend, axis, squareEdge, axis),
        _paint(inks[i]),
      );
    }
  }

  Paint _paint(Color ink) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _wire
    ..strokeCap = StrokeCap.round
    ..color = ink;

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.centre != centre ||
      old.fee != fee ||
      !_sameInks(old.inputs, inputs) ||
      !_sameInks(old.outputs, outputs);
}

bool _sameInks(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The boxes of one side, stacked, reporting where each one landed. A
/// Column would hold them just as well, but the painter needs the
/// centre of every box, and a height written once in the widget and
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
