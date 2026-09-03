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
import '../widgets/reorder.dart';
import '../widgets/sync_button.dart';
import '../widgets/wallet_icon.dart';
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
            onPressed: () => SettingsScreen.open(context),
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
                (_, AsyncData(:final value)) => _WalletList(
                  wallets: value,
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

/// The wallet cards, in the vault's order, pulled down to sync them all
/// and held down to move one. The order a card is dropped in is kept
/// here until the vault has caught up, so nothing snaps back on the
/// way; only this network's wallets are sent, so another network's keep
/// their slots.
class _WalletList extends ConsumerStatefulWidget {
  const _WalletList({required this.wallets, required this.onRefresh});

  final List<WalletMeta> wallets;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_WalletList> createState() => _WalletListState();
}

class _WalletListState extends ConsumerState<_WalletList> {
  /// The order the cards were dropped in, by id, until the vault has
  /// caught up. A list that changed underneath takes the vault's back.
  List<String>? _order;

  /// The cards in the order they show: the vault's, unless a drop is
  /// still on its way there.
  List<WalletMeta> _inOrder() {
    final order = _order;
    final wallets = widget.wallets;
    if (order == null) return wallets;
    final byId = {for (final wallet in wallets) wallet.id: wallet};
    if (order.length != wallets.length || !order.every(byId.containsKey)) {
      _order = null;
      return wallets;
    }
    return [for (final id in order) byId[id]!];
  }

  Future<void> _reorder(int from, int to) async {
    if (from == to) return;
    final ids = [for (final wallet in _inOrder()) wallet.id];
    ids.insert(to, ids.removeAt(from));
    setState(() => _order = ids);
    try {
      await ref.read(bridgeProvider).reorderWallets(ids);
      // Read the vault back, then let the local order go: the provider
      // moves from one list to the next without a gap, so nothing snaps
      // back on the way, and an order set elsewhere afterwards — in the
      // settings, say — is followed here rather than overruled by a
      // drop long since landed. A newer drop keeps its own until then.
      ref.invalidate(walletsProvider);
      await ref.read(walletsProvider.future);
      if (!mounted || !identical(_order, ids)) return;
      setState(() => _order = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _order = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _inOrder();
    final errors = ref.watch(syncErrorsProvider);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ReorderableListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(GerfautSpacing.md),
        buildDefaultDragHandles: false,
        proxyDecorator: liftedProxy,
        itemCount: shown.length,
        onReorderItem: _reorder,
        itemBuilder: (context, index) {
          final wallet = shown[index];
          // A hold lifts the card; a tap still opens it. A handle would
          // be a permanent target for a rare gesture on every card.
          return ReorderableDelayedDragStartListener(
            key: ValueKey(wallet.id),
            index: index,
            child: _WalletCard(
              wallet: wallet,
              error: errors[wallet.id],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WalletHomeScreen(walletId: wallet.id),
                  ),
                );
              },
            ),
          );
        },
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
    // Held and moving, the card is the one thing on screen that really
    // floats, and gets the one shadow. At rest, never.
    final lifted = LiftedItem.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GerfautRadius.lg),
          boxShadow: lifted ? [tokens.shadowOverlay] : null,
        ),
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
                        walletGlyph(wallet.icon),
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
                              style: tokens.label.copyWith(
                                color: tokens.pending,
                              ),
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
      ),
    );
  }
}
