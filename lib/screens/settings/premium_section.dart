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
import '../change_key.dart';
import '../confirm_identity.dart';
import '../premium_channels.dart';
import '../premium_consent.dart';
import '../wallet_home.dart';
import 'premium_devices.dart';
import 'premium_error_note.dart';
import 'premium_protect.dart';

/// How often the server is asked again while a wallet's first scan
/// runs, and for how long before the asking stops.
const Duration scanPollEvery = Duration(seconds: 5);
const Duration scanPollFor = Duration(minutes: 2);

/// The Premium section. The licence first; on a device with full access
/// then the account's devices, the card that protects it until its three
/// steps are done, the wallets the server watches, where alerts go, and
/// what it said lately. A device that waits for approval sees the
/// licence and the wait, and nothing of the account; one the server
/// disconnected sees the licence and the way to connect again.
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

  /// The forget or the deletion is with the core: the confirmation's
  /// buttons are held until it answers, since a second press would be
  /// a second call, and the deletion is not a thing to ask for twice.
  bool _forgetting = false;
  bool _refreshedLicence = false;

  /// The kept key is being tried again, for a device the server
  /// disconnected.
  bool _connecting = false;

  /// The kept key was refused on the way back: it was changed on
  /// another device, and the field asks for the new one.
  bool _keyRejected = false;

  /// A waiting device asks the server again whether it was approved.
  bool _checkingAgain = false;

  /// The last "Copy key" did not reach the clipboard.
  bool _copyFailed = false;

  /// The change of key is on screen: a second tap opens nothing. Two
  /// sheets would send two changes, and the second would draw another
  /// key behind the one the first just showed.
  bool _changingKey = false;

  // The watched wallets.

  /// The wallets a call is out about, each held until its own answer
  /// comes back: one slot for all of them would let the first answer
  /// free every row at once, a call still out included.
  final Set<String> _busyWalletIds = {};
  BridgeException? _walletsError;

  /// The wallet whose unwatch is being asked about, under its row.
  String? _confirmUnwatchId;
  Timer? _scanTimer;
  DateTime? _scanStartedAt;

  // The channels.
  String? _busyChannelId;
  BridgeException? _channelsError;

  /// The channel whose removal is being asked about, under its row.
  String? _confirmRemoveChannelId;

  /// Whoever holds the phone is being asked to prove it: every answer
  /// to a question on this page is held until they have, so a second
  /// tap cannot open a second prompt or send the call on its own.
  bool _verifying = false;

  /// A channel is being added: the sheet is up, or the server is being
  /// asked for one. The button is held meanwhile, since the ntfy and
  /// Telegram kinds are created on the spot and a second tap in that
  /// beat would create a second channel.
  bool _addingChannel = false;

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

  /// Where the providers live. A call that changes what the vault or
  /// the server holds takes it, and the bridge, before its first await,
  /// and reads the state again through it: the page may be left before
  /// the answer, and the rest of the app must follow the change all the
  /// same. `ref` dies with this page; the container outlives it. Only
  /// what the page shows itself waits on `mounted`.
  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks whoever holds the phone to prove they own it, holding every
  /// question on the page meanwhile. True on a yes. [appLockOnly] asks
  /// only behind an app lock, as [confirmIdentity] does.
  Future<bool> _confirmIdentity({bool appLockOnly = false}) async {
    if (_verifying) return false;
    setState(() => _verifying = true);
    try {
      return await confirmIdentity(context, ref, appLockOnly: appLockOnly);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // --- the licence -------------------------------------------------------

  /// The certificate is fetched again once per visit, for the time a
  /// renewal on the site may have added. Quietly: a server out of reach
  /// changes nothing the stored certificate already says.
  void _refreshLicenceOnce(PremiumView view) {
    if (_refreshedLicence || !view.hasKey) return;
    _refreshedLicence = true;
    final container = _container;
    final bridge = container.read(bridgeProvider);
    Future.microtask(() async {
      try {
        final before = view.claims?.expiresAt;
        final licence = await bridge.premiumRefreshLicence();
        if (licence.claims.expiresAt != before) {
          container.invalidate(premiumStateProvider);
        }
      } on BridgeException catch (error) {
        // Offline, or a key the server no longer knows: the stored
        // certificate stands, verified as it is. A device turned away
        // meanwhile reads so from the vault.
        rereadIfDisowned(container, error);
      }
    });
  }

  /// Connects this phone with the key typed in. The account's first
  /// device has full access at once; any later one waits, and the
  /// section shows the wait.
  Future<void> _activate() async {
    if (_activating || _verifying) return;
    // Another key moves a connected device to another account and logs
    // it out of this one: what "Forget this key" does, behind the same
    // question to whoever holds the phone.
    final view = ref.read(premiumStateProvider).valueOrNull;
    final me = view == null
        ? null
        : currentDevice(view, ref.read(premiumMeProvider).valueOrNull);
    final leaving =
        view != null &&
        view.connected &&
        !(me != null && !me.fullAccess) &&
        normalizeKey(_keyController.text) != view.key;
    if (leaving && !await _confirmIdentity()) return;
    if (!mounted) return;
    final container = _container;
    final bridge = _bridge;
    setState(() {
      _activating = true;
      _licenceError = null;
    });
    try {
      await bridge.premiumConnect(_keyController.text);
      invalidatePremium(container);
      if (!mounted) return;
      _keyController.clear();
      _keyRejected = false;
      // The certificate just came in: nothing to fetch again this visit.
      _refreshedLicence = true;
    } on BridgeException catch (error) {
      if (mounted) setState(() => _licenceError = error);
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  /// Puts [key] on the guarded clipboard: the system shows no preview of
  /// it and keeps none in its history. A copy that fails says so under
  /// the buttons, where it was asked, and stays until the next one
  /// works: a toast would be gone before the empty clipboard was found.
  /// True once it is there.
  Future<bool> _copy(String key) async {
    try {
      await ref.read(sensitiveClipboardProvider).copy(key);
    } catch (_) {
      if (mounted) setState(() => _copyFailed = true);
      return false;
    }
    if (mounted) setState(() => _copyFailed = false);
    return true;
  }

  /// "Copy key", offered on the licence until the key is saved.
  Future<void> _copyKey(PremiumView view) async {
    final key = view.keyDisplay ?? view.key;
    if (key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (await _copy(key)) {
      messenger.showSnackBar(const SnackBar(content: Text('Key copied')));
    }
  }

  /// Opens the renewal form, the key on the clipboard.
  ///
  /// The key never rides in the address: see [premiumRenewUrl]. It goes
  /// by the guarded clipboard and the line that follows says where to
  /// put it. The page opens either way: whoever has the key at hand can
  /// type it. While a key change waits for its answer the key here may
  /// already be dead, and none is handed out.
  Future<void> _renew(PremiumView view) async {
    final key = view.key;
    if (key != null && !view.keyChangePending) {
      final messenger = ScaffoldMessenger.of(context);
      if (await _copy(key)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Key copied, paste it on the renewal page'),
          ),
        );
      }
    }
    await openExternal(premiumRenewUrl);
  }

  /// Opens the change of key, once. [resume] sends again the change
  /// whose answer was lost: the same key goes, and only its answer puts
  /// the new key in view.
  Future<void> _changeKey({bool resume = false}) async {
    if (_changingKey) return;
    // Set before the sheet is asked for, so a second tap in the same
    // frame finds it; the rebuild only greys the button after.
    _changingKey = true;
    setState(() {});
    try {
      await showChangeKeySheet(context, resume: resume);
    } finally {
      if (mounted) setState(() => _changingKey = false);
    }
  }

  /// A device the server disconnected tries the key it kept. It comes
  /// back as a new device, which waits like any other; a key changed
  /// elsewhere is refused, and the field comes back for the new one.
  Future<void> _connectAgain(PremiumView view) async {
    final key = view.key;
    if (_connecting || key == null) return;
    final container = _container;
    final bridge = _bridge;
    setState(() {
      _connecting = true;
      _licenceError = null;
    });
    try {
      await bridge.premiumConnect(key);
      invalidatePremium(container);
    } on BridgeException catch (error) {
      // The core kept the server's sentence with the disconnection:
      // the note that offers to connect again says it, once.
      if (error.kind == 'premium_too_many_devices') {
        container.invalidate(premiumStateProvider);
      }
      if (!mounted) return;
      switch (error.kind) {
        case 'premium_unknown_key':
          setState(() => _keyRejected = true);
        // Said by the note that offers to connect again, read above.
        case 'premium_too_many_devices':
          break;
        default:
          setState(() => _licenceError = error);
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// Asks the server again where this waiting device stands: approved
  /// meanwhile, it opens on the whole account.
  Future<void> _checkAgain() async {
    if (_checkingAgain) return;
    setState(() => _checkingAgain = true);
    ref.invalidate(premiumMeProvider);
    try {
      await ref.read(premiumMeProvider.future);
    } catch (_) {
      // The note under the licence says what failed.
    } finally {
      if (mounted) setState(() => _checkingAgain = false);
    }
  }

  /// Forgets the key here, or deletes the account with it. [confirm]
  /// says this device is connected and not known to wait: it may have
  /// full access, and leaving asks who holds the phone.
  Future<void> _forget({required bool confirm}) async {
    if (_forgetting || _verifying) return;
    // Taking the account down is for its owner only. So is taking this
    // device off it when it has full access: the server forgets the
    // device, coming back takes an approval or ten days, and an account
    // left with no device that sees it has nobody to refuse the next
    // one. A device whose access is not known yet, the server out of
    // reach, is asked too rather than let through. A device that waits,
    // or that the server let go, leaves without a question.
    if ((_deleteAccount || confirm) && !await _confirmIdentity()) return;
    if (!mounted) return;
    // Leaving the page while "Forgetting…" shows must not leave the app
    // on a key the vault no longer holds: the settings row and the page
    // opened again read the vault whatever became of this one.
    final container = _container;
    final bridge = _bridge;
    setState(() {
      _forgetting = true;
      _licenceError = null;
    });
    try {
      if (_deleteAccount) {
        // The server first, and nothing is dropped here unless it
        // confirmed: the core does both, in that order, so a refusal
        // leaves the key where it was.
        await bridge.premiumDeleteAccount();
      } else {
        await bridge.premiumLogOut();
      }
      invalidatePremium(container);
      if (!mounted) return;
      setState(() {
        _confirmForget = false;
        _deleteAccount = false;
        _keyRejected = false;
      });
    } on BridgeException catch (error) {
      rereadIfDisowned(container, error);
      if (mounted) setState(() => _licenceError = error);
    } finally {
      if (mounted) setState(() => _forgetting = false);
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
    if (!on) {
      // Off is asked about first: the server deletes the wallet's alert
      // history along with the watch, and the switch does not bring
      // that back. The switch stays on until the answer.
      setState(() => _confirmUnwatchId = wallet.id);
      return;
    }
    if (!view.consented(wallet.id)) {
      // Once per wallet, never replayed: the yes is kept in the vault.
      final yes = await PremiumConsentScreen.ask(context, wallet);
      if (!yes || !mounted) return;
    }
    await _askForWallet(wallet.id, () => _bridge.premiumWatchWallet(wallet.id));
  }

  /// Takes a wallet this phone no longer has off the server: the same
  /// question as the switch, then the same call, with no wallet to ask
  /// a consent for.
  void _unwatchOrphan(String id) => setState(() => _confirmUnwatchId = id);

  /// The yes: the call is made with the question still up, its buttons
  /// held meanwhile, and the question goes only once the server has
  /// said yes. On a refusal it stays, the failure under the card, so
  /// the next try is one tap away rather than a switch and a question.
  Future<void> _unwatch(String id) async {
    if (_busyWalletIds.contains(id)) return;
    if (!await _confirmIdentity() || !mounted) return;
    final done = await _askForWallet(
      id,
      () => _bridge.premiumUnwatchWallet(id),
    );
    if (done && mounted && _confirmUnwatchId == id) {
      setState(() => _confirmUnwatchId = null);
    }
  }

  void _cancelUnwatch() => setState(() => _confirmUnwatchId = null);

  /// One call about one wallet: its row is busy while it runs, a
  /// failure lands under the card, and what the server holds is read
  /// again afterwards. True once the server has said yes.
  Future<bool> _askForWallet(String id, Future<void> Function() call) async {
    final container = _container;
    setState(() {
      _busyWalletIds.add(id);
      _walletsError = null;
    });
    try {
      await call();
      container.invalidate(premiumStateProvider);
      container.invalidate(premiumWalletsProvider);
      container.invalidate(premiumEventsProvider);
      return true;
    } on BridgeException catch (error) {
      rereadIfDisowned(container, error);
      if (mounted) setState(() => _walletsError = error);
      return false;
    } finally {
      if (mounted) setState(() => _busyWalletIds.remove(id));
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
    if (_addingChannel) return;
    setState(() => _addingChannel = true);
    try {
      await _addChannelFlow(view);
    } finally {
      if (mounted) setState(() => _addingChannel = false);
    }
  }

  Future<void> _addChannelFlow(PremiumView view) async {
    final kind = await showAddChannelSheet(context);
    if (kind == null || !mounted) return;
    // A channel is where every alert goes: behind an app lock, whoever
    // holds the phone proves they own it before adding one of theirs.
    // Without a lock nobody is sent to set one for this.
    if (!await confirmIdentity(context, ref, appLockOnly: true)) return;
    if (!mounted) return;
    final container = _container;
    final bridge = _bridge;
    final before = ref.read(premiumChannelsProvider).valueOrNull?.length ?? 0;
    setState(() => _channelsError = null);
    CreatedChannel? created;
    try {
      switch (kind) {
        case ChannelKind.ntfy:
          created = await bridge.premiumCreateChannel(kind);
          final topic = created.topic;
          if (topic != null) {
            // Kept even if the page was left meanwhile: the subscribe
            // link opens again from the channel's row.
            await bridge.setAppPref(ntfyTopicPref(created.channel.id), topic);
            container.invalidate(settingsProvider);
          }
        case ChannelKind.telegram:
          created = await bridge.premiumCreateChannel(kind);
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
      rereadIfDisowned(container, error);
      if (mounted) setState(() => _channelsError = error);
      return;
    }
    if (created == null) return;
    container.invalidate(premiumChannelsProvider);
    container.invalidate(premiumAccountProvider);
    if (!mounted) return;
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

  /// The subscribe link of an ntfy channel, or the link code of a
  /// Telegram chat not linked yet, opened again from the channel's row.
  /// Either hands whoever reads it every alert of the account: behind
  /// an app lock, whoever holds the phone proves they own it first, as
  /// for adding a channel. The page that opens right after a channel is
  /// made asks nothing more: its owner has just been asked.
  Future<void> _reopenNtfy(String subscribeUrl) async {
    if (!await _confirmIdentity(appLockOnly: true) || !mounted) return;
    _openNtfy(subscribeUrl);
  }

  Future<void> _reopenTelegram(PremiumChannel channel, PremiumView view) async {
    if (channel.linkCode == null) return;
    if (!await _confirmIdentity(appLockOnly: true) || !mounted) return;
    _openTelegram(channel, view);
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
          // The core builds the link, and leaves out a code Telegram would
          // not take as a start parameter; without one, the bot alone,
          // and the code is typed.
          startUrl: channel.startUrl ?? 'https://t.me/${view.telegramBot}',
        ),
      ),
    );
  }

  /// A channel just proved itself with its code: its row has had the
  /// card read again, linked, and the account's count with it; an old
  /// failure under the card goes.
  void _confirmed() => setState(() => _channelsError = null);

  Future<void> _test(PremiumChannel channel, {bool quiet = false}) async {
    final container = _container;
    final bridge = _bridge;
    setState(() {
      _busyChannelId = channel.id;
      _channelsError = null;
    });
    try {
      await bridge.premiumTestChannel(channel.id);
      if (mounted && !quiet) _toast('Test sent to ${channel.kind.label}');
    } on BridgeException catch (error) {
      rereadIfDisowned(container, error);
      if (mounted) setState(() => _channelsError = error);
    } finally {
      if (mounted) setState(() => _busyChannelId = null);
    }
  }

  /// Remove, from a channel's menu: asked about under its row first,
  /// since alerts stop reaching it the moment it goes.
  void _askRemove(PremiumChannel channel) {
    setState(() {
      _confirmRemoveChannelId = channel.id;
      _channelsError = null;
    });
  }

  void _cancelRemove() => setState(() => _confirmRemoveChannelId = null);

  /// The yes: the owner proves who they are, then the server is asked,
  /// the question held up until it answers so a failure keeps the next
  /// try one tap away.
  Future<void> _remove(PremiumChannel channel) async {
    if (_busyChannelId != null) return;
    if (!await _confirmIdentity() || !mounted) return;
    final container = _container;
    final bridge = _bridge;
    setState(() {
      _busyChannelId = channel.id;
      _channelsError = null;
    });
    try {
      await bridge.premiumDeleteChannel(channel.id);
      if (channel.kind == ChannelKind.ntfy) {
        // The topic goes with the channel: nothing left to subscribe to.
        await bridge.setAppPref(ntfyTopicPref(channel.id), '');
      }
      container.invalidate(settingsProvider);
      container.invalidate(premiumChannelsProvider);
      container.invalidate(premiumAccountProvider);
      if (!mounted) return;
      _confirmRemoveChannelId = null;
      _toast('Channel removed');
    } on BridgeException catch (error) {
      rereadIfDisowned(container, error);
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

    // Where this device stands decides what the page holds: the whole
    // account, the wait, or the way back in. Nothing is asked without a
    // key, nor for a device the server disconnected, unless a connection
    // whose answer was lost is to be sent again.
    final asksDevice =
        (view.hasKey && !view.disconnected) || view.connectPending;
    final me = asksDevice ? ref.watch(premiumMeProvider) : null;
    // The last answer, the failure of a read made since included: a
    // provider keeps its previous value through an error, and a device
    // the server has just turned away must not go on showing as it was.
    final meError = me != null && me.hasError && !me.isLoading
        ? _bridgeError(me.error)
        : null;
    final turnedAway = disownedKinds.contains(meError?.kind);
    if (turnedAway) {
      // The core dropped the token as the server refused it, found the
      // kept key changed, or met every device the key takes: the vault
      // now says the device is disconnected, and reading it again lands
      // there for good. A first connection sent again and refused for
      // the last reason leaves no key to be disconnected from: the
      // server's sentence stays under the field instead.
      Future.microtask(() {
        if (!mounted) return;
        if (!view.hasKey &&
            meError?.kind == 'premium_too_many_devices' &&
            _licenceError == null) {
          setState(() => _licenceError = meError);
        }
        ref.invalidate(premiumStateProvider);
      });
    }
    // A server out of reach leaves the last answer standing, the note
    // under the licence saying why it could not be checked again. An
    // answer about another connection stands for nothing.
    final device = turnedAway ? null : currentDevice(view, me?.valueOrNull);
    final full = device?.fullAccess ?? false;
    final waiting = device != null && !device.fullAccess;

    // What the server was asked, and whether it answered: a read that
    // failed gets the same amber note as an action that failed, under
    // the card it concerns.
    final account = full ? ref.watch(premiumAccountProvider) : null;
    final candidates = full ? ref.watch(premiumCandidatesProvider) : null;
    final watched = full ? ref.watch(premiumWalletsProvider) : null;
    final channels = full ? ref.watch(premiumChannelsProvider) : null;
    final events = full ? ref.watch(premiumEventsProvider) : null;
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

    final forget = _ForgetQuestion(
      deleteAccount: _deleteAccount,
      // The account goes only from a device that sees it.
      canDelete: full,
      forgetting: _forgetting || _verifying,
      onCancel: _cancelForget,
      // Connected and not known to wait: full access, or not known yet.
      onConfirm: () => _forget(confirm: view.connected && !waiting),
      onDeleteAccountChanged: (on) => setState(() => _deleteAccount = on),
    );
    final devices = full ? ref.watch(accountDevicesProvider) : null;
    final lock = ref.watch(settingsProvider).valueOrNull?.appLock;
    final steps = devices == null
        ? null
        : protectSteps(view: view, devices: devices, lock: lock);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LicenceCard(
          view: view,
          status: status,
          asksKey: _keyRejected,
          full: full,
          waiting: waiting,
          controller: _keyController,
          activating: _activating,
          confirmingForget: _confirmForget && !waiting,
          forget: forget,
          onActivate: _activate,
          onChangeKey: _changeKey,
          onForgetStart: () => setState(() => _confirmForget = true),
          copyFailed: _copyFailed,
          onCopyKey: () => _copyKey(view),
          onRenew: () => _renew(view),
        ),
        if (_keyRejected)
          const Padding(
            padding: EdgeInsets.only(bottom: GerfautSpacing.gutter),
            child: GerfautNotice(
              tone: NoticeTone.info,
              liveRegion: true,
              message: 'This key no longer works. Enter the new one.',
            ),
          ),
        if (_licenceError != null)
          PremiumErrorNote(
            error: _licenceError!,
            onRetry: _activating || !isWellFormedKey(_keyController.text)
                ? null
                : _activate,
          ),
        if (view.hasKey && view.disconnected && !_keyRejected)
          _DisconnectedNote(
            reason: view.disconnectedReason,
            connecting: _connecting,
            onConnect: () => _connectAgain(view),
          ),
        // A key change sent and not answered, on a device that can still
        // finish it: the server may already hold the new key, which only
        // this vault keeps.
        if (view.hasKey &&
            view.keyChangePending &&
            !view.disconnected &&
            !_keyRejected)
          _UnfinishedKeyChangeNote(
            holding: _changingKey,
            onTryAgain: () => _changeKey(resume: true),
          ),
        if (asksDevice && device == null && meError == null)
          Padding(
            padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
            child: Text(
              'Loading…',
              style: tokens.bodySmall.copyWith(color: tokens.textMuted),
            ),
          ),
        if (meError != null)
          PremiumErrorNote(
            error: meError,
            onRetry: () => ref.invalidate(premiumMeProvider),
          ),
        if (waiting)
          _WaitingCard(
            device: device,
            checking: _checkingAgain,
            confirmingForget: _confirmForget,
            forget: forget,
            onCheckAgain: _checkAgain,
            onForgetStart: () => setState(() => _confirmForget = true),
          ),
        if (full) ...[
          const DevicesCard(),
          if (steps != null && protectCardShows(view, steps))
            ProtectAccountCard(view: view, steps: steps),
        ],
        if (full || !view.hasKey)
          ..._accountCards(
            view: view,
            walletsError: walletsError,
            channelsError: channelsError,
            eventsError: eventsError,
          ),
      ],
    );
  }

  /// What the server watches for the account, where it tells, and what
  /// it said lately: in their placeholder words without a key, and read
  /// from the server on a device with full access.
  List<Widget> _accountCards({
    required PremiumView view,
    required BridgeException? walletsError,
    required BridgeException? channelsError,
    required BridgeException? eventsError,
  }) {
    return [
      _WatchedWalletsCard(
        view: view,
        busyWalletIds: _busyWalletIds,
        holding: _verifying,
        confirmingUnwatchId: _confirmUnwatchId,
        onToggle: (wallet, on) => _setWatched(wallet, on, view),
        onUnwatchOrphan: _unwatchOrphan,
        onUnwatchConfirm: _unwatch,
        onUnwatchCancel: _cancelUnwatch,
      ),
      if (walletsError != null)
        PremiumErrorNote(
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
        holding: _verifying,
        confirmingRemoveId: _confirmRemoveChannelId,
        adding: _addingChannel,
        onAdd: () => _addChannel(view),
        onTest: _test,
        onRemove: _askRemove,
        onRemoveConfirm: _remove,
        onRemoveCancel: _cancelRemove,
        onSubscribe: _reopenNtfy,
        onLinkCode: (channel) => _reopenTelegram(channel, view),
        onConfirmed: _confirmed,
      ),
      if (channelsError != null)
        PremiumErrorNote(
          error: channelsError,
          onRetry: () {
            setState(() => _channelsError = null);
            ref.invalidate(premiumChannelsProvider);
          },
        ),
      _RecentAlertsCard(view: view),
      if (eventsError != null)
        PremiumErrorNote(
          error: eventsError,
          onRetry: () => ref.invalidate(premiumEventsProvider),
        ),
    ];
  }

  /// A provider's failure as the bridge named it; anything else is
  /// wrapped so the note still has a sentence.
  static BridgeException? _bridgeError(Object? error) {
    if (error == null) return null;
    if (error is BridgeException) return error;
    return BridgeException('internal', '$error');
  }
}

// --- 1. Licence ------------------------------------------------------------

class _LicenceCard extends StatelessWidget {
  const _LicenceCard({
    required this.view,
    required this.status,
    required this.asksKey,
    required this.full,
    required this.waiting,
    required this.controller,
    required this.activating,
    required this.confirmingForget,
    required this.forget,
    required this.onActivate,
    required this.onChangeKey,
    required this.onForgetStart,
    required this.copyFailed,
    required this.onCopyKey,
    required this.onRenew,
  });

  final PremiumView view;
  final LicenceStatus status;

  /// The field again, whatever the vault holds: the kept key was
  /// refused, and the new one is asked for.
  final bool asksKey;

  /// This device has full access: it may change the key.
  final bool full;

  /// This device waits for approval: "Forget this key" stands on the
  /// card that says so, with the other thing it can do, and not twice.
  final bool waiting;
  final TextEditingController controller;
  final bool activating;

  /// The question under "Forget this key" is up.
  final bool confirmingForget;

  /// That question, built by the section, which holds its state.
  final Widget forget;
  final VoidCallback onActivate;
  final VoidCallback onChangeKey;
  final VoidCallback onForgetStart;

  /// The last copy of the key did not reach the clipboard.
  final bool copyFailed;

  /// Copies the key, offered until the user says it is saved.
  final VoidCallback onCopyKey;

  /// Opens the renewal form, the key on the clipboard.
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return SectionCard(
      icon: LucideIcons.keyRound,
      iconColor: tokens.premium,
      title: 'Licence',
      children: asksKey
          ? _withoutKey(tokens)
          : switch (status) {
              LicenceStatus.none => _withoutKey(tokens),
              LicenceStatus.active => _withKey(tokens, active: true),
              LicenceStatus.expired => _withKey(tokens, active: false),
            },
    );
  }

  List<Widget> _withoutKey(GerfautTokens tokens) {
    final wellFormed = isWellFormedKey(controller.text);
    final strangers = keyStrangers(controller.text);
    // A key is kept, and the field is back over it: changed on another
    // device, or never paid for. Typing the new one is one way on, not
    // the only one: whoever does not have it can still leave. Not on a
    // device that waits, whose card offers it, nor while a change this
    // device can still finish holds the only copy of the new key.
    final canForget =
        view.hasKey && !waiting && !(view.keyChangePending && view.connected);
    return [
      // The field is a node of its own, named by the label above it and
      // carrying what is said about what was typed. A text field has
      // no node of its own otherwise: it takes over the card's, and a
      // screen reader then heard the title and every line of the card
      // as the hint of one edit box, and no text around it.
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  borderSide: BorderSide(color: tokens.premium, width: 2),
                ),
              ),
            ),
            if (strangers.isNotEmpty) ...[
              const SizedBox(height: GerfautSpacing.xs),
              // Not an error panel: the field is not wrong, one symbol is.
              Text(
                'A key never contains l, o, 0 or 1: check '
                '${strangers.join(", ")}.',
                style: tokens.bodySmall.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: GerfautSpacing.sm),
      // A stop of its own, after the field it is about, rather than
      // folded into the card's title ahead of it.
      Semantics(
        container: true,
        child: Text(
          'Bought on gerfaut-wallet.com. The key is shown once at purchase; '
          'there is no account to recover it from.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
      ),
      const SizedBox(height: GerfautSpacing.md),
      // A Wrap: at a large text size the link goes under the button
      // rather than past the edge of the card.
      Wrap(
        spacing: GerfautSpacing.sm,
        runSpacing: GerfautSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PremiumButton(
            label: activating ? 'Activating…' : 'Activate',
            onPressed: wellFormed && !activating ? onActivate : null,
          ),
          GhostButton(
            label: 'Get Premium',
            icon: LucideIcons.externalLink,
            onPressed: () => openExternal(premiumSiteUrl),
          ),
          if (canForget)
            GhostButton(
              label: 'Forget this key',
              icon: LucideIcons.eraser,
              onPressed: confirmingForget || activating ? null : onForgetStart,
            ),
        ],
      ),
      if (confirmingForget && canForget) ...[
        const SizedBox(height: GerfautSpacing.sm),
        forget,
      ],
    ];
  }

  List<Widget> _withKey(GerfautTokens tokens, {required bool active}) {
    final claims = view.claims!;
    // A key change sent and not answered: the key above may be dead,
    // the new one is in the vault, and only its answer shows it. The
    // note under the card finishes it; meanwhile the key is not handed
    // out, and a connected device does not leave, which would lose the
    // new key: the core refuses it too.
    final changing = view.keyChangePending;
    final canForget = !waiting && !(changing && view.connected);
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
      // A Wrap: at a large text size the third button goes to a line of
      // its own rather than past the edge of the card.
      Wrap(
        children: [
          GhostButton(
            label: 'Renew',
            icon: LucideIcons.externalLink,
            onPressed: onRenew,
          ),
          // "Try again" on the note is the change while one is under
          // way: the same key goes, never a second one.
          if (full && !changing)
            GhostButton(
              label: 'Change key',
              icon: LucideIcons.rotateCcwKey,
              onPressed: onChangeKey,
            ),
          // Until the key is saved somewhere, the one place a phone keeps
          // it is one tap from the clipboard. Not while a change is under
          // way: the key here may already be dead.
          if (!view.keySaved && !changing)
            GhostButton(
              label: 'Copy key',
              icon: LucideIcons.copy,
              onPressed: onCopyKey,
            ),
          if (canForget)
            GhostButton(
              label: 'Forget this key',
              icon: LucideIcons.eraser,
              onPressed: confirmingForget ? null : onForgetStart,
            ),
        ],
      ),
      if (copyFailed && !changing) ...[
        const SizedBox(height: GerfautSpacing.xs),
        // Said where it was asked, and it stays: a toast would be gone
        // before anyone noticed the clipboard was empty.
        const GerfautNotice(
          tone: NoticeTone.info,
          liveRegion: true,
          message: 'Could not copy the key.',
        ),
      ],
      if (confirmingForget && canForget) ...[
        const SizedBox(height: GerfautSpacing.sm),
        forget,
      ],
    ];
  }
}

/// The question under "Forget this key", on the licence or on the card
/// of a device that waits: what leaving costs, the box that takes the
/// account down with the key where this device may, and the two
/// answers.
class _ForgetQuestion extends StatelessWidget {
  const _ForgetQuestion({
    required this.deleteAccount,
    required this.canDelete,
    required this.forgetting,
    required this.onCancel,
    required this.onConfirm,
    required this.onDeleteAccountChanged,
  });

  /// The account on the server goes with the key: ticked, the
  /// confirmation is about something nothing brings back.
  final bool deleteAccount;

  /// This device sees the account and may delete it; one that waits,
  /// or that the server disconnected, may only leave.
  final bool canDelete;

  /// The confirmed press is with the core: its buttons are held, and
  /// the one pressed says what it is doing.
  final bool forgetting;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final ValueChanged<bool> onDeleteAccountChanged;

  @override
  Widget build(BuildContext context) {
    final deleting = deleteAccount && canDelete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Amber either way. Nothing on chain is touched by either:
        // forgetting the key stops this phone hearing about the watch,
        // deleting the account stops the watch itself and spends the
        // paid time with it. That is a loss worth a warning, and the
        // words carry it; red stays for what costs funds or privacy.
        GerfautNotice(
          tone: NoticeTone.info,
          liveRegion: true,
          message: deleting
              ? 'Deleting the account removes the wallets it watches, the '
                    'channels it tells and the key itself from the server. '
                    'This cannot be undone, and whatever paid time the key '
                    'had left goes with it.'
              : 'Forgetting the key disconnects this device from your '
                    'Premium account. To use Premium here again, enter the '
                    'key, then approve this device from another one or wait '
                    '10 days.',
        ),
        if (canDelete) ...[
          const SizedBox(height: GerfautSpacing.xs),
          _DeleteAccountBox(
            value: deleteAccount,
            onChanged: forgetting ? null : onDeleteAccountChanged,
          ),
        ],
        const SizedBox(height: GerfautSpacing.xs),
        ConfirmActions(
          cancel: GhostButton(
            label: 'Cancel',
            onPressed: forgetting ? null : onCancel,
          ),
          confirm: DangerButton(
            label: switch ((deleting, forgetting)) {
              (true, true) => 'Deleting…',
              (true, false) => 'Delete and forget',
              (false, true) => 'Forgetting…',
              (false, false) => 'Forget the key',
            },
            onPressed: forgetting ? null : onConfirm,
          ),
        ),
      ],
    );
  }
}

