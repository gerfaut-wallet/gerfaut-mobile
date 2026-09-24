import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/disguise.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/notifications.dart';
import '../src/premium.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import 'scan.dart';
import 'settings/about_section.dart';
import 'settings/backup_section.dart';
import 'settings/general_section.dart';
import 'settings/network_section.dart';
import 'settings/notifications_section.dart';
import 'settings/premium_section.dart';
import 'settings/security_section.dart';
import 'settings/wallets_section.dart';
import 'settings/widgets_section.dart';

/// The eight sections of the settings, in the order the root lists
/// them. The same names as the desktop app, so a setting found on one
/// platform is found on the other by the same word.
enum SettingsSection {
  general('General', LucideIcons.slidersHorizontal),
  network('Network', LucideIcons.globe),
  wallets('Wallets', LucideIcons.wallet),
  security('Security', LucideIcons.lock),
  notifications('Notifications', LucideIcons.bell),
  backup('Backup & sync', LucideIcons.archive),
  about('About', LucideIcons.info),
  premium('Premium', LucideIcons.gem);

  const SettingsSection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Settings: a root list of eight sections, each a screen of its own.
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
      case SettingsSection.premium:
        final premium = ref.watch(premiumStateProvider).valueOrNull;
        if (premium == null) return null;
        switch (licenceStatus(premium)) {
          case LicenceStatus.none:
            return 'Not activated';
          case LicenceStatus.expired:
            return 'Expired ${relativeTimeWords(premium.claims!.expiresAt)}';
          case LicenceStatus.active:
            final until =
                'Active until ${formatDate(premium.claims!.expiresAt)}';
            // A device the server let go, or one still waiting, sees
            // nothing of the account: the line says where it stands
            // rather than a count it cannot have.
            if (premium.disconnected) return '$until · disconnected';
            final me = ref.watch(premiumMeProvider).valueOrNull;
            if (me != null && !me.fullAccess) {
              return '$until · waiting for approval';
            }
            // The count is the server's, read once a key is set; until
            // it answers, the date stands alone rather than a guess.
            final watched = ref.watch(premiumWalletsProvider).valueOrNull;
            if (watched == null) return until;
            final count = switch (watched.length) {
              0 => 'no wallets watched',
              1 => '1 wallet watched',
              final n => '$n wallets watched',
            };
            return '$until · $count';
        }
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
        child: switch (section) {
          SettingsSection.general => _cards(const [GeneralSection()]),
          SettingsSection.network => _cards([
            // A test seam of the section; this screen only forwards
            // its own, which is null outside a test.
            // ignore: invalid_use_of_visible_for_testing_member
            NetworkSection(cameraBuilder: cameraBuilder),
          ]),
          // The wallet rows reorder by drag, and a drag has to scroll
          // the page to reach a row out of sight: this section is its
          // own scroll view, with the rows as a sliver of it.
          SettingsSection.wallets => const WalletsSection(),
          SettingsSection.security => _cards(const [SecuritySection()]),
          SettingsSection.notifications => _cards(const [
            NotificationsSection(),
            WidgetsSection(),
          ]),
          SettingsSection.backup => _cards(const [BackupSection()]),
          SettingsSection.about => _cards(const [AboutSection()]),
          SettingsSection.premium => _cards(const [PremiumSection()]),
        },
      ),
    );
  }

  /// The section's cards, one under the other, on a page that scrolls.
  static Widget _cards(List<Widget> cards) {
    return ListView(
      padding: const EdgeInsets.all(GerfautSpacing.md),
      children: [
        ...cards,
        const SizedBox(height: GerfautSpacing.lg),
      ],
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
              // Bruyère on the gem: the premium colour marks the premium
              // row, and nothing else on this list.
              Icon(
                section.icon,
                size: 20,
                color: section == SettingsSection.premium
                    ? tokens.premium
                    : tokens.textMuted,
              ),
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
