import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../src/bridge.dart';
import '../../src/clipboard.dart';
import '../../src/format.dart';
import '../../src/models.dart';
import '../../src/premium.dart';
import '../../src/state.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notice.dart';
import '../../widgets/overflow_menu.dart';
import '../../widgets/premium_pill.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/wallet_icon.dart';
import '../premium_channels.dart';
import '../premium_consent.dart';
import '../wallet_home.dart';

/// How often the server is asked again while a wallet's first scan
/// runs, and for how long before the asking stops.
const Duration scanPollEvery = Duration(seconds: 5);
const Duration scanPollFor = Duration(minutes: 2);

/// The Premium section: four cards, in this order. The licence, the
/// wallets the server watches, where alerts go, and what it said lately.
///
/// Nothing is sold here: no price, no countdown, one link to the site.
/// Without a key the section is silent, and asks the server nothing.
/// With one, every call that fails says so in an amber note under the
/// card it concerns, never in a toast or a dialog.
class PremiumSection extends ConsumerStatefulWidget {
  const PremiumSection({super.key});

  @override
  ConsumerState<PremiumSection> createState() => _PremiumSectionState();
}

class _PremiumSectionState extends ConsumerState<PremiumSection> {
  // The licence.
  final _keyController = TextEditingController();
  bool _activating = false;
  BridgeException? _licenceError;
  bool _confirmForget = false;
  bool _deleteAccount = false;
  bool _refreshedLicence = false;

  // The watched wallets.
  String? _busyWalletId;
  BridgeException? _walletsError;
  Timer? _scanTimer;
  DateTime? _scanStartedAt;

  // The channels.
  String? _busyChannelId;
  BridgeException? _channelsError;

  @override
  void initState() {
    super.initState();
    _keyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _keyController.dispose();
    _scanTimer?.cancel();
    super.dispose();
  }

  GerfautBridge get _bridge => ref.read(bridgeProvider);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- the licence -------------------------------------------------------

  /// The certificate is fetched again once per visit, for the time a
  /// renewal on the site may have added. Quietly: a server out of reach
  /// changes nothing the stored certificate already says.
  void _refreshLicenceOnce(PremiumView view) {
    if (_refreshedLicence || !view.hasKey) return;
    _refreshedLicence = true;
    Future.microtask(() async {
      try {
        final before = view.claims?.expiresAt;
        final licence = await _bridge.premiumRefreshLicence();
        if (mounted && licence.claims.expiresAt != before) {
          ref.invalidate(premiumStateProvider);
        }
      } on BridgeException {
        // Offline, or a key the server no longer knows: the stored
        // certificate stands, verified as it is.
      }
    });
  }

  Future<void> _activate() async {
    setState(() {
      _activating = true;
      _licenceError = null;
    });
    try {
      await _bridge.premiumActivate(_keyController.text);
      if (!mounted) return;
      _keyController.clear();
      // The certificate just came in: nothing to fetch again this visit.
      _refreshedLicence = true;
      invalidatePremium(ref);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _licenceError = error);
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _forget() async {
    setState(() => _licenceError = null);
    try {
      if (_deleteAccount) {
        // The server first, and nothing is dropped here unless it
        // confirmed: the core does both, in that order, so a refusal
        // leaves the key where it was.
        await _bridge.premiumDeleteAccount();
      } else {
        await _bridge.premiumForgetKey();
      }
      if (!mounted) return;
      setState(() {
        _confirmForget = false;
        _deleteAccount = false;
      });
      invalidatePremium(ref);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _licenceError = error);
    }
  }

  /// Leaves the confirmation, and the box with it: a tick is a choice
  /// made for one press and never a setting.
  void _cancelForget() {
    setState(() {
      _confirmForget = false;
      _deleteAccount = false;
    });
  }

  // --- the wallets -------------------------------------------------------

  Future<void> _setWatched(WalletMeta wallet, bool on, PremiumView view) async {
    if (on && !view.consented(wallet.id)) {
      // Once per wallet, never replayed: the yes is kept in the vault.
      final yes = await PremiumConsentScreen.ask(context, wallet);
      if (!yes || !mounted) return;
    }
    setState(() {
      _busyWalletId = wallet.id;
      _walletsError = null;
    });
    try {
      if (on) {
        await _bridge.premiumWatchWallet(wallet.id);
      } else {
        await _bridge.premiumUnwatchWallet(wallet.id);
      }
      if (!mounted) return;
      ref.invalidate(premiumStateProvider);
      ref.invalidate(premiumWalletsProvider);
      ref.invalidate(premiumEventsProvider);
    } on BridgeException catch (error) {
      if (mounted) setState(() => _walletsError = error);
    } finally {
      if (mounted) setState(() => _busyWalletId = null);
    }
  }

