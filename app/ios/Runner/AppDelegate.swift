import Flutter
import UIKit
import UniformTypeIdentifiers
import workmanager_apple
// Notification buttons run in a background isolate that needs plugins.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Coach notifications in the foreground and their buttons.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // Must match the task name in lib/src/core/background.dart.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      BackupFolderChannel.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "tempo.sync", earliestBeginInSeconds: NSNumber(value: 3 * 60 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackupFolderChannel.register(with: engineBridge.pluginRegistry)
  }
}

/// `tempo/backup_folder` (lib/src/core/backup.dart): a folder the user picks
/// once, kept as a security-scoped bookmark. Dart stores the bookmark in the
/// keychain, so it survives deleting the app. TODO(verify) on device.
final class BackupFolderChannel: NSObject, UIDocumentPickerDelegate {
  /// Channels stay alive for the engine's lifetime.
  private static var live: [BackupFolderChannel] = []
  private var pending: FlutterResult?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "TempoBackupFolder") else { return }
    let c = BackupFolderChannel()
    live.append(c)
    let channel = FlutterMethodChannel(
      name: "tempo/backup_folder", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in c.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "pick" {
      pick(result)
      return
    }
    guard ["list", "read", "write", "delete"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let token = args["token"] as? String, let bookmark = Data(base64Encoded: token)
    else {
      result(FlutterError(code: "bad_token", message: "No folder token", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      do {
        let value = try Self.withFolder(bookmark) { dir in
          try Self.run(call.method, in: dir, args: args)
        }
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func withFolder<T>(_ bookmark: Data, _ body: (URL) throws -> T) throws -> T {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try body(url)
  }

  private static func run(_ method: String, in dir: URL, args: [String: Any]) throws -> Any? {
    let fm = FileManager.default
    if method == "list" {
      let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
      let items = try fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: keys, options: [])
      return items.map { u -> [String: Any] in
        var name = u.lastPathComponent
        // iCloud files not downloaded yet show up as ".<name>.icloud".
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          name = String(name.dropFirst().dropLast(".icloud".count))
        }
        var e: [String: Any] = ["name": name]
        let v = try? u.resourceValues(forKeys: Set(keys))
        if let size = v?.fileSize { e["size"] = size }
        if let m = v?.contentModificationDate {
          e["modified"] = Int(m.timeIntervalSince1970 * 1000)
        }
        return e
      }
    }
    guard let name = args["name"] as? String, !name.contains("/") else {
      throw NSError(domain: "tempo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad name"])
    }
    let file = dir.appendingPathComponent(name)
    var coordError: NSError?
    var inner: Error?
    let coordinator = NSFileCoordinator()
    switch method {
    case "read":
      try? fm.startDownloadingUbiquitousItem(at: file)
      var out = Data()
      coordinator.coordinate(readingItemAt: file, options: [], error: &coordError) { u in
        do { out = try Data(contentsOf: u) } catch { inner = error }
      }
      if let e = coordError { throw e }
      if let e = inner { throw e }
      return FlutterStandardTypedData(bytes: out)
    case "write":
      let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
      coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { u in
        do { try bytes.write(to: u, options: .atomic) } catch { inner = error }
      }
      if let e = coordError { throw e }
      if let e = inner { throw e }
      return nil
    default:  // delete
      guard fm.fileExists(atPath: file.path) else { return nil }
      coordinator.coordinate(writingItemAt: file, options: .forDeleting, error: &coordError) { u in
        do { try fm.removeItem(at: u) } catch { inner = error }
      }
      if let e = coordError { throw e }
      if let e = inner { throw e }
      return nil
    }
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "Picker already open", details: nil))
      return
    }
    guard let top = Self.topController() else {
      result(FlutterError(code: "no_ui", message: "No window to show the picker", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pending = result
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      let inICloud = url.path.contains("/Mobile Documents/")
      result([
        "token": bookmark.base64EncodedString(),
        "name": inICloud ? "iCloud Drive › \(url.lastPathComponent)" : url.lastPathComponent,
      ])
    } catch {
      result(FlutterError(code: "bookmark", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
