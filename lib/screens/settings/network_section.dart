import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/electrum.dart';
import '../../src/models.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/facts.dart';
import '../../widgets/notice.dart';
import '../../widgets/section_card.dart';
import '../../widgets/select_field.dart';
import '../scan.dart';
import 'certificates.dart';
import 'fields.dart';
import 'tor_section.dart';

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

/// The Network section: which chain, which backend serves it, how Tor is
/// reached, and the certificates accepted along the way.
class NetworkSection extends ConsumerStatefulWidget {
  const NetworkSection({super.key, @visibleForTesting this.cameraBuilder});

  /// What the scanner expects when it is opened for a server address.
  static const String backendScanCaption =
      'Point the camera at the QR code your node prints beside its '
      'Electrum or Esplora app.';

  /// Replaces the camera view of the scanner; tests push frames by hand.
  final CameraBuilder? cameraBuilder;

  @override
  ConsumerState<NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends ConsumerState<NetworkSection> {
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

  /// Why the core refused the last scanned code, in its own words. Shown
  /// under the field the scan was meant to fill.
  String? _scanError;

  /// Why the core refused the last save, in its own words: an address
  /// it cannot read, such as a host with a port still in it. Shown under
  /// the button that asked, until the form changes.
  String? _saveError;

  /// The last scanned address names a Tor hidden service. Said under the
  /// fields for as long as they hold what was scanned: a keystroke or
  /// another backend option and the fact no longer describes them.
  bool _scannedOnion = false;

  /// Host whose accepted certificate is one tap from being forgotten.
  String? _forgettingHost;

  @override
  void dispose() {
    _esploraController.dispose();
    _hostController.dispose();
    _portController.dispose();
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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
  /// certificate belongs to that backend, so it goes with it, and so
  /// does a refused scan.
  void _pickBackendKind(String kind) {
    setState(() {
      _backendKind = kind;
      _certificateNote = null;
      _scanError = null;
      _saveError = null;
      _scannedOnion = false;
    });
  }

  /// A backend field was typed in: the Save button follows what it now
  /// holds, and neither a refused scan nor an onion fact describes it
  /// any more.
  void _onBackendFieldChanged() {
    setState(() {
      _scanError = null;
      _saveError = null;
      _scannedOnion = false;
    });
  }

  /// Reads a server address off a QR code: the one a node prints beside
  /// its Electrum app, or an Esplora endpoint. The core says which of
  /// the two it is and the form follows — a scanned `https://` while
  /// Electrum is selected picks Esplora rather than being refused,
  /// which is plainly what was meant. Nothing is saved: the fields are
  /// filled and the person still presses Save.
  Future<void> _scanBackend() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ScanScreen(
          caption: NetworkSection.backendScanCaption,
          // A test seam of ScanScreen; this screen only forwards its
          // own, which is null outside a test.
          // ignore: invalid_use_of_visible_for_testing_member
          cameraBuilder: widget.cameraBuilder,
        ),
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final ScannedBackend backend;
    try {
      backend = await ref.read(bridgeProvider).parseBackend(text.trim());
    } catch (error) {
      // Pointing the wrong QR at it is the likely slip, so the refusal
      // names what was read instead: a BridgeException prints the words
      // the core refused it in.
      if (mounted) setState(() => _scanError = '$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _scanError = null;
      _certificateNote = null;
      _scannedOnion = backend.onion;
      if (backend.kind == 'esplora') {
        _backendKind = 'custom_esplora';
        _esploraController.text = backend.url;
      } else {
        _backendKind = 'custom_electrum';
        // An IPv6 literal goes back into its brackets: host and port are
        // joined again on save, and without them the two cannot be told
        // apart.
        final host = backend.host;
        _hostController.text = host.contains(':') ? '[$host]' : host;
        _portController.text = '${backend.port ?? ''}';
        _tls = backend.tls;
      }
    });
  }

  Future<void> _saveBackend(Network network) async {
    setState(() {
      _savingBackend = true;
      _certificateNote = null;
      _saveError = null;
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
    } on BridgeException catch (error) {
      // Nothing was saved. A note about a certificate the check could
      // not look at says nothing next to an address that was refused.
      if (mounted) {
        setState(() {
          _certificateNote = null;
          _saveError = error.message;
        });
      }
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
              UnknownCertificateDialog(host: report.host, status: status),
        );
        if (accepted != true) return false;
        await bridge.trustCertificate(url, fingerprint);
        return true;
      case ChangedCertificate(:final presented) && final status:
        final accepted = await showDialog<bool>(
          context: context,
          builder: (_) =>
              ChangedCertificateDialog(host: report.host, status: status),
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return Text(
        'Loading…',
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      );
    }
    _seedBackendForm(settings);
    final network = settings.activeNetwork;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        onTap: () => _setNetwork(_networkHints[row].network),
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
                  "this wallet's addresses.",
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
              FieldLabel('Server', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              _PublicServerField(
                network: network,
                selected: _publicServer,
                onChanged: (id) => setState(() => _publicServer = id),
              ),
            ],
            if (_backendKind == 'custom_esplora') ...[
              const SizedBox(height: GerfautSpacing.sm),
              FieldLabel('Server URL', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: MonoField(
                      controller: _esploraController,
                      hint: 'https://node.example.org:3002/api',
                      onChanged: _onBackendFieldChanged,
                      tokens: tokens,
                    ),
                  ),
                  const SizedBox(width: GerfautSpacing.sm),
                  _ScanButton(onPressed: _scanBackend),
                ],
              ),
              if (_scanError != null) ...[
                const SizedBox(height: GerfautSpacing.sm),
                _ScanRefusal(reason: _scanError!, tokens: tokens),
              ],
              if (_scannedOnion) ...[
                const SizedBox(height: GerfautSpacing.sm),
                _OnionNote(mode: settings.tor.mode, tokens: tokens),
              ],
            ],
            if (_backendKind == 'custom_electrum') ...[
              const SizedBox(height: GerfautSpacing.sm),
              FieldLabel('Host', tokens: tokens),
              const SizedBox(height: GerfautSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: MonoField(
                      controller: _hostController,
                      hint: 'node.example.org or xxxxxxxx.onion',
                      onChanged: _onBackendFieldChanged,
                      tokens: tokens,
                    ),
                  ),
                  const SizedBox(width: GerfautSpacing.sm),
                  _ScanButton(onPressed: _scanBackend),
                ],
              ),
              if (_scanError != null) ...[
                const SizedBox(height: GerfautSpacing.sm),
                _ScanRefusal(reason: _scanError!, tokens: tokens),
              ],
              const SizedBox(height: GerfautSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FieldLabel('Port', tokens: tokens),
                        const SizedBox(height: GerfautSpacing.sm),
                        MonoField(
                          controller: _portController,
                          hint: '50002',
                          numeric: true,
                          onChanged: _onBackendFieldChanged,
                          tokens: tokens,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: GerfautSpacing.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: GerfautSpacing.sm),
                    child: Row(
                      children: [
                        Switch(
                          value: _tls,
                          activeThumbColor: tokens.onPrimary,
                          activeTrackColor: tokens.primary,
                          inactiveThumbColor: tokens.textMuted,
                          inactiveTrackColor: tokens.surfaceSunken,
                          onChanged: (value) => setState(() => _tls = value),
                        ),
                        const SizedBox(width: GerfautSpacing.xs),
                        Text('TLS', style: tokens.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              if (_scannedOnion) ...[
                const SizedBox(height: GerfautSpacing.sm),
                _OnionNote(mode: settings.tor.mode, tokens: tokens),
              ],
            ],
            if (_backendKind != 'public_esplora') ...[
              const SizedBox(height: GerfautSpacing.sm),
              // The card below is the one that knows which Tor is used
              // and can test it; this line only says a .onion will take
              // that route. Naming a port and asking for Orbot outlived
              // the built-in client.
              Text(
                'An address ending in .onion goes through Tor; the Tor '
                'card below says which one and lets you test it.',
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
            if (_saveError != null) ...[
              const SizedBox(height: GerfautSpacing.sm),
              _ScanRefusal(reason: _saveError!, tokens: tokens),
            ],
            if (_certificateNote != null) ...[
              const SizedBox(height: GerfautSpacing.sm),
              Text(
                _certificateNote!,
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        ),
        const TorSection(),
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
                CertificateRow(
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
      ],
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

/// Why the core refused the last code read, in its own words, under the
/// field the scan was meant to fill.
///
/// A hint, not a panel: nothing was lost, and the text belongs to the
/// field it explains. It is announced all the same — it lands in
/// reaction to a scan the person just made, and the camera has closed
/// by the time it appears, so nothing else on screen says the code was
/// turned down.
class _ScanRefusal extends StatelessWidget {
  const _ScanRefusal({required this.reason, required this.tokens});

  final String reason;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        reason,
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      ),
    );
  }
}

/// What the core read off the scanned address: a Tor hidden service,
/// so this backend is reached through Tor and nothing else. Names the
/// Tor mode in force, which the card below is the place to change.
class _OnionNote extends StatelessWidget {
  const _OnionNote({required this.mode, required this.tokens});

  final TorMode mode;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Sits on the first line of the text, whatever its size.
          padding: const EdgeInsets.only(top: 3),
          child: Icon(LucideIcons.eyeOff, size: 15, color: tokens.textMuted),
        ),
        const SizedBox(width: GerfautSpacing.sm),
        Expanded(
          child: Text(
            'A Tor hidden service: reached through Tor only '
            '(mode: ${mode.label}).',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Opens the camera on the QR code a node prints beside its Electrum or
/// Esplora app. Nobody retypes a 56-character onion address.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // "Scan" alone says nothing once the field is out of sight.
      label: 'Scan a server address QR code',
      onTap: onPressed,
      excludeSemantics: true,
      child: SecondaryButton(
        label: 'Scan',
        icon: LucideIcons.scanLine,
        onPressed: onPressed,
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
            // The dot rides the first line of a label that wraps, by
            // measurement — the 2px nudge it replaces was right at one
            // font size and wrong at every other.
            FirstLine(
              style: tokens.bodySmall,
              child: Container(
                width: 20,
                height: 20,
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
