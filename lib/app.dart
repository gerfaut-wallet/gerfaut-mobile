import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home.dart';
import 'src/notifications.dart';
import 'src/state.dart';
import 'theme/tokens.dart';

/// Root widget: both Toundra themes, light by default, and the startup
/// bootstrap (Rust bridge + encrypted vault) before the home screen.
class GerfautApp extends ConsumerStatefulWidget {
  const GerfautApp({super.key, this.bootstrap});

  /// Opens the Rust bridge and the vault at startup. Widget tests pass
  /// null (with a fake bridge override) so pumping the app never
  /// touches native code.
  final Future<void> Function()? bootstrap;

  @override
  ConsumerState<GerfautApp> createState() => _GerfautAppState();
}

class _GerfautAppState extends ConsumerState<GerfautApp> {
  late final Future<void>? _ready = widget.bootstrap?.call();

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (ref.watch(themeProvider)) {
      ThemePref.light => ThemeMode.light,
      ThemePref.dark => ThemeMode.dark,
      ThemePref.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Gerfaut',
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      darkTheme: themeFrom(GerfautTokens.dark, Brightness.dark),
      themeMode: themeMode,
      home: _ready == null
          ? const _Hydrated(child: HomeScreen())
          : _BootstrapGate(ready: _ready),
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
      }
    });
    return child;
  }
}

/// Shows a quiet loading scaffold until the bootstrap future settles.
class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate({required this.ready});

  final Future<void> ready;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }
        if (snapshot.hasError) {
          return _StartupErrorScreen(message: '${snapshot.error}');
        }
        return const _Hydrated(child: HomeScreen());
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

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
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

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Gerfaut could not start', style: tokens.body),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                message,
                style: tokens.data.copyWith(color: tokens.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