  /// While a first scan runs the server is asked again every few
  /// seconds, for two minutes at most; when the last scan ends, the log
  /// is read again for the `wallet_registered` line it just gained.
  void _followScans(List<WalletWatch> watched) {
    final scanning = watched.any((w) => w.scanning);
    if (scanning) {
      if (_scanTimer != null) return;
      _scanStartedAt = DateTime.now();
      _scanTimer = Timer.periodic(scanPollEvery, (_) {
        if (DateTime.now().difference(_scanStartedAt!) >= scanPollFor) {
          _stopScanPoll();
          return;
        }
        ref.invalidate(premiumWalletsProvider);
      });
    } else if (_scanTimer != null) {
      _stopScanPoll();
      ref.invalidate(premiumEventsProvider);
    }
  }

  void _stopScanPoll() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanStartedAt = null;
  }

  // --- the channels ------------------------------------------------------

  Future<void> _addChannel(PremiumView view) async {
    final kind = await showAddChannelSheet(context);
    if (kind == null || !mounted) return;
    final before = ref.read(premiumChannelsProvider).valueOrNull?.length ?? 0;
    setState(() => _channelsError = null);
    CreatedChannel? created;
    try {
      switch (kind) {
        case ChannelKind.ntfy:
          created = await _bridge.premiumCreateChannel(kind);
          final topic = created.topic;
          if (topic != null) {
            await _bridge.setAppPref(ntfyTopicPref(created.channel.id), topic);
            if (mounted) ref.invalidate(settingsProvider);
          }
        case ChannelKind.telegram:
          created = await _bridge.premiumCreateChannel(kind);
        case ChannelKind.email:
          created = await Navigator.of(context).push<CreatedChannel>(
            MaterialPageRoute(builder: (_) => const EmailChannelScreen()),
          );
        case ChannelKind.webhook:
          created = await Navigator.of(context).push<CreatedChannel>(
            MaterialPageRoute(builder: (_) => const WebhookChannelScreen()),
          );
      }
    } on BridgeException catch (error) {
      if (mounted) setState(() => _channelsError = error);
      return;
    }
    if (created == null || !mounted) return;
    ref.invalidate(premiumChannelsProvider);
    ref.invalidate(premiumAccountProvider);
    final channel = created.channel;
    // The first channel proves itself at once; one that has not
    // answered yet only once it has, since nothing is delivered to a
    // target still waiting to be linked. Quietly: the message itself
    // is the confirmation, and a toast here would sit on the button of
    // the page about to open.
    if (before == 0 && channel.linked) {
      unawaited(_test(channel, quiet: true));
    }
    switch (kind) {
      case ChannelKind.ntfy:
        final url = created.subscribeUrl;
        if (url != null) _openNtfy(url);
      case ChannelKind.telegram:
        _openTelegram(channel, view);
      case ChannelKind.email:
      case ChannelKind.webhook:
        break;
    }
  }

  void _openNtfy(String subscribeUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NtfyChannelScreen(subscribeUrl: subscribeUrl),
      ),
    );
  }

  void _openTelegram(PremiumChannel channel, PremiumView view) {
    final code = channel.linkCode;
    if (code == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TelegramChannelScreen(
          channelId: channel.id,
          code: code,
          startUrl:
              channel.startUrl ??
              'https://t.me/${view.telegramBot}?start=$code',
        ),
      ),
    );
  }

  /// A channel just proved itself with its code: the card reads it
  /// again, linked, and the account's count with it.
  void _confirmed() {
    setState(() => _channelsError = null);
    ref.invalidate(premiumChannelsProvider);
    ref.invalidate(premiumAccountProvider);
  }

  Future<void> _test(PremiumChannel channel, {bool quiet = false}) async {
    setState(() {
      _busyChannelId = channel.id;
      _channelsError = null;
    });
    try {
      await _bridge.premiumTestChannel(channel.id);
      if (mounted && !quiet) _toast('Test sent to ${channel.kind.label}');
    } on BridgeException catch (error) {
      if (mounted) setState(() => _channelsError = error);
    } finally {
      if (mounted) setState(() => _busyChannelId = null);
    }
  }

  Future<void> _remove(PremiumChannel channel) async {
    setState(() {
      _busyChannelId = channel.id;
      _channelsError = null;
    });
    try {
      await _bridge.premiumDeleteChannel(channel.id);
      if (channel.kind == ChannelKind.ntfy) {
        // The topic goes with the channel: nothing left to subscribe to.
        await _bridge.setAppPref(ntfyTopicPref(channel.id), '');
      }
      if (!mounted) return;
      ref.invalidate(settingsProvider);
      ref.invalidate(premiumChannelsProvider);
      ref.invalidate(premiumAccountProvider);
      _toast('Channel removed');
    } on BridgeException catch (error) {
      if (mounted) setState(() => _channelsError = error);
    } finally {
      if (mounted) setState(() => _busyChannelId = null);
    }
  }

  // --- the page ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final view = ref.watch(premiumStateProvider).valueOrNull;
    if (view == null) {
      return Padding(
        padding: const EdgeInsets.all(GerfautSpacing.md),
        child: Text(
          'Loading…',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      );
    }
    _refreshLicenceOnce(view);
    final status = licenceStatus(view);

    // What the server was asked, and whether it answered: a read that
    // failed gets the same amber note as an action that failed, under
    // the card it concerns. Nothing is asked without a key.
    final account = view.hasKey ? ref.watch(premiumAccountProvider) : null;
    final candidates = view.hasKey
        ? ref.watch(premiumCandidatesProvider)
        : null;
    final watched = view.hasKey ? ref.watch(premiumWalletsProvider) : null;
    final channels = view.hasKey ? ref.watch(premiumChannelsProvider) : null;
    final events = view.hasKey ? ref.watch(premiumEventsProvider) : null;
    final scanned = watched?.valueOrNull;
    if (scanned != null) {
      // Off the build: following a scan moves providers.
      Future.microtask(() {
        if (mounted) _followScans(scanned);
      });
    }
    final walletsError =
        _walletsError ??
        _bridgeError(account?.error) ??
        _bridgeError(candidates?.error) ??
        _bridgeError(watched?.error);
    final channelsError = _channelsError ?? _bridgeError(channels?.error);
    final eventsError = _bridgeError(events?.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LicenceCard(
          view: view,
          status: status,
          controller: _keyController,
          activating: _activating,
          confirmingForget: _confirmForget,
          deleteAccount: _deleteAccount,
          onActivate: _activate,
          onForgetStart: () => setState(() => _confirmForget = true),
          onForgetCancel: _cancelForget,
          onForgetConfirm: _forget,
          onDeleteAccountChanged: (on) => setState(() => _deleteAccount = on),
        ),
        if (_licenceError != null)
          _ErrorNote(
            error: _licenceError!,
            onRetry: _activating || !isWellFormedKey(_keyController.text)
                ? null
                : _activate,
          ),
        _WatchedWalletsCard(
          view: view,
          busyWalletId: _busyWalletId,
          onToggle: (wallet, on) => _setWatched(wallet, on, view),
        ),
        if (walletsError != null)
          _ErrorNote(
            error: walletsError,
            onRetry: () {
              setState(() => _walletsError = null);
              ref.invalidate(premiumAccountProvider);
              ref.invalidate(premiumCandidatesProvider);
              ref.invalidate(premiumWalletsProvider);
            },
          ),
        _ChannelsCard(
          view: view,
          busyChannelId: _busyChannelId,
          onAdd: () => _addChannel(view),
          onTest: _test,
          onRemove: _remove,
          onSubscribe: _openNtfy,
          onLinkCode: (channel) => _openTelegram(channel, view),
          onConfirmed: _confirmed,
        ),
        if (channelsError != null)
          _ErrorNote(
            error: channelsError,
            onRetry: () {
              setState(() => _channelsError = null);
              ref.invalidate(premiumChannelsProvider);
            },
          ),
        _RecentAlertsCard(view: view),
        if (eventsError != null)
          _ErrorNote(
            error: eventsError,
            onRetry: () => ref.invalidate(premiumEventsProvider),
          ),
      ],
    );
  }

  /// A provider's failure as the bridge named it; anything else is
  /// wrapped so the note still has a sentence.
  static BridgeException? _bridgeError(Object? error) {
    if (error == null) return null;
    if (error is BridgeException) return error;
    return BridgeException('internal', '$error');
  }
}

