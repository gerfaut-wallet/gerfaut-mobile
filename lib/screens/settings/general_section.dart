import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/format.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/choice_group.dart';
import '../../widgets/facts.dart';
import '../../widgets/section_card.dart';
import '../../widgets/select_field.dart';

/// The General section: how amounts are shown, and which theme the app
/// wears. Two cards, Display and Appearance.
class GeneralSection extends ConsumerWidget {
  const GeneralSection({super.key});

  /// Sets the display currency and keeps the price source able to quote
  /// it: only CoinGecko serves the currencies past the common seven.
  void _setCurrency(WidgetRef ref, FiatCurrency currency) {
    ref.read(fiatCurrencyProvider.notifier).set(currency);
    if (!ref.read(fiatSourceProvider).supportsCurrency(currency)) {
      ref.read(fiatSourceProvider.notifier).set(PriceSource.coingecko);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final currency = ref.watch(fiatCurrencyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          icon: LucideIcons.coins,
          title: 'Display',
          children: [
            FieldLabel('Unit', tokens: tokens),
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Applies to every amount in the app.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            ChoiceGroup<AmountUnit>(
              label: 'Unit',
              value: ref.watch(unitProvider),
              options: [
                for (final unit in AmountUnit.values)
                  ChoiceOption(value: unit, label: unit.label),
              ],
              onChanged: (unit) => ref.read(unitProvider.notifier).set(unit),
            ),
            const SizedBox(height: GerfautSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fiat value',
                        style: tokens.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          fontVariations: const [FontVariation('wght', 500)],
                        ),
                      ),
                      Text(
                        'Shows the fiat value next to every amount.',
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GerfautSpacing.sm),
                Switch(
                  value: ref.watch(fiatEnabledProvider),
                  activeThumbColor: tokens.onPrimary,
                  activeTrackColor: tokens.primary,
                  inactiveThumbColor: tokens.textMuted,
                  inactiveTrackColor: tokens.surfaceSunken,
                  onChanged: (value) =>
                      ref.read(fiatEnabledProvider.notifier).set(value),
                ),
              ],
            ),
            if (ref.watch(fiatEnabledProvider)) ...[
              const SizedBox(height: GerfautSpacing.md),
              FieldLabel('Currency', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              _CurrencyField(
                selected: currency,
                onChanged: (currency) => _setCurrency(ref, currency),
              ),
              const SizedBox(height: GerfautSpacing.md),
              FieldLabel('Price source', tokens: tokens),
              const SizedBox(height: GerfautSpacing.xs),
              Text(
                'Serves the fiat value and the overview price.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              ChoiceGroup<PriceSource>(
                label: 'Price source',
                value: ref.watch(fiatSourceProvider),
                options: [
                  for (final source in PriceSource.values)
                    ChoiceOption(
                      value: source,
                      label: source.label,
                      // A source that does not quote the currency is
                      // shown as unavailable, never silently broken.
                      enabled: source.supportsCurrency(currency),
                    ),
                ],
                onChanged: (source) =>
                    ref.read(fiatSourceProvider.notifier).set(source),
              ),
              if (currency.reach == CurrencyReach.coingeckoOnly) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'CoinGecko is the only source that quotes '
                  '${currency.code}.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
              if (ref.watch(fiatSourceProvider) == PriceSource.coingecko) ...[
                const SizedBox(height: GerfautSpacing.xs),
                // Required by the CoinGecko API terms wherever their
                // data is shown.
                Text(
                  'Powered by CoinGecko',
                  style: tokens.label.copyWith(
                    fontSize: 11,
                    color: tokens.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: GerfautSpacing.sm),
              _RatePreview(tokens: tokens),
            ],
          ],
        ),
        SectionCard(
          icon: LucideIcons.sunMoon,
          title: 'Appearance',
          children: [
            FieldLabel('Theme', tokens: tokens),
            const SizedBox(height: GerfautSpacing.sm),
            ChoiceGroup<ThemePref>(
              label: 'Theme',
              value: ref.watch(themeProvider),
              options: [
                for (final pref in ThemePref.values)
                  ChoiceOption(
                    value: pref,
                    label: pref.label,
                    icon: _themeIcons[pref],
                  ),
              ],
              onChanged: (pref) => ref.read(themeProvider.notifier).set(pref),
            ),
          ],
        ),
      ],
    );
  }
}

/// Glyph shown before each theme option; the label stays the semantic
/// text.
const Map<ThemePref, IconData> _themeIcons = {
  ThemePref.light: LucideIcons.sun,
  ThemePref.dark: LucideIcons.moon,
  ThemePref.system: LucideIcons.monitor,
};

/// The display currency, thirty of them: the seven every source quotes
/// first, then the ones CoinGecko alone serves, each group announced.
class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.selected, required this.onChanged});

  final FiatCurrency selected;
  final ValueChanged<FiatCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return GerfautSelect<FiatCurrency>(
      label: 'Display currency',
      value: selected,
      groups: [
        for (final reach in CurrencyReach.values)
          GerfautSelectGroup(
            label: reach == CurrencyReach.every
                ? 'Every source'
                : 'CoinGecko only',
            items: [
              for (final currency in FiatCurrency.values.where(
                (c) => c.reach == reach,
              ))
                // The ISO code, then its name so thirty codes stay
                // readable.
                GerfautSelectItem(
                  value: currency,
                  title: currency.code,
                  subtitle: currency.label,
                ),
            ],
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _RatePreview extends ConsumerWidget {
  const _RatePreview({required this.tokens});

  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = ref.watch(priceProvider);
    if (price.hasError) {
      return Text(
        'The price source did not answer. Amounts show without fiat until '
        'it does.',
        style: tokens.bodySmall.copyWith(color: tokens.pending),
      );
    }
    final quote = price.valueOrNull;
    if (quote == null) {
      return Text(
        'Fetching the current price…',
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      );
    }
    return Text(
      '1 BTC = ${formatFiatPrice(quote.rate, quote.currency)} · '
      'updated ${relativeTime(quote.at)}',
      style: tokens.figureOf(color: tokens.textMuted),
    );
  }
}
