import 'package:flutter/material.dart';

import '../../src/bridge.dart';
import '../../src/premium.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';

/// A call that failed, in an amber note under the card it concerns.
/// The words follow the kind: the server out of reach gets a retry, a
/// key the server refuses gets the reason. Which sentence each kind
/// gets lives in [premiumFailure], with the pages that add a channel.
class PremiumErrorNote extends StatelessWidget {
  const PremiumErrorNote({
    super.key,
    required this.error,
    this.onRetry,
    this.refusal,
  });

  final BridgeException error;
  final VoidCallback? onRetry;

  /// The first line when the server refused what this card asked.
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final failure = premiumFailure(error, refusal: refusal);
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: GerfautNotice(
        tone: NoticeTone.info,
        message: failure.message,
        hint: failure.hint,
        detail: failure.detail,
        liveRegion: true,
        action: failure.retry && onRetry != null
            ? GhostButton(label: 'Retry', onPressed: onRetry)
            : null,
      ),
    );
  }
}