/// The server no longer takes this device's token: another device
/// disconnected it, or the key was changed. The key is still here, and
/// "Connect again" tries it: the device comes back as a new one, which
/// waits like any other.
///
/// Or the server would not connect it at all, the key having every
/// device it takes: the note then says so in the server's sentence,
/// which also says what to do first.
class _DisconnectedNote extends StatelessWidget {
  const _DisconnectedNote({
    required this.reason,
    required this.connecting,
    required this.onConnect,
  });

  /// The server's own words for why it would not connect this device.
  final String? reason;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      child: GerfautNotice(
        tone: NoticeTone.info,
        message: disconnectedWords(reason),
        actionsBelow: true,
        action: GhostButton(
          label: connecting ? 'Connecting…' : 'Connect again',
          icon: LucideIcons.plug,
          onPressed: connecting ? null : onConnect,
        ),
      ),
    );
  }
}

/// A key change sent and not answered: the server may already have
/// made the new key the account's, and the key on the card may be dead.
/// Amber, under the licence, with the one way on: "Try again" asks who
/// holds the phone, as a change does, sends the same new key, and shows
/// it once the server has answered.
class _UnfinishedKeyChangeNote extends StatelessWidget {
  const _UnfinishedKeyChangeNote({
    required this.holding,
    required this.onTryAgain,
  });

