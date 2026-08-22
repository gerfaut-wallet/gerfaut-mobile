import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import 'address_chip.dart';

/// Row height of one input/output lane. Taller than desktop: the chip
/// and the amount line need the room at mobile text sizes.
const double _row = 76;

/// Height of one lane card inside its row.
const double _laneH = 60;

/// Width of the strip carrying the ribbons and the tx node.
const double _mid = 150;

/// Lanes shown per side before aggregation into a "+N more" lane.
const int _maxLanes = 7;

/// Width of the transaction node capsule.
const double _nodeW = 22;

/// Extra height under the lanes for the fee branch.
const double _feeDrop = 52;

/// Ribbon thickness bounds; area follows sqrt so small amounts stay
/// visible.
const double _minT = 3;
const double _maxT = 24;

/// Vertical gap between ribbon anchors on the node.
const double _nodeGap = 3;

/// Minimum width of one lane column; below that the diagram scrolls.
const double _minSide = 132;

class _Lane {
  const _Lane({
    required this.label,
    required this.valueSats,
    required this.mine,
    this.more = 0,
  });

  final String? label;
  final int? valueSats;
  final bool mine;

  /// Aggregated remainder lane ("+N more").
  final int more;
}

List<_Lane> _toLanes(List<TxIo> ios) {
  if (ios.length <= _maxLanes) {
    return [
      for (final io in ios)
        _Lane(label: io.address, valueSats: io.valueSats, mine: io.isMine),
    ];
  }
  final shown = ios.sublist(0, _maxLanes - 1);
  final rest = ios.sublist(_maxLanes - 1);
  int? restValue = 0;
  for (final io in rest) {
    if (restValue == null || io.valueSats == null) {
      restValue = null;
    } else {
      restValue += io.valueSats!;
    }
  }
  return [
    for (final io in shown)
      _Lane(label: io.address, valueSats: io.valueSats, mine: io.isMine),
    _Lane(
      label: null,
      valueSats: restValue,
      mine: rest.any((io) => io.isMine),
      more: rest.length,
    ),
  ];
}

double _thickness(int? valueSats, int max) {
  if (valueSats == null || max <= 0) return _minT;
  return _minT + (_maxT - _minT) * math.sqrt(valueSats / max);
}

/// Transaction flow in the spirit of Sparrow and mempool.space: filled
/// ribbons whose thickness follows the amounts converge into the
/// transaction node and fan out again; the fee drips below. Pure
/// geometry, nothing measured. Scrolls horizontally inside its card
/// when the screen is narrower than the lane grid.
class FlowDiagram extends StatelessWidget {
  const FlowDiagram({
    super.key,
    required this.inputs,
    required this.outputs,
    required this.feeSats,
    required this.feeRate,
  });

  final List<TxIo> inputs;
  final List<TxIo> outputs;
  final int? feeSats;
  final double? feeRate;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final inLanes = _toLanes(inputs);
    final outLanes = _toLanes(outputs);
    final laneCount = math.max(math.max(inLanes.length, outLanes.length), 1);
    final height = laneCount * _row;
    var maxValue = 0;
    for (final lane in [...inLanes, ...outLanes]) {
      if (lane.valueSats != null && lane.valueSats! > maxValue) {
        maxValue = lane.valueSats!;
      }
    }
    final tIn = [
      for (final lane in inLanes) _thickness(lane.valueSats, maxValue),
    ];
    final tOut = [
      for (final lane in outLanes) _thickness(lane.valueSats, maxValue),
    ];
    double stackOf(List<double> ts) =>
        ts.fold(0.0, (sum, t) => sum + t) +
        math.max(0, ts.length - 1) * _nodeGap;
    final stackIn = stackOf(tIn);
    final stackOut = stackOf(tOut);
    final nodeH = math.max(48.0, math.max(stackIn, stackOut) + 18);
    final nodeTop = (height - nodeH) / 2;
    // Ribbon anchors stack on the node by cumulative thickness, so
    // ribbons meet the capsule without overlapping: the Sankey look.
    List<double> anchors(List<double> ts, double stack) {
      var cursor = nodeTop + (nodeH - stack) / 2;
      return [
        for (final t in ts)
          () {
            final y = cursor + t / 2;
            cursor += t + _nodeGap;
            return y;
          }(),
      ];
    }

    double laneY(int index, int count) =>
        (height - count * _row) / 2 + index * _row + _row / 2;

