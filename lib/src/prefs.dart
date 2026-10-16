// The preferences of this app alone as the vault keeps them: a flat map
// of strings, written by the screens and read by three isolates, the
// screens', the periodic task's and Live's. The ones both apps keep are
// a typed record of the core: see [Preferences].

/// The keys the preferences are kept under. One place for all of them:
/// an isolate that misspelled one would compile, read nothing, and fall
/// back in silence on a default it was never meant to have.
abstract final class Pref {
  static const theme = 'mobile.theme';
  static const notifyDetails = 'notify.details';
  static const background = 'notify.background';
  static const onboardingSeen = 'onboarding.seen';
  static const widgetBalances = 'widgets.balances';
}

/// The preferences of this app alone that a background isolate acts
/// on, read the way the screens write them: a switch that is on by
/// default is off only for a `"0"`. The ones both apps keep, the notice
/// itself, the unit and the mask among them, are typed in
/// [Settings.preferences].
extension type const AppPrefs(Map<String, String> raw) {
  /// The wallet's name and the amount in what is posted, app lock or
  /// not. On unless turned off: an install from before the switch has
  /// none stored, and gets it on.
  bool get notifyDetails => raw[Pref.notifyDetails] != '0';
}