  /// The change is on screen already.
  final bool holding;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GerfautSpacing.gutter),
      // Not announced by itself: it is the state the page opens on, and
      // the change that failed has said so already.
      child: GerfautNotice(
        tone: NoticeTone.info,
        message: keyChangePendingMessage,
        actionsBelow: true,
        action: PremiumButton(
          label: 'Try again',
          onPressed: holding ? null : onTryAgain,
        ),
      ),
    );
  }
}

/// A device connected with the key and not approved yet: it sees
/// nothing of the account until another device approves it, or the
/// wait ends. The card stands where the account's cards would, says
/// until when, where to approve it, and why the wait is there.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({
    required this.device,
    required this.checking,
    required this.confirmingForget,
    required this.forget,
    required this.onCheckAgain,
    required this.onForgetStart,
  });

  final PremiumDevice device;

  /// The server is being asked again.
  final bool checking;

  /// The question under "Forget this key" is up.
  final bool confirmingForget;
  final Widget forget;
  final VoidCallback onCheckAgain;
  final VoidCallback onForgetStart;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final text = tokens.bodySmall.copyWith(color: tokens.text);
    final until =
        device.pendingUntil ?? device.connectedAt + pendingDays * 86400;
    return SectionCard(
      icon: LucideIcons.hourglass,
      iconColor: tokens.premium,
      title: 'Waiting for approval',
      children: [
        Text(
          'This device connected to your Premium account on '
          '${formatDayMonthYear(device.connectedAt)}. It shows your watched '
          'wallets, '
          'channels and alerts once one of your other devices approves it, '
          'or on ${formatDayMonthYear(until)} without approval.',
          style: text,
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'Approve it in Gerfaut on another device: '
          'Settings › Premium › Devices.',
          style: text,
        ),
        const SizedBox(height: GerfautSpacing.sm),
        Text(
          'The wait protects you if someone else gets your key: they see '
          'nothing and can change nothing while you are warned.',
          style: tokens.bodySmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: GerfautSpacing.md),
        Wrap(
          spacing: GerfautSpacing.sm,
          runSpacing: GerfautSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SecondaryButton(
              label: checking ? 'Checking…' : 'Check again',
              icon: LucideIcons.refreshCw,
              onPressed: checking ? null : onCheckAgain,
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
          forget,
        ],
      ],
    );
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

  /// Null while the press it governs is under way: the box cannot
  /// change what the core is already doing.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final onChanged = this.onChanged;
    // One stop for a screen reader: the box and the words it is about
    // cannot be acted on apart.
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(GerfautRadius.md),
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Checkbox(
                value: value,
                // Glacier, not Bruyère: the box arms a deletion, which
                // is no premium action, and a selection is what the
                // accent is for. The consequence is said in the note
                // above, not painted on the box.
                activeColor: tokens.primary,
                checkColor: tokens.onPrimary,
                side: BorderSide(color: tokens.border, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GerfautRadius.sm),
                ),
                onChanged: onChanged == null
                    ? null
                    : (ticked) => onChanged(ticked ?? false),
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
    required this.busyWalletIds,
    required this.holding,
    required this.confirmingUnwatchId,
    required this.onToggle,
    required this.onUnwatchOrphan,
    required this.onUnwatchConfirm,
    required this.onUnwatchCancel,
  });

  final PremiumView view;

  /// The wallets a call is out about; their rows are held.
  final Set<String> busyWalletIds;

  /// The owner is being asked to prove who they are: the question's
  /// answers are held meanwhile.
  final bool holding;

  /// The wallet whose row carries the unwatch question, if any.
  final String? confirmingUnwatchId;
  final void Function(WalletMeta wallet, bool on) onToggle;

  /// For a wallet the server watches that this phone no longer has.
  final void Function(String id) onUnwatchOrphan;

  /// The two answers to the question under a row.
  final void Function(String id) onUnwatchConfirm;
  final VoidCallback onUnwatchCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final muted = tokens.bodySmall.copyWith(color: tokens.textMuted);
    return SectionCard(
      icon: LucideIcons.radar,
      iconColor: tokens.premium,
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
    // What the server watches that this phone no longer has: removed
    // here before the server could be told, or handed over from
    // another device. Listed after the phone's own wallets, each with
    // a way off the server, since a switch needs a wallet to belong to.
    final local = {for (final w in wallets) w.id};
    final orphans = [
      for (final w in byId.values)
        if (!local.contains(w.id)) w,
    ];
    // The question sits under the row it is about, inside the same
    // slot between two dividers: it is that row's, not the card's.
    Widget asked(Widget row, String id, String name, {required bool local}) {
      if (confirmingUnwatchId != id) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          _UnwatchQuestion(
            name: name,
            local: local,
            busy: busyWalletIds.contains(id),
            holding: holding,
            onConfirm: () => onUnwatchConfirm(id),
            onCancel: onUnwatchCancel,
          ),
        ],
      );
    }

    final rows = <Widget>[
      for (final wallet in wallets)
        asked(
          _WalletRow(
            wallet: wallet,
            watch: byId[wallet.id],
            busy: busyWalletIds.contains(wallet.id),
            onChanged: (on) => onToggle(wallet, on),
          ),
          wallet.id,
          wallet.name,
          local: true,
        ),
      for (final orphan in orphans)
        asked(
          _OrphanRow(
            watch: orphan,
            busy: busyWalletIds.contains(orphan.id),
            onUnwatch: () => onUnwatchOrphan(orphan.id),
          ),
          orphan.id,
          orphan.name,
          local: false,
        ),
    ];
    return [
      if (wallets.isEmpty) ...[
        Text(
          'No ${chain.label.toLowerCase()} wallets to watch yet. The server '
          'watches ${chain.label.toLowerCase()} wallets only.',
          style: muted,
        ),
        if (orphans.isNotEmpty) const SizedBox(height: GerfautSpacing.sm),
      ],
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) Divider(height: 1, thickness: 1, color: tokens.border),
        row,
      ],
    ];
  }
}