/// A call that failed, in an amber note under the card it concerns.
/// The words follow the kind: the server out of reach gets a retry, a
/// key the server refuses gets the reason.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.error, this.onRetry});

  final BridgeException error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (
      String message,
      String? hint,
      String? detail,
      bool retry,
    ) = switch (error.kind) {
      'premium_unreachable' => (
        'Could not reach the Gerfaut server.',
        null,
        null,
        true,
      ),
      'premium_unknown_key' => (
        'Unknown key.',
        'Check it against the key shown at purchase.',
        null,
        false,
      ),
      'premium_no_paid_time' => (
        'This key has no paid time.',
        'Add time on gerfaut-wallet.com, then try again.',
        null,
        false,
      ),
      'premium_rejected' => (
        'The Gerfaut server refused.',
        null,
        error.message,
        false,
      ),
      _ => (error.message, null, null, true),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: GerfautNotice(
        tone: NoticeTone.info,
        message: message,
        hint: hint,
        detail: detail,
        liveRegion: true,
        action: retry && onRetry != null
            ? GhostButton(label: 'Retry', onPressed: onRetry)
            : null,
      ),
    );
  }
}

// --- 1. Licence ------------------------------------------------------------

class _LicenceCard extends ConsumerWidget {
  const _LicenceCard({
    required this.view,
    required this.status,
    required this.controller,
    required this.activating,
    required this.confirmingForget,
    required this.deleteAccount,
    required this.onActivate,
    required this.onForgetStart,
    required this.onForgetCancel,
    required this.onForgetConfirm,
    required this.onDeleteAccountChanged,
  });

