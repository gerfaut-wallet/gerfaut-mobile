import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/notice.dart';
import '../widgets/wallet_icon.dart';

/// The one question asked before a descriptor leaves the device: a
/// whole page, once per wallet, never replayed.
///
/// The note is red because privacy is what is at stake (D-20): the
/// server will derive every address of the wallet, present and future,
/// and see when coins move. The page says so in plain words, lists
/// exactly what is sent, and puts the yes where a thumb finds it.
/// Answers true when the wallet is to be watched.
class PremiumConsentScreen extends StatelessWidget {
  const PremiumConsentScreen({super.key, required this.wallet});

  final WalletMeta wallet;

  /// Asks, and answers true on "Watch this wallet".
  static Future<bool> ask(BuildContext context, WalletMeta wallet) async {
    final answer = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PremiumConsentScreen(wallet: wallet),
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: GerfautAppBar.text('Watch this wallet from the server'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - GerfautSpacing.md * 2,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            walletGlyph(wallet.icon),
                            size: 20,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(width: GerfautSpacing.sm),
                          Expanded(
                            child: Text(
                              wallet.name,
                              style: tokens.h2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GerfautSpacing.md),
                      // Red: what is at stake is privacy, and the note says
                      // so on its own, in words, before anyone reads the
                      // colour.
                      const GerfautNotice(
                        tone: NoticeTone.alert,
                        message:
                            "Gerfaut's server will learn every address of "
                            'this wallet, present and future, and see when '
                            'coins move. It keeps nothing else: no name, no '
                            'e-mail unless you add one as a channel, no IP '
                            'address.',
                      ),
                      const SizedBox(height: GerfautSpacing.lg),
                      Text(
                        'WHAT LEAVES THIS DEVICE',
                        style: tokens.label.copyWith(color: tokens.textMuted),
                      ),
                      const SizedBox(height: GerfautSpacing.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(GerfautRadius.lg),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Column(
                          children: [
                            _SentRow(
                              icon: LucideIcons.fileKey,
                              label: 'The descriptor',
                              detail:
                                  'Public keys and script: enough to derive '
                                  'the addresses, never to spend.',
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: tokens.border,
                            ),
                            _SentRow(
                              icon: LucideIcons.pencil,
                              label: 'The name you gave the wallet',
                              detail:
                                  'So the alerts can say which wallet moved.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: GerfautSpacing.sm),
                      Text(
                        'Switch the wallet off in the settings and the server '
                        'forgets it at once.',
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: GerfautSpacing.lg),
                      Row(
                        children: [
                          GhostButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                          const SizedBox(width: GerfautSpacing.sm),
                          Expanded(
                            child: PremiumButton(
                              label: 'Watch this wallet',
                              expand: true,
                              onPressed: () => Navigator.of(context).pop(true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One thing that is sent: a glyph, its name, and what it amounts to.
class _SentRow extends StatelessWidget {
  const _SentRow({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm + GerfautSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstLine(
            style: tokens.bodySmall,
            child: Icon(icon, size: 16, color: tokens.textMuted),
          ),
          const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tokens.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
                Text(
                  detail,
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