/// One wallet of the server's network: its glyph and name, the Watched
/// pill once the server watches it, the line under the name, and the
/// switch. A wallet the server refused keeps its row: the switch is on,
/// since the server holds it, and the server's own sentence says in
/// amber why nothing is watched under it.
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
    final watch = this.watch;
    final refusal = watch != null && watch.refused;
    final String? line;
    if (busy) {
      line = watch == null ? 'Registering…' : 'Removing…';
    } else if (refusal) {
      // Shown as the server wrote it: it knows the ceiling the wallet
      // went past, the app does not.
      final words = watch.refusal?.message.trim() ?? '';
      line = words.isEmpty ? 'The server does not watch this wallet.' : words;
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
    } else {
      line = null;
    }
    final nameStyle = tokens.bodySmall.copyWith(
      color: tokens.text,
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
                    if (watch != null && !watch.scanning && !refusal)
                      const WatchedPill(),
                  ],
                ),
                if (line != null)
                  Text(
                    line,
                    style: tokens.label.copyWith(
                      letterSpacing: 0,
                      color: refusal && !busy
                          ? tokens.pending
                          : tokens.textMuted,
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
              // On is Bruyère: the wallet is the server's to watch, and
              // the switch says so in the premium colour.
              activeThumbColor: tokens.onPremium,
              activeTrackColor: tokens.premium,
              inactiveThumbColor: tokens.textMuted,
              inactiveTrackColor: tokens.surfaceSunken,
              onChanged: busy ? null : onChanged,
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

/// The question under a row whose switch was turned off, or whose
/// Unwatch was pressed: taking the wallet off the server deletes its
/// alert history there too, and that does not come back with the
/// switch. Amber, since nothing is at stake but a log; the button that
/// does it is the destructive one, as for every deletion that cannot
/// be undone. Never a single tap, and never two: the question stays up
/// while the server answers, its buttons held, so a second press has
/// nothing to land on.
class _UnwatchQuestion extends StatelessWidget {
  const _UnwatchQuestion({
    required this.name,
    required this.local,
    required this.busy,
    required this.holding,
    required this.onConfirm,
    required this.onCancel,
  });

  final String name;

  /// The owner is being asked who they are: the answers wait, their
  /// words unchanged.
  final bool holding;

  /// This phone still holds the wallet, and says so: unwatching is
  /// not removing. A wallet the server alone has gets no such clause.
  final bool local;

  /// The call is with the server: neither answer can be given again.
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: GerfautSpacing.xs,
        bottom: GerfautSpacing.sm,
      ),
      child: GerfautNotice(
        tone: NoticeTone.info,
        liveRegion: true,
        message:
            'Unwatching "$name" also deletes its alert history on the server'
            '${local ? '; the wallet stays on this device.' : '.'}',
        // The sentence takes the whole width; the two answers share a
        // row of their own under it, the way out first.
        actionsBelow: true,
        action: ConfirmActions(
          cancel: GhostButton(
            label: 'Cancel',
            onPressed: busy || holding ? null : onCancel,
          ),
          confirm: DangerButton(
            label: busy ? 'Unwatching…' : 'Unwatch',
            onPressed: busy || holding ? null : onConfirm,
          ),
        ),
      ),
    );
  }
}

