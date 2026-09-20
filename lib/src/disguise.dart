// The disguise: Gerfaut wearing a calculator's name and icon in the
// launcher, with the calculator standing where the lock screen would.
//
// Android is the source of truth. Whether the app is disguised is the
// enabled state of two launcher aliases, read from the package manager
// on first use and before the gate draws anything. It is deliberately
// not a preference in the vault: a backup carries preferences, and a
// backup restored on another phone must not claim a disguise that
// phone's launcher does not show.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'notifications.dart';

/// What the platform does for the disguise. Behind an interface so no
/// test ever reaches the activity.
abstract class Disguise {
  /// Whether the calculator alias is the launcher entry right now.
  Future<bool> isDisguised();

  /// Enables one launcher alias and disables the other.
  Future<void> setDisguised(bool disguised);

  /// Enables or disables every home-screen widget provider of the app.
  Future<void> setWidgetsEnabled(bool enabled);
}

/// The real thing: a method channel the Android activity answers.
class SystemDisguise implements Disguise {
  const SystemDisguise();

  static const MethodChannel _channel = MethodChannel('gerfaut/disguise');

  /// The name of the file the activity keeps beside the app's data
  /// while disguised. The main app never needs it — the channel above
  /// answers on a real device — but the background isolate has no
  /// channel of ours and reads this file directly (see background.dart).
  static const String markerName = 'disguised';

  @override
  Future<bool> isDisguised() async {
    try {
      return await _channel.invokeMethod<bool>('isDisguised') ?? false;
    } on MissingPluginException {
      // No channel at all, which is only ever a widget test: not
      // disguised. A real device always carries the activity's channel.
      return false;
    } on PlatformException {
      // A package manager that will not answer leaves the app as it
      // looks: not disguised.
      return false;
    }
  }

  @override
  Future<void> setDisguised(bool disguised) =>
      _channel.invokeMethod<void>('setDisguised', disguised);

  @override
  Future<void> setWidgetsEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setWidgetsEnabled', enabled);
}

/// The platform side in use. Widget tests override this with a fake.
final disguiseServiceProvider = Provider<Disguise>(
  (ref) => const SystemDisguise(),
);

/// Whether the app is disguised, read from the marker file the activity
/// keeps up to date. This is the background isolate's answer: its Flutter
/// engine carries none of the app's method channels, so it cannot ask
/// the activity — but path_provider still points at the same `filesDir`,
/// where the marker lives. A read that fails is taken as not disguised.
Future<bool> isDisguisedFromDisk() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return await File('${dir.path}/${SystemDisguise.markerName}').exists();
  } catch (_) {
    return false;
  }
}

/// Where the disguise stands.
@immutable
class DisguiseState {
  const DisguiseState({this.disguised = false, this.loaded = false});

  /// The calculator is the launcher entry, and the lock screen.
  final bool disguised;

  /// The platform has been asked; before that the gate draws nothing
  /// rather than guess which screen to show.
  final bool loaded;
}

class DisguiseController extends Notifier<DisguiseState> {
  @override
  DisguiseState build() {
    // Asked on first use, which is the gate watching this before it
    // decides what to draw. The answer lands a moment later; until
    // then [DisguiseState.loaded] is false.
    unawaited(_hydrate());
    return const DisguiseState();
  }

  Future<void> _hydrate() async {
    var disguised = false;
    try {
      disguised = await ref.read(disguiseServiceProvider).isDisguised();
    } catch (_) {
      // Unanswered is not disguised.
    }
    state = DisguiseState(disguised: disguised, loaded: true);
  }

  /// Puts the disguise on or takes it off, widgets included. Going on,
  /// what would give the app away goes first; coming off, the app's own
  /// face comes back before its widgets do.
  Future<void> set(bool disguised) async {
    final service = ref.read(disguiseServiceProvider);
    if (disguised) {
      // Live watch cannot hide: its permanent notification is headed
      // with the app's name. It goes first, and the setting goes back
      // to a periodic check, which stays silent while disguised.
      if (ref.read(backgroundCheckProvider) == BackgroundCheck.live) {
        await ref
            .read(backgroundCheckProvider.notifier)
            .set(BackgroundCheck.quarterHour);
      }
      await service.setWidgetsEnabled(false);
      await service.setDisguised(true);
    } else {
      await service.setDisguised(false);
      await service.setWidgetsEnabled(true);
    }
    state = DisguiseState(disguised: disguised, loaded: true);
  }
}

final disguiseProvider = NotifierProvider<DisguiseController, DisguiseState>(
  DisguiseController.new,
);
