import Flutter
import LocalAuthentication
import Security
import UIKit

// The phone's own prompt, as the app lock may use it: Face ID or Touch
// ID, through an item of the Keychain that only they release. The
// "gerfaut/biometrics" channel, with the answers of StrongBiometrics.kt.
//
// The item is made to be read only after a biometric check of the set
// of faces or fingers enrolled when it was made, and only on a phone
// with a passcode. Adding a face or a finger leaves it in place but
// unreadable for good, so whoever knows the passcode cannot enrol their
// own face and walk in: the app asks for its secret again, and the user
// turns biometrics back on. That set is also written beside the item,
// as the system states it, so a change is told before any prompt, as
// Android tells a key the Keystore dropped.
//
// Gerfaut never sees the biometric; what the item holds opens nothing.
// Reading it after the prompt is the proof the prompt was answered by a
// biometric of the set it was made for.
//
// This side only puts one prompt up and says how it ended. What an end
// means, a refusal or a trip away to come back from, is decided by the
// Dart side (PromptSession, lib/src/lock.dart), which sees the app's
// whole lifecycle.
final class StrongBiometrics {
  static let shared = StrongBiometrics()

  private var channel: FlutterMethodChannel?

  // A prompt is up: a second would take the first one's answer away.
  private var prompting = false

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "gerfaut/biometrics", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "support":
        result(self.support())
      case "keyPresence":
        result(self.keyPresence())
      case "prepareKey":
        result(self.prepareKey())
      case "prompt":
        let args = call.arguments as? [String: Any]
        guard let title = args?["title"] as? String, let cancel = args?["cancel"] as? String
        else {
          result(badArgument("prompt takes title and cancel"))
          return
        }
        self.prompt(title: title, cancel: cancel, result: result)
      case "forget":
        self.forget()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  // What the phone offers: "strong" when Face ID or Touch ID is set up,
  // Apple rating neither below the other; "none" when neither can be
  // had (no sensor, nothing enrolled, no passcode, or the user said no
  // to Face ID for this app); "unavailable" when one is there but cannot
  // answer right now, locked out after too many tries: a passing state
  // that changes nothing. iOS has no weak biometric to answer "weak" for.
  private func support() -> String {
    let context = LAContext()
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      return "strong"
    }
    guard let error, error.domain == LAError.errorDomain else { return "unavailable" }
    switch LAError.Code(rawValue: error.code) {
    case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
      return "none"
    default:
      return "unavailable"
    }
  }

  // A new item in place of any other, for turning biometrics on: the
  // prompt that follows confirms it, or it is forgotten.
  private func prepareKey() -> Bool {
    if prompting { return false }
    forget()
    guard let access = Self.accessControl() else { return false }
    var secret = Data(count: 32)
    let drawn = secret.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard drawn == errSecSuccess else { return false }
    var item = Self.query()
    item[kSecValueData as String] = secret
    item[kSecAttrAccessControl as String] = access
    item[kSecAttrGeneric as String] = Self.enrolled() ?? Data()
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
      forget()
      return false
    }
    return keyPresence() == "present"
  }

  // Whether an item is there for the prompt to release, without asking
  // for anything: "present", "absent" when the Keychain was read and
  // holds none, or "unknown" when it could not be read: no proof of
  // anything.
  private func keyPresence() -> String {
    switch Self.stored() {
    case .present: return "present"
    case .absent: return "absent"
    case .unreadable: return "unknown"
    }
  }

  // Drops the item: the biometric no longer opens anything.
  private func forget() {
    Self.drop()
  }

  // One prompt on the item in place, answered once, with how it ended,
  // in the words of StrongBiometrics.kt:
  //   "passed"   Face ID or Touch ID released the item, and it was read;
  //   "missing"  there is no item;
  //   "reset"    the item no longer opens: the faces or fingers changed;
  //   "busy"     another prompt is up;
  //   "unshown"  the app is in the background, where no prompt shows;
  //   "error:13" the prompt's own "Cancel", as androidx numbers it;
  //   "error:5"  a cancel by the system, the app taken away;
  //   "error:7"  too many tries: the biometric is locked out;
  //   "refused"  anything else that kept it from opening or passing.
  private func prompt(title: String, cancel: String, result: @escaping FlutterResult) {
    if prompting {
      result("busy")
      return
    }
    switch Self.stored() {
    case .absent:
      result("missing")
      return
    case .present(let enrolledThen):
      // A set the system will not state today, locked out say, proves
      // nothing: the Keychain says after the prompt.
      if let enrolledThen, !enrolledThen.isEmpty, let now = Self.enrolled(), now != enrolledThen {
        forget()
        result("reset")
        return
      }
    case .unreadable:
      // Left to the Keychain to say after the prompt.
      break
    }
    if UIApplication.shared.applicationState == .background {
      result("unshown")
      return
    }
    guard let access = Self.accessControl() else {
      result("refused")
      return
    }
    prompting = true
    let context = LAContext()
    context.localizedCancelTitle = cancel
    // No way to the passcode from here: the app's own secret is that way.
    context.localizedFallbackTitle = ""
    context.evaluateAccessControl(access, operation: .useItem, localizedReason: title) {
      passed, error in
      let outcome = passed ? Self.read(with: context) : Self.outcome(of: error)
      if outcome == "reset" { Self.drop() }
      DispatchQueue.main.async {
        self.prompting = false
        result(outcome)
      }
    }
  }

  // The item read with the check just passed. The context asks nothing
  // more: should the Keychain want another check, that is no pass.
  private static func read(with context: LAContext) -> String {
    context.interactionNotAllowed = true
    var search = Self.query()
    search[kSecReturnData as String] = true
    search[kSecMatchLimit as String] = kSecMatchLimitOne
    search[kSecUseAuthenticationContext as String] = context
    var out: CFTypeRef?
    switch SecItemCopyMatching(search as CFDictionary, &out) {
    case errSecSuccess:
      return (out as? Data)?.isEmpty == false ? "passed" : "refused"
    case errSecItemNotFound, errSecAuthFailed:
      // There a moment ago, and unreadable to the check that passed:
      // made for another set of faces or fingers. Told as such, or a
      // prompt that can never pass would be put up at every unlock.
      return "reset"
    default:
      return "refused"
    }
  }

  private static func outcome(of error: Error?) -> String {
    guard let error = error as? LAError else { return "refused" }
    switch error.code {
    case .userCancel, .userFallback:
      return "error:13"
    case .systemCancel, .appCancel, .notInteractive:
      return "error:5"
    case .biometryLockout:
      return "error:7"
    default:
      return "refused"
    }
  }

  private enum Stored {
    // With the set of faces or fingers it was made for, when known.
    case present(Data?)
    case absent
    case unreadable
  }

  // The item's attributes, which the Keychain gives without any check.
  private static func stored() -> Stored {
    let context = LAContext()
    context.interactionNotAllowed = true
    var search = Self.query()
    search[kSecReturnAttributes as String] = true
    search[kSecMatchLimit as String] = kSecMatchLimitOne
    search[kSecUseAuthenticationContext as String] = context
    var out: CFTypeRef?
    switch SecItemCopyMatching(search as CFDictionary, &out) {
    case errSecSuccess:
      let attributes = out as? [String: Any]
      return .present(attributes?[kSecAttrGeneric as String] as? Data)
    case errSecItemNotFound:
      return .absent
    case errSecInteractionNotAllowed:
      // Found, and kept behind its check whole, attributes included.
      return .present(nil)
    default:
      return .unreadable
    }
  }

  private static func drop() {
    SecItemDelete(Self.query() as CFDictionary)
  }

  // The faces or fingers enrolled, as the system states them; nil when
  // it will not say, as when no biometric can be checked right now.
  private static func enrolled() -> Data? {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    else { return nil }
    return context.evaluatedPolicyDomainState
  }

  // Read only on this phone, only while it has a passcode, and only
  // after Face ID or Touch ID checked a face or finger of the set
  // enrolled today.
  private static func accessControl() -> SecAccessControl? {
    SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .biometryCurrentSet,
      nil
    )
  }

  private static func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: service,
    ]
  }

  // A plain name: a list of the Keychain's items must not say what this
  // one opens.
  private static let service = "unlock"
}
