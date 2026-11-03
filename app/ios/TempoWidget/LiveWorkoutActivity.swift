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
      HStack(alignment: .center) {
        TempoLockup(size: 13, color: .white)
        Spacer()
        Text(s.paused ? "PAUSED" : "LIVE").font(.system(size: 10, weight: .bold)).kerning(0.8)
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(Capsule().fill(s.paused ? LA.strain.opacity(0.25) : LA.heart.opacity(0.25)))
          .foregroundColor(s.paused ? LA.strain : LA.heart)
      }
      HStack(alignment: .firstTextBaseline) {
        Image(systemName: "heart.fill").foregroundColor(LA.heart)
        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        Spacer()
        Clock(s: s).font(.system(size: 26, weight: .semibold)).monospacedDigit()
          .multilineTextAlignment(.trailing).frame(maxWidth: 120, alignment: .trailing)
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
    .background(
      LinearGradient(
        colors: [Color(hex: 0x1C1F24), Color(hex: 0x0A0B0D)], startPoint: .topLeading,
        endPoint: .bottomTrailing)
    )
    .activityBackgroundTint(Color(hex: 0x0A0B0D))
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
          // The leading region is narrow: heart, a 3-digit bpm and the zone
          // chip on one row wrapped "104" to "1…". The bpm stays on one line
          // (shrinking a little before it could clip) and the chip sits below.
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
              Image(systemName: "heart.fill").foregroundColor(LA.heart)
              Text(s.bpm.map { "\($0)" } ?? "—").font(.system(size: 26, weight: .medium))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
            }
            if s.zone > 0 {
              Text("Z\(s.zone)").font(.system(size: 12, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(LA.zone(s.zone)))
                .foregroundColor(s.zone == 1 ? .white : .black)
            }
          }
          .dynamicIsland(verticalPlacement: .belowIfTooWide)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Clock(s: s).font(.system(size: 26, weight: .medium)).monospacedDigit()
            .multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing)
            .foregroundColor(s.paused ? LA.strain : .white)
        }
        DynamicIslandExpandedRegion(.center) {
          HStack(spacing: 4) {
            TempoMarkShape().fill(LA.strain).frame(width: 11, height: 11)
            Text(ctx.attributes.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
              .foregroundColor(LA.text2)
          }
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
          Text(s.bpm.map { "\($0)" } ?? "—").monospacedDigit().lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      } compactTrailing: {
        if let d = s.distance {
          Text("\(d) \(s.distanceUnit)").monospacedDigit().foregroundColor(LA.strain)
        } else {
          Clock(s: s).monospacedDigit().frame(maxWidth: 56).foregroundColor(LA.strain)
        }
      } minimal: {
        TempoMarkShape().fill(LA.strain).frame(width: 14, height: 14)
      }
      .widgetURL(LA.url)
      .keylineTint(LA.heart)
    }
  }
}
