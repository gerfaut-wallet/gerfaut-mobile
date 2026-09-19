import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_card.dart';
import '../backup_export.dart';
import '../backup_restore.dart';

/// The settings card that seals the wallet list under a password and
/// opens such a backup: the file or the animated QR code a backup makes
/// is also how wallets travel between the desktop and the phone.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SectionCard(
      icon: LucideIcons.archive,
      title: 'Backup & sync',
      children: [
        Text(
          'Every wallet you watch, encrypted with a password you choose. '
          'Restore it on another device: the same file or QR code moves '
          'your wallets between the desktop and the phone. A backup holds '
          'descriptors and addresses, never a private key or seed.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            SecondaryButton(
              label: 'Export…',
              icon: LucideIcons.upload,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BackupExportScreen(),
                ),
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            SecondaryButton(
              label: 'Restore…',
              icon: LucideIcons.download,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BackupRestoreScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
