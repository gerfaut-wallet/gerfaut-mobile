import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';
import '../../widgets/section_card.dart';
import 'fields.dart';

/// The Wallets section: the gap limit every wallet shares, then the
/// wallets of the active network, each with its own actions.
class WalletsSection extends ConsumerStatefulWidget {
  const WalletsSection({super.key});

  @override
  ConsumerState<WalletsSection> createState() => _WalletsSectionState();
}

class _WalletsSectionState extends ConsumerState<WalletsSection> {
  // Wallet management.
  String? _renamingId;
  final _renameController = TextEditingController();
  String? _confirmRemoveId;
  String? _walletError;

  /// Wallet whose rescan was started here; its row says so meanwhile.
  String? _rescanningId;

  // Gap limit. Seeded from the vault, committed on blur or submit.
  final _gapLimitController = TextEditingController();
  final _gapLimitFocus = FocusNode();
  int? _seededGapLimit;

  @override
  void initState() {
    super.initState();
    // Commit on blur; an invalid value snaps back without noise.
    _gapLimitFocus.addListener(() {
      if (!_gapLimitFocus.hasFocus) _commitGapLimit();
    });
  }

  @override
  void dispose() {
    _renameController.dispose();
    _gapLimitController.dispose();
    _gapLimitFocus.dispose();
    super.dispose();
  }

  void _seedGapLimit(Settings settings) {
    if (_seededGapLimit == settings.gapLimit || _gapLimitFocus.hasFocus) {
      return;
    }
    _seededGapLimit = settings.gapLimit;
    _gapLimitController.text = '${settings.gapLimit}';
  }

