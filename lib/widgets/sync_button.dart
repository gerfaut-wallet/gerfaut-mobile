import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';

/// The sync action in an app bar: the arrows turn while the sync runs.
///
/// A greyed out button says the action is unavailable, which is not the
/// news here: the news is that work is under way. So the icon keeps its
/// full colour and turns instead. The movement is never the only
/// channel, the freshness line says "Syncing…" in words at the same
/// time, and a device asking for less motion gets the still icon.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key, required this.syncing, required this.onPressed});

  final bool syncing;

  /// Ignored while [syncing]: a second sync would only queue behind the
  /// first one. Null when there is nothing to sync at all.
  final VoidCallback? onPressed;

  /// One turn. Slow enough to read as steady work, not as a warning.
  static const Duration turn = Duration(milliseconds: 1400);

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SyncButton.turn,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(SyncButton old) {
    super.didUpdateWidget(old);
    if (old.syncing != widget.syncing) _apply();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.syncing && !still) {
      if (!_controller.isAnimating) _controller.repeat();
      return;
    }
    if (!_controller.isAnimating) return;
    if (still) {
      _controller
        ..stop()
        ..value = 0;
      return;
    }
    // The turn under way finishes rather than stopping mid-rotation.
    _controller.forward().then((_) {
      if (mounted) _controller.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return IconButton(
      tooltip: widget.syncing ? 'Syncing…' : 'Sync',
      onPressed: widget.syncing ? null : widget.onPressed,
      style: IconButton.styleFrom(
        foregroundColor: tokens.text,
        // Busy is not unavailable: while it turns the icon keeps its
        // colour, and only a button with nothing to sync greys out.
        disabledForegroundColor: widget.syncing
            ? tokens.text
            : tokens.textMuted,
      ),
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(LucideIcons.refreshCw, size: 20),
      ),
    );
  }
}