  final PremiumView view;
  final LicenceStatus status;
  final TextEditingController controller;
  final bool activating;
  final bool confirmingForget;

  /// The account on the server goes with the key: ticked, the
  /// confirmation is about something nothing brings back.
  final bool deleteAccount;
  final VoidCallback onActivate;
  final VoidCallback onForgetStart;
  final VoidCallback onForgetCancel;
  final VoidCallback onForgetConfirm;
  final ValueChanged<bool> onDeleteAccountChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SectionCard(
      icon: LucideIcons.keyRound,
      title: 'Licence',
      children: switch (status) {
        LicenceStatus.none => _withoutKey(tokens),
        LicenceStatus.active => _withKey(context, ref, tokens, active: true),
        LicenceStatus.expired => _withKey(context, ref, tokens, active: false),
      },
    );
  }

  List<Widget> _withoutKey(GerfautTokens tokens) {
    final wellFormed = isWellFormedKey(controller.text);
    final strangers = keyStrangers(controller.text);
    return [
      Text(
        'ACCOUNT KEY',
        style: tokens.label.copyWith(color: tokens.textMuted),
      ),
      const SizedBox(height: GerfautSpacing.sm),
      TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !activating,
        keyboardType: TextInputType.visiblePassword,
        textCapitalization: TextCapitalization.none,
        inputFormatters: const [AccountKeyFormatter()],
        style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
        onSubmitted: (_) {
          if (wellFormed && !activating) onActivate();
        },
        decoration: InputDecoration(
          hintText: 'xxxx-xxxx-xxxx-xxxx',
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
      if (strangers.isNotEmpty) ...[
        const SizedBox(height: GerfautSpacing.xs),
        // Not an error panel: the field is not wrong, one symbol is.
        Text(
          'A key never contains l, o, 0 or 1: check ${strangers.join(", ")}.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ],
      const SizedBox(height: GerfautSpacing.sm),
      Text(
        'Bought on gerfaut-wallet.com. The key is shown once at purchase; '
        'there is no account to recover it from.',
        style: tokens.bodySmall.copyWith(color: tokens.textMuted),
      ),
      const SizedBox(height: GerfautSpacing.md),
      Row(
        children: [
          PrimaryButton(
            label: activating ? 'Activating…' : 'Activate',
            onPressed: wellFormed && !activating ? onActivate : null,
          ),
          const SizedBox(width: GerfautSpacing.sm),
          GhostButton(
            label: 'Get Premium',
            icon: LucideIcons.externalLink,
            onPressed: () => openExternal(premiumSiteUrl),
          ),
        ],
      ),
    ];
  }

  /// Opens the renewal form and puts the key on the clipboard.
  ///
  /// The key never rides in the address: see [premiumRenewUrl]. It is
  /// copied through the guarded clipboard, so the system shows no
  /// preview of it and keeps none in its history, and the line that
  /// follows says where to put it.
  Future<void> _renew(BuildContext context, WidgetRef ref, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(sensitiveClipboardProvider).copy(key);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Key copied, paste it on the renewal page'),
      ),
    );
    await openExternal(premiumRenewUrl);
  }

  List<Widget> _withKey(
    BuildContext context,
    WidgetRef ref,
    GerfautTokens tokens, {
    required bool active,
  }) {
    final claims = view.claims!;
    final key = view.key!;
    return [
      if (active)
        Row(
          children: [
            Expanded(
              child: Text(
                'Active until ${formatDate(claims.expiresAt)}',
                style: tokens.body,
              ),
            ),
            const SizedBox(width: GerfautSpacing.sm),
            const PremiumPill(),
          ],
        )
      else
        Text(
          'Expired on ${formatDate(claims.expiresAt)} · alerts stop '
          '$premiumGraceDays days after expiry',
          style: tokens.body.copyWith(color: tokens.pending),
        ),
      const SizedBox(height: GerfautSpacing.sm),
      Wrap(
        children: [
          GhostButton(
            label: 'Renew',
            icon: LucideIcons.externalLink,
            onPressed: () => _renew(context, ref, key),
          ),
          GhostButton(
            label: 'Forget this key',
            icon: LucideIcons.eraser,
            onPressed: confirmingForget ? null : onForgetStart,
          ),
        ],
      ),
      if (confirmingForget) ...[
        const SizedBox(height: GerfautSpacing.sm),
        // Amber while only this device forgets: nothing on chain is
        // touched, the server keeps watching what it was told to, and
        // only this phone stops hearing about it. Red once the server
        // goes too, which is the one thing on this card that nothing
        // undoes.
        GerfautNotice(
          tone: deleteAccount ? NoticeTone.alert : NoticeTone.info,
          message: deleteAccount
              ? 'The server deletes the account this key opens: the '
                    'wallets it watches, the channels and the log, all of '
                    'it. The key stops working, here and anywhere else it '
                    'was entered, and nothing brings any of it back.'
              : 'Forgetting the key stops the watch on this device, not '
                    'on the server. It is your only proof of purchase: '
                    'keep a copy before you forget it here.',
        ),
        const SizedBox(height: GerfautSpacing.xs),
        _DeleteAccountBox(
          value: deleteAccount,
          onChanged: onDeleteAccountChanged,
        ),
        const SizedBox(height: GerfautSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GhostButton(label: 'Cancel', onPressed: onForgetCancel),
            const SizedBox(width: GerfautSpacing.sm),
            DangerButton(
              label: deleteAccount ? 'Delete and forget' : 'Forget key',
              onPressed: onForgetConfirm,
            ),
          ],
        ),
      ],
    ];
  }
}