  /// Commits the gap limit field. An unparseable or out-of-range value
  /// silently returns to the current one; a saved value refreshes the
  /// settings and every wallet view.
  Future<void> _commitGapLimit() async {
    final current = _seededGapLimit ?? 20;
    final parsed = int.tryParse(_gapLimitController.text.trim());
    if (parsed == null || parsed < 1 || parsed > 500) {
      _gapLimitController.text = '$current';
      return;
    }
    if (parsed == current) {
      _gapLimitController.text = '$current';
      return;
    }
    try {
      await ref.read(bridgeProvider).setGapLimit(parsed);
      _seededGapLimit = parsed;
      _gapLimitController.text = '$parsed';
      ref.invalidate(settingsProvider);
      ref.invalidate(walletsProvider);
      ref.invalidate(snapshotProvider);
      if (mounted) _toast('Setting saved');
    } catch (_) {
      _gapLimitController.text = '$current';
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(String id) async {
    final name = _renameController.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(bridgeProvider).renameWallet(id, name);
      ref.invalidate(walletsProvider);
      ref.invalidate(snapshotProvider(id));
      setState(() => _renamingId = null);
      _toast('Setting saved');
    } catch (error) {
      setState(() => _walletError = '$error');
    }
  }

  Future<void> _remove(String id) async {
    try {
      await ref.read(bridgeProvider).removeWallet(id);
      ref.invalidate(walletsProvider);
      setState(() => _confirmRemoveId = null);
      _toast('Wallet removed');
    } catch (error) {
      setState(() => _walletError = '$error');
    }
  }

  Future<void> _rescan(String id) async {
    setState(() {
      _rescanningId = id;
      _walletError = null;
    });
    try {
      final report = await ref.read(syncProvider.notifier).rescanWallet(id);
      if (report != null && mounted) _toast(_rescanSummary(report.newTxCount));
    } catch (error) {
      if (mounted) setState(() => _walletError = '$error');
    } finally {
      if (mounted) setState(() => _rescanningId = null);
    }
  }

  static String _rescanSummary(int count) {
    final found = switch (count) {
      0 => 'no new transactions',
      1 => '1 new transaction',
      _ => '$count new transactions',
    };
    return 'Rescanned · $found';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? [];
    ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    if (settings == null) {
      return Text(
        'Loading…',
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      );
    }
    _seedGapLimit(settings);

    return SectionCard(
      icon: LucideIcons.wallet,
      title: 'Wallets',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gap limit',
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    'How many unused addresses Gerfaut scans past '
                    'the last used one.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  Text(
                    'Rescan a wallet to look again from its first '
                    'address.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            SizedBox(
              width: 72,
              child: MonoField(
                controller: _gapLimitController,
                hint: '1-500',
                numeric: true,
                focusNode: _gapLimitFocus,
                onChanged: () {},
                onSubmitted: _commitGapLimit,
                tokens: tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: GerfautSpacing.md),
        if (wallets.isEmpty)
          Text(
            'No wallets on this network yet.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          )
        else
          for (final wallet in wallets)
            _WalletRow(
              wallet: wallet,
              tokens: tokens,
              renaming: _renamingId == wallet.id,
              confirmingRemove: _confirmRemoveId == wallet.id,
              renameController: _renameController,
              onRenameStart: () {
                setState(() {
                  _renamingId = wallet.id;
                  _confirmRemoveId = null;
                  _renameController.text = wallet.name;
                });
              },
              onRenameSubmit: () => _rename(wallet.id),
              onRemoveStart: () {
                setState(() {
                  _confirmRemoveId = wallet.id;
                  _renamingId = null;
                });
              },
              onRemoveConfirm: () => _remove(wallet.id),
              onCancel: () {
                setState(() {
                  _renamingId = null;
                  _confirmRemoveId = null;
                });
              },
              rescanning: _rescanningId == wallet.id,
              busy: sync.isSyncing(wallet.id),
              onRescan: () => _rescan(wallet.id),
            ),
        if (_walletError != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _walletError!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.wallet,
    required this.tokens,
    required this.renaming,
    required this.confirmingRemove,
    required this.renameController,
    required this.onRenameStart,
    required this.onRenameSubmit,
    required this.onRemoveStart,
    required this.onRemoveConfirm,
    required this.onCancel,
    required this.rescanning,
    required this.busy,
    required this.onRescan,
  });

  final WalletMeta wallet;
  final GerfautTokens tokens;
  final bool renaming;
  final bool confirmingRemove;
  final TextEditingController renameController;
  final VoidCallback onRenameStart;
  final VoidCallback onRenameSubmit;
  final VoidCallback onRemoveStart;
  final VoidCallback onRemoveConfirm;
  final VoidCallback onCancel;

  /// A rescan started from this row is running: the button says so.
  final bool rescanning;

  /// A sync or rescan of this wallet is in flight, wherever it was
  /// started: every action waits for it.
  final bool busy;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final single = wallet.isSingleAddress;
    return Container(
      margin: const EdgeInsets.only(bottom: GerfautSpacing.sm),
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FirstLine(
                style: tokens.body,
                child: Icon(
                  LucideIcons.wallet,
                  size: 16,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              Expanded(
                child: renaming
                    ? Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: renameController,
                              autofocus: true,
                              style: tokens.body,
                              onSubmitted: (_) => onRenameSubmit(),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: tokens.surfaceSunken,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: GerfautSpacing.sm,
                                  vertical: GerfautSpacing.xs,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    GerfautRadius.sm,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Save name',
                            onPressed: onRenameSubmit,
                            icon: Icon(
                              LucideIcons.check,
                              size: 18,
                              color: tokens.primary,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel renaming',
                            onPressed: onCancel,
                            icon: Icon(
                              LucideIcons.x,
                              size: 18,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wallet.name,
                            style: tokens.bodySmall.copyWith(
                              fontWeight: FontWeight.w500,
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                            ),
                          ),
                          Text(
                            single ? 'Single address' : 'Descriptor wallet',
                            style: tokens.label.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (confirmingRemove) ...[
            const SizedBox(height: GerfautSpacing.sm),
            // Amber, and its own copy says why: this only stops
            // watching, nothing moves on chain. Nothing is at stake but
            // a row in a list, and the coins are exactly where they
            // were — red belongs to what costs funds or privacy.
            GerfautNotice(
              tone: NoticeTone.info,
              message:
                  'You are removing "${wallet.name}" from Gerfaut. '
                  'This only stops watching. Nothing moves on chain.',
              // The sentence gets the whole width, the buttons a row of
              // their own under it: beside the text they left it a
              // column eight characters across on a phone.
              actionsBelow: true,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The destructive one is never alone: the panel is
                  // the confirmation, and the way out sits beside it.
                  GhostButton(label: 'Cancel', onPressed: onCancel),
                  const SizedBox(width: GerfautSpacing.sm),
                  DangerButton(
                    label: 'Remove wallet',
                    onPressed: onRemoveConfirm,
                  ),
                ],
              ),
            ),
          ] else if (!renaming) ...[
            const SizedBox(height: GerfautSpacing.xs),
            // Three actions do not fit one line on a narrow phone: the
            // last one flows under the others rather than overflowing.
            Wrap(
              children: [
                GhostButton(
                  label: 'Rename',
                  icon: LucideIcons.pencil,
                  onPressed: busy ? null : onRenameStart,
                ),
                // An incremental sync only looks at the addresses already
                // revealed. Funds past them — a gap limit raised too late,
                // or a descriptor also used by another wallet that went
                // further — only turn up by scanning again from the first
                // address.
                GhostButton(
                  label: rescanning ? 'Rescanning…' : 'Rescan',
                  icon: LucideIcons.scanSearch,
                  onPressed: busy ? null : onRescan,
                ),
                _AlertGhostButton(
                  label: 'Remove',
                  icon: LucideIcons.trash2,
                  onPressed: busy ? null : onRemoveStart,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Ghost button in the alert color: the entry point of a destructive
/// confirmation, mirroring the desktop design amendment.
class _AlertGhostButton extends StatelessWidget {
  const _AlertGhostButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SizedBox(
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: tokens.alert,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: GerfautSpacing.xs),
            Text(label),
          ],
        ),
      ),
    );
  }
}
