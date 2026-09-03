import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/disguise.dart';
import '../src/models.dart';
import '../src/notifications.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import 'scan.dart';
import 'settings/about_section.dart';
import 'settings/backup_section.dart';
import 'settings/general_section.dart';
import 'settings/network_section.dart';
import 'settings/notifications_section.dart';
import 'settings/security_section.dart';
import 'settings/wallets_section.dart';
import 'settings/widgets_section.dart';

/// The seven sections of the settings, in the order the root lists
/// them. The same names as the desktop app, so a setting found on one
/// platform is found on the other by the same word.
enum SettingsSection {
  general('General', LucideIcons.slidersHorizontal),
  network('Network', LucideIcons.globe),
  wallets('Wallets', LucideIcons.wallet),
  security('Security', LucideIcons.lock),
  notifications('Notifications', LucideIcons.bell),
  backup('Backup & sync', LucideIcons.archive),
  about('About', LucideIcons.info);

  const SettingsSection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Settings: a root list of seven sections, each a screen of its own.
///
/// One long page held every card; finding the gap limit meant scrolling
/// past the backend form and the Tor card every time. The root now
/// names the sections and says where each stands in a line, and a
/// section opens on its own page with only its cards.
///
/// Given a [section], the screen *is* that section's page: another
/// screen that wants to land someone on Wallets pushes this and the back
/// arrow returns where they came from, not to a root list they never
/// asked for.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    this.section,
    @visibleForTesting this.cameraBuilder,
  });

  /// Opens the settings on [section], or on the root list.
  static Future<void> open(BuildContext context, {SettingsSection? section}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(section: section)),
    );
  }

  /// The section to land on; null for the root list.
  final SettingsSection? section;

  /// Replaces the camera view of the backend scanner; tests push frames
  /// by hand.
  final CameraBuilder? cameraBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = this.section;
    if (section != null) {
      return SettingsSectionScreen(
        section: section,
        cameraBuilder: cameraBuilder,
      );
    }
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: GerfautAppBar.text('Settings'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(GerfautRadius.lg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                children: [
                  for (final (index, section)
                      in SettingsSection.values.indexed) ...[
                    if (index > 0)
                      Divider(height: 1, thickness: 1, color: tokens.border),
                    _SectionRow(
                      section: section,
                      summary: _summary(ref, section),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsSectionScreen(
                            section: section,
                            cameraBuilder: cameraBuilder,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: GerfautSpacing.lg),
          ],
        ),
      ),
    );
  }

  /// One line under a section's name: where it stands right now, from
  /// state the root already holds. Null while the vault has not
  /// answered.
  String? _summary(WidgetRef ref, SettingsSection section) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    switch (section) {
      case SettingsSection.general:
        final unit = ref.watch(unitProvider);
        final fiat = ref.watch(fiatEnabledProvider)
            ? ref.watch(fiatCurrencyProvider).code
            : 'no fiat';
        final theme = ref.watch(themeProvider);
        return '${unit.label} · $fiat · ${theme.label} theme';
      case SettingsSection.network:
        if (settings == null) return null;
        final network = settings.activeNetwork;
        final backend = switch (settings.backendFor(network)) {
          PublicEsplora() => 'Public API',
          CustomEsplora() => 'Own Esplora',
          CustomElectrum() => 'Own Electrum server',
        };
        return '${network.label} · $backend';
      case SettingsSection.wallets:
        final wallets = ref.watch(walletsProvider).valueOrNull;
        if (settings == null || wallets == null) return null;
        final count = switch (wallets.length) {
          0 => 'No wallets',
          1 => '1 wallet',
          final n => '$n wallets',
        };
        return '$count · gap limit ${settings.gapLimit}';
      case SettingsSection.security:
        if (settings == null) return null;
        final lock = settings.appLock;
        if (lock == null) return 'No app lock';
        final disguised = ref.watch(disguiseProvider).disguised;
        return [
          '${lock.kind.label} lock',
          if (lock.biometric) 'biometrics',
          if (disguised) 'disguised',
        ].join(' · ');
      case SettingsSection.notifications:
        if (!ref.watch(notifyNewTxProvider)) return 'Off';
        final cadence = ref.watch(backgroundCheckProvider);
        return cadence == BackgroundCheck.off
            ? 'On · while the app is open'
            : 'On · ${cadence.label.toLowerCase()}';
      case SettingsSection.backup:
        return 'Export or restore the wallet list';
      case SettingsSection.about:
        return 'Gerfaut $appVersion';
    }
  }
}

/// One section's page: its title in the bar, its cards below, nothing
/// else. The cards are the same ones the single long page held.
class SettingsSectionScreen extends StatelessWidget {
  const SettingsSectionScreen({
    super.key,
    required this.section,
    @visibleForTesting this.cameraBuilder,
  });

  final SettingsSection section;

  /// Replaces the camera view of the backend scanner; tests push frames
  /// by hand.
  final CameraBuilder? cameraBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GerfautAppBar.text(section.title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            ...switch (section) {
              SettingsSection.general => const [GeneralSection()],
              SettingsSection.network => [
                // A test seam of the section; this screen only forwards
                // its own, which is null outside a test.
                // ignore: invalid_use_of_visible_for_testing_member
                NetworkSection(cameraBuilder: cameraBuilder),
              ],
              SettingsSection.wallets => const [WalletsSection()],
              SettingsSection.security => const [SecuritySection()],
              SettingsSection.notifications => const [
                NotificationsSection(),
                WidgetsSection(),
              ],
              SettingsSection.backup => const [BackupSection()],
              SettingsSection.about => const [AboutSection()],
            },
            const SizedBox(height: GerfautSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// One row of the root: the section's glyph, its name, where it stands,
/// and the chevron that says it opens. A list row, not a card: seven
/// cards would be seven frames around seven words.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.summary,
    required this.onTap,
  });

  final SettingsSection section;
  final String? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.md,
            vertical: GerfautSpacing.sm + GerfautSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: tokens.textMuted),
              const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    if (summary != null)
                      Text(
                        summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              // Visible at rest: a row that opens has to read as one
              // before anyone touches it.
              Icon(LucideIcons.chevronRight, size: 16, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
