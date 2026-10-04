import SwiftUI
import WidgetKit

// Home-screen widgets (design 12). Small = Recovery; medium = Recovery,
// Strain and Sleep. Flutter writes the values through home_widget into the
// shared app group (lib/src/core/home_widgets.dart). Older than 2 h: dim and
// say when instead of showing old numbers as current.

private let appGroup = "group.dev.tempo.tempo"

struct Metric {
  let label: String
  let value: String
  let unit: String
  let state: String
  let fill: Double  // 0...1
  let color: Color
}

struct TempoEntry: TimelineEntry {
  let date: Date
  let rec: Metric
  let strain: Metric
  let sleep: Metric
  let stale: Bool
}

private enum Palette {
  static func dark(_ scheme: ColorScheme) -> Bool { scheme == .dark }
  static func surface(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x121417) : .white }
  static func text1(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0xF3F2EF) : Color(hex: 0x121316) }
  static func text2(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0xA9ADB4) : Color(hex: 0x575B62) }
  static func text3(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x858A92) : Color(hex: 0x6B6F76) }
  static func track(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x2A2E35) : Color(hex: 0xDEDBD5) }
  static let recHigh = Color(hex: 0x3CCBC0)
  static let recMid = Color(hex: 0xF0C24B)
  static let recLow = Color(hex: 0xEE4F6C)
  static let strain = Color(hex: 0xFFB066)
  static let sleep = Color(hex: 0x9AA4FF)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> TempoEntry { read(placeholder: true) }

  func getSnapshot(in context: Context, completion: @escaping (TempoEntry) -> Void) {
    completion(read(placeholder: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TempoEntry>) -> Void) {
    // Re-read hourly; the app also reloads on every sync.
    let entry = read(placeholder: false)
    let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(next)))
  }

  private func read(placeholder: Bool) -> TempoEntry {
    let d = UserDefaults(suiteName: appGroup)
    func s(_ k: String, _ fallback: String) -> String { placeholder ? fallback : (d?.string(forKey: k) ?? fallback) }
    func pct(_ k: String, _ fallback: Double) -> Double {
      placeholder ? fallback : Double(d?.integer(forKey: k) ?? 0) / 100
    }
    let updated = Double(d?.string(forKey: "updated_at") ?? "") ?? 0
    let age = Date().timeIntervalSince1970 - updated / 1000
    let stale = !placeholder && age > 2 * 3600
    let level = s("rec_level", "high")
    let recColor: Color =
      level == "high" ? Palette.recHigh : level == "mid" ? Palette.recMid : level == "low" ? Palette.recLow : Color.gray
    let hours = Int(age / 3600)
    return TempoEntry(
      date: Date(),
      rec: Metric(
        label: "Recovery", value: s("rec_value", "78"), unit: s("rec_unit", "%"),
        state: stale ? "Last night" : s("rec_state", "▲ Primed"), fill: pct("rec_fill", 0.78), color: recColor),
      strain: Metric(
        label: "Strain", value: stale ? "—" : s("strain_value", "8.4"), unit: "",
        state: stale ? "Open to sync" : s("strain_state", "Target 13–16"), fill: stale ? 0 : pct("strain_fill", 0.4),
        color: Palette.strain),
      sleep: Metric(
        label: "Sleep", value: s("sleep_value", "92"), unit: s("sleep_value", "92") == "—" ? "" : "%",
        state: stale ? "\(hours) h ago" : s("sleep_state", "7h 12m"), fill: pct("sleep_fill", 0.92),
        color: Palette.sleep),
      stale: stale)
  }
}

struct Ticks: View {
  let count: Int
  let fill: Double
  let color: Color
  @Environment(\.colorScheme) var scheme
  var body: some View {
    let lit = Int((fill * Double(count)).rounded())
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(0..<count, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(i < lit ? color : Palette.track(scheme))
          .frame(height: (i + 1) % 5 == 0 ? 16 : 10)
      }
    }
    .frame(height: 16)
  }
}

struct MetricColumn: View {
  let m: Metric
  let big: Bool
  let ticks: Int
  let stale: Bool
  @Environment(\.colorScheme) var scheme
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(m.label.uppercased())
        .font(.system(size: 10, weight: .semibold)).kerning(0.9)
        .foregroundColor(Palette.text3(scheme))
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(m.value).font(.system(size: big ? 52 : 34, weight: .light)).monospacedDigit()
        Text(m.unit).font(.system(size: 13)).foregroundColor(Palette.text3(scheme))
      }
      .foregroundColor(stale ? Palette.text2(scheme) : Palette.text1(scheme))
      .minimumScaleFactor(0.6)
      .lineLimit(1)
      Text(m.state).font(.system(size: 12, weight: .medium)).lineLimit(1)
        .foregroundColor(stale ? Palette.text2(scheme) : m.color)
      Spacer(minLength: 0)
      Ticks(count: ticks, fill: m.fill, color: stale ? Palette.text3(scheme) : m.color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct TempoWidgetView: View {
  let entry: TempoEntry
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var scheme
  var body: some View {
    Group {
      if family == .systemSmall {
        MetricColumn(m: entry.rec, big: true, ticks: 14, stale: entry.stale)
      } else {
        // Each column opens its own detail screen.
        HStack(spacing: 14) {
          Link(destination: URL(string: "tempo://recovery")!) {
            MetricColumn(m: entry.rec, big: false, ticks: 10, stale: entry.stale)
          }
          Link(destination: URL(string: "tempo://strain")!) {
            MetricColumn(m: entry.strain, big: false, ticks: 10, stale: entry.stale)
          }
          Link(destination: URL(string: "tempo://sleep")!) {
            MetricColumn(m: entry.sleep, big: false, ticks: 10, stale: entry.stale)
          }
        }
      }
    }
    .widgetURL(URL(string: family == .systemSmall ? "tempo://recovery" : "tempo://today"))
    .containerBackground(for: .widget) { Palette.surface(scheme) }
  }
}

@main
struct TempoWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TempoWidget", provider: Provider()) { entry in
      TempoWidgetView(entry: entry)
    }
    .configurationDisplayName("Tempo")
    .description("Recovery, strain and sleep at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
