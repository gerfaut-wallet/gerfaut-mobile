import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/address_chip.dart';
import '../widgets/amounts.dart';

/// Audit view of a wallet's revealed addresses: external first, then
/// change, each row with its usage and the balance sitting on it.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key, required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final list = ref.watch(addressListProvider(walletId));
    final single =
        ref
            .watch(snapshotProvider(walletId))
            .valueOrNull
            ?.meta
            .isSingleAddress ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Addresses')),
      body: SafeArea(
        child: switch (list) {
          AsyncData(:final value) => _AddressListView(
            list: value,
            single: single,
          ),
          AsyncError() => Center(
            child: Text(
              'Addresses could not be loaded.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
          _ => Center(
            child: Text(
              'Loading addresses…',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        },
      ),
    );
  }
}

class _AddressListView extends StatelessWidget {
  const _AddressListView({required this.list, required this.single});

  final AddressList list;

  /// Single watched address: one section, no keychain vocabulary.
  final bool single;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.sm),
      children: [
        if (single)
          _Section(
            title: 'Watched address',
            hint: 'The one address this wallet watches.',
            rows: list.external,
          )
        else ...[
          _Section(
            title: 'External',
            hint: 'Receive addresses, in derivation order.',
            rows: list.external,
          ),
          const SizedBox(height: GerfautSpacing.md),
          _Section(
            title: 'Change',
            hint: 'Internal addresses used by outgoing transactions.',
            rows: list.internal,
            emptyText: 'No change addresses revealed yet.',
          ),
        ],
        if (list.truncated)
          Padding(
            padding: const EdgeInsets.all(GerfautSpacing.md),
            child: Text(
              'Long keychains are capped: only the first 200 addresses '
              'of each are listed.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}

/// One keychain: label header, hint, then dense 44px rows.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.rows,
    this.emptyText,
  });

  final String title;
  final String hint;
  final List<AddressRow> rows;

  /// Shown in place of the rows when the keychain has none.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GerfautSpacing.md,
            GerfautSpacing.sm,
            GerfautSpacing.md,
            GerfautSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: tokens.label.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        if (rows.isEmpty && emptyText != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GerfautSpacing.md,
              vertical: GerfautSpacing.sm,
            ),
            child: Text(
              emptyText!,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          )
        else
          for (final row in rows) ...[
            Divider(height: 1, thickness: 1, color: tokens.border),
            _AddressRowTile(row: row),
          ],
      ],
    );
  }
}

class _AddressRowTile extends StatelessWidget {
  const _AddressRowTile({required this.row});

  final AddressRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: GerfautSpacing.md,
        vertical: GerfautSpacing.sm,
      ),
      child: Row(
        children: [
          // The derivation index anchors the row; a fixed slot keeps
          // the address column aligned.
          SizedBox(
            width: 36,
            child: Text(
              '${row.index}',
              style: tokens.figureOf(color: tokens.textMuted),
            ),
          ),
          Expanded(child: AddressChip(value: row.address, head: 8, tail: 6)),
          const SizedBox(width: GerfautSpacing.sm),
          if (row.used)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: GerfautSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaceSunken,
                borderRadius: BorderRadius.circular(GerfautRadius.full),
                border: Border.all(color: tokens.border),
              ),
              child: Text('Used', style: tokens.label),
            )
          else
            Text(
              'Fresh',
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          const SizedBox(width: GerfautSpacing.sm),
          if (row.balanceSats > 0)
            StackedAmount(sats: row.balanceSats)
          else
            Text('—', style: tokens.figureOf(color: tokens.textMuted)),
        ],
      ),
    );
  }
}
