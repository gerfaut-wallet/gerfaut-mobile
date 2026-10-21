import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/documents.dart';
import '../src/format.dart';
import '../src/lock.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/password_field.dart';
import '../widgets/pinned_action_form.dart';
import '../widgets/setting_switch.dart';
import 'scan.dart';
import '../widgets/toast.dart';

/// Opens the system file picker; tests hand back a file of their own.
typedef BackupFilePicker = Future<XFile?> Function();

/// Said when the password does not open the backup: a wrong password
/// and a file altered under its seal are one and the same to the
/// cipher, so they are stated together.
const String wrongPasswordMessage = 'Wrong password, or the file is damaged.';

/// Said when what was handed over cannot be read as a backup: another
/// file, a QR code of something else, a backup damaged outside what the
/// password guards. The password is not in question.
const String notABackupMessage =
    'This is not a Gerfaut backup, or it is damaged.';

/// Said when a newer Gerfaut made the backup: an update opens it.
const String newerBackupMessage =
    'This backup was made with a newer version of Gerfaut. Update Gerfaut '
    'to open it.';

/// Where the backup being restored was read from.
///
/// A scan opens a camera over the whole screen and a file picker is a
/// screen of the system's, so in both cases the person comes back to a
/// page that has to say what it now holds — rather than leave a greyed
/// button to explain itself. [name] is the file's, null for a scan.
@immutable
class _BackupSource {
  const _BackupSource.qr() : name = null;
  const _BackupSource.file(String this.name);

  final String? name;

