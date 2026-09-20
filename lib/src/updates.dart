// Release updates: what the app knows about a newer version, when it
// asks, and whether it says so.
//
// The core asks GitHub for the latest release, by the route the syncs
// take: with a .onion node configured the request goes through Tor, and
// with Tor out of reach it does not go at all. The automatic check runs
// at most once a day, not on the day of the first launch, and never
// while the app is disguised. The About card can still ask on demand.
//
// What comes back is text from the network. Only a version that parses
// as strict semver is ever kept or shown, rebuilt from its numbers, and
// the page the notice opens is a constant of this file: nothing the
// network says can choose where the browser goes.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'disguise.dart';
import 'models.dart';
import 'state.dart';

/// Application version shown in About. Kept in step with pubspec.yaml.
const String appVersion = '0.1.0';

/// Where "View release" goes. The one place to change when the app is
/// listed on a store.
const String releasePageUrl =
    'https://github.com/gerfaut-wallet/gerfaut-mobile/releases/latest';

/// Seconds between two automatic checks.
const int updateCheckPeriod = 24 * 60 * 60;

/// A debug build can be told a version is out, to see the notice
/// without publishing anything:
/// `--dart-define=GERFAUT_DEBUG_LATEST=v9.9.9`. Read only in debug
/// mode, in place of the request, and through the same parser as an
/// answer from the network.
const String _debugLatest = String.fromEnvironment('GERFAUT_DEBUG_LATEST');

/// A semantic version (semver.org, 2.0.0), parsed strictly.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(
    this.major,
    this.minor,
    this.patch, [
    this.preRelease = const [],
  ]);

  final int major;
  final int minor;
  final int patch;

  /// Dot-separated pre-release identifiers; empty for a stable version.
  final List<String> preRelease;

  bool get isStable => preRelease.isEmpty;

  static const int _maxLength = 64;
  static const String _number = r'(0|[1-9]\d{0,5})';
  static const String _preId = r'(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)';
  static final RegExp _pattern = RegExp(
    '^[vV]?$_number\\.$_number\\.$_number'
    '(?:-($_preId(?:\\.$_preId)*))?'
    r'(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$',
  );

  /// Reads `1.2.3`, `v1.2.3`, `1.2.3-rc.1`, `1.2.3+build`. Null for
  /// anything else: a tag that is not a version announces nothing.
  static ReleaseVersion? tryParse(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > _maxLength) return null;
    final match = _pattern.firstMatch(trimmed);
    if (match == null) return null;
    return ReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4)?.split('.') ?? const [],
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final (mine, theirs) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (mine != theirs) return mine.compareTo(theirs);
    }
    // A pre-release comes before the version it prepares.
    if (isStable || other.isStable) {
      if (isStable == other.isStable) return 0;
      return isStable ? 1 : -1;
    }
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final order = _compareIdentifiers(preRelease[i], other.preRelease[i]);
      if (order != 0) return order;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  /// Numeric identifiers compare as numbers and sort before the others,
  /// which compare as ASCII text. Numbers are compared by length first,
  /// so one of any size never overflows.
  static int _compareIdentifiers(String a, String b) {
    final digits = RegExp(r'^\d+$');
    final aNumeric = digits.hasMatch(a);
    final bNumeric = digits.hasMatch(b);
    if (aNumeric && bNumeric) {
      if (a.length != b.length) return a.length.compareTo(b.length);
      return a.compareTo(b);
    }
    if (aNumeric != bNumeric) return aNumeric ? -1 : 1;
    return a.compareTo(b);
  }

  bool operator >(ReleaseVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));

  /// The version rebuilt from what was parsed, without the `v` and the
  /// build metadata: the only form that is stored or shown.
  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return isStable ? core : '$core-${preRelease.join('.')}';
  }
}

/// The version a release check announces, or null when it announces
/// nothing: an unreadable tag, a pre-release, or a version that is not
/// newer than [current].
ReleaseVersion? announcedVersion(
  String? latest, {
  String current = appVersion,
}) {
  final version = ReleaseVersion.tryParse(latest);
  final running = ReleaseVersion.tryParse(current);
  if (version == null || running == null) return null;
  if (!version.isStable || !(version > running)) return null;
  return version;
}

class UpdateState {
  const UpdateState({
    this.automatic = true,
    this.latest,
    this.announced,
    this.dismissed,
    this.checkedAt,
  });

  /// The automatic check is on.
  final bool automatic;

  /// The newest stable release the last answered check reported.
  final ReleaseVersion? latest;

