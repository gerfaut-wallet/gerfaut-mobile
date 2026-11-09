// Whether the welcome tour has been seen. One preference, kept in the
// encrypted vault like every other, so a reinstall starts over and a
// restore does not.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';
import 'prefs.dart';

class OnboardingNotifier extends VaultPrefNotifier<bool> {
  @override
  VaultPref<bool> get pref => AppPref.onboardingSeen;

  /// Marks the tour as seen, however it was left. A refusal leaves it
  /// closed for this session: the vault brings it back at the next
  /// launch, and putting it back now would open it again under the
  /// hand that just closed it.
  void markSeen() {
    if (state) return;
    unawaited(persist(true));
  }

  /// Shows it again, from the settings.
  void replay() => state = false;
}

/// The welcome tour has been seen, persisted as "onboarding.seen".
final onboardingSeenProvider = NotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);
