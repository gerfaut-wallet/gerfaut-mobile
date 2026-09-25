import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../src/live.dart';
import '../../src/lock.dart';
import '../../src/models.dart';
import '../../src/notifications.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';

/// Opens the sheet that explains Live watch and, on a yes, turns it on
/// and walks through what Android has to be asked. Answers whether Live
/// is on when the sheet closes.
Future<bool> showLiveSheet(BuildContext context) async {
  final turnedOn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const LiveSheet(),
  );
  return turnedOn ?? false;
}

/// Where the sheet stands. One question at a time, each with its reason
/// above it, each refusable.
enum _Step { explain, notificationsRefused, battery, phoneMaker }

/// What Live watch is, said before anything is asked of the system:
/// what it does, what it costs, what the server learns, what stops it.
class LiveSheet extends ConsumerStatefulWidget {
  const LiveSheet({super.key});

  @override
  ConsumerState<LiveSheet> createState() => _LiveSheetState();
}

class _LiveSheetState extends ConsumerState<LiveSheet> {
  _Step _step = _Step.explain;
  bool _busy = false;
  bool _throughTor = false;
  PhoneBrand? _brand;

  /// Whether Android's battery exemption is granted, as last answered:
  /// the maker card leaves out the step that only grants it again.
  bool _exempt = false;

  @override
  void initState() {
    super.initState();
    ref.read(bridgeProvider).usesTor().then((tor) {
      if (mounted && tor) setState(() => _throughTor = true);
    }, onError: (_) {});
  }

  /// The yes. Notifications first, because without them Live would run
  /// and say nothing; then the service; then what makes it last.
  Future<void> _turnOn() async {
    setState(() => _busy = true);
    try {
      final granted = await ref
          .read(notificationServiceProvider)
          .requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _step = _Step.notificationsRefused);
        return;
      }
      await ref
          .read(backgroundCheckProvider.notifier)
          .set(BackgroundCheck.live);
      final platform = ref.read(livePlatformProvider);
      final exempt = await platform.isBatteryExempt();
      _exempt = exempt;
      _brand = PhoneBrand.of(await platform.manufacturer());
      if (!mounted) return;
      if (!exempt) {
        setState(() => _step = _Step.battery);
      } else {
        _afterBattery();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askBattery() async {
    setState(() => _busy = true);
    try {
      _exempt = await ref.read(liveProvider.notifier).requestBatteryExemption();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _afterBattery();
      }
    }
  }

