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
import '../widgets/buttons.dart';
import '../widgets/count_badge.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_pill.dart';
import '../widgets/sync_indicator.dart';
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
  Future<void> _sync() async {
    try {
      await ref.read(syncProvider.notifier).syncWallet(widget.walletId);
    } catch (_) {
      // The failure lands in syncErrorsProvider and the freshness line.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final masked = ref.watch(maskedProvider);
    final syncing = ref
        .watch(syncProvider.notifier)
        .isSyncing(widget.walletId);
    ref.watch(syncProvider);
    final snapshot = ref.watch(snapshotProvider(widget.walletId));

    return Scaffold(
      appBar: AppBar(
        title: Text(snapshot.valueOrNull?.meta.name ?? ''),
        actions: [
          IconButton(
            tooltip: masked ? 'Show balances' : 'Hide balances',
            onPressed: () => ref.read(maskedProvider.notifier).toggle(),
            icon: Icon(
              masked ? LucideIcons.eyeOff : LucideIcons.eye,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Sync',
            onPressed: syncing ? null : _sync,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
          const SizedBox(width: GerfautSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: switch (snapshot) {
          AsyncData(:final value) => _buildLoaded(value, syncing),
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

  Widget _buildLoaded(WalletSnapshot snapshot, bool syncing) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
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
                  error: ref.watch(syncErrorsProvider)[widget.walletId],
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
                      if (snapshot.balance.hasPending) ...[
                        const SizedBox(height: GerfautSpacing.sm),
                        Text(
                          'Includes pending funds not yet confirmed.',
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
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incoming ? 'Received' : 'Sent',
                        style: tokens.bodySmall,
                      ),
                      // Timestamp and status share the second line: on a
                      // phone the date is what may be shortened, never
                      // the amount.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              tx.status.confirmed && tx.status.timestamp != null
                                  ? formatTimestamp(tx.status.timestamp!)
                                  : truncateMiddle(tx.txid, head: 8, tail: 8),
                              style:
                                  tx.status.confirmed &&
                                      tx.status.timestamp != null
                                  ? tokens.figureOf(
                                      size: 12,
                                      color: tokens.textMuted,
                                    )
                                  : tokens.data.copyWith(
                                      fontSize: 12,
                                      color: tokens.textMuted,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: GerfautSpacing.xs + 2),
                          StatusPill(
                            status: tx.status,
                            confirmations: tx.confirmations,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
