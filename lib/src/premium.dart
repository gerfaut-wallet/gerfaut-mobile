// Premium: the account key, what the server watches on its behalf, and
// the heartbeat that says the watch is alive.
//
// The key and the certificate live in the vault, through the core; the
// core also verifies every signed answer. What lives here is what the
// interface decides: when to ask the server again, how a key is typed,
// and when two missed heartbeats become a banner.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'disguise.dart';
import 'models.dart';
import 'notifications.dart';
import 'state.dart';

/// Where premium is bought and renewed. Opened in the browser, never
/// embedded: the app sells nothing.
const String premiumSiteUrl = 'https://gerfaut-wallet.com/premium';

/// The renewal form on that site, opened without the key.
///
/// A key in the address is a key written into the browser's history,
/// offered afterwards by whatever completes addresses, handed to every
/// redirect on the way and kept in the log of whatever serves the page.
/// This one is the only proof of purchase there is, and the account it
/// opens has nothing else standing in front of it. It travels by the
/// clipboard instead, which the app marks so the system does not
/// preview it, and the page asks for it. The fragment names the form
/// and never leaves the browser.
const String premiumRenewUrl = '$premiumSiteUrl#renew';

/// How long alerts keep going out after the paid time ends.
const int premiumGraceDays = 7;

// --- the account -------------------------------------------------------

/// The premium account as the vault keeps it. Invalidated after any
/// change to it; never a network call.
final premiumStateProvider = FutureProvider<PremiumView>((ref) {
  return ref.watch(bridgeProvider).premiumState();
});

/// This device as the server sees it: whether it has full access, and
/// until when it waits. Null without a key, and once the server has
/// disconnected it: nothing is asked then.
///
/// A connection whose answer was lost is sent again here first, as it
/// was, and so is a key kept by a version that had no devices yet, the
/// way a key typed in would be; the vault is read again for the token
/// it now holds. The core decides what may go: nothing while a rate
/// limit's wait runs, and never the key on its own once the server has
/// turned this device away.
final premiumMeProvider = FutureProvider<PremiumDevice?>((ref) async {
  final state = await ref.watch(premiumStateProvider.future);
  final bridge = ref.watch(bridgeProvider);
  final unconnected =
      state.hasKey && !state.disconnected && state.device == null;
  if (state.connectPending || unconnected) {
    final connected = await bridge.premiumEnsureDevice();
    if (connected != null) {
      // Off this build: the state it watches has just changed under it.
      Future.microtask(() => ref.invalidate(premiumStateProvider));
      return connected;
    }
  }
  if (!state.hasKey || state.disconnected) return null;
  return bridge.premiumDevice();
});

/// [me] as the screens may show it: only while it is the device the
/// vault is connected as. An answer read before a logout, a key entered
/// again or another key says nothing of this connection, and stands for
/// nothing while the next one is read.
PremiumDevice? currentDevice(PremiumView view, PremiumDevice? me) {
  final link = view.device;
  if (me == null || link == null || view.disconnected) return null;
  return me.id == link.id ? me : null;
}

/// Whether this device sees the account: everything past the licence
/// waits on it, so a device still waiting asks the server for nothing
/// it would refuse.
final premiumFullAccessProvider = FutureProvider<bool>((ref) async {
  final me = await ref.watch(premiumMeProvider.future);
  return me?.fullAccess ?? false;
});

/// The server's view of the account: paid time, counts, and the network
/// it watches. Null without a key, so nothing is asked before one is
/// entered, and null on a device that waits for approval.
final premiumAccountProvider = FutureProvider<PremiumAccount?>((ref) async {
  if (!await ref.watch(premiumFullAccessProvider.future)) return null;
  return ref.watch(bridgeProvider).premiumAccount();
});

/// This device's connection to the account, as the vault holds it: the
/// key, and the id the server knows this device by. What the server
/// says about devices holds for one connection, and for no other.
typedef PremiumConnection = ({String key, String device});

/// The connection [view] holds; null without a key, without a device,
/// and once the server has disconnected it.
PremiumConnection? premiumConnection(PremiumView? view) {
  final key = view?.key;
  final device = view?.device;
  if (view == null || key == null || device == null || view.disconnected) {
    return null;
  }
  return (key: key, device: device.id);
}