    final showFee = feeSats != null && feeSats! > 0;
    final canvasHeight = height + (showFee ? _feeDrop : 0);

    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const wanted = _minSide * 2 + _mid;
          final width = math.max(constraints.maxWidth, wanted);
          final content = SizedBox(
            width: width,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LaneColumn(
                        lanes: inLanes,
                        side: _Side.input,
                        laneY: (index) => laneY(index, inLanes.length),
                        height: height,
                      ),
                    ),
                    CustomPaint(
                      size: Size(_mid, canvasHeight),
                      painter: _FlowPainter(
                        inLanes: inLanes,
                        outLanes: outLanes,
                        tIn: tIn,
                        tOut: tOut,
                        anchorIn: anchors(tIn, stackIn),
                        anchorOut: anchors(tOut, stackOut),
                        inYs: [
                          for (var i = 0; i < inLanes.length; i++)
                            laneY(i, inLanes.length),
                        ],
                        outYs: [
                          for (var i = 0; i < outLanes.length; i++)
                            laneY(i, outLanes.length),
                        ],
                        nodeTop: nodeTop,
                        nodeH: nodeH,
                        height: height,
                        showFee: showFee,
                        mineColor: tokens.primary,
                        mutedColor: tokens.textMuted,
                        borderColor: tokens.border,
                        nodeFill: tokens.surfaceSunken,
                        feeColor: tokens.pending,
                      ),
                    ),
                    Expanded(
                      child: _LaneColumn(
                        lanes: outLanes,
                        side: _Side.output,
                        laneY: (index) => laneY(index, outLanes.length),
                        height: height,
                      ),
                    ),
                  ],
                ),
                if (showFee)
                  Center(child: _FeePill(feeSats: feeSats!, feeRate: feeRate)),
              ],
            ),
          );
          if (constraints.maxWidth >= wanted) return content;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        },
      ),
    );
  }
}

/// Fee as a pending-tinted pill under the fee branch: amount in the
/// chosen unit, rate as small print. Never an alert, only small print.
class _FeePill extends ConsumerWidget {
  const _FeePill({required this.feeSats, required this.feeRate});

  final int feeSats;
  final double? feeRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm + GerfautSpacing.xs,
        vertical: GerfautSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.pendingSurface,
        borderRadius: BorderRadius.circular(GerfautRadius.full),
        border: Border.all(color: tokens.pending.withValues(alpha: 0.3)),
      ),
      child: Text.rich(
        TextSpan(
          text: 'FEE',
          style: tokens.label.copyWith(color: tokens.pending),
          children: [
            TextSpan(
              text: ' · ${masked ? maskedValue : formatAmount(feeSats, unit)}',
              style: tokens.data.copyWith(
                fontSize: 12,
                color: tokens.pending,
              ),
            ),
            if (feeRate != null)
              TextSpan(
                text: ' · ${feeRate!.toStringAsFixed(1)} sat/vB',
                style: tokens.data.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

enum _Side { input, output }

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lanes,
    required this.side,
    required this.laneY,
    required this.height,
  });

  final List<_Lane> lanes;
  final _Side side;
  final double Function(int index) laneY;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, lane) in lanes.indexed)
            Positioned(
              left: 0,
              right: 0,
              top: laneY(index) - _laneH / 2,
              height: _laneH,
              child: _LaneCard(lane: lane, side: side),
            ),
        ],
      ),
    );
  }
}

/// One input or output as a small card the ribbon plugs into: mine
/// lanes carry the primary tint, aggregate lanes a dashed outline.
class _LaneCard extends StatelessWidget {
  const _LaneCard({required this.lane, required this.side});

  final _Lane lane;
  final _Side side;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.sm + 2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: side == _Side.input
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (lane.more > 0)
            Text(
              '+${lane.more} more '
              '${side == _Side.input ? 'inputs' : 'outputs'}',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              maxLines: 1,
              softWrap: false,
            )
          else if (lane.label != null)
            AddressChip(value: lane.label!)
          else
            Text(
              side == _Side.input ? 'coinbase' : 'script output',
              style: tokens.data.copyWith(color: tokens.textMuted),
              maxLines: 1,
              softWrap: false,
            ),
          if (lane.valueSats != null) ...[
            const SizedBox(height: 2),
            _LaneAmount(sats: lane.valueSats!),
          ],
        ],
      ),
    );
    if (lane.more > 0) {
      return CustomPaint(
        painter: _DashedRRectPainter(
          color: tokens.border,
          radius: GerfautRadius.md,
        ),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: lane.mine
            ? tokens.primary.withValues(alpha: 0.05)
            : tokens.background,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(
          color: lane.mine
              ? tokens.primary.withValues(alpha: 0.4)
              : tokens.border,
        ),
      ),
      child: content,
    );
  }
}

