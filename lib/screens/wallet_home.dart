import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/count_badge.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_pill.dart';
import '../widgets/sync_button.dart';
import '../widgets/sync_indicator.dart';
import 'broadcast.dart';
import 'export.dart';
import 'receive.dart';
import 'tx_detail.dart';

/// Home of one wallet: balance, freshness, transactions and UTXOs.
/// The one primary action, Receive, sits at the bottom under the thumb.
class WalletHomeScreen extends ConsumerStatefulWidget {
  const WalletHomeScreen({super.key, required this.walletId});

  final String walletId;

  @override
  ConsumerState<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends ConsumerState<WalletHomeScreen> {
  void _open(Widget Function(String walletId) build) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => build(widget.walletId)));
  }

  Future<void> _sync() async {
    try {
      await ref.read(syncProvider.notifier).syncWallet(widget.walletId);
    } catch (_) {
      // The failure lands in syncErrorsProvider and the freshness line.
    }
  }

  /// The shortcut the phone gets and the desktop does not: settings are
  /// a swipe and three taps away here, and the title is already a target.
  /// The full path stays Settings -> the wallet -> Rename, and both go
  /// through the one call that writes a name.
  Future<void> _rename(String current) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: current),
    );
    // Empty or unchanged: the dialog closes and nothing is written.
    if (name == null || name.isEmpty || name == current) return;
    try {
      await ref.read(bridgeProvider).renameWallet(widget.walletId, name);
      ref.invalidate(walletsProvider);
      ref.invalidate(snapshotProvider(widget.walletId));
      messenger.showSnackBar(const SnackBar(content: Text('Wallet renamed')));
    } on BridgeException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final syncing = ref.watch(syncProvider.notifier).isSyncing(widget.walletId);
    ref.watch(syncProvider);
    final snapshot = ref.watch(snapshotProvider(widget.walletId));
    final loaded = snapshot.valueOrNull;
    final name = loaded?.meta.name;

    return Scaffold(
      appBar: GerfautAppBar(
        // No pencil: a permanent target next to the title for a rare
        // gesture, when the title is a 44px target already. What says so
        // is the ink under the finger and the label read out loud.
        title: Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            child: Tooltip(
              // The tooltip is the label a screen reader reads out after
              // the name: a second Semantics label would say it twice.
              message: 'Rename this wallet',
              child: InkWell(
                borderRadius: BorderRadius.circular(GerfautRadius.md),
                onTap: name == null ? null : () => _rename(name),
                // No padding of its own: the title stays against the
                // back arrow, where every other page starts.
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: masked ? 'Show balances' : 'Hide balances',
            onPressed: () => ref.read(maskedProvider.notifier).toggle(),
            icon: Icon(masked ? LucideIcons.eyeOff : LucideIcons.eye, size: 20),
          ),
          SyncButton(syncing: syncing, onPressed: _sync),
          IconButton(
            tooltip: 'Broadcast',
            onPressed: () => _open((_) => const BroadcastScreen()),
            icon: const Icon(LucideIcons.radio, size: 20),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: () => _open((id) => ExportScreen(walletId: id)),
            icon: const Icon(LucideIcons.fileDown, size: 20),
          ),
          const SizedBox(width: GerfautSpacing.xs),
        ],
      ),
      // A wallet already loaded stays on screen while it refreshes: a
      // loading line in place of a balance would hide what is known.
      body: SafeArea(
        child: loaded != null
            ? _buildLoaded(loaded, syncing)
            : switch (snapshot) {
                AsyncError() => Center(
                  child: Text(
                    'This wallet could not be loaded.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ),
                _ => Center(
                  child: Text(
                    'Loading wallet…',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ),
              },
      ),
    );
  }

  /// The figure alone can lie: a wallet that never reached a backend
  /// shows zero. The note says where the number comes from.
  static String? _balanceNote(WalletSnapshot snapshot, String? error) {
    final synced = snapshot.meta.lastSync != null;
    if (error != null && !synced) return 'Sync failed: nothing fetched yet.';
    if (error != null) return 'Sync failed: showing the last known balance.';
    if (!synced) return 'Not synced yet.';
    if (snapshot.balance.hasPending) {
      return 'Includes pending funds not yet confirmed.';
    }
    return null;
  }

  Widget _buildLoaded(WalletSnapshot snapshot, bool syncing) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final syncError = ref.watch(syncErrorsProvider)[widget.walletId];
    final note = _balanceNote(snapshot, syncError);
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GerfautSpacing.md,
              GerfautSpacing.sm,
              GerfautSpacing.md,
              GerfautSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SyncIndicator(
                  stamp: snapshot.meta.lastSync,
                  syncing: syncing,
                  error: syncError,
                ),
                const SizedBox(height: GerfautSpacing.md),
                // The balance as a dashboard figure: its own bordered
                // surface, with the role spelled out above it.
                Container(
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
                      Text(
                        'TOTAL BALANCE',
                        style: tokens.label.copyWith(color: tokens.textMuted),
                      ),
                      const SizedBox(height: GerfautSpacing.sm),
                      BalanceAmount(sats: snapshot.balance.total),
                      if (note != null) ...[
                        const SizedBox(height: GerfautSpacing.sm),
                        Text(
                          note,
                          style: tokens.label.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(
                child: _TabLabel(
                  label: 'Transactions',
                  count: snapshot.txs.length,
                ),
              ),
              Tab(
                child: _TabLabel(
                  label: 'UTXOs',
                  count:
                      ref
                          .watch(utxosProvider(widget.walletId))
                          .valueOrNull
                          ?.length ??
                      0,
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _TxList(
                  walletId: widget.walletId,
                  network: snapshot.meta.network,
                  txs: snapshot.txs,
                  truncated: snapshot.truncated,
                ),
                _UtxoList(walletId: widget.walletId),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            child: PrimaryButton(
              label: 'Receive',
              icon: LucideIcons.qrCode,
              expand: true,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReceiveScreen(walletId: widget.walletId),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Rename in place, over the page instead of away from it. The dialog
/// rides above the soft keyboard on its own: [Dialog] adds the view
/// insets to its inset padding.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text('Rename wallet', style: tokens.h2),
      // The title is the field's label: a second one over a single
      // prefilled field would say the same word twice.
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        style: tokens.body,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          filled: true,
          fillColor: tokens.surfaceSunken,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: GerfautSpacing.md,
            vertical: GerfautSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
            borderSide: BorderSide(color: tokens.primary, width: 2),
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(label: 'Save', onPressed: _save),
      ],
    );
  }
}

/// A tab label with the count of what it holds: the sunken pill keeps
/// the number legible without competing with the label.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    // A long label plus its count scales down rather than clipping.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: GerfautSpacing.xs + 2),
            CountBadge(count: count),
          ],
        ],
      ),
    );
  }
}

