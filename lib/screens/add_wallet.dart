import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'scan.dart';
import 'wallet_home.dart';

/// Two steps: paste or import, then confirm what was recognized.
/// Detection is never silent — the user validates before anything is
/// stored.
class AddWalletScreen extends ConsumerStatefulWidget {
  const AddWalletScreen({super.key});

  @override
  ConsumerState<AddWalletScreen> createState() => _AddWalletScreenState();
}

class _AddWalletScreenState extends ConsumerState<AddWalletScreen> {
  final _rawController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  ParsedInput? _parsed;
  Network? _network;
  bool _adding = false;

  @override
  void dispose() {
    _rawController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _parse(String input) async {
    setState(() => _error = null);
    try {
      final parsed = await ref.read(bridgeProvider).parseInput(input);
      final active =
          ref.read(settingsProvider).valueOrNull?.activeNetwork;
      setState(() {
        _parsed = parsed;
        _network = active != null && parsed.networks.contains(active)
            ? active
            : parsed.networks.first;
      });
    } on BridgeException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _importFile() async {
    const typeGroup = XTypeGroup(
      label: 'Wallet material',
      extensions: ['txt', 'json', 'desc'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final text = (await file.readAsString()).trim();
    _rawController.text = text;
    await _parse(text);
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScanScreen()),
    );
    if (text == null || text.trim().isEmpty) return;
    _rawController.text = text.trim();
    await _parse(text.trim());
  }

  Future<void> _submit() async {
    final parsed = _parsed;
    final network = _network;
    final name = _nameController.text.trim();
    if (parsed == null || network == null || name.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final bridge = ref.read(bridgeProvider);
      final meta = await bridge.addWallet(name, parsed, network);
      // The workspace follows the wallet that was just added, otherwise
      // it would land invisible on another network.
      final active = ref.read(settingsProvider).valueOrNull?.activeNetwork;
      if (network != active) {
        await bridge.setActiveNetwork(network);
        ref.invalidate(settingsProvider);
      }
      ref.invalidate(walletsProvider);
      // First sync in the background; its outcome lands on the wallet
      // screen's freshness indicator.
      // ignore: unawaited_futures
      ref
          .read(syncProvider.notifier)
          .syncWallet(meta.id)
          .catchError((_) => null);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => WalletHomeScreen(walletId: meta.id),
        ),
      );
    } on BridgeException catch (error) {
      setState(() {
        _error = error.message;
        _adding = false;
      });
    } catch (error) {
      setState(() {
        _error = '$error';
        _adding = false;
      });
    }
  }

  void _back() {
    setState(() {
      _parsed = null;
      _network = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a wallet')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          child: _parsed == null
              ? _buildInputStep(tokens)
              : _buildConfirmStep(tokens, _parsed!),
        ),
      ),
    );
  }

  Widget _buildInputStep(GerfautTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'DESCRIPTOR, EXTENDED PUBLIC KEY, OR ADDRESS',
          style: tokens.label.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        TextField(
          controller: _rawController,
          maxLines: 5,
          autocorrect: false,
          enableSuggestions: false,
          style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'wpkh([fingerprint/84h/0h/0h]xpub.../0/*)',
            hintStyle: tokens.data.copyWith(
              fontSize: tokens.body.fontSize,
              color: tokens.textMuted,
            ),
            filled: true,
            fillColor: tokens.surfaceSunken,
            contentPadding: const EdgeInsets.all(GerfautSpacing.md),
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
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Gerfaut is watch-only: anything containing a private key or a '
          'seed phrase is refused and never stored.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Row(
          children: [
            GhostButton(
              label: 'Import a file',
              icon: LucideIcons.fileUp,
              onPressed: _importFile,
            ),
            const SizedBox(width: GerfautSpacing.sm),
            GhostButton(
              label: 'Scan',
              icon: LucideIcons.scanLine,
              onPressed: _scan,
            ),
          ],
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Continue',
          expand: true,
          onPressed: _rawController.text.trim().isEmpty
              ? null
              : () => _parse(_rawController.text),
        ),
      ],
    );
  }

  Widget _buildConfirmStep(GerfautTokens tokens, ParsedInput parsed) {
    final payload = parsed.payload;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(GerfautSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(GerfautRadius.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Recognized as ',
                  style: tokens.bodySmall,
                  children: [
                    TextSpan(
                      text: parsed.kind.label,
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    if (payload is DescriptorsPayload)
                      TextSpan(text: ' · ${payload.script.label}'),
                  ],
                ),
              ),
              if (payload is AddressPayload) ...[
                const SizedBox(height: GerfautSpacing.xs),
                Text(
                  payload.address,
                  style: tokens.data.copyWith(color: tokens.textMuted),
                ),
              ],
              if (parsed.warnings.isNotEmpty) ...[
                const SizedBox(height: GerfautSpacing.sm),
                for (final warning in parsed.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: GerfautSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.info,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: GerfautSpacing.sm),
                        Expanded(
                          child: Text(
                            warning.label,
                            style: tokens.bodySmall.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Text('NAME', style: tokens.label.copyWith(color: tokens.textMuted)),
        const SizedBox(height: GerfautSpacing.sm),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: tokens.body,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Cold storage',
            hintStyle: tokens.body.copyWith(color: tokens.textMuted),
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
        const SizedBox(height: GerfautSpacing.md),
        Text('NETWORK', style: tokens.label.copyWith(color: tokens.textMuted)),
        const SizedBox(height: GerfautSpacing.sm),
        Wrap(
          spacing: GerfautSpacing.sm,
          children: [
            for (final candidate in parsed.networks)
              _NetworkPill(
                network: candidate,
                selected: candidate == _network,
                enabled: parsed.networks.length > 1,
                onTap: () => setState(() => _network = candidate),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.md),
          Text(
            _error!,
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: GerfautSpacing.lg),
        Row(
          children: [
            GhostButton(label: 'Back', onPressed: _back),
            const SizedBox(width: GerfautSpacing.sm),
            Expanded(
              child: PrimaryButton(
                label: _adding ? 'Adding…' : 'Add wallet',
                expand: true,
                onPressed:
                    _nameController.text.trim().isEmpty || _adding
                    ? null
                    : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NetworkPill extends StatelessWidget {
  const _NetworkPill({
    required this.network,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Network network;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(GerfautRadius.md),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: GerfautSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(GerfautRadius.md),
        ),
        child: Text(
          network.label,
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