/// The account's devices as the server listed them, oldest first, with
/// the connection they were read with.
class DeviceList {
  const DeviceList(this.connection, this.devices);

  final PremiumConnection? connection;
  final List<PremiumDevice> devices;
}

/// Every device of the account, oldest first. Empty unless this one
/// has full access: only such a device may see the others.
final premiumDevicesProvider = FutureProvider<DeviceList>((ref) async {
  final connection = premiumConnection(
    await ref.watch(premiumStateProvider.future),
  );
  if (connection == null ||
      !await ref.watch(premiumFullAccessProvider.future)) {
    return DeviceList(connection, const []);
  }
  final devices = await ref.watch(bridgeProvider).premiumDevices();
  return DeviceList(connection, devices);
});

/// The account's devices for the connection the vault holds now; null
/// until a list was read with it.
///
/// A list read before the key was forgotten, changed, or replaced by
/// another one is a list of devices this connection may not have: the
/// server disconnected them with the old key, or they belong to another
/// account. It is never shown, nor announced, while the next one loads.
final accountDevicesProvider = Provider<List<PremiumDevice>?>((ref) {
  final connection = premiumConnection(
    ref.watch(premiumStateProvider).valueOrNull,
  );
  final list = ref.watch(premiumDevicesProvider).valueOrNull;
  if (connection == null || list == null || list.connection != connection) {
    return null;
  }
  return list.devices;
});

/// The other devices that wait for approval, from the last list read.
/// What the red banner of the home screen is about.
///
/// Only on a device connected with full access, and never from a list
/// the server has since disowned, or one read under another connection:
/// a device disconnected, waiting again behind a changed key, or moved
/// to another account has no business raising the banner.
final waitingDevicesProvider = Provider<List<PremiumDevice>>((ref) {
  if (!(ref.watch(premiumFullAccessProvider).valueOrNull ?? false)) {
    return const [];
  }
  if (_turnedAway(ref.watch(premiumDevicesProvider).error)) return const [];
  return [
    for (final device in ref.watch(accountDevicesProvider) ?? const [])
      if (!device.fullAccess && !device.thisDevice) device,
  ];
});

/// What asking about this device answers when the server turned it
/// away: its token disowned, the kept key no longer known, or every
/// device the key takes already there. The core has written it to the
/// vault, and reading the vault again shows it.
const Set<String> disownedKinds = {
  'premium_device_disconnected',
  'premium_unknown_key',
  'premium_too_many_devices',
};

/// A failure that says this device no longer sees the account, as
/// opposed to a server out of reach, which says nothing about it.
bool _turnedAway(Object? error) =>
    error is BridgeException &&
    const {
      'premium_device_disconnected',
      'premium_device_pending',
      'premium_no_device',
      'premium_unknown_key',
    }.contains(error.kind);

/// The wallets of this vault the server could watch: those on its
/// network, whichever network the workspace shows. Empty without a key,
/// or while the server's network is not known. Refreshed with the
/// wallet list, so a rename or a removal reaches the rows.
final premiumCandidatesProvider = FutureProvider<List<WalletMeta>>((ref) async {
  ref.watch(walletsProvider);
  final account = await ref.watch(premiumAccountProvider.future);
  final chain = account?.chain;
  if (chain == null) return const [];
  return ref.watch(bridgeProvider).listWallets(chain);
});

/// The wallets the server watches for this key. Empty without a key,
/// and on a device that waits for approval.
final premiumWalletsProvider = FutureProvider<List<WalletWatch>>((ref) async {
  if (!await ref.watch(premiumFullAccessProvider.future)) return const [];
  return ref.watch(bridgeProvider).premiumWallets();
});

/// The account's channels. Empty without a key, and on a device that
/// waits for approval.
final premiumChannelsProvider = FutureProvider<List<PremiumChannel>>((
  ref,
) async {
  if (!await ref.watch(premiumFullAccessProvider.future)) return const [];
  return ref.watch(bridgeProvider).premiumChannels();
});

/// The last events of the account, newest first, each id once: the
/// server may hand the same event twice across two machines, and a
/// doubled line would read as two alerts.
final premiumEventsProvider = FutureProvider<List<PremiumEvent>>((ref) async {
  if (!await ref.watch(premiumFullAccessProvider.future)) return const [];
  final events = await ref.watch(bridgeProvider).premiumRecentEvents();
  final seen = <int>{};
  return [
    for (final event in events)
      if (seen.add(event.id)) event,
  ];
});

