import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/electrum.dart';
import '../src/format.dart';
import '../src/models.dart';
import '../src/onboarding.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/choice_group.dart';
import '../widgets/section_card.dart';
import '../widgets/select_field.dart';
import 'settings/backup_section.dart';
import 'settings/notifications_section.dart';
import 'settings/security_section.dart';
import 'welcome.dart';

/// Application version shown in About. Kept in step with pubspec.yaml.
const String appVersion = '0.1.0';

/// Said when the certificate check did not get through: the backend is
/// saved all the same, and the question comes back on first contact.
const String _uncheckedNote =
    'The certificate could not be checked yet. Gerfaut asks about it on '
    'the first connection.';

const List<({Network network, String hint})> _networkHints = [
  (network: Network.mainnet, hint: 'The Bitcoin network'),
  (network: Network.signet, hint: 'Test network, reliable blocks'),
  (network: Network.testnet4, hint: 'Public test network'),
  (network: Network.regtest, hint: 'Local development chain'),
];

/// Settings: workspace, backend, display, appearance, wallets, about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Backend form.
  final _esploraController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '50002');
  bool _tls = true;
  String _backendKind = 'public_esplora';

  /// Chosen public server id; null is the automatic rotation.
  String? _publicServer;
  Network? _seededFor;
  bool _savingBackend = false;

  /// What the last save had to say about the server's certificate, when
  /// it is worth saying at all. Cleared at the start of the next save.
  String? _certificateNote;

  /// Host whose accepted certificate is one tap from being forgotten.
  String? _forgettingHost;

  // Wallet management.
  String? _renamingId;
  final _renameController = TextEditingController();
  String? _confirmRemoveId;
  String? _walletError;

  /// Wallet whose rescan was started here; its row says so meanwhile.
  String? _rescanningId;

  // Gap limit. Seeded from the vault, committed on blur or submit.
  final _gapLimitController = TextEditingController();
  final _gapLimitFocus = FocusNode();
  int? _seededGapLimit;

  // Update check.
  bool _checkingUpdate = false;
  UpdateCheck? _updateResult;
  bool _updateFailed = false;

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
    _esploraController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _renameController.dispose();
    _gapLimitController.dispose();
    _gapLimitFocus.dispose();
    super.dispose();
  }

  void _seedBackendForm(Settings settings) {
    if (_seededFor == settings.activeNetwork) return;
    _seededFor = settings.activeNetwork;
    // Another network, another backend: what the last save said about a
    // certificate no longer applies.
    _certificateNote = null;
    final config = settings.backendFor(settings.activeNetwork);
    _backendKind = switch (config) {
      PublicEsplora() => 'public_esplora',
      CustomEsplora() => 'custom_esplora',
      CustomElectrum() => 'custom_electrum',
    };
    _publicServer = switch (config) {
      PublicEsplora(:final server) => server,
      _ => null,
    };
    _esploraController.text = switch (config) {
      CustomEsplora(:final url) => url,
      _ => '',
    };
    final electrum = switch (config) {
      CustomElectrum(:final url) => parseElectrumUrl(url),
      _ => (host: '', port: '50002', tls: true),
    };
    _hostController.text = electrum.host;
    _portController.text = electrum.port.isEmpty ? '50002' : electrum.port;
    _tls = electrum.tls;
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
    try {
      await ref.read(bridgeProvider).setGapLimit(parsed);
      _seededGapLimit = parsed;
      _gapLimitController.text = '$parsed';
      ref.invalidate(settingsProvider);
      ref.invalidate(walletsProvider);
      ref.invalidate(snapshotProvider);
      if (mounted) _toast('Setting saved');
    } catch (_) {
      _gapLimitController.text = '$current';
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sets the display currency and keeps the price source able to quote
  /// it: only CoinGecko serves the currencies past the common seven.
  void _setCurrency(FiatCurrency currency) {
    ref.read(fiatCurrencyProvider.notifier).set(currency);
    if (!ref.read(fiatSourceProvider).supportsCurrency(currency)) {
      ref.read(fiatSourceProvider.notifier).set(PriceSource.coingecko);
    }
  }

  Future<void> _setNetwork(Network network) async {
    await ref.read(bridgeProvider).setActiveNetwork(network);
    ref.invalidate(settingsProvider);
    ref.invalidate(walletsProvider);
    if (mounted) _toast('Setting saved');
  }

  bool get _backendValid {
    return switch (_backendKind) {
      'custom_esplora' => _esploraController.text.trim().isNotEmpty,
      'custom_electrum' =>
        _hostController.text.trim().isNotEmpty &&
            RegExp(r'^\d+$').hasMatch(_portController.text.trim()),
      _ => true,
    };
  }

  /// Switches the backend form. What the last save said about a
  /// certificate belongs to that backend, so it goes with it.
  void _pickBackendKind(String kind) {
    setState(() {
      _backendKind = kind;
      _certificateNote = null;
    });
  }

  Future<void> _saveBackend(Network network) async {
    setState(() {
      _savingBackend = true;
      _certificateNote = null;
    });
    final config = switch (_backendKind) {
      'custom_esplora' => CustomEsplora(url: _esploraController.text.trim()),
      'custom_electrum' => CustomElectrum(
        url: buildElectrumUrl(_hostController.text, _portController.text, _tls),
      ),
      _ => PublicEsplora(server: _publicServer),
    };
    try {
      final endpoint = _certificateEndpoint(config, network);
      if (endpoint != null && !await _settleCertificate(endpoint)) return;
      await ref.read(bridgeProvider).setBackend(network, config);
      ref.invalidate(settingsProvider);
      if (mounted) _toast('Setting saved');
    } finally {
      if (mounted) setState(() => _savingBackend = false);
    }
  }

  /// The server in the catalogue behind an identifier, or null when the
  /// list is not in yet or no longer carries it.
  PublicServer? _publicServerById(Network network, String? id) {
    if (id == null) return null;
    final servers = ref.read(publicServersProvider(network)).valueOrNull;
    for (final server in servers ?? const <PublicServer>[]) {
      if (server.id == id) return server;
    }
    return null;
  }

  /// The endpoint whose certificate has to be settled before this
  /// backend is written, or null when there is nothing to settle: an
  /// Esplora instance is reached over the web PKI like any web site,
  /// and a public Electrum server a public authority vouches for needs
  /// no decision from the user.
  String? _certificateEndpoint(BackendConfig config, Network network) {
    switch (config) {
      case CustomElectrum(:final url):
        return url;
      case PublicEsplora(:final server):
        final chosen = _publicServerById(network, server);
        return chosen?.protocol == ServerProtocol.electrum ? chosen!.url : null;
      case CustomEsplora():
        return null;
    }
  }

  /// Settles what the server's certificate amounts to before the
  /// backend is written. Returns false only when the user backed out:
  /// nothing is saved, and nothing is trusted.
  Future<bool> _settleCertificate(String url) async {
    final bridge = ref.read(bridgeProvider);
    final CertificateReport report;
    try {
      report = await bridge.inspectCertificate(url);
    } catch (_) {
      // The check itself could not run. A server can be down, and the
      // choice of backend is still the user's.
      _certificateNote = _uncheckedNote;
      return true;
    }
    if (!mounted) return false;
    switch (report.status) {
      case TrustedCertificate():
      case PinnedCertificate():
      case TorCertificate():
        return true;
      case NotTlsCertificate():
        _certificateNote =
            'Plain TCP, no certificate: what Gerfaut asks this server and '
            'what it answers travel in the clear.';
        return true;
      case UnreachableCertificate():
        _certificateNote = _uncheckedNote;
        return true;
      case UnknownCertificate(:final fingerprint) && final status:
        final accepted = await showDialog<bool>(
          context: context,
          builder: (_) =>
              _UnknownCertificateDialog(host: report.host, status: status),
        );
        if (accepted != true) return false;
        await bridge.trustCertificate(url, fingerprint);
        return true;
      case ChangedCertificate(:final presented) && final status:
        final accepted = await showDialog<bool>(
          context: context,
          builder: (_) =>
              _ChangedCertificateDialog(host: report.host, status: status),
        );
        if (accepted != true) return false;
        await bridge.trustCertificate(url, presented);
        return true;
    }
  }

  Future<void> _forgetCertificate(String host) async {
    await ref.read(bridgeProvider).forgetCertificate(host);
    ref.invalidate(settingsProvider);
    if (!mounted) return;
    setState(() => _forgettingHost = null);
    _toast('Certificate forgotten');
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

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingUpdate = true;
      _updateFailed = false;
      _updateResult = null;
    });
    try {
      final result = await ref.read(bridgeProvider).checkUpdate(appVersion);
      if (mounted) setState(() => _updateResult = result);
    } catch (_) {
      if (mounted) setState(() => _updateFailed = true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
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
    _seedGapLimit(settings);
    final network = settings.activeNetwork;
    final currency = ref.watch(fiatCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          children: [
            SectionCard(
              icon: LucideIcons.globe,
              title: 'Network',
              children: [
                for (var row = 0; row < _networkHints.length; row += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _NetworkCard(
                            entry: _networkHints[row],
                            selected: _networkHints[row].network == network,
                            onTap: () =>
                                _setNetwork(_networkHints[row].network),
                          ),
                        ),
                        const SizedBox(width: GerfautSpacing.sm),
                        Expanded(
                          child: _NetworkCard(
                            entry: _networkHints[row + 1],
                            selected: _networkHints[row + 1].network == network,
                            onTap: () =>
                                _setNetwork(_networkHints[row + 1].network),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row + 2 < _networkHints.length)
                    const SizedBox(height: GerfautSpacing.sm),
                ],
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Only wallets on the selected network are shown.',
                  style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
            SectionCard(
              icon: LucideIcons.server,
              title: 'Backend · ${network.label}',
              children: [
                _BackendOption(
                  value: 'public_esplora',
                  groupValue: _backendKind,
                  label: 'Public API',
                  hint:
                      'Public servers, no setup: the one that answers sees '
                      "this wallet's addresses and serves the fee estimates.",
                  onChanged: _pickBackendKind,
                ),
                _BackendOption(
                  value: 'custom_esplora',
                  groupValue: _backendKind,
                  label: 'My own Esplora',
                  hint: 'An Esplora-compatible HTTP endpoint you run yourself.',
                  onChanged: _pickBackendKind,
                ),
                _BackendOption(
                  value: 'custom_electrum',
                  groupValue: _backendKind,
                  label: 'My own Electrum server',
                  hint: 'electrs or Fulcrum, reachable over TLS or plain TCP.',
                  onChanged: _pickBackendKind,
                ),
                if (_backendKind == 'public_esplora') ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  _FieldLabel('Server', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  _PublicServerField(
                    network: network,
                    selected: _publicServer,
                    onChanged: (id) => setState(() => _publicServer = id),
                  ),
                ],
                if (_backendKind == 'custom_esplora') ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  _FieldLabel('Server URL', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  _MonoField(
                    controller: _esploraController,
                    hint: 'https://node.example.org:3002/api',
                    onChanged: () => setState(() {}),
                    tokens: tokens,
                  ),
                ],
                if (_backendKind == 'custom_electrum') ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  _FieldLabel('Host', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  _MonoField(
                    controller: _hostController,
                    hint: 'node.example.org or xxxxxxxx.onion',
                    onChanged: () => setState(() {}),
                    tokens: tokens,
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('Port', tokens: tokens),
                            const SizedBox(height: GerfautSpacing.sm),
                            _MonoField(
                              controller: _portController,
                              hint: '50002',
                              numeric: true,
                              onChanged: () => setState(() {}),
                              tokens: tokens,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.md),
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: GerfautSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Switch(
                              value: _tls,
                              activeThumbColor: tokens.onPrimary,
                              activeTrackColor: tokens.primary,
                              inactiveThumbColor: tokens.textMuted,
                              inactiveTrackColor: tokens.surfaceSunken,
                              onChanged: (value) =>
                                  setState(() => _tls = value),
                            ),
                            const SizedBox(width: GerfautSpacing.xs),
                            Text('TLS', style: tokens.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (_backendKind != 'public_esplora') ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    'Onion addresses go through the Tor proxy at '
                    '127.0.0.1:9050. Install and start Orbot first; a '
                    'built-in Tor client is planned.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
                const SizedBox(height: GerfautSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PrimaryButton(
                    label: 'Save backend',
                    onPressed: _savingBackend || !_backendValid
                        ? null
                        : () => _saveBackend(network),
                  ),
                ),
                if (_certificateNote != null) ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    _certificateNote!,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
            if (settings.electrumCerts.isNotEmpty)
              SectionCard(
                icon: LucideIcons.shieldCheck,
                title: 'Trusted certificates',
                children: [
                  Text(
                    'Servers whose certificate you accepted. Each one must '
                    'keep presenting it; anything else is refused.',
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: GerfautSpacing.md),
                  for (final entry in settings.electrumCerts.entries)
                    _CertificateRow(
                      host: entry.key,
                      fingerprint: entry.value,
                      tokens: tokens,
                      confirming: _forgettingHost == entry.key,
                      onForgetStart: () =>
                          setState(() => _forgettingHost = entry.key),
                      onForgetConfirm: () => _forgetCertificate(entry.key),
                      onCancel: () => setState(() => _forgettingHost = null),
                    ),
                ],
              ),
            SectionCard(
              icon: LucideIcons.coins,
              title: 'Display',
              children: [
                _FieldLabel('Unit', tokens: tokens),
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
                  onChanged: (unit) =>
                      ref.read(unitProvider.notifier).set(unit),
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
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
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
                  _FieldLabel('Currency', tokens: tokens),
                  const SizedBox(height: GerfautSpacing.sm),
                  _CurrencyField(selected: currency, onChanged: _setCurrency),
                  const SizedBox(height: GerfautSpacing.md),
                  _FieldLabel('Price source', tokens: tokens),
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
                  if (ref.watch(fiatSourceProvider) ==
                      PriceSource.coingecko) ...[
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
                _FieldLabel('Theme', tokens: tokens),
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
                  onChanged: (pref) =>
                      ref.read(themeProvider.notifier).set(pref),
                ),
              ],
            ),
            const SecuritySection(),
            const NotificationsSection(),
            const BackupSection(),
            SectionCard(
              icon: LucideIcons.wallet,
              title: 'Wallets',
              children: [
                Row(
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
                              fontVariations: const [
                                FontVariation('wght', 500),
                              ],
                            ),
                          ),
                          Text(
                            'How many unused addresses Gerfaut scans past '
                            'the last used one.',
                            style: tokens.bodySmall.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                          Text(
                            'Rescan a wallet to look again from its first '
                            'address.',
                            style: tokens.bodySmall.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    SizedBox(
                      width: 72,
                      child: _MonoField(
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
                const SizedBox(height: GerfautSpacing.md),
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
                      rescanning: _rescanningId == wallet.id,
                      busy: sync.isSyncing(wallet.id),
                      onRescan: () => _rescan(wallet.id),
                    ),
                if (_walletError != null) ...[
                  const SizedBox(height: GerfautSpacing.sm),
                  Text(
                    _walletError!,
                    style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
            SectionCard(
              icon: LucideIcons.info,
              title: 'About',
              children: [
                Text.rich(
                  TextSpan(
                    text: 'Gerfaut $appVersion',
                    style: tokens.bodySmall,
                    children: [
                      TextSpan(
                        text: '  for Android',
                        style: tokens.bodySmall.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GerfautSpacing.md),
                if (_updateFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
                    child: Text(
                      'Could not reach the release page. Try again later.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ),
                if (_updateResult != null && !_updateResult!.updateAvailable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
                    child: Text(
                      'You are up to date.',
                      style: tokens.bodySmall.copyWith(color: tokens.textMuted),
                    ),
                  ),
                Row(
                  children: [
                    if (_updateResult != null &&
                        _updateResult!.updateAvailable) ...[
                      PrimaryButton(
                        label: 'Get ${_updateResult!.latest}',
                        onPressed: () => launchUrl(
                          Uri.parse(_updateResult!.url),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                    ],
                    SecondaryButton(
                      label: _checkingUpdate
                          ? 'Checking…'
                          : 'Check for updates',
                      icon: LucideIcons.refreshCw,
                      onPressed: _checkingUpdate ? null : _checkForUpdates,
                    ),
                  ],
                ),
                const SizedBox(height: GerfautSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GhostButton(
                    label: 'Show the welcome tour',
                    icon: LucideIcons.compass,
                    onPressed: () {
                      ref.read(onboardingSeenProvider.notifier).replay();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WelcomeScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: GerfautSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.tokens});

  final String text;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: tokens.label.copyWith(color: tokens.textMuted),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ({Network network, String hint}) entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.md),
      onTap: selected ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(GerfautSpacing.sm + GerfautSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? tokens.surfaceSunken : tokens.surface,
          borderRadius: BorderRadius.circular(GerfautRadius.md),
          border: Border.all(color: selected ? tokens.primary : tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.network.label,
                    style: tokens.bodySmall.copyWith(
                      color: selected ? tokens.primary : tokens.text,
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.check, size: 15, color: tokens.primary),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              entry.hint,
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonoField extends StatelessWidget {
  const _MonoField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.tokens,
    this.numeric = false,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final GerfautTokens tokens;
  final bool numeric;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.url,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: hint,
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
    );
  }
}

/// Which public server answers: Automatic first, then every server the
/// core lists for this network. A quiet line stands in for the control
/// when the catalogue is empty (regtest) or out of reach.
class _PublicServerField extends ConsumerWidget {
  const _PublicServerField({
    required this.network,
    required this.selected,
    required this.onChanged,
  });

  final Network network;

  /// Identifier of the chosen server; null is the automatic rotation.
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return ref
        .watch(publicServersProvider(network))
        .when(
          loading: () => Text(
            'Loading the server list…',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
          error: (error, stack) => Text(
            'The server list is unavailable. Gerfaut keeps rotating over '
            'every public instance.',
            style: tokens.bodySmall.copyWith(color: tokens.pending),
          ),
          data: (servers) => _list(context, tokens, servers),
        );
  }

  Widget _list(
    BuildContext context,
    GerfautTokens tokens,
    List<PublicServer> servers,
  ) {
    if (servers.isEmpty) {
      return Text(
        'No public server exists on ${network.label}. Run your own node '
        'and point Gerfaut at it.',
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      );
    }
    // A server retired by a later version falls back to Automatic, which
    // is what the core does with an identifier it no longer knows.
    PublicServer? chosen;
    for (final server in servers) {
      if (server.id == selected) chosen = server;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GerfautSelect<String?>.items(
          label: 'Public server',
          value: chosen?.id,
          items: [
            const GerfautSelectItem<String?>(
              value: null,
              title: 'Automatic',
              subtitle: 'Rotates over every public Esplora.',
            ),
            for (final server in servers)
              // A host is an identifier: mono, never cut at the end.
              GerfautSelectItem<String?>(
                value: server.id,
                title: server.label,
                // A server that signs its own certificate says so here,
                // before it is picked rather than after.
                subtitle: server.selfSigned
                    ? '${server.protocol.label} · signs its own certificate'
                    : server.protocol.label,
                mono: true,
              ),
          ],
          onChanged: onChanged,
        ),
        if (chosen?.protocol == ServerProtocol.electrum) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'An Electrum server cannot serve a single-address wallet.',
            style: tokens.bodySmall.copyWith(color: tokens.pending),
          ),
        ],
        if (chosen?.selfSigned ?? false) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            'This server signs its own certificate. Gerfaut shows you its '
            'fingerprint before it connects.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }
}

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
      '1 BTC = ${formatFiat(satsPerBtc, quote.rate, quote.currency)} · '
      'updated ${relativeTime(quote.at)}',
      style: tokens.figureOf(color: tokens.textMuted),
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
    required this.rescanning,
    required this.busy,
    required this.onRescan,
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

  /// A rescan started from this row is running: the button says so.
  final bool rescanning;

  /// A sync or rescan of this wallet is in flight, wherever it was
  /// started: every action waits for it.
  final bool busy;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final single = wallet.isSingleAddress;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  LucideIcons.wallet,
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
                            child: TextField(
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
                                  borderRadius: BorderRadius.circular(
                                    GerfautRadius.sm,
                                  ),
                                  borderSide: BorderSide.none,
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
                        ],
                      ),
              ),
            ],
          ),
          if (confirmingRemove) ...[
            const SizedBox(height: GerfautSpacing.sm),
            Container(
              padding: const EdgeInsets.all(GerfautSpacing.sm),
              decoration: BoxDecoration(
                color: tokens.alertSurface,
                borderRadius: BorderRadius.circular(GerfautRadius.md),
                border: Border.all(color: tokens.alert.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.triangleAlert,
                        size: 16,
                        color: tokens.alert,
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      Expanded(
                        child: Text(
                          'You are removing "${wallet.name}" from Gerfaut. '
                          'This only stops watching. Nothing moves on chain.',
                          style: tokens.bodySmall.copyWith(color: tokens.alert),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GerfautSpacing.sm),
                  Row(
                    children: [
                      DangerButton(
                        label: 'Remove wallet',
                        onPressed: onRemoveConfirm,
                      ),
                      const SizedBox(width: GerfautSpacing.sm),
                      GhostButton(label: 'Cancel', onPressed: onCancel),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (!renaming) ...[
            const SizedBox(height: GerfautSpacing.xs),
            // Three actions do not fit one line on a narrow phone: the
            // last one flows under the others rather than overflowing.
            Wrap(
              children: [
                GhostButton(
                  label: 'Rename',
                  icon: LucideIcons.pencil,
                  onPressed: busy ? null : onRenameStart,
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

/// A fingerprint on its own quiet surface: mono, in rows of eight byte
/// pairs, so it can be read against what the server prints.
class _FingerprintBlock extends StatelessWidget {
  const _FingerprintBlock({
    required this.label,
    required this.fingerprint,
    this.color,
  });

  final String label;
  final String fingerprint;

  /// Ink of the digits; the default is the body colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, tokens: tokens),
        const SizedBox(height: GerfautSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(GerfautSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surfaceSunken,
            borderRadius: BorderRadius.circular(GerfautRadius.sm),
          ),
          child: Text(
            groupFingerprint(fingerprint),
            style: tokens.data.copyWith(
              fontSize: 13,
              height: 1.5,
              color: color ?? tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// One thing a certificate says about itself: a quiet label, then the
/// value in the body ink.
class _CertificateFact extends StatelessWidget {
  const _CertificateFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: GerfautSpacing.xs),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          children: [TextSpan(text: value, style: tokens.bodySmall)],
        ),
      ),
    );
  }
}

/// No public authority vouches for this certificate: the user is shown
/// what the server presents and decides once, the way SSH asks.
class _UnknownCertificateDialog extends StatelessWidget {
  const _UnknownCertificateDialog({required this.host, required this.status});

  final String host;
  final UnknownCertificate status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final subject = status.subject;
    final expires = status.expires;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text('This server signs its own certificate', style: tokens.h2),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No public authority vouches for the certificate of $host. '
                'Compare the fingerprint below with the one your server '
                'shows, then accept it once: Gerfaut remembers it and '
                'refuses anything else afterwards.',
                style: tokens.bodySmall,
              ),
              const SizedBox(height: GerfautSpacing.md),
              _FingerprintBlock(
                label: 'SHA-256 fingerprint',
                fingerprint: status.fingerprint,
              ),
              if (subject != null)
                _CertificateFact(label: 'Subject', value: subject),
              if (expires != null)
                _CertificateFact(
                  label: 'Valid until',
                  value: formatTimestamp(expires),
                ),
              _CertificateFact(label: 'Why it is asked', value: status.reason),
              const SizedBox(height: GerfautSpacing.md),
              Text(
                'On the machine that runs the server, this prints the same '
                'string:',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: GerfautSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GerfautSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                child: Text(
                  'openssl x509 -noout -fingerprint -sha256 -in <cert>',
                  style: tokens.data.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Accepting records this fingerprint for $host. Any other '
                'certificate from that host is refused afterwards.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          label: 'Accept and save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The accepted certificate is not the one the server presents. Either
/// its operator replaced it, or something sits in between. Refused by
/// default; accepting takes two deliberate steps.
class _ChangedCertificateDialog extends StatefulWidget {
  const _ChangedCertificateDialog({required this.host, required this.status});

  final String host;
  final ChangedCertificate status;

  @override
  State<_ChangedCertificateDialog> createState() =>
      _ChangedCertificateDialogState();
}

class _ChangedCertificateDialogState extends State<_ChangedCertificateDialog> {
  /// Set by the first tap on the trust action; only the second one
  /// accepts anything.
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return AlertDialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GerfautRadius.lg),
      ),
      title: Text("This server's certificate changed", style: tokens.h2),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(GerfautSpacing.sm + 4),
                decoration: BoxDecoration(
                  color: tokens.alertSurface,
                  borderRadius: BorderRadius.circular(GerfautRadius.md),
                  border: Border.all(
                    color: tokens.alert.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        LucideIcons.triangleAlert,
                        size: 16,
                        color: tokens.alert,
                      ),
                    ),
                    const SizedBox(width: GerfautSpacing.sm),
                    Expanded(
                      child: Text(
                        '${widget.host} was accepted with one certificate '
                        'and now presents another. Either whoever runs it '
                        'replaced it, or something sits between you and it.',
                        style: tokens.bodySmall.copyWith(
                          color: tokens.alert,
                          fontWeight: FontWeight.w500,
                          fontVariations: const [FontVariation('wght', 500)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GerfautSpacing.md),
              _FingerprintBlock(
                label: 'Accepted before',
                fingerprint: widget.status.stored,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              _FingerprintBlock(
                label: 'Presented now',
                fingerprint: widget.status.presented,
                color: tokens.alert,
              ),
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                'Nothing is saved and nothing is trusted until you say so. '
                'Ask whoever runs the server before accepting the new one.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
              if (_confirming) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'Trusting it makes Gerfaut accept this certificate for '
                  '${widget.host} from now on. Do it only if you know why '
                  'it changed.',
                  style: tokens.bodySmall.copyWith(
                    color: tokens.alert,
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation('wght', 500)],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _confirming
          ? [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              DangerButton(
                label: 'Trust it anyway',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ]
          : [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.alert),
                onPressed: () => setState(() => _confirming = true),
                child: const Text('Trust the new certificate'),
              ),
              PrimaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
    );
  }
}

/// One accepted certificate: the host it belongs to, its fingerprint,
/// and the way out. Forgetting asks first.
class _CertificateRow extends StatelessWidget {
  const _CertificateRow({
    required this.host,
    required this.fingerprint,
    required this.tokens,
    required this.confirming,
    required this.onForgetStart,
    required this.onForgetConfirm,
    required this.onCancel,
  });

  final String host;
  final String fingerprint;
  final GerfautTokens tokens;
  final bool confirming;
  final VoidCallback onForgetStart;
  final VoidCallback onForgetConfirm;
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
          Text(
            host,
            style: tokens.data.copyWith(
              fontSize: tokens.bodySmall.fontSize,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: GerfautSpacing.xs),
          Text(
            groupFingerprint(fingerprint),
            style: tokens.data.copyWith(
              fontSize: 12,
              height: 1.5,
              color: tokens.textMuted,
            ),
          ),
          if (confirming) ...[
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              'Gerfaut asks again the next time it connects to $host.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Row(
              children: [
                SecondaryButton(
                  label: 'Forget certificate',
                  onPressed: onForgetConfirm,
                ),
                const SizedBox(width: GerfautSpacing.sm),
                GhostButton(label: 'Cancel', onPressed: onCancel),
              ],
            ),
          ] else ...[
            const SizedBox(height: GerfautSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Forget',
                icon: LucideIcons.trash2,
                onPressed: onForgetStart,
              ),
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
    return SizedBox(
      height: 44,
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
    );
  }
}