/// The box that takes the account down with the key.
///
/// Off by default, and off again the moment the confirmation is left:
/// deleting the account is a thing to ask for on purpose, once, never
/// a preference that waits ticked for the next press.
class _DeleteAccountBox extends StatelessWidget {
  const _DeleteAccountBox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    // One stop for a screen reader: the box and the words it is about
    // cannot be acted on apart.
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Checkbox(
                value: value,
                activeColor: tokens.alert,
                checkColor: tokens.onPrimary,
                side: BorderSide(color: tokens.border, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                onChanged: (ticked) => onChanged(ticked ?? false),
              ),
              const SizedBox(width: GerfautSpacing.xs),
              Expanded(
                child: Text(
                  'Also delete everything on the server',
                  style: tokens.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. Watched wallets ----------------------------------------------------

class _WatchedWalletsCard extends ConsumerWidget {
  const _WatchedWalletsCard({
    required this.view,
    required this.busyWalletId,
    required this.onToggle,
  });

  final PremiumView view;
  final String? busyWalletId;
  final void Function(WalletMeta wallet, bool on) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    return SectionCard(
      icon: LucideIcons.radar,
      title: 'Watched wallets',
      children: [
        if (!view.hasKey)
          Text(
            'Activate your key to have the server watch a wallet and tell '
            'you when its coins move.',
            style: muted,
          )
        else
          ..._rows(context, ref, tokens),
      ],
    );
  }

  List<Widget> _rows(
    BuildContext context,
    WidgetRef ref,
    GerfautTokens tokens,
  ) {
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    final account = ref.watch(premiumAccountProvider);
    final candidates = ref.watch(premiumCandidatesProvider);
    final watched = ref.watch(premiumWalletsProvider);
    if (account.hasError || candidates.hasError || watched.hasError) {
      // The note under the card says what failed; the card keeps quiet.
      return [Text('The server could not be asked.', style: muted)];
    }
    final chain = account.valueOrNull?.chain;
    final wallets = candidates.valueOrNull;
    final byId = {
      for (final w in watched.valueOrNull ?? const <WalletWatch>[]) w.id: w,
    };
    if (account.valueOrNull == null || wallets == null || !watched.hasValue) {
      return [Text('Loading…', style: muted)];
    }
    if (chain == null) {
      return [
        Text(
          'This build does not know the network the server watches '
          '(${account.valueOrNull!.network}).',
          style: muted,
        ),
      ];
    }
    if (wallets.isEmpty) {
      return [
        Text(
          'No ${chain.label.toLowerCase()} wallets to watch yet. The server '
          'watches ${chain.label.toLowerCase()} wallets only.',
          style: muted,
        ),
      ];
    }
    return [
      for (final (index, wallet) in wallets.indexed) ...[
        if (index > 0) Divider(height: 1, thickness: 1, color: tokens.border),
        _WalletRow(
          wallet: wallet,
          watch: byId[wallet.id],
          busy: busyWalletId == wallet.id,
          onChanged: (on) => onToggle(wallet, on),
        ),
      ],
    ];
  }
}

/// One wallet of the server's network: its glyph and name, the Watched
/// pill once the server has it, the line under the name, and the
/// switch. A single address is greyed and says why.
class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.wallet,
    required this.watch,
    required this.busy,
    required this.onChanged,
  });

  final WalletMeta wallet;

