import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/password_field.dart';
import '../widgets/pinned_action_form.dart';
import 'scan.dart';

/// Opens the system file picker; tests hand back a file of their own.
typedef BackupFilePicker = Future<XFile?> Function();

/// Said when the core cannot open the backup: the two causes are one
/// and the same to the cipher, so they are stated together.
const String wrongPasswordMessage = 'Wrong password, or the file is damaged.';

/// Restoring a backup: a file or a scanned QR code and its password,
/// then what it holds, wallet by wallet, before anything is added.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({
    super.key,
    @visibleForTesting this.filePicker,
    @visibleForTesting this.cameraBuilder,
  });

  /// What the scanner expects, shown under the camera.
  static const String scanCaption =
      'Point the camera at a Gerfaut backup QR code: it is animated, keep '
      'the camera on it.';

  /// Replaces the system file picker.
  final BackupFilePicker? filePicker;

  /// Replaces the camera view of the scanner; tests push frames by hand.
  final CameraBuilder? cameraBuilder;

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  final _passwordController = TextEditingController();

  /// The backup as the core takes it: base64 of the file, or the text a
  /// scan yields.
  String? _source;

  /// Where the source came from, for the line under the buttons.
  String? _sourceLabel;
  bool _opening = false;
  String? _error;
  BackupPreview? _preview;

  /// Indexes of the wallets to restore; already-watched ones never
  /// enter it.
  final Set<int> _chosen = {};
  bool _applySettings = false;
  bool _restoring = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  static Future<XFile?> _pickBackupFile() {
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Gerfaut backup', extensions: ['gerfaut']),
        // A backup renamed or saved by another app still opens; the core
        // says what is not one.
        XTypeGroup(label: 'Any file'),
      ],
    );
  }

  /// Largest file worth reading, mirroring the core's own cap: a
  /// backup of a hundred wallets weighs a few tens of kilobytes.
  static const int _maxBackupBytes = 8 * 1024 * 1024;

  Future<void> _openFile() async {
    final file = await (widget.filePicker ?? _pickBackupFile)();
    if (file == null) return;
    // Checked before reading: picking a video by mistake must cost a
    // sentence, not the memory of the whole file.
    if (await file.length() > _maxBackupBytes) {
      if (!mounted) return;
      setState(
        () => _error = 'This file is far too large to be a Gerfaut backup.',
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _source = base64Encode(bytes);
      _sourceLabel = 'File: ${file.name} · ${formatBytes(bytes.length)}';
      _error = null;
    });
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ScanScreen(
          caption: BackupRestoreScreen.scanCaption,
          // A test seam of ScanScreen; this screen only forwards its
          // own, which is null outside a test.
          // ignore: invalid_use_of_visible_for_testing_member
          cameraBuilder: widget.cameraBuilder,
        ),
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _source = text.trim();
      _sourceLabel = 'QR code scanned';
      _error = null;
    });
  }

  String _messageOf(BridgeException error) =>
      error.kind == 'vault' ? wrongPasswordMessage : error.message;

  Future<void> _open() async {
    final source = _source;
    if (source == null || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final preview = await ref
          .read(bridgeProvider)
          .previewBackup(source, _passwordController.text);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _chosen
          ..clear()
          ..addAll([
            for (final wallet in preview.wallets)
              if (!wallet.alreadyWatched) wallet.index,
          ]);
        _applySettings = false;
      });
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _restore() async {
    final source = _source;
    if (source == null || _restoring || _chosen.isEmpty) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Held before the first await: `ref` belongs to this widget and
    // throws once it is gone, but the container it points at does not.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final bridge = ref.read(bridgeProvider);
      final report = await bridge.importBackup(
        source,
        _passwordController.text,
        ImportChoices(
          indexes: _chosen.toList()..sort(),
          applySettings: _applySettings,
        ),
      );
      // The workspace follows the restored wallets when none of them is
      // on the active network, otherwise they would land invisible.
      var active = (await ref.read(settingsProvider.future)).activeNetwork;
      final added = report.added;
      if (added.isNotEmpty && !added.any((w) => w.network == active)) {
        active = added.first.network;
        await bridge.setActiveNetwork(active);
      }
      // Leaving the screen mid-import must not swallow the result: the
      // wallets are in the vault either way, and the lists have to be
      // told even if this widget is gone. The container outlives it.
      container.invalidate(settingsProvider);
      container.invalidate(walletsProvider);
      // First sync in the background; its outcome lands on each wallet's
      // freshness indicator.
      unawaited(
        container
            .read(syncProvider.notifier)
            .syncAll(active)
            .catchError((_) => null),
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(_restoredMessage(report))));
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  static String _restoredMessage(ImportReport report) {
    final count = report.added.length;
    final wallets = count == 1
        ? '1 wallet restored'
        : '$count wallets restored';
    return report.settingsApplied ? '$wallets · settings applied' : wallets;
  }

  void _toggle(int index, bool chosen) {
    setState(() {
      if (chosen) {
        _chosen.add(index);
      } else {
        _chosen.remove(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore a backup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: preview == null
              ? _buildSourceStep(tokens)
              : _buildChoiceStep(tokens, preview),
        ),
      ),
    );
  }

  Widget _buildSourceStep(GerfautTokens tokens) {
    final ready =
        !_opening && _source != null && _passwordController.text.isNotEmpty;
    return PinnedActionForm(
      action: PrimaryButton(
        label: _opening ? 'Opening…' : 'Open backup',
        expand: true,
        onPressed: ready ? _open : null,
      ),
      children: [
        Text(
          'A backup made by Gerfaut on this phone or on the desktop, and '
          'the password it was sealed with.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Open a file',
                icon: LucideIcons.fileUp,
                onPressed: _openFile,
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: 'Scan a QR code',
                icon: LucideIcons.scanLine,
                onPressed: _scan,
              ),
            ),
          ],
        ),
        if (_sourceLabel != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _sourceLabel!,
            style: tokens.figureOf(size: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
        PasswordField(
          label: 'Password',
          controller: _passwordController,
          onChanged: () => setState(() => _error = null),
          onSubmitted: ready ? _open : null,
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

  Widget _buildChoiceStep(GerfautTokens tokens, BackupPreview preview) {
    final total = preview.wallets.length;
    final count = _chosen.length;
    return PinnedActionForm(
      action: PrimaryButton(
        label: _restoring
            ? 'Restoring…'
            : count == 1
            ? 'Restore 1 wallet'
            : 'Restore $count wallets',
        expand: true,
        onPressed: count == 0 || _restoring ? null : _restore,
      ),
      children: [
        Text(
          'Backup from ${formatTimestamp(preview.createdAt)} · '
          '${total == 1 ? '1 wallet' : '$total wallets'}',
          style: tokens.figureOf(size: 14, weight: FontWeight.w500),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            children: [
              for (final (position, wallet) in preview.wallets.indexed) ...[
                if (position > 0)
                  Divider(height: 1, thickness: 1, color: tokens.border),
                _WalletRow(
                  wallet: wallet,
                  chosen: _chosen.contains(wallet.index),
                  onChanged: wallet.alreadyWatched
                      ? null
                      : (chosen) => _toggle(wallet.index, chosen),
                ),
              ],
            ],
          ),
        ),
        if (preview.hasSettings) ...[
          const SizedBox(height: GerfautSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apply node settings',
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    Text(
                      "Replaces your backend choice and gap limit with the "
                      "backup's.",
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              Switch(
                value: _applySettings,
                activeThumbColor: tokens.onPrimary,
                activeTrackColor: tokens.primary,
                inactiveThumbColor: tokens.textMuted,
                inactiveTrackColor: tokens.surfaceSunken,
                onChanged: (value) => setState(() => _applySettings = value),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.md),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.md),
      ],
    );
  }
}

/// One wallet of the backup: a checkbox, its name, and what it is. A
/// wallet already watched here stays visible, unchecked and out of
/// reach: restoring it again would only be skipped.
class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.wallet,
    required this.chosen,
    required this.onChanged,
  });

  final BackupWalletPreview wallet;
  final bool chosen;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final enabled = onChanged != null;
    final kind = wallet.kind is SingleAddressKind
        ? 'Single address'
        : 'Descriptor wallet';
    final detail = enabled
        ? '${wallet.network.label} · $kind'
        : '${wallet.network.label} · $kind · Already watched';
    return InkWell(
      onTap: enabled ? () => onChanged!(!chosen) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: GerfautSpacing.sm,
          vertical: GerfautSpacing.xs,
        ),
        child: Row(
          children: [
            Checkbox(
              value: enabled && chosen,
              activeColor: tokens.primary,
              checkColor: tokens.onPrimary,
              side: BorderSide(color: tokens.border, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GerfautRadius.sm),
              ),
              onChanged: enabled ? (value) => onChanged!(value ?? false) : null,
            ),
            const SizedBox(width: GerfautSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet.name,
                    style: tokens.bodySmall.copyWith(
                      color: enabled ? tokens.text : tokens.textMuted,
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    detail,
                    style: tokens.label.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
