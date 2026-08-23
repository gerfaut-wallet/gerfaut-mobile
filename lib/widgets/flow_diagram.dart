import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import 'address_chip.dart';

/// Vertical pitch of one input/output lane.
const double _row = 52;

/// Height of one lane card inside its row.
const double _cardH = 40;

/// Width of the strip carrying the links and the TX block.
const double _mid = 120;

/// Lanes shown per side before aggregation into a "+N more" lane.
const int _maxLanes = 7;

/// Width of the TX block.
const double _nodeW = 44;

/// Extra height under the lanes for the fee branch.
const double _feeDrop = 44;

/// Minimum width of one lane column; below that the diagram scrolls.
const double _minSide = 290;

/// What a lane means, which sets its icon and line color.
enum _LaneRole {
  mineIn,
  externalIn,
  coinbase,
  receive,
  change,
  externalOut,
  opReturn,
  more,
}

class _Lane {
  const _Lane({
    required this.role,
    required this.label,
    required this.valueSats,
    this.more = 0,
    this.preview,
  });

  final _LaneRole role;
  final String? label;
  final int? valueSats;

  /// Aggregated remainder lane ("+N more").
  final int more;

  /// OP_RETURN preview: decoded text, or hex.
  final String? preview;

  bool get mine =>
      role == _LaneRole.mineIn ||
      role == _LaneRole.receive ||
      role == _LaneRole.change;
}

enum _Side { input, output }

List<_Lane> _toLanes(List<TxIo> ios, _Side side, bool coinbase) {
  _Lane lane(TxIo io) {
    if (side == _Side.input) {
      return _Lane(
        role: coinbase
            ? _LaneRole.coinbase
            : io.isMine
            ? _LaneRole.mineIn
            : _LaneRole.externalIn,
        label: io.address,
        valueSats: io.valueSats,
      );
    }
    if (io.opReturn != null) {
      return _Lane(
        role: _LaneRole.opReturn,
        label: null,
        valueSats: null,
        preview: io.opReturn!.text ?? io.opReturn!.hex,
      );
    }
    return _Lane(
      role: io.isMine
          ? (io.change ? _LaneRole.change : _LaneRole.receive)
          : _LaneRole.externalOut,
      label: io.address,
      valueSats: io.valueSats,
    );
  }

  if (ios.length <= _maxLanes) return [for (final io in ios) lane(io)];
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
    for (final io in shown) lane(io),
    _Lane(
      role: _LaneRole.more,
      label: null,
      valueSats: restValue,
      more: rest.length,
    ),
  ];
}

/// Transaction flow: every input line converges on a central TX block
/// and every output line leaves it, mirrored and evenly spaced. Wallet
/// lanes carry the accent color and a role icon; the fee drips from the
/// block down to its pill. Pure geometry, nothing measured. Scrolls
/// horizontally inside its card on narrow screens.
class FlowDiagram extends StatelessWidget {
  const FlowDiagram({
    super.key,
    required this.inputs,
    required this.outputs,
    required this.feeSats,
    required this.feeRate,
    this.isCoinbase = false,
    this.coinbasePool,
  });

  final List<TxIo> inputs;
  final List<TxIo> outputs;
  final int? feeSats;
  final double? feeRate;
  final bool isCoinbase;
  final String? coinbasePool;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final inLanes = _toLanes(inputs, _Side.input, isCoinbase);
    final outLanes = _toLanes(outputs, _Side.output, false);
    final laneCount = math.max(math.max(inLanes.length, outLanes.length), 1);
    final height = laneCount * _row;
    final maxSide = math.max(inLanes.length, outLanes.length);
    // The block grows with the lane count but stays inside the strip.
    final nodeH = math.min(
      math.max(_nodeW, 12.0 * maxSide + 16),
      math.max(_nodeW, height - 8),
    );
    final nodeTop = (height - nodeH) / 2;

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
                        coinbasePool: coinbasePool,
                      ),
                    ),
                    CustomPaint(
                      size: Size(_mid, canvasHeight),
                      painter: _FlowPainter(
                        inRoles: [for (final lane in inLanes) lane.role],
                        outRoles: [for (final lane in outLanes) lane.role],
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
                        showFee: showFee,
                        primaryColor: tokens.primary,
                        mutedColor: tokens.textMuted,
                        pendingColor: tokens.pending,
                        borderColor: tokens.border,
                        nodeFill: tokens.surface,
                        labelStyle: tokens.data.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.96,
                          color: tokens.textMuted,
                          fontWeight: FontWeight.w500,
                          fontVariations: const [FontVariation('wght', 500)],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _LaneColumn(
                        lanes: outLanes,
                        side: _Side.output,
                        laneY: (index) => laneY(index, outLanes.length),
                        height: height,
                        coinbasePool: null,
                      ),
                    ),
                  ],
                ),
                if (showFee)
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      SizedBox(
                        width: _mid,
                        child: Center(
                          child: _FeePill(feeSats: feeSats!, feeRate: feeRate),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
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
    );
  }
}