  void _afterBattery() {
    if (_brand != null) {
      setState(() => _step = _Step.phoneMaker);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: GerfautSpacing.md,
        right: GerfautSpacing.md,
        top: GerfautSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + GerfautSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_step) {
              _Step.explain => _explain(context),
              _Step.notificationsRefused => _refused(context),
              _Step.battery => _battery(context),
              _Step.phoneMaker => _phoneMaker(context),
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _explain(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final automatic =
        settings != null &&
        settings.activeNetwork == Network.mainnet &&
        switch (settings.backendFor(Network.mainnet)) {
          PublicEsplora(:final server) => server == null,
          _ => false,
        };
    return [
      Text('Live watch', style: tokens.h2),
      const SizedBox(height: GerfautSpacing.sm),
      Text(
        'Gerfaut keeps a connection open to your server and tells you '
        'when a transaction appears, and again when it confirms.',
        style: tokens.body,
      ),
      const SizedBox(height: GerfautSpacing.md),
      const _Fact(
        title: 'What it takes',
        body:
            'A small permanent notification: Android requires one to let '
            'an app keep running. It also uses some battery, more on mobile '
            'data than on Wi-Fi. How much has not been measured yet.',
      ),
      const _Fact(
        title: 'What your server learns',
        body:
            'What a sync already tells it, which is the addresses of your '
            'wallets, and now also that your phone stays connected, from '
            'where, and when. Nothing goes to Gerfaut.',
      ),
      if (automatic)
        const _Fact(
          title: 'With the Automatic backend',
          body:
              'The live connection goes to an Electrum server of an '
              'operator already in the rotation. No new party is involved.',
        ),
      const _Fact(
        title: 'What can stop it',
        body:
            'Force-stopping Gerfaut ends Live until you open the app '
            'again: Android allows nothing else. Some phones’ battery '
            'savers stop it too, and the calculator disguise turns it off. '
            'Gerfaut still checks every 15 minutes whenever Live cannot '
            'run.',
      ),
      if (_throughTor) ...[
        const SizedBox(height: GerfautSpacing.xs),
        const GerfautNotice(
          tone: NoticeTone.info,
          message:
              'Your connection goes through Tor. Keeping it open costs '
              'more battery than a direct one, above all on mobile data.',
        ),
      ],
      const SizedBox(height: GerfautSpacing.md),
      PrimaryButton(
        label: _busy ? 'Turning on…' : 'Turn on Live',
        expand: true,
        onPressed: _busy ? null : _turnOn,
      ),
      const SizedBox(height: GerfautSpacing.sm),
      GhostButton(
        label: 'Not now',
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
      ),
    ];
  }

  List<Widget> _refused(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return [
      Text('Live needs notifications', style: tokens.h2),
      const SizedBox(height: GerfautSpacing.sm),
      Text(
        'Notifications are off for Gerfaut in the system settings. '
        'Without them Live would have nothing to tell you with, so it '
        'stays off. Allow them there, then choose Live again.',
        style: tokens.body,
      ),
      const SizedBox(height: GerfautSpacing.md),
      PrimaryButton(
        label: 'Close',
        expand: true,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ];
  }

  List<Widget> _battery(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return [
      Text('Live is on', style: tokens.h2),
      const SizedBox(height: GerfautSpacing.sm),
      Text('One more thing makes it last.', style: tokens.body),
      const SizedBox(height: GerfautSpacing.md),
      const _Fact(
        title: 'Let Gerfaut run in the background',
        body:
            'Android may stop Live after a while to save battery, and '
            'will not let it start again by itself unless Gerfaut is '
            'exempt from battery optimisation. Android asks you next; you '
            'can say no, and Live still runs, less reliably.',
      ),
      const SizedBox(height: GerfautSpacing.sm),
      PrimaryButton(
        label: 'Ask Android',
        expand: true,
        onPressed: _busy ? null : _askBattery,
      ),
      const SizedBox(height: GerfautSpacing.sm),
      GhostButton(label: 'Not now', onPressed: _busy ? null : _afterBattery),
    ];
  }

  /// Opens Gerfaut's page in the system settings. The trip is one the
  /// sheet sends the user on, and the steps are still to be read on the
  /// way back: it does not count as leaving the app.
  Future<void> _openAppSettings() async {
    final lock = ref.read(lockProvider.notifier)..expectExcursion();
    final opened = await ref.read(livePlatformProvider).openAppSettings();
    if (!opened) lock.forgetExcursion();
  }

  List<Widget> _phoneMaker(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final brand = _brand!;
    final steps = brand.maker.stepsFor(exempt: _exempt);
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    return [
      Semantics(
        header: true,
        child: Text('On a ${brand.label} phone', style: tokens.h2),
      ),
      const SizedBox(height: GerfautSpacing.sm),
      Text(
        'This phone runs its own battery manager, and it stops background '
        'apps whatever Android allows. Gerfaut cannot change these settings '
        'for you. To keep Live running:',
        style: tokens.body,
      ),
      const SizedBox(height: GerfautSpacing.sm),
      for (final (index, step) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: GerfautSpacing.xs),
          // One node per step, its place in the list said first.
          child: MergeSemantics(
            child: Semantics(
              label: 'Step ${index + 1} of ${steps.length}.',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 20,
                      child: Text('${index + 1}.', style: muted),
                    ),
                  ),
                  Expanded(child: Text(step, style: muted)),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: GerfautSpacing.sm),
      SecondaryButton(
        label: 'Open Gerfaut’s app info',
        icon: LucideIcons.settings,
        onPressed: _openAppSettings,
      ),
      const SizedBox(height: GerfautSpacing.sm),
      Text(
        'Menus move from one version to the next. dontkillmyapp.com keeps '
        'the steps up to date for each maker.',
        style: muted,
      ),
      const SizedBox(height: GerfautSpacing.md),
      PrimaryButton(
        label: 'Done',
        expand: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      const SizedBox(height: GerfautSpacing.sm),
      GhostButton(
        label: 'Open dontkillmyapp.com',
        icon: LucideIcons.externalLink,
        onPressed: () => launchUrl(
          Uri.parse(brand.helpUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ];
  }
}

/// A titled paragraph of the explanation.
class _Fact extends StatelessWidget {
  const _Fact({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tokens.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
              fontVariations: const [FontVariation('wght', 500)],
            ),
          ),
          Text(body, style: tokens.bodySmall.copyWith(color: tokens.textMuted)),
        ],
      ),
    );
  }
}
