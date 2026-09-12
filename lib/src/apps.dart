// Handing a link to one named app, and to no other.
//
// A link opened the ordinary way travels as an implicit intent: the
// system offers it to every app that declared the scheme, and the
// person picks one from a chooser. For an ntfy subscribe link that
// chooser is the leak. The topic in it is the whole secret of the
// channel — whoever holds it reads the alerts of the account — and any
// app on the phone may declare `ntfy://` to be offered it.
//
// So the intent names the package it is for. The link reaches that app
// or no app at all, and no app at all is a thing the screen can say.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a link in one named app. Behind an interface so no test ever
/// reaches the platform.
abstract class AppOpener {
  /// True once the app has the link.
  ///
  /// False when it is not installed: an app that is not there has no
  /// activity to start, and the platform says so rather than falling
  /// back to whatever else would take the link.
  Future<bool> openIn({required String package, required String url});
}

/// The real one: a method channel the Android activity answers with an
/// explicit intent.
class SystemAppOpener implements AppOpener {
  const SystemAppOpener();

  static const MethodChannel _channel = MethodChannel('gerfaut/window');

  @override
  Future<bool> openIn({required String package, required String url}) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openInApp', {
        'package': package,
        'url': url,
      });
      return opened ?? false;
    } on PlatformException {
      // Nothing was started, which is what the caller acts on.
      return false;
    } on MissingPluginException {
      // A platform without the channel, such as a widget test.
      return false;
    }
  }
}

/// The opener in use. Widget tests override this with a fake.
final appOpenerProvider = Provider<AppOpener>((ref) => const SystemAppOpener());