/// Forgets everything read from the server, after something changed it.
void invalidatePremium(WidgetRef ref) {
  ref.invalidate(premiumStateProvider);
  ref.invalidate(premiumMeProvider);
  ref.invalidate(premiumDevicesProvider);
  ref.invalidate(premiumAccountProvider);
  ref.invalidate(premiumCandidatesProvider);
  ref.invalidate(premiumWalletsProvider);
  ref.invalidate(premiumChannelsProvider);
  ref.invalidate(premiumEventsProvider);
}

/// Where a channel's ntfy topic is kept in the vault, by channel id: the
/// server masks it afterwards, and the subscribe link has to be
/// reachable again after leaving the page.
String ntfyTopicPref(String channelId) => 'premium.ntfy.$channelId';

/// Digits in the code the server mails to an address before it ever
/// writes to it. Mirrors the server, which draws six.
const int confirmationCodeLength = 6;

/// What happened to a channel the server turned off, and the way back.
///
/// Only a webhook goes this way today — one written to a private or
/// local address, which the server refuses to post to and disables
/// rather than keep trying — but the flag belongs to every kind, so
/// every kind has a sentence rather than a silence. The same words as
/// the desktop app's.
String offReason(PremiumChannel channel) => switch (channel.kind) {
  ChannelKind.webhook =>
    'This webhook points at an address that is not reachable from the '
        'internet, so nothing is delivered to it. Point it at a public '
        'address and add it again.',
  _ =>
    'The server turned this channel off, so nothing is delivered to it. '
        'Remove it and add it again.',
};

// --- the key -------------------------------------------------------------

/// The thirty-two symbols a key is drawn from: no `l`, `o`, `0` or `1`,
/// nothing to misread from a screen. Mirrors the core, which judges the
/// key again before anything is sent.
const String keyAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

/// Symbols in a key, dashes not counted.
const int keySymbols = 16;

/// Lowercase, dashes and spaces dropped: what was typed, made canonical.
String normalizeKey(String raw) =>
    raw.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();

/// `abcd-efgh-ijkm-npqr`, as far as the typing has gone.
String formatKey(String raw) {
  final compact = normalizeKey(raw);
  final groups = <String>[];
  for (var i = 0; i < compact.length; i += 4) {
    groups.add(
      compact.substring(i, i + 4 > compact.length ? compact.length : i + 4),
    );
  }
  return groups.join('-');
}

/// Whether a typed key has the shape of one; not whether it exists.
bool isWellFormedKey(String raw) {
  final compact = normalizeKey(raw);
  return compact.length == keySymbols &&
      compact.codeUnits.every((c) => keyAlphabet.codeUnits.contains(c));
}

/// The symbols of a typed key the alphabet leaves out, `l` and `0` and
/// their kin: the one mistake a screen makes, and the one worth saying.
Set<String> keyStrangers(String raw) {
  final compact = normalizeKey(raw);
  return {
    for (final unit in compact.codeUnits)
      if (!keyAlphabet.codeUnits.contains(unit)) String.fromCharCode(unit),
  };
}

/// Types the key the way it is shown: lowercase, a dash after every
/// four symbols, sixteen symbols at most. Pasting works with or without
/// dashes, in any case; the caret stays with the symbol it was after.
class AccountKeyFormatter extends TextInputFormatter {
  const AccountKeyFormatter();