  /// What the server says about it; null when it is not watched.
  final WalletWatch? watch;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final single = wallet.isSingleAddress;
    final watch = this.watch;
    final String? line;
    if (busy) {
      line = watch == null ? 'Registering…' : 'Removing…';
    } else if (watch != null) {
      // The server states the pending scan when it can, and then the
      // row says what it is: a scan queued behind others, which is not
      // the same promise as one under way. A server that says nothing
      // is read by the date it stamps at the end, and that only tells
      // us the scan is not done.
      line = switch (watch) {
        WalletWatch(baselinePending: true) => 'First scan pending',
        WalletWatch(scanning: true) => 'Scanning…',
        _ =>
          'Watched since ${formatDate(watch.watchedSince)} · '
              '${_coins(watch.coins)}',
      };
    } else if (single) {
      line = 'Single addresses cannot be watched yet.';
    } else {
      line = null;
    }
    final nameStyle = tokens.bodySmall.copyWith(
      color: single ? tokens.textMuted : tokens.text,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.xs),
      child: Row(
        children: [
          Icon(walletGlyph(wallet.icon), size: 16, color: tokens.textMuted),
          const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: GerfautSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(wallet.name, style: nameStyle),
                    if (watch != null && !watch.scanning) const WatchedPill(),
                  ],
                ),
                if (line != null)
                  Text(
                    line,
                    style: tokens.label.copyWith(
                      letterSpacing: 0,
                      color: tokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: GerfautSpacing.sm),
          Semantics(
            label: 'Watch ${wallet.name} from the server',
            child: Switch(
              value: watch != null,
              onChanged: single || busy ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }

  static String _coins(int coins) => switch (coins) {
    0 => 'no coins',
    1 => '1 coin',
    final n => '$n coins',
  };
}

// --- 3. Channels -------------------------------------------------------------

class _ChannelsCard extends ConsumerWidget {
  const _ChannelsCard({
    required this.view,
    required this.busyChannelId,
    required this.onAdd,
    required this.onTest,
    required this.onRemove,
    required this.onSubscribe,
    required this.onLinkCode,
    required this.onConfirmed,
  });

  final PremiumView view;
  final String? busyChannelId;
  final VoidCallback onAdd;
  final void Function(PremiumChannel channel) onTest;
  final void Function(PremiumChannel channel) onRemove;

  /// Reopens the subscribe page of an ntfy channel whose topic the
  /// vault still holds.
  final void Function(String subscribeUrl) onSubscribe;

  /// Reopens the code page of a Telegram channel the bot has not heard
  /// from yet.
  final void Function(PremiumChannel channel) onLinkCode;

  /// Told once a channel has been linked by its code, so the card and
  /// the account are read again.
  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    final channels = view.hasKey ? ref.watch(premiumChannelsProvider) : null;
    final prefs = ref.watch(settingsProvider).valueOrNull?.appPrefs ?? const {};
    final list = channels?.valueOrNull;
    return SectionCard(
      icon: LucideIcons.bellRing,
      title: 'Channels',
      children: [
        if (!view.hasKey)
          Text(
            'Where the alerts go: the ntfy app, Telegram, an e-mail, or a '
            'webhook of yours.',
            style: muted,
          )
        else if (channels!.hasError)
          Text('The server could not be asked.', style: muted)
        else if (list == null)
          Text('Loading…', style: muted)
        else ...[
          if (list.isEmpty)
            Text(
              'No channel yet: alerts have nowhere to go until you add one.',
              style: muted,
            ),
          for (final (index, channel) in list.indexed) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: tokens.border),
            _ChannelRow(
              channel: channel,
              busy: busyChannelId == channel.id,
              topic: _topic(prefs, channel),
              onTest: () => onTest(channel),
              onRemove: () => onRemove(channel),
              onSubscribe: onSubscribe,
              onLinkCode: () => onLinkCode(channel),
            ),
            // The code the address received, asked for under the row
            // it belongs to: an address is written to only once its
            // owner has proved they read it.
            if (channel.kind == ChannelKind.email && !channel.linked)
              _ConfirmCodeRow(channel: channel, onConfirmed: onConfirmed),
          ],
          const SizedBox(height: GerfautSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: 'Add a channel',
              icon: LucideIcons.plus,
              onPressed: onAdd,
            ),
          ),
        ],
      ],
    );
  }

  /// The subscribe URL of an ntfy channel created on this device, or
  /// null once the topic is gone or was never known here.
  String? _topic(Map<String, String> prefs, PremiumChannel channel) {
    if (channel.kind != ChannelKind.ntfy) return null;
    final topic = prefs[ntfyTopicPref(channel.id)];
    if (topic == null || topic.isEmpty) return null;
    return '${view.ntfyBaseUrl}/$topic';
  }
}

