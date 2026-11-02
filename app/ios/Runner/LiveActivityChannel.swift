import ActivityKit
import Flutter
import Foundation

/// `tempo/live_activity` (lib/src/core/workout_presence.dart): starts,
/// updates and ends the live workout's Live Activity. Local updates only,
/// no push token: nothing about the workout leaves the phone.
/// TODO(verify) on an iPhone with a Dynamic Island and one without.
final class LiveActivityChannel {
  private static var channel: FlutterMethodChannel?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "TempoLiveActivity") else { return }
    let c = FlutterMethodChannel(name: "tempo/live_activity", binaryMessenger: registrar.messenger())
    c.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(false)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start": Self.start(args, result)
      case "update": Self.update(args, result)
      case "end": Self.end(result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel = c
  }

  @available(iOS 16.2, *)
  private static func start(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let state = TempoWorkoutAttributes.ContentState(map: args)
    else {
      result(false)
      return
    }
    Task {
      // One workout at a time: end anything left over first.
      for a in Activity<TempoWorkoutAttributes>.activities {
        await a.end(nil, dismissalPolicy: .immediate)
      }
      let attrs = TempoWorkoutAttributes(
        title: args["title"] as? String ?? "Workout",
        sport: args["sport"] as? String ?? "other")
      do {
        _ = try Activity.request(
          attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        await MainActor.run { result(true) }
      } catch {
        await MainActor.run {
          result(FlutterError(code: "activity", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  @available(iOS 16.2, *)
  private static func update(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let state = TempoWorkoutAttributes.ContentState(map: args) else {
      result(nil)
      return
    }
    Task {
      // Marked stale if the app stops updating (killed mid-workout).
      let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
      for a in Activity<TempoWorkoutAttributes>.activities {
        await a.update(content)
      }
      await MainActor.run { result(nil) }
    }
  }

  @available(iOS 16.2, *)
  private static func end(_ result: @escaping FlutterResult) {
    Task {
      for a in Activity<TempoWorkoutAttributes>.activities {
        await a.end(nil, dismissalPolicy: .immediate)
      }
      await MainActor.run { result(nil) }
    }
  }
}
