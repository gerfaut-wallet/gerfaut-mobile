import Flutter
import UIKit
import UniformTypeIdentifiers

// The channels the Dart side calls that no plugin answers, served as
// the Android activity serves them (MainActivity.kt): the same method
// names, the same arguments, the same answers and the same error codes,
// so lib/src reads both platforms alike.
enum PlatformChannels {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "GerfautPlatformChannels") else {
      return
    }
    let messenger = registrar.messenger()
    WindowGuard.shared.register(messenger: messenger)
    Documents.shared.register(messenger: messenger)
    StrongBiometrics.shared.register(messenger: messenger)
  }
}

// Where a sheet of the system's goes up: over whatever is on top in the
// window of the scene in front, a sheet already up included, since a
// controller that is presenting something presents nothing more.
enum Presenter {
  static func top() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene =
      scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first { $0.activationState == .foregroundInactive }
    guard let windows = scene?.windows,
      let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    else { return nil }
    var top = window.rootViewController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }
}

func badArgument(_ message: String) -> FlutterError {
  FlutterError(code: "bad_argument", message: message, details: nil)
}

// What the system lets others see of Gerfaut's window, and the
// clipboard for what identifies a wallet: the "gerfaut/window" channel.
final class WindowGuard {
  static let shared = WindowGuard()

  private var channel: FlutterMethodChannel?

  // Set by the Dart side while an app lock exists (lib/src/window.dart).
  private var secure = false

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "gerfaut/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "setSecure":
        guard let secure = call.arguments as? Bool else {
          result(badArgument("setSecure takes a boolean"))
          return
        }
        self.setSecure(secure)
        result(nil)
      case "copySensitive":
        guard let text = call.arguments as? String else {
          result(badArgument("copySensitive takes a string"))
          return
        }
        self.copySensitive(text)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    if capture == nil {
      capture = NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.captureChanged()
      }
    }
  }

  // Watches the screen being recorded, mirrored or shared.
  private var capture: NSObjectProtocol?

  // iOS has no switch that blanks a window in screenshots or
  // recordings. What it does have is the picture of the app the
  // switcher keeps, taken as the app leaves the screen, before the lock
  // has drawn: readable by anyone holding the phone. While secure, a
  // plain cover goes over every window of the scene the moment it stops
  // being active, so that picture is of the cover, and comes off when
  // the scene is active again. Turned off, a cover up goes at once.
  //
  // Nor can a screenshot be kept from happening; a recording, a
  // mirrored or shared screen can be shown nothing: the cover also
  // stays up for as long as the screen is captured.
  private func setSecure(_ secure: Bool) {
    self.secure = secure
    if secure {
      captureChanged()
    } else {
      for scene in UIApplication.shared.connectedScenes {
        uncover(scene)
      }
    }
  }

  private func captureChanged() {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      if Self.captured(scene) {
        cover(scene)
      } else if scene.activationState == .foregroundActive {
        uncover(scene)
      }
    }
  }

  private static func captured(_ scene: UIWindowScene) -> Bool {
    scene.screen.isCaptured
  }

  // From the scene delegate, as the scene loses the focus or leaves the
  // screen: the second is there for a scene that went without the first.
  func cover(_ scene: UIScene) {
    guard secure, let scene = scene as? UIWindowScene else { return }
    for window in scene.windows where window.viewWithTag(Self.coverTag) == nil {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .systemBackground
      cover.tag = Self.coverTag
      window.addSubview(cover)
    }
  }

  // From the scene delegate, as the scene is active again; a screen
  // still captured keeps its cover.
  func uncover(_ scene: UIScene) {
    guard let scene = scene as? UIWindowScene else { return }
    if secure && Self.captured(scene) { return }
    for window in scene.windows {
      for view in window.subviews where view.tag == Self.coverTag {
        view.removeFromSuperview()
      }
    }
  }

  // Puts text on the clipboard for this phone alone, and for a minute.
  //
  // Local only, so it does not travel to the user's other devices by
  // Universal Clipboard, where it would sit outside the app's reach.
  // Expiring, so it leaves the clipboard a minute later by itself,
  // whether the app is still running or not: iOS drops only this item,
  // so anything copied since, from any app, is the user's and stays.
  // The Dart side says "Copied for 1 minute".
  private func copySensitive(_ text: String) {
    UIPasteboard.general.setItems(
      [[UTType.utf8PlainText.identifier: text]],
      options: [
        .localOnly: true,
        .expirationDate: Date().addingTimeInterval(Self.sensitiveSeconds),
      ]
    )
  }

  // A number no other view of the window is likely to carry.
  private static let coverTag = 0x6765_7266

  private static let sensitiveSeconds: TimeInterval = 60
}
