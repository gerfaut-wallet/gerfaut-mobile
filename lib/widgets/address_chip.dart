import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../theme/tokens.dart';

/// Address or txid shown inline: Givre surface, mono 13px, truncated in
/// the middle only. Tap copies the full value with explicit feedback —
/// the icon flips to a check for 1.5 s.
class AddressChip extends StatefulWidget {
  const AddressChip({
    super.key,
    required this.value,
    this.head = 6,
    this.tail = 4,
    this.emphasis = false,
  });

  final String value;
  final int head;
  final int tail;

  /// Wallet-owned address: primary wash and full-strength medium text,
  /// so "mine" reads against the muted external gray (desktop mirror).
  final bool emphasis;

  @override
  State<AddressChip> createState() => _AddressChipState();
}

class _AddressChipState extends State<AddressChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Semantics(
      button: true,
      label: 'Copy ${widget.value}',
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        onTap: _copy,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.sm,
            vertical: GerfautSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.emphasis
                ? tokens.primary.withValues(alpha: 0.10)
                : tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  truncateMiddle(
                    widget.value,
                    head: widget.head,
                    tail: widget.tail,
                  ),
                  style: widget.emphasis
                      ? tokens.data.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w500,
                          fontVariations: const [FontVariation('wght', 500)],
                        )
                      : tokens.data.copyWith(color: tokens.textMuted),
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Icon(
                _copied ? LucideIcons.check : LucideIcons.copy,
                size: 14,
                color: _copied ? tokens.confirmed : tokens.textMuted,
              ),
              if (_copied) ...[
                const SizedBox(width: GerfautSpacing.xs),
                Text(
                  'Copied',
                  style: tokens.label.copyWith(color: tokens.confirmed),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