  /// What the page states, in the same words for either source.
  String get sentence => 'Backup read from ${name ?? 'the QR code'}';
}

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
  final _passwordFocus = FocusNode();

  /// The backup as the core takes it: base64 of the file, or the text a
  /// scan yields.
  String? _source;

  /// Where that source came from, for the panel under the buttons.
  _BackupSource? _from;
  bool _opening = false;
  String? _error;
  BackupPreview? _preview;

  /// Indexes of the wallets to restore; ones already watched or refused
  /// by the core never enter it.
  final Set<int> _chosen = {};
  bool _applySettings = false;
  bool _restoring = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// A backup has landed. The page says so and the caret follows it:
  /// the scanner and the picker both hand focus back to the button that
  /// opened them, which is a step already taken — the password is the
  /// one that is not.
  void _landed(String source, _BackupSource from) {
    setState(() {
      _source = source;
      _from = from;
      _error = null;
    });
    _passwordFocus.requestFocus();
  }

  /// Any file: a backup renamed or saved by another app still opens,
  /// and the core says what is not one.
  static Future<XFile?> _pickBackupFile() =>
      openBoundedFile(maxBytes: _maxBackupBytes);

  /// Largest file worth reading, mirroring the core's own cap: a
  /// backup of a hundred wallets weighs a few tens of kilobytes.
  static const int _maxBackupBytes = 8 * 1024 * 1024;

  Future<void> _openFile() async {
    final lock = ref.read(lockProvider.notifier);
    // The picker is a screen of the system's: Android pauses Gerfaut
    // behind it, and coming back from a picker the user opened here is
    // not coming back from the background.
    final XFile? file;
    try {
      file = await lock.excursion(
        widget.filePicker ?? _pickBackupFile,
        // Picked, then not read: the trip did happen.
        cameUp: (error) => error is FileReadException,
      );
    } on FileReadException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    } catch (_) {
      // No picker came up.
      if (!mounted) return;
      setState(
        () => _error = 'No app on this phone can open a file to restore.',
      );
      return;
    }
    if (file == null) return;
    // The picker has read no further than this: a larger file comes
    // with its size and nothing else.
    if (await file.length() > _maxBackupBytes) {
      if (!mounted) return;
      setState(
        () => _error = 'This file is far too large to be a Gerfaut backup.',
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    _landed(base64Encode(bytes), _BackupSource.file(file.name));
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<QrProgress>(
      MaterialPageRoute<QrProgress>(
        builder: (_) => ScanScreen(
          caption: BackupRestoreScreen.scanCaption,
          privateKey: privateKeyNotABackup,
          // A test seam of ScanScreen; this screen only forwards its
          // own, which is null outside a test.
          // ignore: invalid_use_of_visible_for_testing_member
          cameraBuilder: widget.cameraBuilder,
        ),
      ),
    );
    final text = scanned?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    _landed(text.trim(), const _BackupSource.qr());
  }

  /// What a refused file says, chosen on the core's code, in the words
  /// the desktop app uses. Only a wrong key is blamed on the password:
  /// saying it of a file that is not a backup, or one a newer Gerfaut
  /// made, would send someone retyping a password that was right. A
  /// private key in it gets its own sentence, and everything else is
  /// the core's own words, verbatim.
  String _messageOf(BridgeException error) => switch (error.kind) {
    'wrong_key' => wrongPasswordMessage,
    'unreadable_backup' => notABackupMessage,
    'newer_format' => newerBackupMessage,
    _ => materialRefusal(error, backup: true),
  };

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
              if (!wallet.outOfReach) wallet.index,
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
      var active = (await container.read(settingsProvider.future))
          .activeNetwork;
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
      messenger.showSnackBar(Toast(_restoredMessage(report)));
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = _restoreMessageOf(error));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// What a failed restore says. A restore goes whole or not at all, so
  /// a wallet the core refuses stops every one of them, and the words
  /// say so. The core names the wallet in its own words; a network that
  /// does not match or a private key comes under `invalid_input` with
  /// that name.
  String _restoreMessageOf(BridgeException error) => switch (error.kind) {
    'descriptor' =>
      'A wallet in this backup is not a descriptor Gerfaut can watch, so '
          'nothing was restored. The core says: ${error.message}',
    'invalid_input' => 'Nothing was restored. The core says: ${error.message}',
    _ => _messageOf(error),
  };

  String _restoredMessage(ImportReport report) {
    final count = report.added.length;
    final wallets = count == 1
        ? '1 wallet restored'
        : '$count wallets restored';
    final settings = report.settingsApplied ? ' · settings applied' : '';
    return '$wallets$settings${leftOutWords(_leftOut(report))}';
  }

  /// The wallets a restore left out because the core cannot watch them:
  /// those the preview marked, which this screen never asks for, and
  /// any the core left out of the restore itself.
  List<String> _leftOut(ImportReport report) {
    final names = [
      for (final wallet in _preview?.wallets ?? const <BackupWalletPreview>[])
        if (!wallet.alreadyWatched && wallet.refused != null)
          calledInBackup(wallet.index, wallet.name),
    ];
    for (final wallet in report.refused) {
      final called = calledInBackup(wallet.index, wallet.name);
      if (!names.contains(called)) names.add(called);
    }
    return names;
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
      appBar: GerfautAppBar.text('Restore a backup'),
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
    final from = _from;
    final ready =
        !_opening && _source != null && _passwordController.text.isNotEmpty;
    return PinnedActionForm(
      action: PrimaryButton(
        label: _opening ? 'Opening…' : 'Open backup',
        expand: true,
        busy: _opening,
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
        if (from != null) ...[
          const SizedBox(height: GerfautSpacing.md),
          _ReadPanel(source: from),
        ],
        const SizedBox(height: GerfautSpacing.md),
        PasswordField(
          label: 'Password',
          controller: _passwordController,
          focusNode: _passwordFocus,
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
                  onChanged: wallet.outOfReach
                      ? null
                      : (chosen) => _toggle(wallet.index, chosen),
                ),
              ],
            ],
          ),
        ),
        if (preview.hasSettings) ...[
          const SizedBox(height: GerfautSpacing.md),
          SettingSwitch(
            title: 'Apply node settings',
            hint:
                "Replaces your backend choice and gap limit with the backup's, "
                'and adds the certificates it accepted.',
            value: _applySettings,
            onChanged: (value) => setState(() => _applySettings = value),
          ),
          if (preview.backends.isNotEmpty ||
              preview.electrumHosts.isNotEmpty) ...[
            const SizedBox(height: GerfautSpacing.sm),
            _SettingsPanel(
              backends: preview.backends,
              hosts: preview.electrumHosts,
            ),
          ],
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

/// What the page now holds, once a file or a scan has landed.
///
/// It is a card and not the grey aside it replaced: a scanner closing
/// over the page and returning a line the weight of a caption reads as
/// a crash, which is what it was taken for. Stated as a fact, at the
/// weight of one, on the ordinary card surface — a backup read is not
/// an event to celebrate and carries no colour of its own.
///
/// It describes the field below it rather than announcing itself: a
/// region that appears together with its own text is read out
/// unreliably, while the caret landing in the password field is not.
/// Its two lines are one stop, since neither can be acted on alone.
class _ReadPanel extends StatelessWidget {
  const _ReadPanel({required this.source});

  final _BackupSource source;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(GerfautSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(GerfautRadius.lg),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source.sentence, style: tokens.bodySmall),
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Type its password to open it.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the node settings of a backup would put in place, named.
///
/// The toggle above says what is replaced; a person deciding has to
/// know what with. A backend is the machine every address of every
/// wallet is asked for, and a pinned certificate is one this phone
/// will then trust without asking again — neither is a thing to take
/// from a file sight unseen. A backup that carries no settings shows
/// nothing here at all.
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.backends, required this.hosts});

  /// One node per network the backup names.
  final List<BackupBackend> backends;

  /// `host:port` of every Electrum certificate it would pin.
  final List<String> hosts;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final label = tokens.label.copyWith(color: tokens.textMuted);
    final value = tokens.data;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(GerfautSpacing.sm + GerfautSpacing.xs),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (backends.isNotEmpty) ...[
            Text('NODES', style: label),
            for (final backend in backends)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: GerfautSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backend.network.label,
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      // A host is long and the screen is narrow, so it
                      // takes what is left and wraps. It is not cut
                      // short: this panel exists to be read before it
                      // is accepted, and a name ending in an ellipsis
                      // is a name whose end nobody checked.
                      Expanded(
                        child: Text(
                          backend.backend,
                          style: value,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (hosts.isNotEmpty) ...[
            if (backends.isNotEmpty) const SizedBox(height: GerfautSpacing.sm),
            Text('PINNED CERTIFICATES', style: label),
            for (final host in hosts)
              Padding(
                padding: const EdgeInsets.only(top: GerfautSpacing.xs),
                child: Text(host, style: value),
              ),
          ],
        ],
      ),
    );
  }
}

