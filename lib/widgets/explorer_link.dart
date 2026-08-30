import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/state.dart';
import '../theme/tokens.dart';
import 'notice.dart';
import 'buttons.dart';

/// The "View on mempool.space" row: a 44px tap target around a one-line
/// link, behind the privacy warning.
class ExplorerLink extends ConsumerWidget {
  const ExplorerLink({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.sm),
        onTap: () => openExplorer(context, ref, url),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GerfautSpacing.sm + GerfautSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View on mempool.space',
                style: tokens.bodySmall.copyWith(color: tokens.primary),
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Icon(LucideIcons.externalLink, size: 14, color: tokens.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The explorer link sits behind a privacy warning: a third party can
/// link the transaction to the viewer's IP address. Once acknowledged
/// for good, the dialog steps aside.
void openExplorer(BuildContext context, WidgetRef ref, String url) {
  void launch() {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  if (ref.read(explorerAckProvider)) {
    launch();
    return;
  }

  final tokens = Theme.of(context).extension<GerfautTokens>()!;
  var skipNextTime = false;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            backgroundColor: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GerfautRadius.lg),
            ),
            title: Text('Open an external explorer', style: tokens.h2),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handing an explorer operator the link between this
                  // transaction and an IP address is a privacy loss:
                  // red, by the rule, not by the tone of the sentence.
                  const GerfautNotice(
                    tone: NoticeTone.alert,
                    message:
                        'This opens the transaction on mempool.space, a '
                        'third-party website. Its operator can link this '
                        'transaction to your IP address.',
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Consider a VPN or Tor if that link matters to you.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  InkWell(
                    borderRadius: BorderRadius.circular(GerfautRadius.sm),
                    onTap: () => setState(() => skipNextTime = !skipNextTime),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: GerfautSpacing.sm + 2,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: skipNextTime,
                              activeColor: tokens.primary,
                              checkColor: tokens.onPrimary,
                              side: BorderSide(
                                color: tokens.textMuted,
                                width: 1.5,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) =>
                                  setState(() => skipNextTime = value ?? false),
                            ),
                          ),
                          const SizedBox(width: GerfautSpacing.sm),
                          Expanded(
                            child: Text(
                              'Do not show this warning again',
                              style: tokens.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              PrimaryButton(
                label: 'Open explorer',
                onPressed: () {
                  if (skipNextTime) {
                    ref.read(explorerAckProvider.notifier).set(true);
                  }
                  Navigator.of(dialogContext).pop();
                  launch();
                },
              ),
            ],
          );
        },
      );
    },
  );
}
