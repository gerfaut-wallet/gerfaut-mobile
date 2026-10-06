import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/live.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';
import '../../widgets/reorder.dart';
import '../../widgets/section_card.dart';
import '../../widgets/setting_switch.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/tap_target.dart';
import '../../widgets/wallet_icon.dart';
import 'fields.dart';
import '../../widgets/toast.dart';

/// The Wallets section: the gap limit every wallet shares, then the
/// wallets of the active network in the order the home screen lists
/// them, each with its own actions and a handle to move it.
///
/// The section is its page's whole scroll view, the rows a sliver of
/// it: a row dragged to the edge has to scroll the page to reach a row
/// out of sight, and a list boxed inside a scrolling column cannot.
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

  /// The wallet a removal is under way for, the owner's check included:
  /// its question's answers are held, so a second tap sends nothing.
  String? _removingId;

  /// Wallet whose rescan was started here; its row says so meanwhile.
  String? _rescanningId;

  /// The order the rows were dropped in, by id, kept until the vault
  /// has caught up: without it the moved row would snap back for the
  /// frame between the drop and the refreshed list.
  List<String>? _order;

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
    // Committed on blur, which leaving the page is too: the views are
    // read again through the container, which outlives the page.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(bridgeProvider).setGapLimit(parsed);
      container.invalidate(settingsProvider);
      container.invalidate(walletsProvider);
      container.invalidate(snapshotProvider);
      if (!mounted) return;
      _seededGapLimit = parsed;
      _gapLimitController.text = '$parsed';
      _toast('Setting saved');
    } catch (_) {
      if (mounted) _gapLimitController.text = '$current';
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(Toast(message));
  }

  Future<void> _rename(String id) async {
    final name = _renameController.text.trim();
    if (name.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(bridgeProvider).renameWallet(id, name);
      container.invalidate(walletsProvider);
      container.invalidate(snapshotProvider(id));
      if (!mounted) return;
      setState(() => _renamingId = null);
      _toast('Setting saved');
    } catch (error) {
      if (mounted) setState(() => _walletError = '$error');
    }
  }

  Future<void> _remove(String id) async {
    if (_removingId != null) return;
    // Held before the first await: the list is read again even if the
    // page was left meanwhile. `ref` dies with it.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _removingId = id);
    try {
      await ref.read(bridgeProvider).removeWallet(id);
      container.invalidate(walletsProvider);
      if (!mounted) return;
      setState(() => _confirmRemoveId = null);
      _toast('Wallet removed');
    } catch (error) {
      if (mounted) setState(() => _walletError = '$error');
    } finally {
      if (mounted) setState(() => _removingId = null);
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

  /// Offers the seven glyphs and stores the one picked. The same glyph
  /// answers on the home card: the wallet list is refreshed with it.
  Future<void> _pickIcon(WalletMeta wallet) async {
    final chosen = await WalletIconPicker.show(context, current: wallet.icon);
    if (chosen == null || chosen == wallet.icon || !mounted) return;
    setState(() => _walletError = null);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(bridgeProvider).setWalletIcon(wallet.id, chosen);
      container.invalidate(walletsProvider);
      container.invalidate(snapshotProvider(wallet.id));
      if (mounted) _toast('Setting saved');
    } catch (error) {
      if (mounted) setState(() => _walletError = '$error');
    }
  }

  /// The rows in the order they show: the vault's, unless a drop is
  /// still on its way there. A list that changed underneath — a wallet
  /// added or removed meanwhile — takes the vault's order back.
  List<WalletMeta> _inOrder(List<WalletMeta> wallets) {
    final order = _order;
    if (order == null) return wallets;
    final byId = {for (final wallet in wallets) wallet.id: wallet};
    if (order.length != wallets.length || !order.every(byId.containsKey)) {
      _order = null;
      return wallets;
    }
    return [for (final id in order) byId[id]!];
  }

  /// Moves one row and tells the core the new order of the rows shown:
  /// only this network's wallets, so another network's keep their slots.
  Future<void> _reorder(List<WalletMeta> shown, int from, int to) async {
    if (from == to) return;
    final ids = [for (final wallet in shown) wallet.id];
    ids.insert(to, ids.removeAt(from));
    setState(() {
      _order = ids;
      _walletError = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(bridgeProvider).reorderWallets(ids);
      // Read the vault back, then let the local order go: nothing snaps
      // back on the way, and an order set on the home screen afterwards
      // is followed here rather than overruled by a drop long since
      // landed. A newer drop keeps its own until then.
      container.invalidate(walletsProvider);
      await container.read(walletsProvider.future);
      if (!mounted || !identical(_order, ids)) return;
      setState(() => _order = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _order = null;
        _walletError = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? [];
    ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    if (settings == null) {
      return Padding(
        padding: const EdgeInsets.all(GerfautSpacing.md),
        child: Text(
          'Loading…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      );
    }
    _seedGapLimit(settings);
    final shown = _inOrder(wallets);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          // The page margin, and the same room under the card as the
          // other section pages leave.
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.md,
            GerfautSpacing.md,
            GerfautSpacing.md,
            GerfautSpacing.md + GerfautSpacing.lg,
          ),
          sliver: SliverSectionCard(
            icon: LucideIcons.wallet,
            title: 'Wallets',
            slivers: [
              SliverToBoxAdapter(child: _gapLimit(tokens)),
              if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: Text(
                    'No wallets on this network yet.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                )
              else
                // The order here is the order of the home screen.
                SliverReorderableList(
                  proxyDecorator: liftedProxy,
                  itemCount: shown.length,
                  onReorderItem: (from, to) => _reorder(shown, from, to),
                  itemBuilder: (context, index) => _row(shown, index, sync),
                ),
              if (_walletError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: GerfautSpacing.sm),
                    // Said aloud as it appears.
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _walletError!,
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              if (shown.isNotEmpty)
                SliverToBoxAdapter(child: _LivePins(wallets: shown)),
            ],
          ),
        ),
      ],
    );
  }

  /// The gap limit, its two lines of explanation, and its field.
  Widget _gapLimit(GerfautTokens tokens) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.md),
      child: Row(
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
              label: 'Gap limit',
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
    );
  }

  /// The row of the wallet at [index] among those [shown].
  Widget _row(List<WalletMeta> shown, int index, SyncController sync) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final wallet = shown[index];
    return _WalletRow(
      key: ValueKey(wallet.id),
      index: index,
      wallet: wallet,
      tokens: tokens,
      // One wallet has nowhere to go: no handle to promise it.
      movable: shown.length > 1,
      renaming: _renamingId == wallet.id,
      confirmingRemove: _confirmRemoveId == wallet.id,
      removing: _removingId == wallet.id,
      coverage: ref.watch(walletCoverageProvider(wallet.id)),
      renameController: _renameController,
      onRenameStart: () {
        setState(() {
          _renamingId = wallet.id;
          _confirmRemoveId = null;
          _renameController.text = wallet.name;
        });
      },
      onRenameSubmit: () => _rename(wallet.id),
      onPickIcon: () => _pickIcon(wallet),
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
    );
  }
}

