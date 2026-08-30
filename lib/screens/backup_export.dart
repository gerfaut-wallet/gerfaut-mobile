import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/format.dart' show formatBytes;
import '../src/lock.dart';
import '../src/models.dart';
import '../src/share.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/choice_group.dart';
import '../widgets/facts.dart';
import '../widgets/password_field.dart';
import '../widgets/pinned_action_form.dart';
import 'backup_qr.dart';

/// Shortest password the core accepts, after trimming. Checked here too
/// so a short one is told before anything is sealed.
const int minPasswordChars = 8;

/// Which wallets a backup takes.
enum _Scope { all, network }

/// Sealing the wallet list: what goes in and the password, then the two
/// ways out, a file to keep and an animated QR code for the other
/// device. Nothing leaves this device until one of them is used.
class BackupExportScreen extends ConsumerStatefulWidget {
  const BackupExportScreen({super.key});

  @override
  ConsumerState<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends ConsumerState<BackupExportScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  _Scope _scope = _Scope.all;
  bool _includeSettings = false;
  bool _creating = false;
  String? _error;
  BackupBundle? _bundle;

  /// Every wallet on every network, fetched once: the choice counts
  /// them, and the network option lists their ids.
  List<WalletMeta>? _all;

  @override
  void initState() {
    super.initState();
    ref.read(bridgeProvider).listWallets().then((wallets) {
      if (mounted) setState(() => _all = wallets);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// What is wrong with the password pair, or null when it can seal.
  String? _passwordProblem() {
    // The core trims before checking: a stray space is not a character.
    final password = _passwordController.text.trim();
    if (password.length < minPasswordChars) {
      return 'Use at least $minPasswordChars characters.';
    }
    if (_confirmController.text.trim() != password) {
      return 'The two passwords differ.';
    }
    return null;
  }

  Future<void> _create() async {
    final problem = _passwordProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final active = ref.read(settingsProvider).valueOrNull?.activeNetwork;
    final ids = _scope == _Scope.all
        ? null
        : [
            for (final wallet in _all ?? const <WalletMeta>[])
              if (wallet.network == active) wallet.id,
          ];
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final bundle = await ref
          .read(bridgeProvider)
          .exportBackup(
            BackupOptions(walletIds: ids, includeSettings: _includeSettings),
            _passwordController.text,
          );
      if (mounted) setState(() => _bundle = bundle);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _saveFile(BackupBundle bundle) async {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    // The sheet that picks where the file goes is a screen of the
    // system's: Android pauses Gerfaut behind it, and coming back from
    // it is not coming back from the background.
    ref.read(lockProvider.notifier).expectExcursion();
    await ref
        .read(backupSharerProvider)
        .shareBackup(
          bytes: base64Decode(bundle.data),
          filename: 'gerfaut-backup-${now.year}-$month-$day.gerfaut',
        );
  }

  void _showQr(BackupBundle bundle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupQrScreen(frames: bundle.frames),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final bundle = _bundle;
    return Scaffold(
      appBar: GerfautAppBar.text('Export a backup'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: bundle == null
              ? _buildOptions(tokens)
              : _buildResult(tokens, bundle),
        ),
      ),
    );
  }

  Widget _buildOptions(GerfautTokens tokens) {
    final all = _all;
    final active = ref.watch(settingsProvider).valueOrNull?.activeNetwork;
    final onNetwork = all == null || active == null
        ? null
        : all.where((w) => w.network == active).length;
    final ready =
        !_creating &&
        all != null &&
        _passwordController.text.isNotEmpty &&
        _confirmController.text.isNotEmpty;
    return PinnedActionForm(
      action: PrimaryButton(
        label: _creating ? 'Creating…' : 'Create backup',
        expand: true,
        onPressed: ready ? _create : null,
      ),
      children: [
        Text(
          'Descriptors and addresses, sealed under a password. Never a key.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        FieldLabel('Wallets', tokens: tokens),
        const SizedBox(height: GerfautSpacing.sm),
        ChoiceGroup<_Scope>(
          label: 'Wallets',
          value: _scope,
          options: [
            ChoiceOption(
              value: _Scope.all,
              label: all == null
                  ? 'All wallets'
                  : 'All wallets (${all.length})',
            ),
            // Both counts equal means the second option would seal the
            // same thing under another name: it is left out.
            if (onNetwork != null && onNetwork != all!.length)
              ChoiceOption(
                value: _Scope.network,
                label: '${active!.label} only ($onNetwork)',
              ),
          ],
          onChanged: (scope) => setState(() => _scope = scope),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Include node settings',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    'Your backend choice, accepted certificates and gap '
                    'limit.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Switch(
              value: _includeSettings,
              activeThumbColor: tokens.onPrimary,
              activeTrackColor: tokens.primary,
              inactiveThumbColor: tokens.textMuted,
              inactiveTrackColor: tokens.surfaceSunken,
              onChanged: (value) => setState(() => _includeSettings = value),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.md),
        PasswordField(
          label: 'Password',
          controller: _passwordController,
          onChanged: () => setState(() => _error = null),
        ),
        const SizedBox(height: GerfautSpacing.md),
        PasswordField(
          label: 'Confirm password',
          controller: _confirmController,
          onChanged: () => setState(() => _error = null),
          onSubmitted: ready ? _create : null,
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Choose it now and type it on the other device. There is no way '
          'to recover it.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
      ],
    );
  }

  Widget _buildResult(GerfautTokens tokens, BackupBundle bundle) {
    final count = bundle.walletCount == 1
        ? '1 wallet'
        : '${bundle.walletCount} wallets';
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.archive, size: 18, color: tokens.textMuted),
              const SizedBox(width: GerfautSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count · ${formatBytes(bundle.sizeBytes)}',
                      style: tokens.figureOf(size: 16, weight: FontWeight.w500),
                    ),
                    Text(
                      'Sealed with your password.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Save file',
                icon: LucideIcons.save,
                onPressed: () => _saveFile(bundle),
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: 'Show QR code',
                icon: LucideIcons.qrCode,
                onPressed: () => _showQr(bundle),
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'The QR code is animated: the other device reads it in a few '
          'seconds, whichever frame it starts on.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