  static final RegExp _symbol = RegExp(r'[a-z0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toLowerCase();
    // Symbols before the caret, so it can be put back after the same one.
    final caret = newValue.selection.baseOffset.clamp(0, text.length);
    var symbolsBeforeCaret = 0;
    final symbols = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (!_symbol.hasMatch(char)) continue;
      if (symbols.length >= keySymbols) break;
      symbols.write(char);
      if (i < caret) symbolsBeforeCaret++;
    }
    final formatted = formatKey(symbols.toString());
    // A dash before every group but the first.
    final groupsBeforeCaret = symbolsBeforeCaret == 0
        ? 0
        : (symbolsBeforeCaret - 1) ~/ 4;
    final offset = (symbolsBeforeCaret + groupsBeforeCaret).clamp(
      0,
      formatted.length,
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

// --- what the screens say ------------------------------------------------

/// The sentence of a licence at the root of the settings and on the
/// card: where the paid time stands, in the words of the state.
enum LicenceStatus { none, active, expired }

LicenceStatus licenceStatus(PremiumView? state, {int? nowUnix}) {
  final claims = state?.claims;
  if (state == null || !state.hasKey || claims == null) {
    return LicenceStatus.none;
  }
  final now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return claims.isActive(now) ? LicenceStatus.active : LicenceStatus.expired;
}

/// What an event says on its line, after the wallet's name.
String alertPhrase(PremiumEvent event) {
  return switch (event.kind) {
    AlertKind.spendDetected => 'coins are moving',
    AlertKind.spendConfirmed => 'a spend was confirmed',
    AlertKind.coinsGone => 'coins are gone',
    AlertKind.receiveDetected => 'a payment is coming in',
    AlertKind.receiveConfirmed => 'a payment was confirmed',
    AlertKind.timelockDue => switch (event.data['milestone']) {
      'open' => 'a timelock is open',
      '1d' => 'a timelock opens within a day',
      '7d' => 'a timelock opens within a week',
      _ => 'a timelock opens within a month',
    },
    AlertKind.walletRegistered => 'now watched by the server',
    // The server's own sentence when the event carries one.
    AlertKind.walletRefused => switch (event.data['message']) {
      final String words when words.trim().isNotEmpty =>
        'refused by the server: ${words.trim()}',
      _ => 'refused by the server',
    },
    AlertKind.other => 'something happened',
  };
}

// --- what a failure says --------------------------------------------------

/// The cases a premium card knows how to talk about.
///
/// One per sentence worth writing, and [other] for everything else that
/// can reach a premium card — the vault, a wallet that moved, a bridge
/// that was never started. Nothing falls through: [other] has a
/// sentence of its own, and the machine's words go under it rather than
/// in front of the person reading.
enum PremiumFailureKind {
  unreachable,
  refused,
  rateLimited,
  unknownKey,
  noPaidTime,
  noKey,
  invalid,
  devicePending,
  deviceDisconnected,
  tooManyDevices,
  noDevice,
  keyChangePending,
  tor,
  other,
}

/// Which case a bridge failure falls in. The kinds are [premiumErrorKinds]
/// plus `tor`, which reaches these calls because they take the same route
/// the backend does.
PremiumFailureKind premiumFailureKind(String kind) => switch (kind) {
  'premium_unreachable' => PremiumFailureKind.unreachable,
  'premium_rejected' => PremiumFailureKind.refused,
  'premium_rate_limited' => PremiumFailureKind.rateLimited,
  'premium_unknown_key' => PremiumFailureKind.unknownKey,
  'premium_no_paid_time' => PremiumFailureKind.noPaidTime,
  'premium_no_key' => PremiumFailureKind.noKey,
  'premium_invalid' => PremiumFailureKind.invalid,
  'premium_device_pending' => PremiumFailureKind.devicePending,
  'premium_device_disconnected' => PremiumFailureKind.deviceDisconnected,
  'premium_too_many_devices' => PremiumFailureKind.tooManyDevices,
  'premium_no_device' => PremiumFailureKind.noDevice,
  'premium_key_change_pending' => PremiumFailureKind.keyChangePending,
  'tor' => PremiumFailureKind.tor,
  _ => PremiumFailureKind.other,
};

/// What a failed premium call reads as under the card it concerns.
class PremiumFailure {
  const PremiumFailure(
    this.message, {
    this.hint,
    this.detail,
    this.retry = false,
  });

  /// The first line, and always the app's own words: never a status
  /// code, never a parser's complaint.
  final String message;

  /// What to do about it, quieter under the message.
  final String? hint;

  /// The other side's own sentence, verbatim. Takes the place of [hint].
  final String? detail;

  /// Whether asking the same thing again could work.
  final bool retry;
}

/// A 5xx carries the server's own sentence: it answered, it just could
/// not do the thing — the confirmation e-mail that would not send, say.
/// The core wraps its errors ("the premium server is unreachable: HTTP
/// 502: ..."), so this is not anchored to the start of the message; an
/// anchored match never fires and quietly turns every such answer into
/// an outage.
final RegExp _statusWords = RegExp(r'HTTP \d{3}: (.+)$');

/// What went wrong, in words fit for a card: one sentence, a quieter
/// second line when there is something to do about it or something the
/// other side said, and whether offering "Retry" makes sense.
///
/// [refusal] takes the place of the first line when the server refused
/// what this screen asked. The server's words name the case — a code
/// that is wrong, an address it already has — but not the step they are
/// about, and a page that asked for one thing should say which.
PremiumFailure premiumFailure(BridgeException error, {String? refusal}) {
  return switch (premiumFailureKind(error.kind)) {
    PremiumFailureKind.unreachable => PremiumFailure(
      _serverSentence(error.message) ?? 'Could not reach the Gerfaut server.',
      retry: true,
    ),
    PremiumFailureKind.refused => PremiumFailure(
      refusal ?? 'The Gerfaut server refused.',
      detail: error.message,
    ),
    // Nothing is wrong with what was asked: the server wants a pause,
    // and says how long when it knows. Word for word what the desktop
    // app says.
    PremiumFailureKind.rateLimited => PremiumFailure(switch (error.retryAfter) {
      final int seconds => 'The server asks to wait. Try again in $seconds s.',
      null => 'The server asks to wait. Try again in a moment.',
    }, retry: true),
    PremiumFailureKind.unknownKey => const PremiumFailure(
      'Unknown key.',
      hint: 'Check it against the key shown at purchase.',
    ),
    PremiumFailureKind.noPaidTime => const PremiumFailure(
      'This key has no paid time.',
      hint: 'Add time on gerfaut-wallet.com, then try again.',
    ),
    PremiumFailureKind.noKey => const PremiumFailure(
      'Enter an account key first.',
    ),
    // A certificate, a heartbeat, a clock too far off: this device
    // cannot trust what it was handed. The clock is the one of the
    // three a person can do anything about.
    PremiumFailureKind.invalid => const PremiumFailure(
      "The server's answer did not check out.",
      hint: "Check this phone's date and time, then try again.",
      retry: true,
    ),
    // The server's own sentences, shown as they are: they say what the
    // device can do about it, and the desktop app shows the same.
    PremiumFailureKind.devicePending => const PremiumFailure(
      'This device is waiting for approval: approve it on another of your '
      'devices, or wait until it gets full access.',
    ),
    PremiumFailureKind.deviceDisconnected => const PremiumFailure(
      'This device was disconnected from the Premium account.',
    ),
    PremiumFailureKind.tooManyDevices => PremiumFailure(
      _sentence(error.message) ??
          'This key already has 10 devices; disconnect one from a device '
              'with full access.',
    ),
    PremiumFailureKind.noDevice => const PremiumFailure(
      'Connect this device with the Premium key first.',
    ),
    // Logging out, or entering another key, would lose the new key a
    // change drew: the server may hold it already, and nothing else does.
    PremiumFailureKind.keyChangePending => const PremiumFailure(
      keyChangePendingMessage,
    ),
    // The call goes through Tor whenever the backend of the active
    // network does, and nothing falls back to the clear: a Tor that
    // cannot be reached is a call that never happened. The core's own
    // sentence names the proxy it wanted, which is not what a person
    // reading this card can act on.
    PremiumFailureKind.tor => const PremiumFailure(
      'Tor is not available on this phone.',
      hint:
          'These calls go through Tor and never around it. The Tor card '
          'is under Network.',
      retry: true,
    ),
    PremiumFailureKind.other => PremiumFailure(
      'That did not go through.',
      detail: error.message,
      retry: true,
    ),
  };
}

/// The sentence a failing status carried, capitalized and stopped, or
/// null when the answer held none — then the server is simply out of
/// reach, and saying more would be inventing it.
String? _serverSentence(String message) {
  final match = _statusWords.firstMatch(message);
  if (match == null) return null;
  return _sentence(match.group(1)!);
}

/// The server's words as a sentence of the page: capitalized and
/// stopped, nothing else changed. Null when there are none.
String? _sentence(String words) {
  final trimmed = words.trim();
  if (trimmed.isEmpty) return null;
  final capital = trimmed[0].toUpperCase() + trimmed.substring(1);
  return RegExp(r'[.!?]$').hasMatch(capital) ? capital : '$capital.';
}

// --- devices -------------------------------------------------------------

/// What the licence says while a key change waits for its answer.
const String keyChangePendingMessage =
    'The key change did not finish. Try again to complete it.';

/// What the note under the licence says of a device the server
/// disconnected: the server's own sentence when it gave one, the key
/// having every device it takes, and the app's words otherwise. The
/// desktop app says the same.
String disconnectedWords(String? reason) {
  final words = reason == null ? null : _sentence(reason);
  return words ?? 'This device was disconnected from your Premium account.';
}

/// How long a new device waits without approval. Mirrors the server,
/// which decides it.
const int pendingDays = 10;

/// Whole days a waiting device has left, counting the one under way:
/// a device due tomorrow morning has one day left, never zero.
int waitingDaysLeft(PremiumDevice device, {int? nowUnix}) {
  final until = device.pendingUntil;
  if (until == null) return 0;
  final now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final seconds = until - now;
  if (seconds <= 0) return 1;
  return (seconds + 86399) ~/ 86400;
}

/// The state of a waiting device on its row.
String waitingLabel(PremiumDevice device, {int? nowUnix}) {
  final days = waitingDaysLeft(device, nowUnix: nowUnix);
  return 'Waiting · $days ${days == 1 ? 'day' : 'days'} left';
}

/// How often the device list is read again while the app is open, for
/// a device that connected meanwhile.
const Duration deviceCheckPeriod = Duration(minutes: 5);

/// What a notification says about a device that waits for approval.
TxNotice deviceNotice(PremiumDevice device, {required bool locked}) {
  return TxNotice(
    id: noticeId('device:${device.id}'),
    // Under an app lock the generic form every notification takes
    // there: the app's name, and what happened without the particulars.
    // The desktop app's words.
    title: locked ? lockedTitle : 'Gerfaut Premium: new device',
    body: locked
        ? 'A new device asks for access. Open Gerfaut to approve or refuse it.'
        : 'A new ${device.label} asks for access to your Premium account. '
              'Open Gerfaut to approve or refuse it.',
  );
}

/// Keeps an eye on the account's devices while the app is open, on a
/// device with full access: when it opens, when it comes back to the
/// front, and every five minutes in between. A device that waits for
/// approval raises the red banner of the home screen, and one
/// notification of its own, once: the core keeps which ones were
/// announced and hands each out a single time, so neither a restart
/// nor two readers at once say anything twice.
///
/// On a device that waits itself, the same rhythm asks the server
/// where it stands, so that it opens on the whole account by itself
/// once approved, or once its wait is over.
///
/// Whoever reads the list — this watch, the banner, the Devices card —
/// feeds the announcement, so a device seen anywhere is announced.
class DeviceWatch extends Notifier<void> {
  Timer? _timer;

  /// While this device waits: asks the server where it stands.
  Timer? _waitTimer;
  bool _checking = false;

  @override
  void build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _waitTimer?.cancel();
      _waitTimer = null;
    });
    ref.listen(premiumMeProvider, (_, next) {
      final me = next.valueOrNull;
      if (me != null && !me.fullAccess && !next.hasError) {
        _waitTimer ??= Timer.periodic(deviceCheckPeriod, (_) => _askMe());
      } else if (!next.isLoading) {
        _waitTimer?.cancel();
        _waitTimer = null;
      }
      // Turned away while nobody looked: the core dropped the token, or
      // found every device the key takes, and the vault read again says
      // so everywhere, the settings row included.
      final error = next.error;
      if (!next.isLoading &&
          error is BridgeException &&
          disownedKinds.contains(error.kind)) {
        ref.invalidate(premiumStateProvider);
      }
    }, fireImmediately: true);
    // Listened to, not watched: nothing listens to this watch itself,
    // and a provider nobody listens to is not rebuilt when what it
    // watches changes. A subscription keeps both answers coming.
    ref.listen(premiumFullAccessProvider, (_, next) {
      if (next.valueOrNull ?? false) {
        _timer ??= Timer.periodic(deviceCheckPeriod, (_) => check());
      } else if (!next.isLoading) {
        _timer?.cancel();
        _timer = null;
      }
    }, fireImmediately: true);
    // Listening is what reads the list the first time: the check at
    // opening. Every list after it, whoever asked, passes here too.
    ref.listen(premiumDevicesProvider, (_, next) {
      final list = next.valueOrNull;
      if (list == null || next.isLoading || !_full) return;
      // A list read under a connection this device no longer holds
      // announces nothing: its devices are not this account's news.
      final now = premiumConnection(ref.read(premiumStateProvider).valueOrNull);
      if (now == null || list.connection != now) return;
      unawaited(_announce(list.devices));
    }, fireImmediately: true);
    // The logouts the server could not be told of go at the start.
    Future.microtask(flushLogouts);
  }

  bool get _full => ref.read(premiumFullAccessProvider).valueOrNull ?? false;

  /// Tells the server about the connections this device left while it
  /// could not be reached: the core holds their tokens, and asks nothing
  /// when it holds none. What still cannot go waits for the next start,
  /// return or heartbeat.
  Future<void> flushLogouts() async {
    try {
      await ref.read(bridgeProvider).premiumFlushLogouts();
    } catch (_) {
      // Out of reach: the tokens stay queued in the vault.
    }
  }

  /// This device waits for approval.
  bool get _waiting {
    final me = ref.read(premiumMeProvider).valueOrNull;
    return me != null && !me.fullAccess;
  }

  /// Asks the server again where this waiting device stands.
  void _askMe() => ref.invalidate(premiumMeProvider);

  /// Reads the list again, now.
  Future<void> check() async {
    if (_checking || !_full) return;
    _checking = true;
    try {
      ref.invalidate(premiumDevicesProvider);
      await ref.read(premiumDevicesProvider.future);
    } on BridgeException catch (error) {
      switch (error.kind) {
        // The server no longer takes this device's token: the core
        // dropped it, and the vault says so.
        case 'premium_device_disconnected':
          ref.invalidate(premiumStateProvider);
        // The key was changed elsewhere and this device came back as a
        // new one, or its access is not what it was.
        case 'premium_device_pending':
          ref.invalidate(premiumMeProvider);
      }
    } catch (_) {
      // Out of reach: the next check tries again.
    } finally {
      _checking = false;
    }
  }

  /// The app is back in front: the list is read again. Only a real
  /// return counts, from another app or from the phone's lock; the
  /// notification shade pulled down over Gerfaut is not one.
  ///
  /// A connection whose answer was lost is sent again then too, and the
  /// logouts still owed to the server are told.
  void resume() {
    final state = ref.read(premiumStateProvider).valueOrNull;
    if (_waiting || (state?.connectPending ?? false)) {
      _askMe();
    } else {
      unawaited(check());
    }
    unawaited(flushLogouts());
  }

  Future<void> _announce(List<PremiumDevice> devices) async {
    final waiting = [
      for (final device in devices)
        if (!device.fullAccess && !device.thisDevice) device,
    ];
    final List<String> fresh;
    try {
      // Handed the whole waiting list, the core keeps it and gives
      // back the devices it had not seen: an empty list clears it.
      fresh = await ref.read(bridgeProvider).premiumMarkAnnounced([
        for (final device in waiting) device.id,
      ]);
    } catch (_) {
      // Nothing was taken: the next list asks again.
      return;
    }
    if (fresh.isEmpty) return;
    // Posted only while the app's notifications are on, and never while
    // disguised: a notification's header carries the app's name. The
    // banner says it inside the app either way, and the device counts
    // as announced all the same.
    if (!ref.read(notifyNewTxProvider)) return;
    if (ref.read(disguiseProvider).disguised) return;
    // Settings not read yet say nothing of a lock: said as if there
    // were one.
    final settings = ref.read(settingsProvider).valueOrNull;
    final locked = settings == null || notifiesLocked(settings);
    final service = ref.read(notificationServiceProvider);
    for (final device in waiting) {
      if (!fresh.contains(device.id)) continue;
      final notice = deviceNotice(device, locked: locked);
      try {
        await service.show(notice.id, notice.title, notice.body);
      } catch (_) {
        // A notification the system will not post is not a failed
        // check: the banner is still there.
      }
    }
  }
}

