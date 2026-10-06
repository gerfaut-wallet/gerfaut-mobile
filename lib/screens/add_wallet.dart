import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../src/bridge.dart';
import '../src/documents.dart';
import '../src/lock.dart';
import '../src/models.dart';
import '../src/state.dart';
import '../theme/tokens.dart';
import '../widgets/app_bar.dart';
import '../widgets/buttons.dart';
import '../widgets/choice_group.dart';
import '../widgets/notice.dart';
import '../widgets/pinned_action_form.dart';
import '../widgets/select_field.dart';
import 'scan.dart';
import 'wallet_home.dart';

/// Two steps: paste or import, then confirm what was recognized.
/// Detection is never silent — the user validates before anything is
/// stored.
class AddWalletScreen extends ConsumerStatefulWidget {
  const AddWalletScreen({
    super.key,
    @visibleForTesting this.filePicker,
    @visibleForTesting this.cameraBuilder,
  });

  /// Stands in for the system's file picker, so a test can answer it
  /// without a platform under the test binding.
  final Future<XFile?> Function()? filePicker;

  /// Replaces the camera view of the scanner; tests push frames by hand.
  final CameraBuilder? cameraBuilder;

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

  /// What the core assumed reading the last code scanned, which the text
  /// it gave no longer shows; and of that, what goes with [_parsed]: the
  /// warnings of a parse of that very text.
  ({String text, List<InputWarning> warnings})? _scanned;
  List<InputWarning> _assumed = const [];

  /// The advanced disclosure, and what it holds. The fields survive a
  /// re-parse: a user who tried one branch tries the next from there.
  bool _advanced = false;
  final _receiveController = TextEditingController();
  final _changeController = TextEditingController();
  final _originController = TextEditingController();

  /// What the fields amount to, or null when they are at their default.
  DerivationChoice? _derivation() {
    final receive = _receiveController.text.trim();
    final change = _changeController.text.trim();
    final origin = _originController.text.trim();
    if (receive.isEmpty) return null;
    return DerivationChoice(
      receive: receive,
      change: change.isEmpty ? null : change,
      origin: origin.isEmpty ? null : origin,
    );
  }

  /// Seeds the fields from what the core says is in effect, so opening
  /// the disclosure shows the paths actually used.
  void _seedDerivation(ParsedInput parsed) {
    final choice = parsed.derivation;
    if (choice == null) return;
    _receiveController.text = choice.receive;
    _changeController.text = choice.change ?? '';
    _originController.text = choice.origin ?? '';
  }

  @override
  void dispose() {
    _rawController.dispose();
    _nameController.dispose();
    _receiveController.dispose();
    _changeController.dispose();
    _originController.dispose();
    super.dispose();
  }

  /// What the last parse that went through was asked, so a network
  /// picked afterwards rebuilds that same wallet on it.
  ImportOptions _asked = const ImportOptions();

  /// The parse asked last. Only its answer is taken: picks made in a row
  /// are answered in any order, and an older answer landing after a
  /// newer one would put back what the user had moved away from.
  int _parsing = 0;

  /// The network of the parse asked last, while its answer is awaited;
  /// null when that parse was not a pick of one.
  Network? _picked;