/// What a wallet of a backup is called on screen: its name, or its
/// place in the backup when it has none.
String calledInBackup(int index, String name) =>
    name.trim().isEmpty ? 'Wallet ${index + 1}' : name;

/// " · 1 left out: Handed over", " · 2 left out", or nothing.
String leftOutWords(List<String> names) => switch (names.length) {
  0 => '',
  1 => ' · 1 left out: ${names.single}',
  final count => ' · $count left out',
};

/// One wallet of the backup: a checkbox, its name, and what it is. A
/// wallet already watched here, or one the core refuses, stays visible,
/// unchecked and out of reach: showing what will not be done says more
/// than dropping it, which would read as a backup missing a wallet. A
/// refused one says why, in the core's words.
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
    final refused = wallet.alreadyWatched ? null : wallet.refused;
    final detail = enabled
        ? '${wallet.network.label} · $kind'
        : wallet.alreadyWatched
        ? '${wallet.network.label} · $kind · Already watched'
        : '${wallet.network.label} · $kind · Cannot be restored';
    // One node: the box is read with the wallet it restores, not as a
    // nameless "not checked".
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!chosen) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: GerfautTouch.target),
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
                side: BorderSide(color: tokens.textMuted, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                onChanged: enabled
                    ? (value) => onChanged!(value ?? false)
                    : null,
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      calledInBackup(wallet.index, wallet.name),
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
                    if (refused != null)
                      Padding(
                        padding: const EdgeInsets.only(top: GerfautSpacing.xs),
                        child: Text(
                          refused,
                          style: tokens.label.copyWith(color: tokens.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