/// Lane amount: chosen unit, masked-aware, no fiat, never wrapped.
class _LaneAmount extends ConsumerWidget {
  const _LaneAmount({required this.sats});

  final int sats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final unit = ref.watch(unitProvider);
    return Text(
      masked ? maskedValue : formatAmount(sats, unit),
      style: tokens.data,
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// Dashed hairline outline for the aggregate "+N more" lane.
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Offset(0.5, 0.5) & Size(size.width - 1, size.height - 1),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) {
    return old.color != color || old.radius != radius;
  }
}

class _FlowPainter extends CustomPainter {
  const _FlowPainter({
    required this.inLanes,
    required this.outLanes,
    required this.tIn,
    required this.tOut,
    required this.anchorIn,
    required this.anchorOut,
    required this.inYs,
    required this.outYs,
    required this.nodeTop,
    required this.nodeH,
    required this.height,
    required this.showFee,
    required this.mineColor,
    required this.mutedColor,
    required this.borderColor,
    required this.nodeFill,
    required this.feeColor,
  });

  final List<_Lane> inLanes;
  final List<_Lane> outLanes;
  final List<double> tIn;
  final List<double> tOut;
  final List<double> anchorIn;
  final List<double> anchorOut;
  final List<double> inYs;
  final List<double> outYs;
  final double nodeTop;
  final double nodeH;
  final double height;
  final bool showFee;
  final Color mineColor;
  final Color mutedColor;
  final Color borderColor;
  final Color nodeFill;
  final Color feeColor;

  /// A constant-thickness ribbon between two anchors: two mirrored
  /// cubic curves closed into one filled shape.
  Path _ribbon(double x0, double y0, double x1, double y1, double t) {
    final c1 = x0 + (x1 - x0) * 0.38;
    final c2 = x0 + (x1 - x0) * 0.62;
    final h = t / 2;
    return Path()
      ..moveTo(x0, y0 - h)
      ..cubicTo(c1, y0 - h, c2, y1 - h, x1, y1 - h)
      ..lineTo(x1, y1 + h)
      ..cubicTo(c2, y1 + h, c1, y0 + h, x0, y0 + h)
      ..close();
  }

  Paint _fill(bool mine) => Paint()
    ..style = PaintingStyle.fill
    ..color = mine
        ? mineColor.withValues(alpha: 0.5)
        : mutedColor.withValues(alpha: 0.18);

  @override
  void paint(Canvas canvas, Size size) {
    const nodeX = _mid / 2;

    for (final (index, lane) in inLanes.indexed) {
      canvas.drawPath(
        _ribbon(
          0,
          inYs[index],
          nodeX - _nodeW / 2 + 2,
          anchorIn[index],
          tIn[index],
        ),
        _fill(lane.mine),
      );
    }
    for (final (index, lane) in outLanes.indexed) {
      canvas.drawPath(
        _ribbon(
          nodeX + _nodeW / 2 - 2,
          anchorOut[index],
          _mid,
          outYs[index],
          tOut[index],
        ),
        _fill(lane.mine),
      );
    }

    if (showFee) {
      // Dotted branch: short dashes with round caps read as dots.
      final path = Path()
        ..moveTo(nodeX, nodeTop + nodeH - 1)
        ..lineTo(nodeX, height + _feeDrop - 14);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..color = feeColor.withValues(alpha: 0.7);
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          canvas.drawPath(metric.extractPath(distance, distance + 1), paint);
          distance += 7;
        }
      }
    }

    // The transaction node capsule.
    final node = RRect.fromRectAndRadius(
      Rect.fromLTWH(nodeX - _nodeW / 2, nodeTop, _nodeW, nodeH),
      const Radius.circular(_nodeW / 2),
    );
    canvas.drawRRect(node, Paint()..color = nodeFill);
    canvas.drawRRect(
      node,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) {
    return old.inLanes != inLanes ||
        old.outLanes != outLanes ||
        old.anchorIn != anchorIn ||
        old.anchorOut != anchorOut ||
        old.showFee != showFee ||
        old.mineColor != mineColor ||
        old.mutedColor != mutedColor ||
        old.borderColor != borderColor ||
        old.nodeFill != nodeFill ||
        old.feeColor != feeColor;
  }
}