/// One channel: its glyph, its kind, the masked target under it, the
/// Telegram state as a pill, and the actions under a menu.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.busy,
    required this.topic,
    required this.onTest,
    required this.onRemove,
    required this.onSubscribe,
    required this.onLinkCode,
  });

  final PremiumChannel channel;
  final bool busy;

  /// The subscribe URL, when this device still knows the topic.
  final String? topic;
  final VoidCallback onTest;
  final VoidCallback onRemove;
  final void Function(String subscribeUrl) onSubscribe;
  final VoidCallback onLinkCode;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final topic = this.topic;
    // Who the alerts reach, when the server knows a name for them. A
    // server that predates the field, or a kind that has no such name,
    // leaves it null and the row reads as it always did.
    final name = channel.linkedName;
    final linkedName = name == null || name.isEmpty ? null : name;
    // The address has the code and has not sent it back: nothing is
    // delivered there until it does.
    final awaitingCode = channel.kind == ChannelKind.email && !channel.linked;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.xs),
      child: Row(
        children: [
          Icon(channelGlyph(channel.kind), size: 16, color: tokens.textMuted),
          const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: GerfautSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      channel.kind.label,
                      style: tokens.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    if (channel.kind == ChannelKind.telegram)
                      channel.linked
                          ? const StatusPill.tone(
                              tone: PillTone.neutral,
                              icon: LucideIcons.link,
                              label: 'Linked',
                            )
                          : const StatusPill.tone(
                              tone: PillTone.pending,
                              icon: LucideIcons.clock,
                              label: 'Waiting for the bot',
                            ),
                    if (channel.kind == ChannelKind.email && !channel.linked)
                      const StatusPill.tone(
                        tone: PillTone.pending,
                        icon: LucideIcons.clock,
                        label: 'Waiting for the code',
                      ),
                  ],
                ),
                if (busy)
                  Text(
                    'Working…',
                    style: tokens.label.copyWith(
                      letterSpacing: 0,
                      color: tokens.textMuted,
                    ),
                  )
                else if (awaitingCode)
                  // Where the six digits went. The server masks the
                  // address the same way whether it is waiting or
                  // linked: enough to tell which one, never a copy.
                  Text(
                    'Confirmation sent to ${channel.target}',
                    style: tokens.label.copyWith(
                      letterSpacing: 0,
                      color: tokens.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (linkedName != null)
                  // A Telegram target is a chat id nobody recognizes.
                  // The name the bot learned says which end of it this
                  // is, which is what the masked target says elsewhere.
                  Text(
                    'Linked to $linkedName',
                    style: tokens.label.copyWith(
                      letterSpacing: 0,
                      color: tokens.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (channel.target.isNotEmpty)
                  // Masked by the server: proof of which one, not a copy.
                  Text(
                    channel.target,
                    style: tokens.data.copyWith(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          OverflowMenu(
            tooltip: 'More for ${channel.kind.label}',
            items: [
              if (topic != null)
                OverflowMenuItem(
                  icon: LucideIcons.rss,
                  label: 'Subscribe link',
                  detail: 'Open or copy the topic again',
                  onSelected: () => onSubscribe(topic),
                ),
              if (channel.waitingForBot)
                OverflowMenuItem(
                  icon: LucideIcons.messageSquareText,
                  label: 'Link code',
                  detail: 'Send it to the bot',
                  onSelected: onLinkCode,
                ),
              // Nothing is sent to a target that has not answered yet,
              // so there is no test to offer until it has.
              if (channel.linked)
                OverflowMenuItem(
                  icon: LucideIcons.bellRing,
                  label: 'Send a test',
                  onSelected: busy ? () {} : onTest,
                ),
              OverflowMenuItem(
                icon: LucideIcons.trash2,
                label: 'Remove',
                onSelected: busy ? () {} : onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The six digits the server mailed, typed back.
///
/// An address is written to only once its owner has shown they read
/// it: until the code comes back the channel exists and receives
/// nothing. So the field sits under the row it belongs to rather than
/// on a page of its own — the channel is already made, this is the
/// last step of making it — and what the server says about a code
/// lands beside the field that was typed into, not under the card.
class _ConfirmCodeRow extends ConsumerStatefulWidget {
  const _ConfirmCodeRow({required this.channel, required this.onConfirmed});

  final PremiumChannel channel;

  /// Told once the server has linked the channel.
  final VoidCallback onConfirmed;

  @override
  ConsumerState<_ConfirmCodeRow> createState() => _ConfirmCodeRowState();
}

class _ConfirmCodeRowState extends ConsumerState<_ConfirmCodeRow> {
  final _controller = TextEditingController();
  bool _busy = false;
  BridgeException? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _complete => _controller.text.length == confirmationCodeLength;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(bridgeProvider)
          .premiumConfirmChannel(widget.channel.id, _controller.text);
      if (!mounted) return;
      _controller.clear();
      widget.onConfirmed();
    } on BridgeException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What a refused code says, and the server's own sentence under it.
  ///
  /// The server answers in plain English and those words are the ones
  /// that name the case — a code that is wrong, one that expired, one
  /// tried too many times, an e-mail that never left. They are kept
  /// verbatim; what is added is the line that says which step failed,
  /// since the words alone do not say they are about a code.
  (String, String?) get _problem {
    final error = _error!;
    return switch (error.kind) {
      'premium_rejected' => ('The code was not accepted.', error.message),
      'premium_unreachable' => ('Could not reach the Gerfaut server.', null),
      _ => (error.message, null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final ready = _complete && !_busy;
    return Padding(
      // Under the row's words, not under its glyph: the block belongs
      // to the channel above it and reads as its continuation.
      padding: const EdgeInsets.only(
        left: GerfautSpacing.md + GerfautSpacing.sm + GerfautSpacing.xs,
        bottom: GerfautSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CODE', style: tokens.label.copyWith(color: tokens.textMuted)),
          const SizedBox(height: GerfautSpacing.sm),
          // A Wrap, so the button goes to a line of its own at a large
          // text size instead of squeezing the field off the screen.
          Wrap(
            spacing: GerfautSpacing.sm,
            runSpacing: GerfautSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 128,
                child: _CodeField(
                  controller: _controller,
                  enabled: !_busy,
                  onChanged: () => setState(() => _error = null),
                  onSubmitted: ready ? _confirm : null,
                ),
              ),
              PrimaryButton(
                label: _busy ? 'Confirming…' : 'Confirm',
                onPressed: ready ? _confirm : null,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: GerfautSpacing.sm),
            GerfautNotice(
              tone: NoticeTone.info,
              message: _problem.$1,
              detail: _problem.$2,
              liveRegion: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Six digits and nothing else: the number keyboard, no suggestions,
/// mono at the body size so the phone never zooms.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(confirmationCodeLength),
      ],
      style: tokens.data.copyWith(fontSize: tokens.body.fontSize),
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        hintText: '000000',
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

// --- 4. Recent alerts --------------------------------------------------------

class _RecentAlertsCard extends ConsumerWidget {
  const _RecentAlertsCard({required this.view});

  final PremiumView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    final events = view.hasKey ? ref.watch(premiumEventsProvider) : null;
    final list = events?.valueOrNull ?? const <PremiumEvent>[];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const [];
    final known = {for (final w in wallets) w.id};
    return SectionCard(
      icon: LucideIcons.history,
      title: 'Recent alerts',
      children: [
        if (events != null && events.hasError)
          Text('The server could not be asked.', style: muted)
        else if (events != null && !events.hasValue)
          Text('Loading…', style: muted)
        else if (list.isEmpty)
          Text(
            'No alerts yet. Gerfaut will tell you here and on your channels.',
            style: muted,
          )
        else
          for (final (index, event) in list.indexed) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: tokens.border),
            _AlertRow(
              event: event,
              onTap: known.contains(event.wallet)
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            WalletHomeScreen(walletId: event.wallet),
                      ),
                    )
                  : null,
            ),
          ],
      ],
    );
  }
}

/// One event: a glyph in a 32px chip tinted by what happened, the
/// wallet's name and the phrase, the relative time at the end. Touched,
/// it opens the wallet, when this vault has it.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.event, required this.onTap});

  final PremiumEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final (IconData icon, Color ink, Color chip) = switch (event.kind) {
      // Coins leaving is the one thing the app exists to shout about.
      AlertKind.spendDetected || AlertKind.spendConfirmed => (
        LucideIcons.arrowUpRight,
        tokens.alert,
        tokens.alertSurface,
      ),
      AlertKind.coinsGone => (
        LucideIcons.triangleAlert,
        tokens.alert,
        tokens.alertSurface,
      ),
      AlertKind.receiveConfirmed => (
        LucideIcons.arrowDownLeft,
        tokens.confirmed,
        tokens.confirmedSurface,
      ),
      AlertKind.receiveDetected => (
        LucideIcons.arrowDownLeft,
        tokens.pending,
        tokens.pendingSurface,
      ),
      AlertKind.timelockDue => (
        LucideIcons.hourglass,
        tokens.pending,
        tokens.pendingSurface,
      ),
      AlertKind.walletRegistered => (
        LucideIcons.radar,
        tokens.textMuted,
        tokens.surfaceSunken,
      ),
      AlertKind.other => (
        LucideIcons.circleAlert,
        tokens.textMuted,
        tokens.surfaceSunken,
      ),
    };
    final phrase = alertPhrase(event);
    return Semantics(
      button: onTap != null,
      label: '${event.walletName}: $phrase, ${relativeTimeWords(event.at)}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.xs + 2),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: chip,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 15, color: ink),
              ),
              const SizedBox(width: GerfautSpacing.sm + GerfautSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: event.walletName,
                    style: tokens.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: const [FontVariation('wght', 500)],
                    ),
                    children: [
                      TextSpan(text: ' · $phrase', style: tokens.bodySmall),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: GerfautSpacing.sm),
              Text(
                relativeTime(event.at),
                style: tokens.label.copyWith(
                  letterSpacing: 0,
                  color: tokens.textMuted,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: GerfautSpacing.xs),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: tokens.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