final deviceWatchProvider = NotifierProvider<DeviceWatch, void>(
  DeviceWatch.new,
);

// --- the heartbeat -------------------------------------------------------

/// How often the server is asked whether it is alive, while a wallet is
/// watched.
const Duration heartbeatPeriod = Duration(minutes: 15);

/// Missed beats in a row before the banner shows. One says nothing: a
/// phone in a tunnel misses one too.
const int heartbeatFailuresForBanner = 2;

/// How long a dismissed banner stays down while the outage goes on.
const Duration offlineAcknowledgement = Duration(hours: 24);

/// Where the watch stands, as the last heartbeats told it.
class WatchStatus {
  const WatchStatus({this.failures = 0, this.offlineSince, this.lastVerified});

  /// Heartbeats missed in a row.
  final int failures;

  /// Unix seconds of the first missed beat of this run; null while the
  /// server answers.
  final int? offlineSince;

  /// Unix seconds of the last verified beat; null before the first.
  final int? lastVerified;

  /// Two beats missed in a row: the banner's condition.
  bool get offline => failures >= heartbeatFailuresForBanner;
}

/// Whether the banner shows: the watch is offline, and the user has not
/// dismissed it for the time being.
bool watchBannerShows(
  WatchStatus status,
  PremiumView? premium, {
  int? nowUnix,
}) {
  if (!status.offline) return false;
  final until = premium?.acknowledgedOfflineUntil;
  if (until == null) return true;
  final now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return now >= until;
}

