import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/amounts.dart';
import '../widgets/app_bar.dart';
import '../widgets/brand.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_button.dart';
import 'add_wallet.dart';
import 'broadcast.dart';
import 'settings.dart';
import 'wallet_home.dart';

/// Home: the wallets of the active workspace network as cards, or the
/// empty state. Pull down to sync them all; the one primary action sits
/// at the bottom.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// One background refresh at startup, the first time this screen sees
  /// wallets to refresh; data stays visibly stamped. Read off the build
  /// rather than listened for: the list often loads before this screen
  /// first builds — whatever feeds the home-screen widgets asks for it
  /// first — and a listener would wait for a change that never comes.
  void _autoSyncOnce(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).valueOrNull;
    final network = ref.read(settingsProvider).valueOrNull?.activeNetwork;
    if (wallets == null || wallets.isEmpty || network == null) return;
    if (ref.read(autoSyncedProvider)) return;
    // Off the frame: starting a sync moves provider state, which a
    // build in progress must not.
    Future.microtask(() {
      if (!context.mounted || ref.read(autoSyncedProvider)) return;
      ref.read(autoSyncedProvider.notifier).state = true;
      ref.read(syncProvider.notifier).syncAll(network);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    _autoSyncOnce(context, ref);

    final settings = ref.watch(settingsProvider);
    final wallets = ref.watch(walletsProvider);
    final masked = ref.watch(maskedProvider);
    ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    final network = settings.valueOrNull?.activeNetwork;

    return Scaffold(
      appBar: GerfautAppBar(
        title: Row(
          children: [
            // The falcon alone: whoever opens the app knows its name,
            // and the mark says it in the space of a glyph.
            GerfautMark(
              color: tokens.primary,
              height: 26,
              semanticLabel: 'Gerfaut',
            ),
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
          // The list shows balances, so it masks them from here too.
          IconButton(
            tooltip: masked ? 'Show balances' : 'Hide balances',
            onPressed: () => ref.read(maskedProvider.notifier).toggle(),
            icon: Icon(masked ? LucideIcons.eyeOff : LucideIcons.eye, size: 20),
          ),
          // Syncs every wallet of the network at once, and turns for as
          // long as any of them is still working.
          SyncButton(
            syncing: sync.syncingAny,
            onPressed: network == null || (wallets.valueOrNull?.isEmpty ?? true)
                ? null
                : () => sync.syncAll(network),
          ),
          // A transaction belongs to the workspace network, not to one
          // wallet: broadcasting starts from here.
          IconButton(
            tooltip: 'Broadcast',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BroadcastScreen(),
                ),
              );
            },
            icon: const Icon(LucideIcons.radio, size: 20),
          ),
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
                (_, AsyncData(:final value)) when value.isEmpty => EmptyState(
                  // The first screen of the app: the full logo, once,
                  // where every other empty state gets a watermark.
                  art: GerfautLockup(
                    color: tokens.primary,
                    width: 160,
                    semanticLabel: 'Gerfaut',
                  ),
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
///
/// The name and the balance, nothing else. A freshness line repeated on
/// every card spends a whole row on an answer nobody looks for while
/// scanning a list; it belongs on the wallet's own page, where a single
/// balance is being read and "where does this number come from?" is
/// actually the question. What stays is what tells the cards apart, and
/// they shrink by the line they lost: more wallets fit on screen, which
/// is the one thing this list has to do.
class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet, required this.onTap, this.error});

  final WalletMeta wallet;
  final VoidCallback onTap;

  /// The one exception to the rule above: a sync that failed contradicts
  /// the figure right above it, and a stale balance stated as fact is a
  /// lie. A sync that went well has nothing to say.
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
                    Icon(LucideIcons.wallet, size: 16, color: tokens.textMuted),
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
                if (error != null) ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  // One line, amber: the reason is a long press away
                  // here, and spelled out on the wallet's page.
                  Tooltip(
                    message: error!,
                    triggerMode: TooltipTriggerMode.longPress,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.triangleAlert,
                          size: 13,
                          color: tokens.pending,
                        ),
                        const SizedBox(width: GerfautSpacing.xs),
                        Flexible(
                          child: Text(
                            'Sync failed',
                            style: tokens.label.copyWith(color: tokens.pending),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