/// Transactions are list rows, never cards: they scan vertically.
/// 48px rows, hairline separators, figures right-aligned.
class _TxList extends ConsumerWidget {
  const _TxList({
    required this.walletId,
    required this.network,
    required this.txs,
    this.truncated = false,
  });

  final String walletId;
  final Network network;
  final List<TxSummary> txs;

  /// The list is partial (busy watched address); the balance stays exact.
  final bool truncated;

  /// Fetches one more round and states what it brought back.
  Future<void> _loadOlder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await ref.read(historyProvider.notifier).loadMore(walletId);
      if (added == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (added) {
            0 => 'History is complete',
            1 => '1 older transaction',
            _ => '$added older transactions',
          }),
        ),
      );
    } on BridgeException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    if (txs.isEmpty && !truncated) {
      return const EmptyState(
        title: 'No transactions yet',
        hint: 'Once this wallet sees activity on the chain, it shows up here.',
      );
    }

    // Pending first; otherwise the core's order (newest confirmed first).
    final sorted = [
      ...txs.where((tx) => !tx.status.confirmed),
      ...txs.where((tx) => tx.status.confirmed),
    ];

    ref.watch(historyProvider);
    final loading = ref.read(historyProvider.notifier).isLoading(walletId);

    return ListView.separated(
      itemCount: sorted.length + (truncated ? 1 : 0),
      separatorBuilder: (_, _) =>
          Divider(height: 1, thickness: 1, color: tokens.border),
      itemBuilder: (context, index) {
        if (index == sorted.length) {
          // The rest of the history is one action away, not a warning.
          return Padding(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            child: Column(
              children: [
                SecondaryButton(
                  label: loading ? 'Fetching…' : 'Load older transactions',
                  icon: LucideIcons.chevronDown,
                  onPressed: loading ? null : () => _loadOlder(context, ref),
                ),
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'This address has a long history: it loads in rounds. '
                  'The balance above already covers all of it.',
                  style: tokens.label.copyWith(color: tokens.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final tx = sorted[index];
        final incoming = tx.netSats >= 0;
        final pending = !tx.status.confirmed;
        final dated = tx.status.confirmed && tx.status.timestamp != null;
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TxDetailScreen(
                  walletId: walletId,
                  txid: tx.txid,
                  network: network,
                ),
              ),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: GerfautSpacing.md,
              vertical: GerfautSpacing.xs + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: incoming && !pending
                        ? tokens.confirmedSurface
                        : tokens.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    incoming
                        ? LucideIcons.arrowDownLeft
                        : LucideIcons.arrowUpRight,
                    size: 15,
                    color: incoming && !pending
                        ? tokens.confirmed
                        : tokens.textMuted,
                    // Said out loud, since the word is not written any
                    // more: the arrow, the sign and the colour say it
                    // on screen, and this says it to a screen reader.
                    semanticLabel: incoming ? 'Received' : 'Sent',
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                // One line: the date reads in full, and the state is a
                // glyph rather than a pill. "Sent" and "Received" are
                // dropped on the phone, where the arrow, the sign and
                // the colour already carry the direction three times.
                Expanded(
                  child: Text(
                    dated
                        ? formatTimestamp(tx.status.timestamp!)
                        : truncateMiddle(tx.txid, head: 8, tail: 8),
                    style: dated
                        ? tokens.figureOf(size: 13)
                        : tokens.data.copyWith(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                StatusGlyph(status: tx.status),
                const SizedBox(width: GerfautSpacing.sm),
                ListAmount(sats: tx.netSats, pending: pending),
                const SizedBox(width: 2),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// UTXOs as dense rows: outpoint, address, status, value in sats.
class _UtxoList extends ConsumerWidget {
  const _UtxoList({required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final utxos = ref.watch(utxosProvider(walletId));

    return switch (utxos) {
      AsyncData(:final value) when value.isEmpty => const EmptyState(
        title: 'No unspent outputs',
        hint: 'UTXOs appear here as soon as the wallet holds coins.',
      ),
      AsyncData(:final value) => ListView.separated(
        itemCount: value.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, thickness: 1, color: tokens.border),
        itemBuilder: (context, index) {
          final utxo = value[index];
          return Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: GerfautSpacing.md,
              vertical: GerfautSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AddressChip(value: utxo.outpoint, head: 8, tail: 6),
                      if (utxo.address != null) ...[
                        const SizedBox(height: GerfautSpacing.xs),
                        AddressChip(value: utxo.address!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(status: utxo.status),
                    const SizedBox(height: GerfautSpacing.xs),
                    StackedAmount(sats: utxo.valueSats),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      AsyncError() => Center(
        child: Text(
          'UTXOs could not be loaded.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ),
      _ => Center(
        child: Text(
          'Loading UTXOs…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ),
    };
  }
}
