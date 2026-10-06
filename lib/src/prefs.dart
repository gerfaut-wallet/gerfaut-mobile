// The app's preferences as the vault keeps them: a flat map of strings,
// written by the screens and read by three isolates, the screens', the
// periodic task's and Live's.

import 'format.dart';

/// The keys the preferences are kept under. One place for all of them:
/// an isolate that misspelled one would compile, read nothing, and fall
/// back in silence on a default it was never meant to have.
abstract final class Pref {
  static const theme = 'mobile.theme';
  static const masked = 'mobile.masked';
  static const unit = 'display.unit';
  static const fiat = 'display.fiat';
  static const fiatCurrency = 'display.fiat_currency';
  static const fiatSource = 'display.fiat_source';
  static const explorerAck = 'privacy.explorer_ack';
  static const recentBroadcasts = 'broadcast.recent';
  static const notifyNewTx = 'notify.new_tx';
  static const notifyDetails = 'notify.details';
  static const background = 'notify.background';
  static const onboardingSeen = 'onboarding.seen';
  static const widgetBalances = 'widgets.balances';
  static const updatesAuto = 'updates.auto';
  static const updatesCheckedAt = 'updates.checked_at';
  static const updatesLatest = 'updates.latest';
  static const updatesDismissed = 'updates.dismissed';
}

/// The preferences a background isolate acts on, read the way the
/// screens write them: a switch that is off by default is on only for
/// an explicit `"1"`, one that is on by default off only for a `"0"`.
extension type const AppPrefs(Map<String, String> raw) {
  /// A notice when a sync finds a transaction. Off unless asked for.
  bool get notifyNewTx => raw[Pref.notifyNewTx] == '1';

  /// The wallet's name and the amount in what is posted, app lock or
  /// not. On unless turned off: an install from before the switch has
  /// none stored, and gets it on.
  bool get notifyDetails => raw[Pref.notifyDetails] != '0';

  /// Balances hidden on screen, and so in what is posted.
  bool get masked => raw[Pref.masked] == '1';

  /// The unit amounts are said in; BTC when none was chosen.
  AmountUnit get unit => AmountUnit.fromId(raw[Pref.unit]) ?? AmountUnit.btc;
}
