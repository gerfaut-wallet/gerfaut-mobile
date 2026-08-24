import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/format.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';
import '../widgets/buttons.dart';
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
                BalanceAmount(sats: snapshot.balance.total),
                if (snapshot.balance.hasPending) ...[
                  const SizedBox(height: GerfautSpacing.xs),
                  Text(
                    'includes pending funds not yet confirmed',
                    style: tokens.label.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Transactions'),
              Tab(text: 'UTXOs'),
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

/// Transactions are list rows, never cards: they scan vertically.
/// 44px minimum, hairline separators, amounts right-aligned in mono.
class _TxList extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    if (txs.isEmpty) {
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

    final list = ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, thickness: 1, color: tokens.border),
      itemBuilder: (context, index) {
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
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: GerfautSpacing.md,
              vertical: GerfautSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: incoming && !pending
                        ? tokens.confirmedSurface
                        : tokens.surfaceSunken,
                    shape: BoxShape.circle,
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
                      Text(
                        tx.status.confirmed && tx.status.timestamp != null
                            ? formatTimestamp(tx.status.timestamp!)
                            : truncateMiddle(tx.txid, head: 8, tail: 8),
                        style: tx.status.confirmed && tx.status.timestamp != null
                            ? tokens.figureOf(
                                size: 12,
                                color: tokens.textMuted,
                              )
                            : tokens.data.copyWith(
                                fontSize: 12,
                                color: tokens.textMuted,
                              ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                StatusPill(status: tx.status, confirmations: tx.confirmations),
                const SizedBox(width: GerfautSpacing.sm),
                ListAmount(sats: tx.netSats, pending: pending),
              ],
            ),
          ),
        );
      },
    );
    if (!truncated) {
      return list;
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.md,
            GerfautSpacing.sm,
            GerfautSpacing.md,
            0,
          ),
          child: Text(
            'This address has more history than Gerfaut fetched: the list '
            'below is partial. The balance stays exact.',
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
        ),
        Expanded(child: list),
      ],
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