/// "Always watch live first", an advanced setting folded away under
/// the list. When Live cannot follow every address, it follows the
/// pinned wallets before the others, then the ones holding coins.
/// Pinning many large wallets can leave the rest to the syncs: the
/// user's call to make, and why the switches are out of the way.
class _LivePins extends ConsumerStatefulWidget {
  const _LivePins({required this.wallets});

  /// The wallets of the active network, in the order of the list.
  final List<WalletMeta> wallets;

  @override
  ConsumerState<_LivePins> createState() => _LivePinsState();
}

class _LivePinsState extends ConsumerState<_LivePins> {
  bool _open = false;

  /// The wallet a pin is on its way to the vault for: the other
  /// switches wait for it.
  String? _savingId;

  /// What the vault refused, under the wallet it was for.
  ({String id, String message})? _failure;

  Future<void> _pin(WalletMeta wallet, bool pinned) async {
    if (_savingId != null) return;
    // Held before the await: the list is read again even if the page
    // was left meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _savingId = wallet.id;
      _failure = null;
    });
    try {
      await ref.read(bridgeProvider).setWalletLivePinned(wallet.id, pinned);
      container.invalidate(walletsProvider);
      messenger.showSnackBar(Toast('Setting saved'));
    } on BridgeException catch (error) {
      if (mounted) {
        setState(() => _failure = (id: wallet.id, message: error.message));
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final pinned = widget.wallets.where((w) => w.livePinned).length;
    // Folded, the button still says when something is pinned: a choice
    // that changes what Live follows is never out of sight entirely.
    final label = !_open && pinned > 0
        ? 'Advanced · ${pinned == 1 ? '1 wallet' : '$pinned wallets'} '
              'watched live first'
        : 'Advanced';
    return Container(
      margin: const EdgeInsets.only(top: GerfautSpacing.sm),
      padding: const EdgeInsets.only(top: GerfautSpacing.xs),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GhostButton(
            label: label,
            icon: _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            expanded: _open,
            onPressed: () => setState(() => _open = !_open),
          ),
          if (_open) ...[
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Always watch live first',
              style: tokens.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation('wght', 500)],
              ),
            ),
            Text(
              'When Live cannot follow every address, the wallets turned '
              'on here are followed first.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            for (final wallet in widget.wallets) ...[
              const SizedBox(height: GerfautSpacing.sm),
              SettingSwitch(
                title: wallet.name,
                semanticLabel: 'Always watch ${wallet.name} live first',
                value: wallet.livePinned,
                onChanged: _savingId != null
                    ? null
                    : (pinned) => _pin(wallet, pinned),
              ),
              if (_failure?.id == wallet.id)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _failure!.message,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    super.key,
    required this.index,
    required this.wallet,
    required this.tokens,
    required this.movable,
    required this.renaming,
    required this.confirmingRemove,
    required this.removing,
    required this.coverage,
    required this.renameController,
    required this.onRenameStart,
    required this.onRenameSubmit,
    required this.onPickIcon,
    required this.onRemoveStart,
    required this.onRemoveConfirm,
    required this.onCancel,
    required this.rescanning,
    required this.busy,
    required this.onRescan,
  });

  /// Position in the list, for the drag handle.
  final int index;
  final WalletMeta wallet;
  final GerfautTokens tokens;

  /// Whether a handle is shown: only when there is somewhere to move to.
  final bool movable;
  final bool renaming;
  final bool confirmingRemove;

  /// The removal is under way: its answers are held.
  final bool removing;

  /// How much of the wallet Live follows, while Live cannot follow
  /// every wallet whole; null otherwise.
  final WalletCoverage? coverage;
  final TextEditingController renameController;
  final VoidCallback onRenameStart;
  final VoidCallback onRenameSubmit;
  final VoidCallback onPickIcon;
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
    // Under the finger, the row is the one thing that really floats:
    // its own surface, the overlay shadow. At rest it has neither.
    final lifted = LiftedItem.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: GerfautSpacing.sm),
      padding: const EdgeInsets.all(GerfautSpacing.md),
      decoration: BoxDecoration(
        color: lifted ? tokens.surface : null,
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        border: Border.all(color: tokens.border),
        boxShadow: lifted ? [tokens.shadowOverlay] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // On the line of the name, whichever face it wears: the
              // field while renaming, the small one otherwise.
              FirstLine(
                style: renaming ? tokens.body : tokens.bodySmall,
                child: Icon(
                  walletGlyph(wallet.icon),
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
                            child: Semantics(
                              label: 'Wallet name',
                              child: TextField(
                                controller: renameController,
                                autofocus: true,
                                style: tokens.body,
                                onSubmitted: (_) => onRenameSubmit(),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: tokens.surfaceSunken,
                                  // The height of every other field: a
                                  // box the thumb lands in.
                                  constraints: const BoxConstraints(
                                    minHeight: GerfautTouch.target,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: GerfautSpacing.sm,
                                    vertical: GerfautSpacing.sm + 2,
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
                          if (coverage != null) ...[
                            const SizedBox(height: GerfautSpacing.xs),
                            LiveCoveragePill(coverage: coverage!),
                          ],
                        ],
                      ),
              ),
              if (movable && !renaming) ...[
                const SizedBox(width: GerfautSpacing.sm),
                // The handle starts a drag at once; the row itself is
                // full of buttons a long press would fight with. The
                // list already announces "move up" and "move down" on
                // the row, so the glyph has nothing to add out loud.
                ReorderableDragStartListener(
                  index: index,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: GerfautTouch.target,
                      child: Center(
                        child: Icon(
                          LucideIcons.gripVertical,
                          size: 18,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
              // The destructive one is never alone: the panel is the
              // confirmation, and the way out sits beside it — or
              // above it, once the text is too large for one line.
              action: ConfirmActions(
                cancel: GhostButton(
                  label: 'Cancel',
                  onPressed: removing ? null : onCancel,
                ),
                confirm: DangerButton(
                  label: 'Remove wallet',
                  onPressed: removing ? null : onRemoveConfirm,
                ),
              ),
            ),
          ] else if (!renaming) ...[
            const SizedBox(height: GerfautSpacing.xs),
            // Four actions do not fit one line on a narrow phone: the
            // last ones flow under the others rather than overflowing.
            Wrap(
              children: [
                GhostButton(
                  label: 'Rename',
                  icon: LucideIcons.pencil,
                  onPressed: busy ? null : onRenameStart,
                ),
                GhostButton(
                  label: 'Icon',
                  icon: LucideIcons.shapes,
                  onPressed: busy ? null : onPickIcon,
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
    return TapTarget(
      child: SizedBox(
        height: GerfautTouch.control,
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
      ),
    );
  }
}