/// Fee as a pending-tinted pill the dashed branch touches: amount in
/// the chosen unit, rate as small print. Never an alert.
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
              style: tokens.data.copyWith(fontSize: 12, color: tokens.pending),
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

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lanes,
    required this.side,
    required this.laneY,
    required this.height,
    required this.coinbasePool,
  });

  final List<_Lane> lanes;
  final _Side side;
  final double Function(int index) laneY;
  final double height;
  final String? coinbasePool;

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
              top: laneY(index) - _cardH / 2,
              height: _cardH,
              child: _LaneCard(lane: lane, side: side, pool: coinbasePool),
            ),
        ],
      ),
    );
  }
}

/// One input or output as a one-line card the link plugs into: role
/// icon, address chip, amount, never wrapping. Mine lanes carry the
/// primary tint, aggregate lanes a dashed outline.
class _LaneCard extends StatelessWidget {
  const _LaneCard({required this.lane, required this.side, required this.pool});

  final _Lane lane;
  final _Side side;
  final String? pool;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final (icon, iconColor) = switch (lane.role) {
      _LaneRole.mineIn => (LucideIcons.wallet, tokens.primary),
      _LaneRole.receive => (LucideIcons.arrowDownLeft, tokens.primary),
      _LaneRole.change => (LucideIcons.undo2, tokens.primary),
      _LaneRole.coinbase => (LucideIcons.pickaxe, tokens.textMuted),
      _LaneRole.opReturn => (LucideIcons.scrollText, tokens.pending),
      _ => (null, tokens.textMuted),
    };
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.sm + 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: GerfautSpacing.sm - 2),
          ],
          if (lane.role == _LaneRole.more)
            Text(
              '+${lane.more} more '
              '${side == _Side.input ? 'inputs' : 'outputs'}',
              style: tokens.bodySmall.copyWith(
                fontSize: 12,
                color: tokens.textMuted,
              ),
              maxLines: 1,
              softWrap: false,
            )
          else if (lane.role == _LaneRole.opReturn) ...[
            Text(
              'OP_RETURN',
              style: tokens.data.copyWith(fontSize: 12, color: tokens.pending),
              maxLines: 1,
              softWrap: false,
            ),
            if (lane.preview != null) ...[
              const SizedBox(width: GerfautSpacing.sm - 2),
              Flexible(
                child: Text(
                  lane.preview!,
                  style: tokens.data.copyWith(
                    fontSize: 11,
                    color: tokens.textMuted,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ] else if (lane.role == _LaneRole.coinbase)
            Flexible(
              child: Text(
                'coinbase${pool != null ? ' · $pool' : ''}',
                style: tokens.data.copyWith(color: tokens.textMuted),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (lane.label != null)
            Flexible(child: AddressChip(value: lane.label!))
          else
            Text(
              side == _Side.input ? 'unknown input' : 'script output',
              style: tokens.data.copyWith(color: tokens.textMuted),
              maxLines: 1,
              softWrap: false,
            ),
          if (lane.valueSats != null && lane.role != _LaneRole.opReturn) ...[
            const Spacer(),
            const SizedBox(width: GerfautSpacing.xs),
            _LaneAmount(sats: lane.valueSats!),
          ],
        ],
      ),
    );
    if (lane.role == _LaneRole.more) {
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
            : lane.role == _LaneRole.opReturn
            ? tokens.pendingSurface
            : tokens.background,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(
          color: lane.mine
              ? tokens.primary.withValues(alpha: 0.4)
              : lane.role == _LaneRole.opReturn
              ? tokens.pending.withValues(alpha: 0.3)
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
    required this.inRoles,
    required this.outRoles,
    required this.inYs,
    required this.outYs,
    required this.nodeTop,
    required this.nodeH,
    required this.showFee,
    required this.primaryColor,
    required this.mutedColor,
    required this.pendingColor,
    required this.borderColor,
    required this.nodeFill,
    required this.labelStyle,
  });

  final List<_LaneRole> inRoles;
  final List<_LaneRole> outRoles;
  final List<double> inYs;
  final List<double> outYs;
  final double nodeTop;
  final double nodeH;
  final bool showFee;
  final Color primaryColor;
  final Color mutedColor;
  final Color pendingColor;
  final Color borderColor;
  final Color nodeFill;
  final TextStyle labelStyle;

  Color _strokeOf(_LaneRole role) => switch (role) {
    _LaneRole.mineIn ||
    _LaneRole.receive ||
    _LaneRole.change => primaryColor.withValues(alpha: 0.9),
    _LaneRole.opReturn => pendingColor.withValues(alpha: 0.6),
    _ => mutedColor.withValues(alpha: 0.45),
  };

  /// Symmetric cubic between two points: control points at 45% and 55%.
  Path _link(double x0, double y0, double x1, double y1) {
    final c1 = x0 + (x1 - x0) * 0.45;
    final c2 = x0 + (x1 - x0) * 0.55;
    return Path()
      ..moveTo(x0, y0)
      ..cubicTo(c1, y0, c2, y1, x1, y1);
  }

  /// Anchors spread evenly inside the block edge, mirrored per side.
  double _anchorY(int index, int count) =>
      nodeTop + (nodeH * (index + 1)) / (count + 1);

  @override
  void paint(Canvas canvas, Size size) {
    const cx = _mid / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final (index, role) in inRoles.indexed) {
      canvas.drawPath(
        _link(
          0,
          inYs[index],
          cx - _nodeW / 2,
          _anchorY(index, inRoles.length),
        ),
        line..color = _strokeOf(role),
      );
    }
    for (final (index, role) in outRoles.indexed) {
      canvas.drawPath(
        _link(
          cx + _nodeW / 2,
          _anchorY(index, outRoles.length),
          _mid,
          outYs[index],
        ),
        line..color = _strokeOf(role),
      );
    }

    if (showFee) {
      // Dashed pending branch from the block down to the fee pill.
      final path = Path()
        ..moveTo(cx, nodeTop + nodeH)
        ..lineTo(cx, size.height);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..color = pendingColor.withValues(alpha: 0.7);
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          canvas.drawPath(metric.extractPath(distance, distance + 1), paint);
          distance += 7;
        }
      }
    }

    // The TX block: everything meets here.
    final node = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - _nodeW / 2, nodeTop, _nodeW, nodeH),
      const Radius.circular(10),
    );
    canvas.drawRRect(node, Paint()..color = nodeFill);
    canvas.drawRRect(
      node,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
    final label = TextPainter(
      text: TextSpan(text: 'TX', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(cx - label.width / 2, nodeTop + (nodeH - label.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) {
    return !listEquals(old.inRoles, inRoles) ||
        !listEquals(old.outRoles, outRoles) ||
        !listEquals(old.inYs, inYs) ||
        !listEquals(old.outYs, outYs) ||
        old.nodeTop != nodeTop ||
        old.nodeH != nodeH ||
        old.showFee != showFee ||
        old.primaryColor != primaryColor ||
        old.mutedColor != mutedColor ||
        old.pendingColor != pendingColor ||
        old.borderColor != borderColor ||
        old.nodeFill != nodeFill;
  }
}
