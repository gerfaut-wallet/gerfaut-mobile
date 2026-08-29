import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/section_card.dart';

/// Where Tor stands right now. Read on demand: nothing is probed or
/// started until the screen asks.
final torStatusProvider = FutureProvider.autoDispose<TorStatus>((ref) {
  // Re-read after the mode changes.
  ref.watch(settingsProvider);
  return ref.watch(bridgeProvider).torStatus();
});

/// The settings card for how `.onion` backends reach Tor.
class TorSection extends ConsumerStatefulWidget {
  const TorSection({super.key});

  @override
  ConsumerState<TorSection> createState() => _TorSectionState();
}

class _TorSectionState extends ConsumerState<TorSection> {
  bool _connecting = false;
  String? _error;
  TorRoute? _route;

  Future<void> _setMode(TorMode mode) async {
    setState(() {
      _error = null;
      _route = null;
    });
    final settings = ref.read(settingsProvider).valueOrNull;
    try {
      await ref
          .read(bridgeProvider)
          .setTorSettings(
            TorSettings(mode: mode, socksProxy: settings?.tor.socksProxy),
          );
      ref.invalidate(settingsProvider);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
      _route = null;
    });
    try {
      final route = await ref.read(bridgeProvider).torConnect();
      if (mounted) setState(() => _route = route);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
      ref.invalidate(torStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final tor = ref.watch(settingsProvider).valueOrNull?.tor;
    final status = ref.watch(torStatusProvider).valueOrNull;
    if (tor == null) return const SizedBox.shrink();
    final embedded = status?.embeddedAvailable ?? false;

    return SectionCard(
      icon: LucideIcons.venetianMask,
      title: 'Tor',
      children: [
        Text(
          embedded
              ? 'An address ending in .onion goes through Tor. Gerfaut uses '
                    'the Tor already running on this device when there is '
                    'one, and starts its own otherwise.'
              : 'An address ending in .onion goes through Tor. This build '
                    'has no Tor of its own: start Tor or Orbot first.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        ChoiceGroup<TorMode>(
          label: 'Tor',
          value: tor.mode,
          options: [
            for (final mode in TorMode.values)
              ChoiceOption(
                value: mode,
                label: mode.label,
                // Nothing built in means nothing to choose.
                enabled: embedded || mode != TorMode.embedded,
              ),
          ],
          onChanged: _setMode,
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(switch (tor.mode) {
          TorMode.auto =>
            'The Tor on this device if it answers, the built-in one '
                'otherwise.',
          TorMode.system =>
            'Only the Tor on this device, at '
                '${tor.socksProxy ?? status?.socksProxy ?? '127.0.0.1:9050'}.',
          TorMode.embedded =>
            'Only the built-in Tor. The first connection takes a little '
                'longer while it starts.',
        }, style: tokens.bodySmall.copyWith(color: tokens.textMuted)),
        if (status != null && status.running) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            status.bootstrapped
                ? 'Running through the ${status.via?.label ?? 'Tor'}.'
                : 'Starting… ${status.bootstrapPercent}%',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        if (_route != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'Reached through the ${_route!.via.label}.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryButton(
            label: _connecting ? 'Connecting…' : 'Test the connection',
            icon: LucideIcons.plug,
            onPressed: _connecting ? null : _connect,
          ),
        ),
      ],
    );
  }
}
