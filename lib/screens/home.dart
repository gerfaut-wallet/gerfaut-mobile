import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/amounts.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_indicator.dart';
import 'add_wallet.dart';
import 'settings.dart';
import 'wallet_home.dart';

/// Home: the wallets of the active workspace network as cards, or the
/// empty state. Pull down to sync them all; the one primary action sits
/// at the bottom.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _autoSyncOnce(WidgetRef ref) {
    ref.listen(walletsProvider, (_, next) {
      final wallets = next.valueOrNull;
      final network = ref.read(settingsProvider).valueOrNull?.activeNetwork;
      if (wallets != null &&
          wallets.isNotEmpty &&
          network != null &&
          !ref.read(autoSyncedProvider)) {
        ref.read(autoSyncedProvider.notifier).state = true;
        // One background refresh at startup; data stays visibly stamped.
        ref.read(syncProvider.notifier).syncAll(network);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    _autoSyncOnce(ref);

    final settings = ref.watch(settingsProvider);
    final wallets = ref.watch(walletsProvider);
    ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    final network = settings.valueOrNull?.activeNetwork;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Gerfaut'),
            if (network != null && network != Network.mainnet) ...[
              const SizedBox(width: GerfautSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: GerfautSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(GerfautRadius.full),
                ),
                child: Text(
                  network.label,
                  style: tokens.label.copyWith(color: tokens.pending),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(LucideIcons.settings, size: 20),
          ),
          const SizedBox(width: GerfautSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: switch ((settings, wallets)) {
                (AsyncError(), _) || (_, AsyncError()) => Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GerfautSpacing.md,
                    ),
                    child: Text(
                      'The vault could not be opened. Restart Gerfaut; if '
                      'this persists, the secure storage refused access to '
                      'the vault key.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                (_, AsyncData(:final value)) when value.isEmpty =>
                  const EmptyState(
                    title: 'No wallets yet',
                    hint:
                        'Import a descriptor, xpub, or address to start '
                        'watching it.',
                  ),
                (_, AsyncData(:final value)) => RefreshIndicator(
                  onRefresh: () async {
                    if (network == null) return;
                    final report = await sync.syncAll(network);
                    if (report == null || !context.mounted) return;
                    // A benign confirmation: the summary may disappear,
                    // per-wallet failures stay on the freshness lines.
                    final synced = report.reports.length;
                    final failed = report.failures.length;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          failed == 0
                              ? (synced == 1
                                    ? '1 wallet synced'
                                    : '$synced wallets synced')
                              : '$synced synced, $failed failed',
                        ),
                      ),
                    );
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(GerfautSpacing.md),
                    itemCount: value.length,
                    itemBuilder: (context, index) {
                      final wallet = value[index];
                      return _WalletCard(
                        wallet: wallet,
                        syncing: sync.isSyncing(wallet.id),
                        error: ref.watch(syncErrorsProvider)[wallet.id],
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  WalletHomeScreen(walletId: wallet.id),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                _ => Center(
                  child: Text(
                    'Opening the vault…',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.all(GerfautSpacing.md),
              child: PrimaryButton(
                label: 'Add a wallet',
                expand: true,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddWalletScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One watched wallet: surface card, hairline border, no shadow.
class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.syncing,
    required this.onTap,
    this.error,
  });

  final WalletMeta wallet;
  final bool syncing;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(GerfautRadius.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GerfautRadius.lg),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      wallet.isSingleAddress
                          ? LucideIcons.mapPin
                          : LucideIcons.wallet,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(
                      child: Text(
                        wallet.name,
                        style: tokens.h2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GerfautSpacing.sm),
                BalanceAmount(sats: wallet.cachedBalance.total),
                const SizedBox(height: GerfautSpacing.sm),
                SyncIndicator(
                  stamp: wallet.lastSync,
                  syncing: syncing,
                  error: error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
