// Release updates: what the core says about a newer version, and when
// the app tells it that a session is open.
//
// The core decides all of it and keeps it in the vault: when it asks
// GitHub on its own (at most once a day, never within a day of the
// first session, and a day Tor is needed and not running does not
// count), which release is worth announcing (never a pre-release) and
// which one the user closed. The request takes the route the syncs
// take: with a .onion node configured it goes through Tor, and with Tor
// out of reach it does not go at all. The check of a session never
// starts the built-in Tor for itself, as the price widget does not: it
// waits for the one a sync or Live brought up, and the next return to
// the screen asks again. The app says when the wallets come on screen,
// never while it is locked or disguised, and shows what comes back.
// The About card can still ask on demand, and that one starts Tor.
//
// The page the notice opens is a constant of this file: nothing the
// network says can choose where the browser goes.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge.dart';
import 'disguise.dart';
import 'models.dart';
import 'state.dart';

/// Application version shown in About, and the one the core compares
/// releases with. The same as `version` in pubspec.yaml, which the
/// build stamps on the APK: a test fails the moment the two part, so a
/// release never announces itself to the people already running it.
const String appVersion = '0.1.0';

/// Where "View release" goes. The one place to change when the app is
/// listed on a store.
const String releasePageUrl =
    'https://github.com/gerfaut-wallet/gerfaut-mobile/releases/latest';

/// Where "Report a problem" goes: the issues of this repository.
const String issuesPageUrl =
    'https://github.com/gerfaut-wallet/gerfaut-mobile/issues';

/// Whether a version of this app is a beta: every 0.x version is, and
/// the label goes away by itself at 1.0.0.
bool isBetaVersion(String version) => version.startsWith('0.');

/// A debug build can be told a version is out, to see the notice
/// without publishing anything:
/// `--dart-define=GERFAUT_DEBUG_LATEST=9.9.9`. Read only in debug mode,
/// in place of asking the core, and named as it is written.
const String _debugLatest = String.fromEnvironment('GERFAUT_DEBUG_LATEST');

class UpdateState {
  const UpdateState({this.status = const UpdateStatus(), this.notice});

  /// What the core said last.
  final UpdateStatus status;

  /// The release the home card names; null when there is nothing to
  /// say. Taken from the core as the wallets came on screen: the card
  /// speaks of a release known before the session, never of one found
  /// during it, so nothing moves under a finger.
  final String? notice;

  /// The automatic check is on.
  bool get automatic => status.automatic;
}

class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  GerfautBridge get _bridge => ref.read(bridgeProvider);

  /// Reads what the core says, asking GitHub nothing. A core that does
  /// not answer leaves everything as it was.
  Future<void> load() async {
    try {
      final status = await _bridge.updateStatus(appVersion);
      state = UpdateState(status: status, notice: state.notice);
    } catch (_) {
      // Nothing read, nothing changed.
    }
  }

  /// The wallets just came on screen: at launch, after an unlock, or
  /// back from the background. A release already known is announced
  /// now; one the core finds now is announced the next time.
  ///
  /// Nothing while disguised: the notice names Gerfaut.
  Future<void> sessionStarted() async {
    final disguise = ref.read(disguiseProvider);
    if (!disguise.loaded || disguise.disguised) {
      state = UpdateState(status: state.status);
      return;
    }
    if (kDebugMode && _debugLatest.isNotEmpty) {
      state = UpdateState(status: state.status, notice: _debugLatest);
      return;
    }
    try {
      final known = await _bridge.updateStatus(appVersion);
      state = UpdateState(status: known, notice: known.announce);
      _follow(await _bridge.updateSession(appVersion));
    } catch (_) {
      // A core that did not answer: nothing more to say.
    }
  }

  /// Takes what the core says now. A notice already up follows the
  /// facts; none comes up mid-session.
  void _follow(UpdateStatus status) {
    state = UpdateState(
      status: status,
      notice: state.notice == null ? null : status.announce,
    );
  }

  /// The button in About: asks now, due or not, and gives back what the
  /// core says. A check that fails throws its [BridgeException], once
  /// what the core noted of it is read.
  Future<UpdateStatus> checkNow() async {
    try {
      final status = await _bridge.checkUpdate(appVersion);
      _follow(status);
      return status;
    } on BridgeException {
      await load();
      rethrow;
    }
  }

  void setAutomatic(bool on) {
    final status = state.status;
    state = UpdateState(
      status: UpdateStatus(
        automatic: on,
        announce: status.announce,
        available: status.available,
        torUnavailable: status.torUnavailable,
      ),
      notice: state.notice,
    );
    _bridge.setUpdateAutomatic(on).catchError((_) {}).whenComplete(load);
  }

  /// Closes the notice for the release it names, for good.
  void dismiss() {
    final version = state.notice;
    if (version == null) return;
    state = UpdateState(status: state.status);
    _bridge.dismissUpdate(version).catchError((_) {}).whenComplete(load);
  }
}

/// What the core says about newer releases.
final updateProvider = NotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);
