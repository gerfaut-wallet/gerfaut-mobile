import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'screens/backup_restore.dart';
import 'screens/calculator.dart';
import 'screens/home.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome.dart';
import 'src/disguise.dart';
import 'src/home_widgets.dart';
import 'src/lock.dart';
import 'src/models.dart';
import 'src/notifications.dart';
import 'src/onboarding.dart';
import 'src/premium.dart';
import 'src/state.dart';
import 'src/updates.dart';
import 'src/vault_key.dart';
import 'theme/tokens.dart';
import 'widgets/buttons.dart';
import 'widgets/notice.dart';

/// Root widget: both Toundra themes, light by default, and the startup
/// bootstrap (Rust bridge + encrypted vault) before the home screen.
class GerfautApp extends ConsumerStatefulWidget {
  const GerfautApp({super.key, this.bootstrap, this.startOver});

  /// Opens the Rust bridge and the vault at startup. Widget tests pass
  /// null (with a fake bridge override) so pumping the app never
  /// touches native code.
  final Future<void> Function()? bootstrap;

  /// Sets an unopenable vault aside so that [bootstrap] can start an
  /// empty one. The real app moves the file; widget tests pass a fake.
  final Future<void> Function()? startOver;

  @override
  ConsumerState<GerfautApp> createState() => _GerfautAppState();
}

class _GerfautAppState extends ConsumerState<GerfautApp> {
  late Future<void>? _ready = widget.bootstrap?.call();

  /// Reaches the navigator from outside the tree, for the one route the
  /// bootstrap itself pushes: the restore page after a vault was set
  /// aside.
  final _navigator = GlobalKey<NavigatorState>();

  /// Runs the bootstrap again, on a fresh future so the gate rebuilds
  /// from its loading state.
  void _retry() {
    final bootstrap = widget.bootstrap;
    if (bootstrap == null) return;
    setState(() {
      _ready = bootstrap();
    });
  }

  /// Sets the vault aside, opens an empty one, and lands on the restore
  /// page: the one place a backup brings the wallets back from. Without
  /// a backup the page is left with the back gesture, and the empty
  /// vault is what remains.
  void _startOver() {
    final bootstrap = widget.bootstrap;
    if (bootstrap == null) return;
    setState(() {
      _ready = (widget.startOver ?? setVaultAside)()
          .then((_) => bootstrap())
          .then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigator.currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => const BackupRestoreScreen(),
                ),
              );
            });
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (ref.watch(themeProvider)) {
      ThemePref.light => ThemeMode.light,
      ThemePref.dark => ThemeMode.dark,
      ThemePref.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Gerfaut',
      navigatorKey: _navigator,
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      darkTheme: themeFrom(GerfautTokens.dark, Brightness.dark),
      themeMode: themeMode,
      home: _ready == null
          ? const _Hydrated(child: _Gate())
          : _BootstrapGate(
              ready: _ready!,
              onRetry: _retry,
              onStartOver: _startOver,
            ),
    );
  }
}

