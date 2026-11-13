import Flutter
import UIKit
import UniformTypeIdentifiers

// The "gerfaut/files" channel: the system's save and open dialogs, and
// the share sheet, as lib/src/documents.dart and lib/src/share.dart ask
// for them.
final class Documents: NSObject, UIDocumentPickerDelegate {
  static let shared = Documents()

  private var channel: FlutterMethodChannel?

  // The dialog under way, save or open, and the call waiting for its
  // answer. One at a time: a second picker would have nothing to go
  // over, and its call would wait for ever.
  private var pending: Pending?

  private final class Pending {
    enum Kind {
      // The file staged for the export, gone once the dialog closes.
      case save(staged: URL?)
      case open(maxBytes: Int)
    }

    var kind: Kind
    let result: FlutterResult
    weak var picker: UIDocumentPickerViewController?

    init(_ kind: Kind, _ result: @escaping FlutterResult) {
      self.kind = kind
      self.result = result
    }
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "gerfaut/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "createDocument":
        guard let filename = args?["filename"] as? String,
          args?["mimeType"] is String,
          let bytes = args?["bytes"] as? FlutterStandardTypedData
        else {
          result(badArgument("createDocument takes filename, mimeType and bytes"))
          return
        }
        self.createDocument(filename: filename, bytes: bytes.data, result: result)
      case "share":
        guard let filename = args?["filename"] as? String,
          args?["mimeType"] is String,
          let bytes = args?["bytes"] as? FlutterStandardTypedData
        else {
          result(badArgument("share takes filename, mimeType and bytes"))
          return
        }
        self.share(filename: filename, bytes: bytes.data, result: result)
      case "openDocument":
        guard let mimeTypes = args?["mimeTypes"] as? [String],
          let maxBytes = args?["maxBytes"] as? Int, maxBytes >= 0
        else {
          result(badArgument("openDocument takes mimeTypes and maxBytes"))
          return
        }
        self.openDocument(mimeTypes: mimeTypes, maxBytes: maxBytes, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  // The system's export dialog on a copy of the bytes, under the name
  // given: true once the user put it somewhere, false when the dialog
  // was dismissed.
  //
  // The dialog copies a file that exists, so the bytes are written
  // first, under a folder of their own among the shared copies, and
  // that copy goes as soon as the dialog closes; should the app end
  // with the dialog up, the sweep of lib/src/share.dart takes it an
  // hour later, as it does a share's. A copy that could not
  // be written fails before any dialog opens: "failed", which the Dart
  // side reads as no trip away, unlike "write_failed".
  private func createDocument(filename: String, bytes: Data, result: @escaping FlutterResult) {
    if pending != nil {
      result(FlutterError(code: "busy", message: "a file dialog is already up", details: nil))
      return
    }
    let save = Pending(.save(staged: nil), result)
    pending = save
    DispatchQueue.global(qos: .userInitiated).async {
      let staged = Result { try Staging.write(bytes, named: filename, under: Staging.shares) }
      DispatchQueue.main.async {
        let file: URL
        switch staged {
        case .success(let url):
          file = url
        case .failure(let error):
          self.pending = nil
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          return
        }
        guard let presenter = Presenter.top() else {
          self.pending = nil
          Staging.discard(file)
          result(
            FlutterError(code: "unavailable", message: "no screen to open the dialog on", details: nil)
          )
          return
        }
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = self
        save.kind = .save(staged: file)
        save.picker = picker
        presenter.present(picker, animated: true)
      }
    }
  }

  // The system's open dialog: answers the file it names, its name, its
  // size, and its bytes when there are no more than maxBytes of them. A
  // larger file comes back without its bytes, having been read no
  // further than the limit. Null when the dialog was dismissed.
  //
  // The file is opened where it is, not copied in first: a video picked
  // by mistake would otherwise be copied whole before its size is known.
  private func openDocument(mimeTypes: [String], maxBytes: Int, result: @escaping FlutterResult) {
    if pending != nil {
      result(FlutterError(code: "busy", message: "a file is already being picked", details: nil))
      return
    }
    guard let presenter = Presenter.top() else {
      result(
        FlutterError(code: "unavailable", message: "no screen to open the dialog on", details: nil))
      return
    }
    let named = mimeTypes.compactMap { UTType(mimeType: $0) }
    let types = named.isEmpty ? [UTType.item] : named
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    let open = Pending(.open(maxBytes: maxBytes), result)
    open.picker = picker
    pending = open
    presenter.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    finish(controller, picked: urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(controller, picked: nil)
  }

  private func finish(_ controller: UIDocumentPickerViewController, picked: URL?) {
    guard let done = pending, done.picker === controller else { return }
    pending = nil
    switch done.kind {
    case .save(let staged):
      // The dialog made its own copy before it said so: the staged one
      // has done its work.
      if let staged { Staging.discard(staged) }
      done.result(picked != nil)
    case .open(let maxBytes):
      guard let url = picked else {
        done.result(nil)
        return
      }
      // A provider may fetch the file over the network: read off the
      // main thread, answered on it.
      DispatchQueue.global(qos: .userInitiated).async {
        let answer = Result { try Self.readBounded(url, maxBytes: maxBytes) }
        DispatchQueue.main.async {
          switch answer {
          case .success(let file):
            done.result(file)
          case .failure(let error):
            done.result(
              FlutterError(code: "read_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  // What openDocument answers for one file. The size the provider
  // states is trusted only to refuse early: the bytes are counted as
  // they come, and the reading stops one past the limit. Through a file
  // coordinator, which brings down a file kept in the cloud before it
  // is read.
  private static func readBounded(_ url: URL, maxBytes: Int) throws -> [String: Any] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let name = url.lastPathComponent
    var answer: Result<[String: Any], Error> = .failure(CocoaError(.fileReadUnknown))
    var coordination: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { at in
      answer = Result {
        let stated = try? at.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let stated, stated > maxBytes {
          return ["name": name, "size": stated, "bytes": NSNull()]
        }
        let handle = try FileHandle(forReadingFrom: at)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count <= maxBytes {
          guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
          bytes.append(chunk)
        }
        if bytes.count > maxBytes {
          return ["name": name, "size": bytes.count, "bytes": NSNull()]
        }
        return ["name": name, "size": bytes.count, "bytes": FlutterStandardTypedData(bytes: bytes)]
      }
    }
    if let coordination { throw coordination }
    return try answer.get()
  }

  // Writes the file, then opens the share sheet on it. Answers once the
  // sheet is up, and nothing about what was picked there: the sheet is
  // all the feedback there is.
  //
  // The file goes into a folder of its own under shared/ in the caches,
  // which is where the sweep of lib/src/share.dart looks: it stays an
  // hour, for the app that reads it late, then goes, folder and all.
  private func share(filename: String, bytes: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let staged = Result { try Staging.write(bytes, named: filename, under: Staging.shares) }
      DispatchQueue.main.async {
        let file: URL
        switch staged {
        case .success(let url):
          file = url
        case .failure(let error):
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          return
        }
        guard let presenter = Presenter.top() else {
          result(
            FlutterError(code: "unavailable", message: "no screen to open the sheet on", details: nil)
          )
          return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        // On an iPad the sheet is a popover, and one with nothing to
        // point at ends the app: it points at the middle of the screen,
        // with no arrow.
        if let popover = sheet.popoverPresentationController {
          let view: UIView = presenter.view
          popover.sourceView = view
          popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
          popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
        result(nil)
      }
    }
  }
}

// The copies the dialogs and the share sheet are handed: each under a
// folder no other one uses, so no two ever have the same address.
enum Staging {
  // Under the caches, where lib/src/share.dart sweeps them after an hour.
  static var shares: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("shared", isDirectory: true)
  }

  // The name is the one the dialog or the receiving app shows; anything
  // in it that would climb out of the folder is dropped.
  static func write(_ bytes: Data, named filename: String, under root: URL) throws -> URL {
    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var name = (filename as NSString).lastPathComponent
    if name.isEmpty || name == "." || name == ".." || name == "/" { name = "shared" }
    let file = folder.appendingPathComponent(name, isDirectory: false)
    guard file.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path
    else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    try bytes.write(to: file)
    return file
  }

  // The file and its folder. Best effort: the sweep takes what is left.
  static func discard(_ file: URL) {
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }
}