/// A wallet the server watches that this phone no longer has. No
/// switch, since there is no wallet for one to belong to: the name the
/// server kept, why the row is here, the Watched pill, and a button
/// that takes it off the server.
class _OrphanRow extends StatelessWidget {
  const _OrphanRow({
    required this.watch,
    required this.busy,
    required this.onUnwatch,
  });

  final WalletWatch watch;
  final bool busy;
  final VoidCallback onUnwatch;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: GerfautSpacing.xs),
      child: Row(
        children: [
          Icon(LucideIcons.wallet, size: 16, color: tokens.textMuted),
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
                      watch.name,
                      style: tokens.bodySmall.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                      ),
                    ),
                    const WatchedPill(),
                  ],
                ),
                Text(
                  busy
                      ? 'Removing…'
                      : 'Removed from this phone, still watched by the server.',
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
            label: 'Stop watching ${watch.name} from the server',
            child: GhostButton(
              label: 'Unwatch',
              onPressed: busy ? null : onUnwatch,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 3. Channels -------------------------------------------------------------

class _ChannelsCard extends ConsumerWidget {
  const _ChannelsCard({
    required this.view,
    required this.busyChannelId,
    required this.holding,
    required this.confirmingRemoveId,
    required this.adding,
    required this.onAdd,
    required this.onTest,
    required this.onRemove,
    required this.onRemoveConfirm,
    required this.onRemoveCancel,
    required this.onSubscribe,
    required this.onLinkCode,
    required this.onConfirmed,
  });

  final PremiumView view;
  final String? busyChannelId;

  /// The owner is being asked who they are: the question's answers
  /// wait meanwhile.
  final bool holding;

  /// The channel whose removal is being asked about, if any.
  final String? confirmingRemoveId;

  /// A channel is on its way: the button that starts one is held.
  final bool adding;
  final VoidCallback onAdd;
  final void Function(PremiumChannel channel) onTest;

  /// Remove, from the row's menu: puts the question under the row.
  final void Function(PremiumChannel channel) onRemove;

  /// The two answers to that question.
  final void Function(PremiumChannel channel) onRemoveConfirm;
  final VoidCallback onRemoveCancel;

  /// Reopens the subscribe page of an ntfy channel whose topic the
  /// vault still holds.
  final void Function(String subscribeUrl) onSubscribe;

  /// Reopens the code page of a Telegram channel the bot has not heard
  /// from yet.
  final void Function(PremiumChannel channel) onLinkCode;

  /// Told once a channel has been linked by its code, the card and the
  /// account already read again.
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
      iconColor: tokens.premium,
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
            if (confirmingRemoveId == channel.id)
              _RemoveChannelQuestion(
                busy: busyChannelId == channel.id,
                holding: holding,
                onConfirm: () => onRemoveConfirm(channel),
                onCancel: onRemoveCancel,
              ),
            // The server turned this one off and delivers nothing to
            // it, whatever else the row would have said: amber under
            // the row, and the words say on their own what to do.
            // Nothing is at risk on chain; the alerts simply do not
            // arrive until it is done.
            if (!channel.enabled)
              Padding(
                padding: const EdgeInsets.only(
                  left:
                      GerfautSpacing.md + GerfautSpacing.sm + GerfautSpacing.xs,
                  bottom: GerfautSpacing.sm,
                ),
                child: GerfautNotice(
                  tone: NoticeTone.info,
                  message: offReason(channel),
                ),
              )
            // The code the address received, asked for under the row
            // it belongs to: an address is written to only once its
            // owner has proved they read it.
            else if (channel.kind == ChannelKind.email && !channel.linked)
              // Keyed by the channel: the field holds what was typed,
              // and a list that reorders under it must not hand that
              // to another channel's row.
              _ConfirmCodeRow(
                key: ValueKey(channel.id),
                channel: channel,
                onConfirmed: onConfirmed,
              ),
          ],
          const SizedBox(height: GerfautSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              label: adding ? 'Adding…' : 'Add a channel',
              icon: LucideIcons.plus,
              onPressed: adding ? null : onAdd,
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

/// The question under a channel whose Remove was chosen. Amber: the
/// alerts stop going there, and nothing on chain is touched; the button
/// that does it is the destructive one, as for every removal. It stays
/// up while the server answers, its buttons held, so a second press has
/// nothing to land on.
class _RemoveChannelQuestion extends StatelessWidget {
  const _RemoveChannelQuestion({
    required this.busy,
    required this.holding,
    required this.onConfirm,
    required this.onCancel,
  });

  /// The call is with the server.
  final bool busy;

  /// The owner is being asked who they are.
  final bool holding;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final held = busy || holding;
    return Padding(
      padding: const EdgeInsets.only(
        top: GerfautSpacing.xs,
        bottom: GerfautSpacing.sm,
      ),
      child: GerfautNotice(
        tone: NoticeTone.info,
        liveRegion: true,
        message: removeChannelQuestion,
        actionsBelow: true,
        action: ConfirmActions(
          cancel: GhostButton(
            label: 'Cancel',
            onPressed: held ? null : onCancel,
          ),
          confirm: DangerButton(
            label: busy ? 'Removing…' : 'Remove',
            onPressed: held ? null : onConfirm,
          ),
        ),
      ),
    );
  }
}

/// What removing a channel asks first.
const String removeChannelQuestion =
    'Remove this channel? Gerfaut stops sending alerts to it at once.';

/// One channel: its glyph, its kind, the masked target under it, the
/// state as a pill when it has one, and the actions under a menu.
///
/// A channel the server turned off reads as such before anything
/// else: the pill says nothing is delivered, and the menu offers no
/// test and no code, since the server writes nothing to it either way.
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
    final off = !channel.enabled;
    // The address has the code and has not sent it back: nothing is
    // delivered there until it does.
    final awaitingCode =
        !off && channel.kind == ChannelKind.email && !channel.linked;
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
                    if (off)
                      // Amber, not red: nothing on chain is at stake,
                      // and the glyph says it is a warning rather than
                      // a wait.
                      const StatusPill.tone(
                        tone: PillTone.pending,
                        icon: LucideIcons.triangleAlert,
                        label: 'Not delivering',
                      )
                    else if (channel.kind == ChannelKind.telegram)
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
                            )
                    else if (awaitingCode)
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
              if (!off && channel.waitingForBot)
                OverflowMenuItem(
                  icon: LucideIcons.messageSquareText,
                  label: 'Link code',
                  detail: 'Send it to the bot',
                  onSelected: onLinkCode,
                ),
              // Nothing is sent to a target that has not answered yet,
              // nor to one the server turned off: no test to offer
              // whose only outcome is that refusal.
              if (!off && channel.linked)
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
  const _ConfirmCodeRow({
    super.key,
    required this.channel,
    required this.onConfirmed,
  });

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
    // Held before the call, as the section does: the channel is linked
    // whether or not this row is still on screen when the server says so.
    final container = ProviderScope.containerOf(context, listen: false);
    final bridge = ref.read(bridgeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bridge.premiumConfirmChannel(widget.channel.id, _controller.text);
      container.invalidate(premiumChannelsProvider);
      container.invalidate(premiumAccountProvider);
      if (!mounted) return;
      _controller.clear();
      widget.onConfirmed();
    } on BridgeException catch (error) {
      rereadIfDisowned(container, error);
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What a refused code says, and the server's own sentence under it.
  ///
  /// The server answers in plain English and those words are the ones
  /// that name the case — a code that is wrong, one that expired, one
  /// tried too many times. They are kept verbatim, the bridge having
  /// dropped the prefix the core wraps them in; what is added is the
  /// line that says which step failed, since the words alone do not say
  /// they are about a code.

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final ready = _complete && !_busy;
    final error = _error;
    final problem = error == null
        ? null
        : premiumFailure(error, refusal: 'The code was not accepted.');
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
          // Named on the field itself, which the button beside it keeps
          // from sharing one node with this label.
          ExcludeSemantics(
            child: Text(
              'CODE',
              style: tokens.label.copyWith(color: tokens.textMuted),
            ),
          ),
          const SizedBox(height: GerfautSpacing.sm),
          // A Wrap, so the button goes to a line of its own at a large
          // text size instead of squeezing the field off the screen.
          Wrap(
            spacing: GerfautSpacing.sm,
            runSpacing: GerfautSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                // Six mono digits and their padding at the body size,
                // and as much again as the text is scaled: a fixed
                // width held four of them at twice the size. The Wrap
                // still caps it at the row's width.
                width: MediaQuery.textScalerOf(context).scale(128),
                child: _CodeField(
                  controller: _controller,
                  enabled: !_busy,
                  onChanged: () => setState(() => _error = null),
                  onSubmitted: ready ? _confirm : null,
                ),
              ),
              PremiumButton(
                label: _busy ? 'Confirming…' : 'Confirm',
                onPressed: ready ? _confirm : null,
              ),
            ],
          ),
          if (problem != null) ...[
            const SizedBox(height: GerfautSpacing.sm),
            GerfautNotice(
              tone: NoticeTone.info,
              message: problem.message,
              hint: problem.hint,
              detail: problem.detail,
              liveRegion: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Six digits and nothing else: the number keyboard, no suggestions,
/// mono at the body size so the phone never zooms, and never under the
/// 44px a thumb needs.
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
    // A node of its own, as the key's field: otherwise the field takes
    // over the card's, and the channels are read as its hint.
    return Semantics(
      container: true,
      label: 'Code',
      child: TextField(
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
        textAlignVertical: TextAlignVertical.center,
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
          // The line and its padding come to 42px at the body size: the
          // floor is what makes the field a target, the text centred in
          // whatever the floor leaves.
          constraints: const BoxConstraints(minHeight: 44),
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
            borderSide: BorderSide(color: tokens.premium, width: 2),
          ),
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
      iconColor: tokens.premium,
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
      // Nothing is lost, and something is not watched: worth reading.
      AlertKind.walletRefused => (
        LucideIcons.circleSlash,
        tokens.pending,
        tokens.pendingSurface,
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
