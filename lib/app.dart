import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Root widget: both Toundra themes, light by default, and the startup
/// bootstrap (Rust bridge + encrypted vault) before the home screen.
class GerfautApp extends StatefulWidget {
  const GerfautApp({super.key, this.bootstrap});

  /// Opens the Rust bridge and the vault at startup. Widget tests pass
  /// null (or a fake) so pumping the app never touches native code.
  final Future<void> Function()? bootstrap;

  @override
  State<GerfautApp> createState() => _GerfautAppState();
}

class _GerfautAppState extends State<GerfautApp> {
  late final Future<void>? _ready = widget.bootstrap?.call();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gerfaut',
      theme: themeFrom(GerfautTokens.light, Brightness.light),
      darkTheme: themeFrom(GerfautTokens.dark, Brightness.dark),
      themeMode: ThemeMode.system,
      home: _ready == null ? const HomeScreen() : _BootstrapGate(ready: _ready),
    );
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
        return const HomeScreen();
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

/// The empty state: no wallet watched yet, one action.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No wallets yet', style: tokens.body),
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Import a descriptor, xpub, or address to start watching it.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: GerfautSpacing.lg),
                _PrimaryButton(
                  label: 'Add a wallet',
                  onPressed: () => _showAddWalletPlaceholder(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddWalletPlaceholder(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
          ),
          title: Text('Add a wallet', style: tokens.h2),
          content: Text(
            'Importing wallets is not available yet.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: tokens.primary),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// The single primary action of a screen: Glacier surface, 44px tall.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: 44,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.md),
          ),
          textStyle: tokens.bodySmall.copyWith(
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