  /// Asks the core for [input]. On [network] when given, otherwise on
  /// the one shown. The network shown changes only with the answer for
  /// it, so the first address and the network the wallet is added on
  /// always go together.
  Future<void> _parse(
    String input, {
    ScriptKind? script,
    DerivationChoice? derivation,
    Network? network,
  }) async {
    final asked = ++_parsing;
    _picked = network;
    setState(() => _error = null);
    // A re-parse keeps the network the user already picked; a new input
    // starts on the one on screen. The core derives the first address
    // for it, so the address shown is the one the wallet will give.
    var preferred = network ?? _network;
    if (preferred == null) {
      try {
        preferred = (await ref.read(settingsProvider.future)).activeNetwork;
      } on Object {
        // No settings to read: the first candidate stands.
      }
      if (!mounted) return;
    }
    final options = ImportOptions(
      script: script,
      derivation: derivation,
      network: preferred,
    );
    try {
      final parsed = await ref
          .read(bridgeProvider)
          .parseInputWithOptions(input, options);
      if (!mounted || asked != _parsing) return;
      _picked = null;
      final scanned = _scanned;
      setState(() {
        _parsed = parsed;
        _assumed = scanned != null && scanned.text == input.trim()
            ? scanned.warnings
            : const [];
        _asked = options;
        _network = preferred != null && parsed.networks.contains(preferred)
            ? preferred
            : parsed.networks.first;
      });
      _seedDerivation(parsed);
    } on BridgeException catch (error) {
      // Refused, what was shown stays: the network with its address.
      if (!mounted || asked != _parsing) return;
      _picked = null;
      setState(() => _error = materialRefusal(error));
    } catch (error) {
      if (!mounted || asked != _parsing) return;
      _picked = null;
      setState(() => _error = '$error');
    }
  }

  /// The script type is rebuilt by the core, never patched locally: the
  /// descriptors and the preview address must come from one place. The
  /// derivation goes along, or picking a script would undo it.
  void _chooseScript(ScriptKind chosen) {
    // ignore: unawaited_futures
    _parse(
      _rawController.text.trim(),
      script: chosen,
      derivation: _advanced ? _derivation() : null,
    );
  }

  /// The first address belongs to a network: picking another one asks
  /// the core for it again, on the wallet as it stands. A regtest
  /// wallet shown a signet address would be compared with the wrong one.
  void _chooseNetwork(Network? network) {
    if (network == null || network == (_picked ?? _network)) return;
    if (network == _network) {
      // Back on the network shown before the last pick was answered:
      // that answer, landing later, would move away from it.
      _picked = null;
      _parsing++;
      return;
    }
    // ignore: unawaited_futures
    _parse(
      _rawController.text.trim(),
      script: _asked.script,
      derivation: _asked.derivation,
      network: network,
    );
  }

  /// Rebuilds the wallet on the typed paths. What comes back is the
  /// core's answer: the card, the first address and the warnings.
  void _applyDerivation(ScriptKind script) {
    // ignore: unawaited_futures
    _parse(
      _rawController.text.trim(),
      script: script,
      derivation: _derivation(),
    );
  }