/// Hydrates the UI preferences from the vault as soon as the settings
/// load. It sits below the bootstrap gate on purpose: watching the
/// settings is what asks the core for them, and nothing may ask before
/// the bridge is up and the vault open.
class _Hydrated extends ConsumerWidget {
  const _Hydrated({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(settingsProvider, (_, next) {
      final settings = next.valueOrNull;
      if (settings != null && !ref.read(prefsHydratedProvider)) {
        ref.read(prefsHydratedProvider.notifier).state = true;
        final prefs = settings.appPrefs;
        ref.read(themeProvider.notifier).hydrate(prefs['mobile.theme']);
        ref.read(maskedProvider.notifier).hydrate(prefs['mobile.masked']);
        ref.read(unitProvider.notifier).hydrate(prefs['display.unit']);
        ref.read(fiatEnabledProvider.notifier).hydrate(prefs['display.fiat']);
        // Currency before source: the source only takes if it quotes
        // the currency that was stored with it.
        ref
            .read(fiatCurrencyProvider.notifier)
            .hydrate(prefs['display.fiat_currency']);
        ref
            .read(fiatSourceProvider.notifier)
            .hydrate(prefs['display.fiat_source']);
        ref
            .read(explorerAckProvider.notifier)
            .hydrate(prefs['privacy.explorer_ack']);
        ref
            .read(recentBroadcastsProvider.notifier)
            .hydrate(prefs['broadcast.recent']);
        ref.read(notifyNewTxProvider.notifier).hydrate(prefs['notify.new_tx']);
        ref
            .read(backgroundCheckProvider.notifier)
            .hydrate(prefs['notify.background']);
        ref
            .read(onboardingSeenProvider.notifier)
            .hydrate(prefs['onboarding.seen']);
        ref
            .read(widgetBalancesProvider.notifier)
            .hydrate(prefs['widgets.balances']);
        ref.read(updateProvider.notifier).hydrate(prefs);
        // The widgets follow from here: everything they show is
        // hydrated now, so the first thing they get is the right thing.
        ref.read(widgetFeedProvider);
        // The heartbeat too: it reads the premium state and asks the
        // server at once when a wallet is watched, then every quarter
        // hour, from wherever the app is.
        ref.read(watchMonitorProvider);
      }
      // The vault says whether a lock exists, every time it is read:
      // the first reading with one in it is what puts the screen up.
      if (settings != null) {
        final first = !ref.read(lockProvider).loaded;
        ref.read(lockProvider.notifier).syncFromSettings(settings.appLock);
        _dropOrphanDisguise(ref, settings);
        // A vault without a lock opens on the wallets: that is a
        // session starting, as an unlock is with one.
        if (first) _startUpdateSession(ref);
      }
    });
    // The platform may answer about the disguise after the vault has
    // answered about the lock: the same check, from the other side.
    ref.listen(disguiseProvider, (previous, next) {
      final settings = ref.read(settingsProvider).valueOrNull;
      if (settings != null) _dropOrphanDisguise(ref, settings);
      // The session waits for this answer when the vault gave its own
      // first: nothing about a release is said before the app knows
      // which face it wears.
      if (next.loaded && !(previous?.loaded ?? false)) {
        _startUpdateSession(ref);
      }
    });
    return child;
  }

  /// Takes the disguise off a vault that carries no lock.
  ///
  /// A disguise has no meaning without the PIN that opens it, and the
  /// settings card turns the two off together. But the lock can go on
  /// its own — a vault restored from a backup, app storage the system
  /// cleared — and the calculator would then stand in the launcher in
  /// front of an app that opens on a tap. The launcher face follows
  /// the lock: none, none.
  void _dropOrphanDisguise(WidgetRef ref, Settings settings) {
    final disguise = ref.read(disguiseProvider);
    if (settings.appLock != null || !disguise.loaded || !disguise.disguised) {
      return;
    }
    // A platform that refuses leaves the calculator up; the settings
    // card can be asked again, and says why if it fails there too.
    unawaited(
      ref.read(disguiseProvider.notifier).set(false).catchError((_) {}),
    );
  }
}

/// Tells the update notice that the wallets just came on screen. Only
/// once the preferences are in and the vault is unlocked: a release is
/// never announced, nor asked about, from behind the lock.
void _startUpdateSession(WidgetRef ref) {
  final lock = ref.read(lockProvider);
  if (!ref.read(prefsHydratedProvider) || !lock.loaded || lock.locked) return;
  unawaited(ref.read(updateProvider.notifier).sessionStarted());
}

/// What the app shows once the vault is open: the lock while it is
/// locked, the welcome tour on a vault with nothing in it, otherwise
/// the wallets.
///
/// The lock replaces the app rather than covering it: nothing of a
/// wallet is in the tree behind it, so no screenshot, no accessibility
/// walk and no back gesture reaches one.
///
/// Disguised, the lock is the calculator: the same rule, another face.
/// The disguise is read from the platform, not the vault, and the gate
/// waits for that answer as it waits for the lock's, so no frame of the
/// wrong face is ever drawn.
class _Gate extends ConsumerStatefulWidget {
  const _Gate();

