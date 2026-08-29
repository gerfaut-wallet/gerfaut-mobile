// Whether the welcome tour has been seen. One preference, kept in the
// encrypted vault like every other, so a reinstall starts over and a
// restore does not.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void hydrate(String? stored) {
    // Only an explicit "1" counts as seen: an unreadable preference
    // shows the tour again rather than swallowing it.
    state = stored == '1';
  }

  /// Marks the tour as seen, however it was left.
  void markSeen() {
    if (state) return;
    state = true;
    ref
        .read(bridgeProvider)
        .setAppPref('onboarding.seen', '1')
        .catchError((_) {});
  }

  /// Shows it again, from the settings.
  void replay() => state = false;
}

/// The welcome tour has been seen, persisted as "onboarding.seen".
final onboardingSeenProvider = NotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);
