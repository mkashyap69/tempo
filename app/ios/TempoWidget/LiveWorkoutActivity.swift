import ActivityKit
import SwiftUI
import WidgetKit

// The live workout on the lock screen and in the Dynamic Island. Started
// and updated by the app (Runner/LiveActivityChannel.swift); the clock
// ticks on its own between updates, so it stays right even when iOS
// delays one. State: ios/Shared/TempoWorkoutAttributes.swift.

private enum LA {
  static let heart = Color(hex: 0xEE4F6C)
  static let strain = Color(hex: 0xFFB066)
  static let text2 = Color(hex: 0xA9ADB4)
  static let zones: [Color] = [
    // The app's dark-theme zone fills (design/tokens.dart).
    Color(hex: 0x5D636D), Color(hex: 0xFFE0B3), Color(hex: 0xFFBE76),
    Color(hex: 0xFF9446), Color(hex: 0xEE6A2C),
  ]
  static func zone(_ z: Int) -> Color { z >= 1 && z <= 5 ? zones[z - 1] : text2 }
  static let url = URL(string: "tempo://workout?homeWidget")!
}

@available(iOS 16.2, *)
private struct Clock: View {
  let s: TempoWorkoutAttributes.ContentState
  var body: some View {
    if s.paused {
      Text(Self.mmss(s.elapsed))
    } else {
      // Counts up from `since` without the app.
      Text(timerInterval: s.since...Date.distantFuture, countsDown: false)
    }
  }
  static func mmss(_ sec: Int) -> String {
    let h = sec / 3600, m = (sec % 3600) / 60, r = sec % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
  }
}

@available(iOS 16.2, *)
private struct Stat: View {
  let label: String
  let value: String
  let unit: String
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.6)
        .foregroundColor(LA.text2)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(value).font(.system(size: 20, weight: .medium)).monospacedDigit()
        Text(unit).font(.system(size: 11)).foregroundColor(LA.text2)
      }
      .lineLimit(1).minimumScaleFactor(0.7)
    }
  }
}

@available(iOS 16.2, *)
private struct LockScreen: View {
  let title: String
  let s: TempoWorkoutAttributes.ContentState
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "heart.fill").foregroundColor(LA.heart)
        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        Spacer()
        if s.paused {
          Text("PAUSED").font(.system(size: 11, weight: .bold)).foregroundColor(LA.strain)
        }
        Clock(s: s).font(.system(size: 22, weight: .semibold)).monospacedDigit()
          .multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing)
      }
      HStack(alignment: .top, spacing: 16) {
        Stat(
          label: s.zone > 0 ? "Heart · Z\(s.zone)" : "Heart", value: s.bpm.map { "\($0)" } ?? "—",
          unit: "bpm")
        if let d = s.distance {
          Stat(label: "Distance", value: d, unit: s.distanceUnit)
        }
        if let p = s.pace {
          Stat(label: "Pace", value: p, unit: s.paceUnit)
        } else if let st = s.strain {
          Stat(label: "Strain", value: st, unit: "")
        }
        Spacer(minLength: 0)
      }
      if let seg = s.segment {
        Text(seg).font(.system(size: 12, weight: .medium)).foregroundColor(LA.text2)
      }
    }
    .padding(16)
    .foregroundColor(.white)
    .activityBackgroundTint(Color(hex: 0x121417))
    .activitySystemActionForegroundColor(.white)
    .widgetURL(LA.url)
  }
}

@available(iOS 16.2, *)
struct LiveWorkoutActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TempoWorkoutAttributes.self) { ctx in
      LockScreen(title: ctx.attributes.title, s: ctx.state)
    } dynamicIsland: { ctx in
      let s = ctx.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundColor(LA.heart)
            Text(s.bpm.map { "\($0)" } ?? "—").font(.system(size: 26, weight: .medium))
              .monospacedDigit()
            if s.zone > 0 {
              Text("Z\(s.zone)").font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(LA.zone(s.zone)))
                .foregroundColor(s.zone == 1 ? .white : .black)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Clock(s: s).font(.system(size: 26, weight: .medium)).monospacedDigit()
            .multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing)
            .foregroundColor(s.paused ? LA.strain : .white)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 16) {
            if let d = s.distance { Stat(label: "Distance", value: d, unit: s.distanceUnit) }
            if let p = s.pace { Stat(label: "Pace", value: p, unit: s.paceUnit) }
            if let st = s.strain { Stat(label: "Strain", value: st, unit: "") }
            if let seg = s.segment {
              Text(seg).font(.system(size: 12)).foregroundColor(LA.text2)
            }
            Spacer(minLength: 0)
          }
        }
      } compactLeading: {
        HStack(spacing: 3) {
          Image(systemName: "heart.fill").foregroundColor(LA.heart)
          Text(s.bpm.map { "\($0)" } ?? "—").monospacedDigit()
        }
      } compactTrailing: {
        if let d = s.distance {
          Text("\(d) \(s.distanceUnit)").monospacedDigit().foregroundColor(LA.strain)
        } else {
          Clock(s: s).monospacedDigit().frame(maxWidth: 56).foregroundColor(LA.strain)
        }
      } minimal: {
        Image(systemName: "heart.fill").foregroundColor(LA.heart)
      }
      .widgetURL(LA.url)
      .keylineTint(LA.heart)
    }
  }
}