/// Asks the server for its signed heartbeat when the app opens and every
/// fifteen minutes after, for as long as a key is set and a wallet was
/// handed over. The core verifies the signature and the clock; anything
/// short of a fresh, genuine beat counts as missed. Two missed in a row
/// is the banner; one verified beat clears it, and lifts a dismissal so
/// the next outage shows again.
class WatchMonitor extends Notifier<WatchStatus> {
  Timer? _timer;
  bool _checking = false;
  int? _lastCheckAt;
  WatchStatus _status = const WatchStatus();

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  WatchStatus build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    final premium = ref.watch(premiumStateProvider).valueOrNull;
    final active =
        premium != null && premium.hasKey && premium.watched.isNotEmpty;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return _status;
    }
    _timer ??= Timer.periodic(heartbeatPeriod, (_) => check());
    // At once on the first sight of a watched wallet, then on the
    // period; off the build itself, which must not move state.
    if (_due) Future.microtask(check);
    return _status;
  }

  bool get _due {
    final last = _lastCheckAt;
    return last == null || _now() - last >= heartbeatPeriod.inSeconds;
  }

  bool get _active {
    final premium = ref.read(premiumStateProvider).valueOrNull;
    return premium != null && premium.hasKey && premium.watched.isNotEmpty;
  }

  /// One heartbeat, now. A connection whose answer was lost goes again
  /// with it, through [premiumMeProvider]: the pulse is one of the
  /// occasions it gets, with the start and the return to the front.
  Future<void> check() async {
    if (_checking || !_active) return;
    _checking = true;
    _lastCheckAt = _now();
    if (ref.read(premiumStateProvider).valueOrNull?.connectPending ?? false) {
      ref.invalidate(premiumMeProvider);
    }
    final bridge = ref.read(bridgeProvider);
    try {
      await bridge.premiumHeartbeat();
      _status = WatchStatus(failures: 0, lastVerified: _now());
      // The server is back: a dismissal made during the outage has
      // done its job, and the next one has to show again.
      final premium = ref.read(premiumStateProvider).valueOrNull;
      if (premium?.acknowledgedOfflineUntil != null) {
        await bridge.premiumAcknowledgeOffline(null);
        ref.invalidate(premiumStateProvider);
      }
    } catch (_) {
      _status = WatchStatus(
        failures: _status.failures + 1,
        offlineSince: _status.offlineSince ?? _now(),
        lastVerified: _status.lastVerified,
      );
    } finally {
      _checking = false;
      state = _status;
    }
  }

  /// The app is back in front: a beat is asked if the last one is older
  /// than the period, since timers sleep with the app.
  void resume() {
    if (_active && _due) check();
  }

  /// Puts the banner down for a day of this outage. Stored in the
  /// vault, so a restart does not bring it back.
  Future<void> acknowledge() async {
    final until = _now() + offlineAcknowledgement.inSeconds;
    await ref.read(bridgeProvider).premiumAcknowledgeOffline(until);
    ref.invalidate(premiumStateProvider);
  }
}

final watchMonitorProvider = NotifierProvider<WatchMonitor, WatchStatus>(
  WatchMonitor.new,
);