  @override
  ConsumerState<_Gate> createState() => _GateState();
}

class _GateState extends ConsumerState<_Gate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockProvider.notifier);
    switch (state) {
      // `inactive` alone is not leaving: a permission dialog, an
      // incoming call and the notification shade all raise it, and so
      // does every step on the way out and back. Out of sight is
      // `hidden`, `paused`, and `detached` when the view goes with it.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        lock.noteHidden();
      case AppLifecycleState.resumed:
        lock.noteResumed();
        // The launcher may have gained or lost a widget meanwhile. Only
        // once the preferences are in: a feed started before them would
        // publish the defaults first.
        if (ref.read(prefsHydratedProvider)) {
          ref.read(widgetFeedProvider).resume();
          // Timers sleep with the app: a beat older than the period is
          // asked for again on the way back.
          ref.read(watchMonitorProvider.notifier).resume();
          _startUpdateSession(ref);
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Locking while a screen is pushed would leave that screen in front
    // of the lock: this gate is the navigator's first route, so every
    // route above it has to go before the lock can mean anything.
    ref.listen(lockProvider, (previous, next) {
      if (next.locked && !(previous?.locked ?? false)) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      }
      if (!next.locked && (previous?.locked ?? false)) {
        _startUpdateSession(ref);
      }
    });
    // Watching the settings is what asks the core for them, and their
    // arrival is what tells the lock whether to show.
    final settings = ref.watch(settingsProvider);
    final lock = ref.watch(lockProvider);
    final disguise = ref.watch(disguiseProvider);
    if (settings.hasError) {
      return _StartupErrorScreen(
        error: settings.error!,
        onRetry: () => ref.invalidate(settingsProvider),
      );
    }
    if (!lock.loaded || !disguise.loaded) return const _StartupScreen();
    if (lock.locked) {
      // The calculator never asks for a biometric: a system prompt
      // over a calculator would give the app away.
      return disguise.disguised ? const CalculatorScreen() : const LockScreen();
    }

    // The tour only ever stands in front of an empty vault: someone
    // with wallets already knows what this is.
    final wallets = ref.watch(walletsProvider).valueOrNull;
    final hydrated = ref.watch(prefsHydratedProvider);
    final seen = ref.watch(onboardingSeenProvider);
    if (hydrated && !seen && wallets != null && wallets.isEmpty) {
      return const WelcomeScreen();
    }
    return const HomeScreen();
  }
}

/// Shows a quiet loading scaffold until the bootstrap future settles.
class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate({
    required this.ready,
    required this.onRetry,
    required this.onStartOver,
  });

  final Future<void> ready;
  final VoidCallback onRetry;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }
        if (snapshot.hasError) {
          return _StartupErrorScreen(
            error: snapshot.error!,
            onRetry: onRetry,
            onStartOver: onStartOver,
          );
        }
        return const _Hydrated(child: _Gate());
      },
    );
  }
}

/// Builds a [ThemeData] whose colors all come from the Toundra tokens.
ThemeData themeFrom(GerfautTokens tokens, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    secondary: tokens.primary,
    onSecondary: tokens.onPrimary,
    error: tokens.alert,
    onError: tokens.alertSurface,
    surface: tokens.surface,
    onSurface: tokens.text,
    outline: tokens.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    dividerColor: tokens.border,
    fontFamily: GerfautFonts.ui,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: tokens.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tokens.h2,
    ),
    iconButtonTheme: IconButtonThemeData(
      // 44px, the touch target of every other control in Gerfaut. The
      // Material default is 48, which spreads a row of actions wider
      // than the header has to give.
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
      ),
    ),
    // Every sheet from the bottom of the screen, whoever opens it: the
    // card surface and the rounded top edge of DESIGN.md, in place of
    // the Material defaults (a tinted surface, 28px corners) that a
    // sheet left to itself would take.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GerfautRadius.canvas),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.text,
      contentTextStyle: tokens.bodySmall.copyWith(color: tokens.background),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.text,
      unselectedLabelColor: tokens.textMuted,
      indicatorColor: tokens.primary,
      dividerColor: tokens.border,
      labelStyle: tokens.bodySmall.copyWith(fontWeight: FontWeight.w500),
      unselectedLabelStyle: tokens.bodySmall,
    ),
    extensions: [tokens],
  );
}

