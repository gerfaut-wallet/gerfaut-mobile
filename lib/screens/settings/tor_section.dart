import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/onion_icon.dart';
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
      if (!mounted) return;
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
      // A bootstrap can take a minute and a half: by the time it
      // answers the screen may be gone, and `ref` would throw.
      if (mounted) {
        setState(() => _connecting = false);
        ref.invalidate(torStatusProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final tor = ref.watch(settingsProvider).valueOrNull?.tor;
    final status = ref.watch(torStatusProvider).valueOrNull;
    if (tor == null) return const SizedBox.shrink();
    final embedded = status?.embeddedAvailable ?? false;

    // No semantic label on the glyph: the title beside it already
    // says the word, and a screen reader would say it twice.
    return SectionCard.glyph(
      glyph: const OnionIcon(),
      title: 'Tor',
      children: [
        Text(
          embedded
              ? 'An address ending in .onion goes through Tor. Gerfaut '
                    'starts its own Tor client, or uses the one already '
                    'running on this device when told to.'
              : 'An address ending in .onion goes through Tor. This build '
                    'has no Tor of its own: choose System below, with a Tor '
                    'app such as Orbot running on this device.',
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
        // The system proxy is whatever answers on a local port. On a
        // desktop that is the user's own daemon; on a phone the port is
        // first come, first served, and the app holding it learns every
        // .onion name and can answer for the server. So on Android
        // Automatic is the built-in client and nothing else — the core
        // never falls back to a local port there — and choosing the
        // system one is said for what it is.
        Text(switch (tor.mode) {
          TorMode.auto =>
            'The built-in Tor. A Tor app on this device is used only '
                'when you choose it below.',
          TorMode.system =>
            'Only the Tor on this device, at '
                '${tor.socksProxy ?? status?.socksProxy ?? '127.0.0.1:9050'}. '
                'On a phone any app can answer on that port and pose as '
                'Tor, which is why Automatic never falls back to it on '
                'Android.',
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