  /// What [latest] was when the wallets last came on screen: the notice
  /// speaks of a release known before the session, never of one found
  /// during it, so nothing moves under a finger.
  final ReleaseVersion? announced;

  /// The release the notice was last closed on.
  final ReleaseVersion? dismissed;

  /// Unix seconds of the last automatic check, answered or not.
  final int? checkedAt;

  /// The release the notice names; null when there is nothing to say.
  ReleaseVersion? get notice {
    final version = announced;
    final running = ReleaseVersion.tryParse(appVersion);
    if (version == null || running == null || !(version > running)) {
      return null;
    }
    final closed = dismissed;
    if (closed != null && !(version > closed)) return null;
    return version;
  }

  static const Object _keep = Object();

  UpdateState copyWith({
    bool? automatic,
    Object? latest = _keep,
    Object? announced = _keep,
    ReleaseVersion? dismissed,
    int? checkedAt,
  }) {
    return UpdateState(
      automatic: automatic ?? this.automatic,
      latest: identical(latest, _keep)
          ? this.latest
          : latest as ReleaseVersion?,
      announced: identical(announced, _keep)
          ? this.announced
          : announced as ReleaseVersion?,
      dismissed: dismissed ?? this.dismissed,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }
}

/// This device's clock, in unix seconds. A provider so a test can move
/// it.
final updateClockProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
);

class UpdateController extends Notifier<UpdateState> {
  bool _checking = false;

  @override
  UpdateState build() => const UpdateState();

  void hydrate(Map<String, String> prefs) {
    state = UpdateState(
      // Only an explicit "0" turns it off.
      automatic: prefs['updates.auto'] != '0',
      latest: _stable(prefs['updates.latest']),
      dismissed: ReleaseVersion.tryParse(prefs['updates.dismissed']),
      checkedAt: int.tryParse(prefs['updates.checked_at'] ?? ''),
    );
  }

  static ReleaseVersion? _stable(String? text) {
    final version = ReleaseVersion.tryParse(text);
    return version != null && version.isStable ? version : null;
  }

  void setAutomatic(bool on) {
    state = state.copyWith(automatic: on);
    _store('updates.auto', on ? '1' : '0');
  }

  /// The wallets just came on screen: at launch, after an unlock, or
  /// back from the background. A release already known is announced
  /// now; one this check finds is announced the next time.
  ///
  /// Nothing while disguised: the notice names Gerfaut.
  Future<void> sessionStarted() async {
    final disguise = ref.read(disguiseProvider);
    if (!disguise.loaded || disguise.disguised) {
      state = state.copyWith(announced: null);
      return;
    }
    state = state.copyWith(announced: state.latest);
    await _checkIfDue();
  }

  Future<void> _checkIfDue() async {
    if (kDebugMode && _debugLatest.isNotEmpty) {
      _remember(announcedVersion(_debugLatest));
      return;
    }
    if (_checking || !state.automatic) return;
    final now = ref.read(updateClockProvider)();
    final last = state.checkedAt;
    // A stamp from the future is a clock that was moved: check again.
    if (last != null && last <= now && now - last < updateCheckPeriod) return;
    state = state.copyWith(checkedAt: now);
    _store('updates.checked_at', '$now');
    // The first day asks nothing: whoever just installed Gerfaut gets to
    // read the About card, and its switch, before the app speaks to
    // GitHub on its own.
    if (last == null) return;
    _checking = true;
    try {
      record(await ref.read(bridgeProvider).checkUpdate(appVersion));
    } catch (_) {
      // Offline, rate-limited, unreadable, or Tor needed and not to be
      // had: nothing to say, and the next check is tomorrow's.
    } finally {
      _checking = false;
    }
  }

  /// Keeps what a check reported, whoever asked. An answer with nothing
  /// to announce takes back what an earlier one said: a release that
  /// was withdrawn stops being offered.
  void record(UpdateCheck check) => _remember(announcedVersion(check.latest));

  void _remember(ReleaseVersion? version) {
    if (version == state.latest) return;
    state = state.copyWith(
      latest: version,
      // A notice already up follows the facts; none comes up mid-session.
      announced: state.announced == null ? null : version,
    );
    _store('updates.latest', version == null ? '' : '$version');
  }

  /// Closes the notice for the release it names, for good.
  void dismiss() {
    final version = state.notice;
    if (version == null) return;
    state = state.copyWith(dismissed: version);
    _store('updates.dismissed', '$version');
  }

  void _store(String key, String value) {
    ref.read(bridgeProvider).setAppPref(key, value).catchError((_) {});
  }
}

/// What is known about newer releases, persisted as "updates.*".
final updateProvider = NotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);
