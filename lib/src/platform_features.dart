// What the phone's system lets Gerfaut do, in one place. Android and
// iOS share the app, and part of it rests on things only Android has:
// a foreground service for Live, launcher aliases for the disguise,
// home-screen widgets drawn by the app's own providers. A screen or a
// rule that depends on one of them reads it here, and nowhere else
// asks which system it runs on.
//
// The choice follows `defaultTargetPlatform`, so a test that sets
// `debugDefaultTargetPlatformOverride` gets the other system's set
// whole. The screens read it through [platformFeaturesProvider], which
// a widget test may override alone; an isolate with no provider tree,
// the background check, reads [PlatformFeatures.current].

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What one system lets Gerfaut do.
@immutable
class PlatformFeatures {
  const PlatformFeatures._({
    required this.system,
    required this.liveWatch,
    required this.checksKeepCadence,
    required this.disguise,
    required this.homeWidgets,
    required this.releaseChecks,
  });

  static const android = PlatformFeatures._(
    system: 'Android',
    liveWatch: true,
    checksKeepCadence: true,
    disguise: true,
    homeWidgets: true,
    releaseChecks: true,
  );

  /// Live needs a service that keeps running behind the app, which iOS
  /// has no room for. The disguise is not offered: iOS keeps the name
  /// under the icon, puts up an alert of its own at every change of
  /// icon, and the App Review guidelines (2.5.19, 4.1) take an app
  /// passing for another as a reason to refuse it. The widgets wait for
  /// a WidgetKit extension. New versions reach an iPhone through
  /// TestFlight or the App Store, which say so themselves.
  static const ios = PlatformFeatures._(
    system: 'iOS',
    liveWatch: false,
    checksKeepCadence: false,
    disguise: false,
    homeWidgets: false,
    releaseChecks: false,
  );

  /// The set of [platform]. Android's for every other one: the app is
  /// only built for these two, and a widget test runs as Android.
  static PlatformFeatures of(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? ios : android;

  /// The set of the system this runs on, for code outside the provider
  /// tree.
  static PlatformFeatures get current => of(defaultTargetPlatform);

  /// The system's name, as the texts that speak of it say it.
  final String system;

  /// Live watch: a connection kept open by a foreground service, the
  /// battery exemption it asks for, the advice for each phone maker.
  final bool liveWatch;

  /// The system runs the periodic check at the cadence it was given,
  /// give or take the delays of battery saving. iOS wakes the app when
  /// it sees fit instead: the cadence asked for is not passed on, the
  /// next turn may come a quarter of an hour later at best, and none
  /// comes once the user has swiped the app away. There the check keeps
  /// the cadence itself, and skips a turn that comes before it is due.
  final bool checksKeepCadence;

  /// Gerfaut can stand in the launcher as a calculator.
  final bool disguise;

  /// Home-screen widgets, and the periodic task that repaints them.
  final bool homeWidgets;

  /// Gerfaut asks GitHub for its latest release and points to it. A
  /// GitHub release holds the APKs and the desktop builds: on a system
  /// whose store delivers the app, the app asks nothing and says
  /// nothing of versions.
  final bool releaseChecks;
}

/// What the system the app runs on lets it do. Overridden in a test
/// that wants the screens of another system.
final platformFeaturesProvider = Provider<PlatformFeatures>(
  (ref) => PlatformFeatures.current,
);
