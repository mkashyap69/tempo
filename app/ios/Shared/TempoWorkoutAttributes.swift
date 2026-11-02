import ActivityKit
import Foundation

/// The live workout's Live Activity. Compiled into both the Runner app
/// (which starts and updates it, LiveActivityChannel.swift) and the
/// TempoWidget extension (which draws it, LiveWorkoutActivity.swift).
/// The state mirrors WorkoutView.toMap in lib/src/core/workout_presence.dart.
@available(iOS 16.1, *)
struct TempoWorkoutAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// Now minus the moving time: a running clock counts up from here.
    var since: Date
    var elapsed: Int
    var paused: Bool
    var bpm: Int?
    var zone: Int
    var distance: String?
    var distanceUnit: String
    var pace: String?
    var paceUnit: String
    var strain: String?
    var segment: String?
  }

  var title: String
  var sport: String
}

@available(iOS 16.1, *)
extension TempoWorkoutAttributes.ContentState {
  /// From the Flutter channel's map; nil when a required key is missing.
  init?(map: [String: Any]) {
    guard let since = map["since"] as? NSNumber else { return nil }
    self.since = Date(timeIntervalSince1970: since.doubleValue / 1000)
    elapsed = (map["elapsed"] as? NSNumber)?.intValue ?? 0
    paused = map["paused"] as? Bool ?? false
    bpm = (map["bpm"] as? NSNumber)?.intValue
    zone = (map["zone"] as? NSNumber)?.intValue ?? 0
    distance = map["distance"] as? String
    distanceUnit = map["distanceUnit"] as? String ?? "km"
    pace = map["pace"] as? String
    paceUnit = map["paceUnit"] as? String ?? "/km"
    strain = map["strain"] as? String
    segment = map["segment"] as? String
  }
}
