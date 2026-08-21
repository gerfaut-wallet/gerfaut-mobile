import 'package:flutter/material.dart';

import '../src/format.dart';
import '../theme/tokens.dart';

/// Large balance figure: mono, tabular, masked-aware, never animated.
/// BTC with all 8 decimals plus an explicit sats subline.
class BalanceAmount extends StatelessWidget {
  const BalanceAmount({super.key, required this.sats, required this.masked});

  final int sats;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: masked ? maskedValue : formatBtc(sats),
            style: tokens.amount,
            children: [
              TextSpan(
                text: ' BTC',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.xs),
        Text(
          masked ? maskedValue : formatSats(sats),
          style: tokens.data.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// Signed list amount. Direction is also carried by icon and sign
/// elsewhere in the row — color is never the only signal.
class ListAmount extends StatelessWidget {
  const ListAmount({
    super.key,
    required this.sats,
    required this.masked,
    this.pending = false,
  });

  final int sats;
  final bool masked;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final color = sats > 0 && !pending ? tokens.confirmed : tokens.text;
    return Text(
      masked ? maskedValue : formatBtcSigned(sats),
      style: tokens.data.copyWith(color: color),
      textAlign: TextAlign.right,
    );
  }
}
