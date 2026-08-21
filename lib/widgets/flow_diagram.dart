import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/models.dart';
import '../theme/tokens.dart';
import 'address_chip.dart';
import 'amounts.dart';

/// Row height of one input/output lane.
const double _row = 56;

/// Width of the strip carrying the curves and the tx node.
const double _mid = 150;

/// Extra height under the lanes for the fee branch.
const double _feeDrop = 44;

/// Lanes shown per side before aggregation into a "+N more" lane.
const int _maxLanes = 8;

/// Minimum width of one lane column; below that the diagram scrolls.
const double _minSide = 120;

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

/// Stroke width proportional to the lane's share of the largest value.
double _strokeWidth(int? valueSats, int max) {
  if (valueSats == null || max <= 0) return 1.5;
  return 1.5 + valueSats / max * 7.5;
}

/// Transaction flow: inputs converge into the transaction node, outputs
/// fan out, the fee drops below. Curve thickness follows the amounts,
/// in the spirit of Sparrow and mempool.space. Pure geometry: the lane
/// grid is fixed, so positions are computed, never measured. Scrolls
/// horizontally when the screen is narrower than the lane grid.
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
    final showFee = feeSats != null && feeSats! > 0;
    final canvasHeight = height + (showFee ? _feeDrop : 0);

    double laneY(int index, int count) => count == laneCount
        ? index * _row + _row / 2
        : (height - count * _row) / 2 + index * _row + _row / 2;

    final diagram = Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wanted = _minSide * 2 + _mid;
            final width = math.max(constraints.maxWidth, wanted);
            final content = SizedBox(
              width: width,
              height: canvasHeight,
              child: Row(
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
                      laneCount: laneCount,
                      height: height,
                      maxValue: maxValue,
                      feeSats: showFee ? feeSats : null,
                      lineColor: tokens.border,
                      mineColor: tokens.primary,
                      feeColor: tokens.pending,
                      nodeFill: tokens.surface,
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
            );
            if (constraints.maxWidth >= wanted) return content;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            );
          },
        ),
        if (showFee)
          Padding(
            padding: const EdgeInsets.only(top: GerfautSpacing.xs),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Network fee · ',
                  style: tokens.label.copyWith(color: tokens.pending),
                ),
                InlineAmount(sats: feeSats!),
                if (feeRate != null)
                  Text(
                    ' (${feeRate!.toStringAsFixed(1)} sat/vB)',
                    style: tokens.label.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: diagram,
    );
  }
}

enum _Side { input, output }

class _LaneColumn extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, lane) in lanes.indexed)
            Positioned(
              left: 0,
              right: side == _Side.input ? GerfautSpacing.sm : null,
              top: laneY(index) - _row / 2,
              height: _row,
              child: Padding(
                padding: EdgeInsets.only(
                  left: side == _Side.output ? GerfautSpacing.sm : 0,
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
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      )
                    else if (lane.label != null)
                      AddressChip(value: lane.label!)
                    else
                      Text(
                        side == _Side.input ? 'coinbase' : 'unknown',
                        style: tokens.data.copyWith(color: tokens.textMuted),
                      ),
                    if (lane.valueSats != null)
                      InlineAmount(sats: lane.valueSats!),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  const _FlowPainter({
    required this.inLanes,
    required this.outLanes,
    required this.laneCount,
    required this.height,
    required this.maxValue,
    required this.feeSats,
    required this.lineColor,
    required this.mineColor,
    required this.feeColor,
    required this.nodeFill,
  });

  final List<_Lane> inLanes;
  final List<_Lane> outLanes;
  final int laneCount;
  final double height;
  final int maxValue;
  final int? feeSats;
  final Color lineColor;
  final Color mineColor;
  final Color feeColor;
  final Color nodeFill;

  double _laneY(int index, int count) => count == laneCount
      ? index * _row + _row / 2
      : (height - count * _row) / 2 + index * _row + _row / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeHeight = math.max(40.0, math.min(height * 0.6, 160.0));
    final nodeTop = (height - nodeHeight) / 2;
    const nodeX = _mid / 2;
    double nodeY(int index, int count) =>
        nodeTop + (index + 0.5) / count * nodeHeight;

    Paint stroke(Color color, double opacity, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = width;

    for (final (index, lane) in inLanes.indexed) {
      final y = _laneY(index, inLanes.length);
      final ny = nodeY(index, inLanes.length);
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(_mid * 0.3, y, nodeX - 40, ny, nodeX - 9, ny);
      canvas.drawPath(
        path,
        stroke(
          lane.mine ? mineColor : lineColor,
          lane.mine ? 0.75 : 1,
          _strokeWidth(lane.valueSats, maxValue),
        ),
      );
    }
    for (final (index, lane) in outLanes.indexed) {
      final y = _laneY(index, outLanes.length);
      final ny = nodeY(index, outLanes.length);
      final path = Path()
        ..moveTo(nodeX + 9, ny)
        ..cubicTo(nodeX + 40, ny, _mid * 0.7, y, _mid, y);
      canvas.drawPath(
        path,
        stroke(
          lane.mine ? mineColor : lineColor,
          lane.mine ? 0.75 : 1,
          _strokeWidth(lane.valueSats, maxValue),
        ),
      );
    }

    if (feeSats != null) {
      // Dotted branch: short dashes with round caps read as dots.
      final path = Path()
        ..moveTo(nodeX, nodeTop + nodeHeight - 2)
        ..lineTo(nodeX, height + _feeDrop - 18);
      final paint = stroke(
        feeColor,
        0.8,
        math.max(1.5, _strokeWidth(feeSats, maxValue)),
      );
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          canvas.drawPath(
            metric.extractPath(distance, distance + 1),
            paint,
          );
          distance += 7;
        }
      }
    }

    final node = RRect.fromRectAndRadius(
      Rect.fromLTWH(nodeX - 9, nodeTop, 18, nodeHeight),
      const Radius.circular(9),
    );
    canvas.drawRRect(node, Paint()..color = nodeFill);
    canvas.drawRRect(
      node,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) {
    return old.inLanes != inLanes ||
        old.outLanes != outLanes ||
        old.maxValue != maxValue ||
        old.feeSats != feeSats ||
        old.lineColor != lineColor ||
        old.mineColor != mineColor ||
        old.feeColor != feeColor ||
        old.nodeFill != nodeFill;
  }
}
