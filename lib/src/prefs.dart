// The preferences of this app alone as the vault keeps them: a flat map
// of strings, written by the screens and read by three isolates, the
// screens', the periodic task's and Live's. The ones both apps keep are
// a typed record of the core: see [Preferences].

import 'notifications.dart';
import 'state.dart';

/// The keys the preferences are kept under. One place for all of them:
/// an isolate that misspelled one would compile, read nothing, and fall
/// back in silence on a default it was never meant to have.
abstract final class Pref {
  static const theme = 'mobile.theme';
  static const notifyDetails = 'notify.details';
  static const background = 'notify.background';
  static const onboardingSeen = 'onboarding.seen';
  static const widgetBalances = 'widgets.balances';

  /// The launch at which the phone first said it had no strong
  /// biometric, while biometrics stood on; empty or absent when none.
  static const biometricLack = 'lock.biometric_lack';
}

/// One preference of this app alone: its key, and the one rule that
/// reads it, default included, and writes it. The screens hydrate by it
/// and every isolate reads by it: a rule written twice drifts, and an
/// isolate would act on a default the screens never show.
final class VaultPref<T> {
  const VaultPref(this.key, {required this.decode, required this.encode});

  final String key;

  /// What a stored string means, nothing stored or unreadable included.
  final T Function(String? stored) decode;

  /// What the vault keeps for a value.
  final String Function(T value) encode;

  /// The preference in the vault's flat map of this app's preferences.
  T read(Map<String, String> prefs) => decode(prefs[key]);
}

/// The preferences of this app alone that the screens show, each with
/// its rule.
abstract final class AppPref {
  static const theme = VaultPref<ThemePref>(
    Pref.theme,
    decode: _theme,
    encode: _themeId,
  );

  /// The wallet's name and the amount in what is posted, app lock or
  /// not. On unless turned off: an install from before the switch has
  /// none stored, and gets it on.
  static const notifyDetails = VaultPref<bool>(
    Pref.notifyDetails,
    decode: _onUnlessOff,
    encode: _flag,
  );

  /// How transactions are looked for off screen, off when nothing or
  /// something unknown is stored.
  static const background = VaultPref<BackgroundCheck>(
    Pref.background,
    decode: _cadence,
    encode: _cadenceStored,
  );

  /// Only an explicit "1" counts as seen: an unreadable preference
  /// shows the tour again rather than swallowing it.
  static const onboardingSeen = VaultPref<bool>(
    Pref.onboardingSeen,
    decode: _offUnlessOn,
    encode: _flag,
  );

  /// Only an explicit "1" shows the amounts: a widget is read over the
  /// shoulder, so they stay masked until asked for.
  static const widgetBalances = VaultPref<bool>(
    Pref.widgetBalances,
    decode: _offUnlessOn,
    encode: _flag,
  );

  static String _flag(bool on) => on ? '1' : '0';
  static bool _onUnlessOff(String? stored) => stored != '0';
  static bool _offUnlessOn(String? stored) => stored == '1';
  static ThemePref _theme(String? stored) =>
      ThemePref.fromId(stored) ?? ThemePref.light;
  static String _themeId(ThemePref pref) => pref.id;
  static BackgroundCheck _cadence(String? stored) =>
      BackgroundCheck.fromStored(stored) ?? BackgroundCheck.off;
  static String _cadenceStored(BackgroundCheck check) => check.stored;
}

/// The preferences of this app alone that a background isolate acts
/// on, read by the rules the screens hydrate by. The ones both apps
/// keep, the notice itself, the unit and the mask among them, are typed
/// in [Settings.preferences].
extension type const AppPrefs(Map<String, String> raw) {
  bool get notifyDetails => AppPref.notifyDetails.read(raw);

  BackgroundCheck get background => AppPref.background.read(raw);

  bool get widgetBalances => AppPref.widgetBalances.read(raw);
}
