import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// Application version shown in About. Kept in step with pubspec.yaml.
const String appVersion = '0.1.0';

const List<({Network network, String hint})> _networkHints = [
  (network: Network.mainnet, hint: 'The Bitcoin network'),
  (network: Network.signet, hint: 'Test network with reliable blocks'),
  (network: Network.testnet4, hint: 'Public test network'),
  (network: Network.regtest, hint: 'Local development chain'),
];

/// Settings: workspace network, backend, theme, wallet management.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  String _backendKind = 'public_esplora';
  Network? _seededFor;
  bool _savingBackend = false;
  String? _renamingId;
  final _renameController = TextEditingController();
  String? _confirmRemoveId;
  String? _walletError;

  @override
  void dispose() {
    _urlController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void _seedBackendForm(Settings settings) {
    if (_seededFor == settings.activeNetwork) return;
    _seededFor = settings.activeNetwork;
    final config = settings.backendFor(settings.activeNetwork);
    _backendKind = switch (config) {
      PublicEsplora() => 'public_esplora',
      CustomEsplora() => 'custom_esplora',
      CustomElectrum() => 'custom_electrum',
    };
    _urlController.text = switch (config) {
      CustomEsplora(:final url) => url,
      CustomElectrum(:final url) => url,
      _ => '',
    };
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setNetwork(Network network) async {
    await ref.read(bridgeProvider).setActiveNetwork(network);
    ref.invalidate(settingsProvider);
    ref.invalidate(walletsProvider);
    if (mounted) _toast('Setting saved');
  }

  Future<void> _saveBackend(Network network) async {
    setState(() => _savingBackend = true);
    final url = _urlController.text.trim();
    final config = switch (_backendKind) {
      'custom_esplora' => CustomEsplora(url: url),
      'custom_electrum' => CustomElectrum(url: url),
      _ => const PublicEsplora(),
    };
    try {
      await ref.read(bridgeProvider).setBackend(network, config);
      ref.invalidate(settingsProvider);
      if (mounted) _toast('Setting saved');
    } finally {
      if (mounted) setState(() => _savingBackend = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? [];

    if (settings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: Text(
            'Loading…',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ),
      );
    }
    _seedBackendForm(settings);
    final network = settings.activeNetwork;
    final hint = _networkHints
        .firstWhere((entry) => entry.network == network)
        .hint;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            _SectionTitle('Workspace', tokens: tokens),
            Text(
              'NETWORK',
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Wrap(
              spacing: GerfautSpacing.sm,
              runSpacing: GerfautSpacing.sm,
              children: [
                for (final entry in _networkHints)
                  _Pill(
                    label: entry.network.label,
                    selected: entry.network == network,
                    onTap: () => _setNetwork(entry.network),
                  ),
              ],
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              '$hint. The workspace only shows wallets on this network.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            _Separator(tokens: tokens),
            _SectionTitle('Backend · ${network.label}', tokens: tokens),
            _BackendOption(
              value: 'public_esplora',
              groupValue: _backendKind,
              label: 'Public API',
              hint:
                  'mempool.space, blockstream.info — no setup. The server '
                  "operator can see this wallet's addresses.",
              onChanged: (value) => setState(() => _backendKind = value),
            ),
            _BackendOption(
              value: 'custom_esplora',
              groupValue: _backendKind,
              label: 'My own Esplora',
              hint: 'An Esplora-compatible HTTP endpoint you run yourself.',
              onChanged: (value) => setState(() => _backendKind = value),
            ),
            _BackendOption(
              value: 'custom_electrum',
              groupValue: _backendKind,
              label: 'My own Electrum server',
              hint: 'electrs or Fulcrum, ssl://host:port or tcp://host:port.',
              onChanged: (value) => setState(() => _backendKind = value),
            ),
            if (_backendKind != 'public_esplora') ...[
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'SERVER URL',
                style: tokens.label.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              TextField(
                controller: _urlController,
                autocorrect: false,
                enableSuggestions: false,
                style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _backendKind == 'custom_esplora'
                      ? 'https://node.example.org:3002/api'
                      : 'ssl://node.example.org:50002',
                  hintStyle: tokens.data.copyWith(
                    fontSize: tokens.body.fontSize,
                    color: tokens.textMuted,
                  ),
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
            ],
            const SizedBox(height: GerfautSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: SecondaryButton(
                label: 'Save backend',
                onPressed:
                    _savingBackend ||
                        (_backendKind != 'public_esplora' &&
                            _urlController.text.trim().isEmpty)
                    ? null
                    : () => _saveBackend(network),
              ),
            ),
            _Separator(tokens: tokens),
            _SectionTitle('Appearance', tokens: tokens),
            Text('THEME', style: tokens.label.copyWith(color: tokens.textMuted)),
            const SizedBox(height: GerfautSpacing.sm),
            Wrap(
              spacing: GerfautSpacing.sm,
              children: [
                for (final pref in ThemePref.values)
                  _Pill(
                    label: pref.label,
                    selected: ref.watch(themeProvider) == pref,
                    onTap: () => ref.read(themeProvider.notifier).set(pref),
                  ),
              ],
            ),
            _Separator(tokens: tokens),
            _SectionTitle('Wallets', tokens: tokens),
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
                ),
            if (_walletError != null) ...[
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                _walletError!,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
            _Separator(tokens: tokens),
            _SectionTitle('About', tokens: tokens),
            Text('Gerfaut $appVersion', style: tokens.bodySmall),
            const SizedBox(height: GerfautSpacing.xs),
            Text(
              'Watch-only by design: this application contains no code to '
              'generate keys, handle seeds, or sign transactions. There is '
              'no send button.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.tokens});

  final String title;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.md),
      child: Text(title, style: tokens.h2),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.tokens});

  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.lg),
      child: Divider(height: 1, thickness: 1, color: tokens.border),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.md),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.md),
        ),
        child: Text(
          label,
          style: tokens.bodySmall.copyWith(
            color: selected ? tokens.onPrimary : tokens.text,
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
      ),
    );
  }
}

class _BackendOption extends StatelessWidget {
  const _BackendOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final selected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.md),
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? tokens.primary : tokens.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                  Text(
                    hint,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
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
          if (renaming)
            TextField(
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
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          else
            Text(
              wallet.name,
              style: tokens.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation('wght', 500)],
              ),
            ),
          const SizedBox(height: GerfautSpacing.sm),
          if (confirmingRemove) ...[
            Text(
              'Stop watching this wallet? Nothing on chain changes.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Row(
              children: [
                SecondaryButton(label: 'Remove', onPressed: onRemoveConfirm),
                const SizedBox(width: GerfautSpacing.sm),
                GhostButton(label: 'Cancel', onPressed: onCancel),
              ],
            ),
          ] else if (renaming)
            Row(
              children: [
                SecondaryButton(label: 'Save', onPressed: onRenameSubmit),
                const SizedBox(width: GerfautSpacing.sm),
                GhostButton(label: 'Cancel', onPressed: onCancel),
              ],
            )
          else
            Row(
              children: [
                GhostButton(label: 'Rename', onPressed: onRenameStart),
                GhostButton(label: 'Remove', onPressed: onRemoveStart),
              ],
            ),
        ],
      ),
    );
  }
}
