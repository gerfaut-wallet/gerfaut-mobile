import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../src/bridge.dart';
import '../../src/models.dart';
import '../../src/onboarding.dart';
import '../../src/state.dart';
import '../../src/updates.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_card.dart';
import '../../widgets/setting_switch.dart';
import '../../widgets/status_pill.dart';
import '../welcome.dart';

export '../../src/updates.dart' show appVersion;

/// The About card: the version, a release check on demand and the
/// switch of the automatic one, and the way back to the welcome tour.
///
/// Every 0.x version is a public beta: the card says so next to the
/// version, with one line on what that asks of you and a button to
/// report a problem. Both go away by themselves at 1.0.0.
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _checkingUpdate = false;
  UpdateCheck? _updateResult;
  bool _updateFailed = false;
  bool _torDown = false;

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingUpdate = true;
      _updateFailed = false;
      _torDown = false;
      _updateResult = null;
    });
    try {
      final result = await ref.read(bridgeProvider).checkUpdate(appVersion);
      if (!mounted) return;
      ref.read(updateProvider.notifier).record(result);
      setState(() => _updateResult = result);
    } on BridgeException catch (error) {
      if (!mounted) return;
      // With a .onion node the request only ever leaves through Tor.
      setState(() {
        _torDown = error.kind == 'tor';
        _updateFailed = !_torDown;
      });
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
    // The tag is the network's word: only a version that parses is
    // named, and the page it opens is ours to choose, not the answer's.
    final newer = announcedVersion(result?.latest);
    final automatic = ref.watch(updateProvider).automatic;
    final beta = isBetaVersion(appVersion);
    return SectionCard(
      icon: LucideIcons.info,
      title: 'About',
      children: [
        Wrap(
          spacing: GerfautSpacing.sm,
          runSpacing: GerfautSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Gerfaut $appVersion', style: tokens.bodySmall),
            if (beta)
              const StatusPill.tone(
                tone: PillTone.pending,
                icon: LucideIcons.flaskConical,
                label: 'Beta',
              ),
            Text(
              'for Android',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
        if (beta) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'This is a public beta. Check addresses and amounts on your '
            'signing device, and report anything that looks wrong.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: 'Report a problem',
              icon: LucideIcons.messageSquareWarning,
              onPressed: () => launchUrl(
                Uri.parse(issuesPageUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        if (_updateFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Text(
              'Could not reach the release page. Try again later.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        if (_torDown)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Text(
              'Tor could not be reached, so nothing was asked. Your node is '
              'a .onion address, and this request only goes through Tor.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        if (result != null && newer == null)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
            child: Text(
              'You are up to date.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        Row(
          children: [
            if (newer != null) ...[
              PrimaryButton(
                label: 'Get $newer',
                onPressed: () => launchUrl(
                  Uri.parse(releasePageUrl),
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
        const SizedBox(height: GerfautSpacing.md),
        SettingSwitch(
          title: 'Check automatically',
          // Worded as on the desktop; the disguise is the phone's alone.
          hint:
              'Asks GitHub for the latest release at most once a day while '
              'Gerfaut is unlocked, and downloads nothing. With a .onion '
              'node it goes through Tor or not at all, and never while the '
              'app is disguised.',
          value: automatic,
          onChanged: (on) => ref.read(updateProvider.notifier).setAutomatic(on),
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
