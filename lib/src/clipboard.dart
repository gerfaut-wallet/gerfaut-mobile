// Copying something the rest of the phone has no business reading.
//
// Android 13 and later flash a preview of whatever is copied and keep a
// history of it; any app in the foreground can read the clipboard
// besides. A clip marked sensitive is shown as hidden in that preview
// and left out of the history, which is the difference between a secret
// that crosses the screen once and one that stays there. A minute later
// it leaves the clipboard too, unless something else was copied over it
// meanwhile, as on the desktop app.
//
// What goes through here is what identifies a wallet or opens its
// alerts: a descriptor, the policy read off it, the ntfy topic, the
// account key. An address and a transaction are on the chain for anyone
// to read, so they keep the plain clipboard: marking them would spend
// the distinction on things that are not secret, and a flag that means
// everything means nothing.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puts text on the clipboard, marked sensitive where the platform
/// knows the flag. Behind an interface so no test ever reaches the
/// platform.
abstract class SensitiveClipboard {
  /// True when the clipboard lets go of [text] by itself a minute
  /// later; false for a plain copy, which stays.
  Future<bool> copy(String text);
}

/// How long a sensitive copy stays on the clipboard, as the Android
/// activity counts it.
const String sensitiveCopyStays = '1 minute';

/// The confirmation after a copy: "Key copied", or "Key copied for 1
/// minute" when the clipboard lets go of it by itself, in the desktop
/// app's words.
String copiedWords(String words, {required bool timed}) =>
    timed ? '$words for $sensitiveCopyStays' : words;

/// The real one: a method channel the Android activity answers, which
/// builds the clip with the flag on it.
class SystemSensitiveClipboard implements SensitiveClipboard {
  const SystemSensitiveClipboard();

  static const MethodChannel _channel = MethodChannel('gerfaut/window');

  @override
  Future<bool> copy(String text) async {
    try {
      await _channel.invokeMethod<void>('copySensitive', text);
      return true;
    } on PlatformException {
      await _plain(text);
    } on MissingPluginException {
      // A platform without the channel, such as a widget test.
      await _plain(text);
    }
    return false;
  }

  /// The clipboard every other copy in Gerfaut uses.
  ///
  /// The flag asks the system to keep a clip out of its preview and its
  /// history; it never decided who may read the clipboard. So a copy
  /// that cannot be marked is exactly the copy Gerfaut made before the
  /// flag existed, and it is better than a button that says "Copied"
  /// over an empty clipboard.
  static Future<void> _plain(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// The clipboard in use. Widget tests override this with a fake.
final sensitiveClipboardProvider = Provider<SensitiveClipboard>(
  (ref) => const SystemSensitiveClipboard(),
);
