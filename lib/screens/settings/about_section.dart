import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../src/models.dart';
import '../../src/onboarding.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_card.dart';
import '../welcome.dart';

/// Application version shown in About. Kept in step with pubspec.yaml.
const String appVersion = '0.1.0';

/// The About card: the version, a release check, and the way back to
/// the welcome tour.
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _checkingUpdate = false;
  UpdateCheck? _updateResult;
  bool _updateFailed = false;

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingUpdate = true;
      _updateFailed = false;
      _updateResult = null;
    });
    try {
      final result = await ref.read(bridgeProvider).checkUpdate(appVersion);
      if (mounted) setState(() => _updateResult = result);
    } catch (_) {
      if (mounted) setState(() => _updateFailed = true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final result = _updateResult;
    return SectionCard(
      icon: LucideIcons.info,
      title: 'About',
      children: [
        Text.rich(
          TextSpan(
            text: 'Gerfaut $appVersion',
            style: tokens.bodySmall,
            children: [
              TextSpan(
                text: '  for Android',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.md),
        if (_updateFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Text(
              'Could not reach the release page. Try again later.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        if (result != null && !result.updateAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Text(
              'You are up to date.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        Row(
          children: [
            if (result != null && result.updateAvailable) ...[
              PrimaryButton(
                label: 'Get ${result.latest}',
                onPressed: () => launchUrl(
                  Uri.parse(result.url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
            ],
            SecondaryButton(
              label: _checkingUpdate ? 'Checking…' : 'Check for updates',
              icon: LucideIcons.refreshCw,
              onPressed: _checkingUpdate ? null : _checkForUpdates,
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            label: 'Show the welcome tour',
            icon: LucideIcons.compass,
            onPressed: () {
              ref.read(onboardingSeenProvider.notifier).replay();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
              );
            },
          ),
        ),
      ],
    );
  }
}