/// The quiet screen of a starting app. It names the vault only once the
/// platform has said the app is not disguised: a calculator that opened
/// on "Opening the vault…" would have told everything in one frame.
class _StartupScreen extends ConsumerWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final disguise = ref.watch(disguiseProvider);
    if (!disguise.loaded || disguise.disguised) return const Scaffold();
    return Scaffold(
      body: Center(
        child: Text(
          'Opening the vault…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ),
    );
  }
}

/// What the app shows when the vault did not open: the error, in the
/// core's words, and a way to try again.
///
/// A vault whose key is gone gets more than the words. It is the one
/// startup failure with a cause a person can do something about, and
/// the something is spelled out: the key does not travel with the
/// vault, so a phone restored from a backup comes back with a file
/// nobody can open. The way out is a fresh vault and a Gerfaut backup,
/// behind a confirmation that says the file is set aside, not deleted.
class _StartupErrorScreen extends StatefulWidget {
  const _StartupErrorScreen({
    required this.error,
    required this.onRetry,
    this.onStartOver,
  });

  final Object error;
  final VoidCallback onRetry;

  /// Sets the vault aside and starts over; null where that makes no
  /// sense, the settings that failed to load after the vault opened.
  final VoidCallback? onStartOver;

  @override
  State<_StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<_StartupErrorScreen> {
  bool _confirmingStartOver = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final error = widget.error;
    final keyGone = error is VaultKeyMissingException;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Gerfaut could not start', style: tokens.h2),
                const SizedBox(height: GerfautSpacing.sm),
                if (keyGone) ...[
                  Text(
                    'The vault is here, but the key that opens it is gone.',
                    style: tokens.body,
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Android keeps that key in its secure storage, apart '
                    'from the vault, and it does not travel: a phone '
                    'restored from a backup, moved to a new device or reset '
                    'comes back with the vault file and without the key. '
                    'Nothing can open the vault without it.',
                    style: muted,
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'If the phone was only restarting, try again first. '
                    'Otherwise, a backup made with Gerfaut brings the '
                    'wallets back into an empty vault.',
                    style: muted,
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  SelectableText(
                    error.detail,
                    style: tokens.data.copyWith(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                  ),
                ] else
                  SelectableText(
                    '$error',
                    style: tokens.data.copyWith(color: tokens.textMuted),
                  ),
                const SizedBox(height: GerfautSpacing.md),
                Wrap(
                  spacing: GerfautSpacing.sm,
                  runSpacing: GerfautSpacing.sm,
                  children: [
                    SecondaryButton(
                      label: 'Try again',
                      icon: LucideIcons.refreshCw,
                      onPressed: widget.onRetry,
                    ),
                    if (keyGone && widget.onStartOver != null)
                      GhostButton(
                        label: 'Start over…',
                        icon: LucideIcons.archiveRestore,
                        onPressed: _confirmingStartOver
                            ? null
                            : () => setState(() => _confirmingStartOver = true),
                      ),
                  ],
                ),
                if (_confirmingStartOver) ...[
                  const SizedBox(height: GerfautSpacing.md),
                  // Amber: the file is kept. What is lost was lost
                  // before this screen, and the sentence says so.
                  GerfautNotice(
                    tone: NoticeTone.info,
                    message:
                        'Gerfaut opens an empty vault and the restore page. '
                        'The vault it cannot open is set aside under another '
                        'name, not deleted.',
                    liveRegion: true,
                    actionsBelow: true,
                    action: ConfirmActions(
                      cancel: GhostButton(
                        label: 'Cancel',
                        onPressed: () =>
                            setState(() => _confirmingStartOver = false),
                      ),
                      confirm: DangerButton(
                        label: 'Start over',
                        onPressed: widget.onStartOver,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