  Future<void> _importFile() async {
    final lock = ref.read(lockProvider.notifier);
    // The picker is a screen of the system's: Android pauses Gerfaut
    // behind it, and coming back from a picker the user opened here is
    // not coming back from the background. Without this the lock lands
    // on the way in and takes the picked file with it.
    final XFile? file;
    try {
      final picker = widget.filePicker;
      file = await lock.excursion(
        () => picker != null
            ? picker()
            : openBoundedFile(maxBytes: _maxMaterialBytes),
        // Picked, then not read: the trip did happen.
        cameUp: (error) => error is FileReadException,
      );
    } on FileReadException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    } catch (_) {
      // No picker came up.
      if (mounted) {
        setState(
          () => _error = 'No app on this phone can open a file to read.',
        );
      }
      return;
    }
    if (file == null) return;
    // The core reads no more than this much wallet material. The
    // picker has read no further than that: a larger file comes with
    // its size and nothing else.
    if (await file.length() > _maxMaterialBytes) {
      if (mounted) {
        setState(() => _error = 'This file is too large to be a wallet.');
      }
      return;
    }
    final String text;
    try {
      // Decoded here: an XFile made of bytes reads them as Latin-1,
      // which garbles every accent in a label and never fails.
      text = utf8.decode(await file.readAsBytes()).trim();
    } on Exception {
      // Not UTF-8, or not readable at all.
      if (mounted) {
        setState(() => _error = 'This file is not text Gerfaut can read.');
      }
      return;
    }
    if (!mounted) return;
    _rawController.text = text;
    await _parse(text);
  }

  /// The most wallet material the core reads, in bytes.
  ///
  /// The picker offers every file. A wallet comes as `.txt`, `.json`,
  /// `.bsms`, `.desc` or no extension at all, and a phone's file
  /// providers have no type for the last three: they call them
  /// `application/octet-stream`, or nothing, so a filter on text and
  /// JSON greyed out the very files a coordinator or a signer writes.
  /// What was picked is held to this size and to UTF-8 instead, and the
  /// core says what the text is.
  static const int _maxMaterialBytes = 64 * 1024;

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<QrProgress>(
      MaterialPageRoute<QrProgress>(
        builder: (_) => ScanScreen(
          // A test seam of ScanScreen; this screen only forwards its
          // own, which is null outside a test.
          // ignore: invalid_use_of_visible_for_testing_member
          cameraBuilder: widget.cameraBuilder,
        ),
      ),
    );
    final text = scanned?.text?.trim();
    if (scanned == null || text == null || text.isEmpty || !mounted) return;
    _scanned = (text: text, warnings: scanned.warnings);
    _rawController.text = text;
    await _parse(text);
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
      // Held before the await: `ref` belongs to this widget, the
      // container it points at outlives it.
      final container = ProviderScope.containerOf(context, listen: false);
      final meta = await bridge.addWallet(name, parsed, network);
      // The workspace follows the wallet that was just added, otherwise
      // it would land invisible on another network.
      final active = container
          .read(settingsProvider)
          .valueOrNull
          ?.activeNetwork;
      if (network != active) {
        // The wallet is in the vault whatever happens here: a switch
        // that fails must not read as a failed add, or adding again
        // would only be refused as a duplicate. The wallet page opens
        // anyway; the network is set from the settings.
        try {
          await bridge.setActiveNetwork(network);
        } catch (_) {
          // The page about to open is the wallet's own.
        }
        container.invalidate(settingsProvider);
      }
      container.invalidate(walletsProvider);
      // First sync in the background; its outcome lands on the wallet
      // screen's freshness indicator.
      // ignore: unawaited_futures
      container
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
        _error = materialRefusal(error);
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
    // An answer still on its way would bring the step just left back.
    _parsing++;
    _picked = null;
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
      appBar: GerfautAppBar.text('Add a wallet'),
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
    // The action stays at the bottom while there is room, and the form
    // scrolls under the keyboard instead of hiding it.
    return PinnedActionForm(
      action: PrimaryButton(
        label: 'Continue',
        expand: true,
        onPressed: _rawController.text.trim().isEmpty
            ? null
            : () => _parse(_rawController.text),
      ),
      children: [
        // Read once, on the field: its hint is an example descriptor, a
        // string of brackets nobody needs spelled out as its name.
        ExcludeSemantics(
          child: Text(
            'DESCRIPTOR, EXTENDED PUBLIC KEY, OR ADDRESS',
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Semantics(
          label: 'Descriptor, extended public key, or address',
          child: TextField(
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
        ),
        if (_error != null) ...[
          const SizedBox(height: GerfautSpacing.sm),
          // Said aloud as it appears: the field above is what was typed.
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
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
              if (parsed.previewAddress != null) ...[
                const SizedBox(height: GerfautSpacing.sm),
                Text(
                  'First address',
                  style: tokens.label.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: 2),
                SelectableText(parsed.previewAddress!, style: tokens.data),
              ],
            ],
          ),
        ),
        // What was recognized stays in the card; what was not gets its
        // own panel. Amber, never red: none of these costs the user
        // funds or privacy, they state a convention that was applied.
        for (final warning in [
          ...parsed.warnings,
          ..._assumed.where((assumed) => !parsed.warnings.contains(assumed)),
        ]) ...[
          const SizedBox(height: GerfautSpacing.gutter),
          GerfautNotice(tone: NoticeTone.info, message: warning.label),
        ],
        if (parsed.scriptOptions.isNotEmpty &&
            payload is DescriptorsPayload) ...[
          const SizedBox(height: GerfautSpacing.md),
          Text(
            'SCRIPT TYPE',
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: GerfautSpacing.sm),
          // The value is what the core holds, never a local choice it
          // rejected.
          GerfautSelect<ScriptKind>.items(
            label: 'Script type',
            value: payload.script,
            items: [
              for (final option in parsed.scriptOptions)
                GerfautSelectItem(
                  value: option,
                  title: option.label,
                  // The start of the addresses on the network the wallet
                  // goes to, never mainnet's on a test network.
                  subtitle: switch (option.addressStart(
                    _network ?? Network.mainnet,
                  )) {
                    final start? => 'Addresses starting with $start',
                    null => null,
                  },
                ),
            ],
            onChanged: (chosen) {
              if (chosen != payload.script) _chooseScript(chosen);
            },
          ),
          const SizedBox(height: GerfautSpacing.xs + 2),
          Text(
            'Compare the first address above with your wallet.',
            style: tokens.bodySmall.copyWith(color: tokens.textMuted),
          ),
        ],
        // Only a lone extended key leaves the branches open; everything
        // else carries its own and the core ignores a choice here.
        if (parsed.derivationEditable && payload is DescriptorsPayload) ...[
          const SizedBox(height: GerfautSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: 'Advanced',
              icon: _advanced ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              expanded: _advanced,
              onPressed: () => setState(() => _advanced = !_advanced),
            ),
          ),
          if (_advanced) ...[
            const SizedBox(height: GerfautSpacing.sm),
            _PathField(
              key: const Key('derivation.receive'),
              label: 'Receive path',
              controller: _receiveController,
              hint: '0/*',
              tokens: tokens,
            ),
            const SizedBox(height: GerfautSpacing.sm),
            _PathField(
              key: const Key('derivation.change'),
              label: 'Change path',
              controller: _changeController,
              hint: 'Leave empty to not track change',
              tokens: tokens,
            ),
            const SizedBox(height: GerfautSpacing.sm),
            _PathField(
              key: const Key('derivation.origin'),
              label: 'Key origin',
              controller: _originController,
              hint: "[deadbeef/84'/0'/0']",
              tokens: tokens,
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Text(
              'For a key used outside the usual branches. The first '
              'address above updates so you can check.',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: GerfautSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: SecondaryButton(
                label: 'Apply',
                onPressed: () => _applyDerivation(payload.script),
              ),
            ),
          ],
        ],
        const SizedBox(height: GerfautSpacing.md),
        ExcludeSemantics(
          child: Text(
            'NAME',
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Semantics(
          label: 'Wallet name',
          child: TextField(
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
        ),
        const SizedBox(height: GerfautSpacing.md),
        Text('NETWORK', style: tokens.label.copyWith(color: tokens.textMuted)),
        const SizedBox(height: GerfautSpacing.sm),
        // An input that fits one network, a mainnet address say, leaves
        // nothing to choose: a group of one option would read as a
        // control that does nothing. The network is said plainly, as
        // the backup scope is, and as on the desktop.
        if (parsed.networks.length == 1)
          Text(
            (_network ?? parsed.networks.single).label,
            style: tokens.body.copyWith(color: tokens.text),
          )
        else
          // Nullable: nothing is picked until the descriptor is parsed.
          ChoiceGroup<Network?>(
            label: 'Network',
            value: _network,
            options: [
              for (final candidate in parsed.networks)
                ChoiceOption(value: candidate, label: candidate.label),
            ],
            onChanged: _chooseNetwork,
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
                onPressed: _nameController.text.trim().isEmpty || _adding
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

/// One derivation field: an identifier, so it reads in the mono face,
/// at the size every mobile input uses.
class _PathField extends StatelessWidget {
  const _PathField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.tokens,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final GerfautTokens tokens;

  @override
  Widget build(BuildContext context) {
    // One node: the field is read with its caption, not as the example
    // path its hint shows.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: tokens.label.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: GerfautSpacing.xs),
          TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
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
                vertical: GerfautSpacing.sm + GerfautSpacing.xs,
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
      ),
    );
  }
}
