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

  func entry(placeholder: Bool) -> TempoEntry { read(placeholder: placeholder) }

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
          Link(destination: URL(string: "tempo://recovery?homeWidget")!) {
            MetricColumn(m: entry.rec, big: false, ticks: 10, stale: entry.stale)
          }
          Link(destination: URL(string: "tempo://strain?homeWidget")!) {
            MetricColumn(m: entry.strain, big: false, ticks: 10, stale: entry.stale)
          }
          Link(destination: URL(string: "tempo://sleep?homeWidget")!) {
            MetricColumn(m: entry.sleep, big: false, ticks: 10, stale: entry.stale)
          }
        }
      }
    }
    .widgetURL(URL(string: family == .systemSmall ? "tempo://recovery?homeWidget" : "tempo://today?homeWidget"))
    .containerBackground(for: .widget) { Palette.surface(scheme) }
  }
}

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

// MARK: - Tempo Coach session widget

struct SessionEntry: TimelineEntry {
  let date: Date
  let title: String
  let detail: String
  let status: String
  let level: String  // pending | late | done | missed | rest
  let stale: Bool
}

struct SessionProvider: TimelineProvider {
  func placeholder(in context: Context) -> SessionEntry { read(placeholder: true) }

  func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
    completion(read(placeholder: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
    completion(Timeline(entries: [read(placeholder: false)], policy: .after(next)))
  }

  private func read(placeholder: Bool) -> SessionEntry {
    let d = UserDefaults(suiteName: appGroup)
    func s(_ k: String, _ fallback: String) -> String { placeholder ? fallback : (d?.string(forKey: k) ?? fallback) }
    let updated = Double(d?.string(forKey: "updated_at") ?? "") ?? 0
    let stale = !placeholder && Date().timeIntervalSince1970 - updated / 1000 > 12 * 3600
    return SessionEntry(
      date: Date(), title: s("session_title", "Easy run 35′"),
      detail: stale ? "Open Tempo to update today’s plan" : s("session_detail", "Z1–Z2 · adds ~6 strain"),
      status: stale ? "" : s("session_status", "Planned 18:00"), level: s("session_level", "pending"),
      stale: stale)
  }
}

struct SessionWidgetView: View {
  let entry: SessionEntry
  @Environment(\.colorScheme) var scheme
  var statusColor: Color {
    switch entry.level {
    case "done": return Palette.recHigh
    case "missed": return Palette.recLow
    case "late": return Palette.recMid
    default: return Palette.text2(scheme)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("TODAY").font(.system(size: 10, weight: .semibold)).kerning(0.9)
        .foregroundColor(Palette.text3(scheme))
      Text(entry.title).font(.system(size: 18, weight: .medium)).lineLimit(1)
        .foregroundColor(Palette.text1(scheme))
      Text(entry.detail).font(.system(size: 12)).lineLimit(1)
        .foregroundColor(Palette.text2(scheme))
      Spacer(minLength: 0)
      HStack {
        Text(entry.status).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          .foregroundColor(statusColor)
        Spacer()
        if entry.level != "rest" && !entry.stale {
          Link(destination: URL(string: "tempo://start?homeWidget")!) {
            Text("Start").font(.system(size: 13, weight: .semibold))
              .padding(.horizontal, 16).padding(.vertical, 7)
              .background(Capsule().fill(Palette.text1(scheme)))
              .foregroundColor(Palette.surface(scheme))
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(URL(string: "tempo://coach?homeWidget"))
    .containerBackground(for: .widget) { Palette.surface(scheme) }
  }
}

struct TempoSessionWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TempoSessionWidget", provider: SessionProvider()) { entry in
      SessionWidgetView(entry: entry)
    }
    .configurationDisplayName("Tempo · Session")
    .description("Today’s session, its status and Start.")
    .supportedFamilies([.systemMedium])
  }
}

// MARK: - Day widget (large) and lock-screen widgets

struct DayEntry: TimelineEntry {
  let date: Date
  let base: TempoEntry
  let callLead: String
  let callRest: String
  let callTone: String  // good | mid | low | plain | muted
  let steps: String
  let stepsGoal: String
  let stepsFill: Double
  let strainLo: Double
  let strainHi: Double
  let bedTime: String
  let sleepNeed: String
  let session: String
}

struct DayProvider: TimelineProvider {
  func placeholder(in context: Context) -> DayEntry { read(placeholder: true) }

  func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
    completion(read(placeholder: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
    completion(Timeline(entries: [read(placeholder: false)], policy: .after(next)))
  }

  private func read(placeholder: Bool) -> DayEntry {
    let d = UserDefaults(suiteName: appGroup)
    func s(_ k: String, _ fallback: String) -> String { placeholder ? fallback : (d?.string(forKey: k) ?? fallback) }
    func pct(_ k: String, _ fallback: Double) -> Double {
      placeholder ? fallback : Double(d?.integer(forKey: k) ?? 0) / 100
    }
    let base = Provider().entry(placeholder: placeholder)
    return DayEntry(
      date: Date(), base: base,
      callLead: base.stale ? "Open Tempo" : s("call_lead", "Primed."),
      callRest: base.stale ? " to update today." : s("call_rest", " Go for the planned tempo run."),
      callTone: base.stale ? "muted" : s("call_tone", "good"),
      steps: base.stale ? "—" : s("steps_value", "6,240"), stepsGoal: s("steps_goal", "8,000"),
      stepsFill: base.stale ? 0 : pct("steps_fill", 0.78),
      strainLo: pct("strain_lo", 0.62), strainHi: pct("strain_hi", 0.76),
      bedTime: s("bed_time", "22:45"), sleepNeed: s("sleep_need", "8h 05m"),
      session: s("session_title", "Easy run 35′"))
  }
}

private func toneColor(_ tone: String, _ scheme: ColorScheme) -> Color {
  switch tone {
  case "good": return Palette.recHigh
  case "mid": return Palette.recMid
  case "low": return Palette.recLow
  case "plain": return Palette.text1(scheme)
  default: return Palette.text2(scheme)
  }
}

/// A bar with today's strain and its target band shaded.
struct TargetBar: View {
  let fill: Double
  let lo: Double
  let hi: Double
  let color: Color
  @Environment(\.colorScheme) var scheme
  var body: some View {
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.track(scheme))
        if hi > lo {
          Rectangle().fill(color.opacity(0.3))
            .frame(width: g.size.width * (hi - lo))
            .offset(x: g.size.width * lo)
        }
        Capsule().fill(color).frame(width: max(6, g.size.width * min(1, fill)))
      }
    }
    .frame(height: 8)
    .clipShape(Capsule())
  }
}

struct DayWidgetView: View {
  let entry: DayEntry
  @Environment(\.colorScheme) var scheme
  var body: some View {
    let b = entry.base
    VStack(alignment: .leading, spacing: 12) {
      (Text(entry.callLead).foregroundColor(toneColor(entry.callTone, scheme))
        + Text(entry.callRest).foregroundColor(Palette.text1(scheme)))
        .font(.system(size: 17, weight: .medium)).lineLimit(3)
      HStack(spacing: 14) {
        Link(destination: URL(string: "tempo://recovery?homeWidget")!) {
          MetricColumn(m: b.rec, big: false, ticks: 10, stale: b.stale)
        }
        Link(destination: URL(string: "tempo://strain?homeWidget")!) {
          MetricColumn(m: b.strain, big: false, ticks: 10, stale: b.stale)
        }
        Link(destination: URL(string: "tempo://sleep?homeWidget")!) {
          MetricColumn(m: b.sleep, big: false, ticks: 10, stale: b.stale)
        }
      }
      .frame(height: 104)
      VStack(alignment: .leading, spacing: 6) {
        row("Strain", "\(b.strain.value) · target band shaded")
        TargetBar(fill: b.strain.fill, lo: entry.strainLo, hi: entry.strainHi, color: Palette.strain)
      }
      VStack(alignment: .leading, spacing: 6) {
        row("Steps", "\(entry.steps) of \(entry.stepsGoal)")
        TargetBar(fill: entry.stepsFill, lo: 0, hi: 0, color: Palette.recHigh)
      }
      Spacer(minLength: 0)
      HStack {
        label("Today", entry.session)
        Spacer()
        label("In bed by", "\(entry.bedTime) · need \(entry.sleepNeed)")
      }
    }
    .widgetURL(URL(string: "tempo://today?homeWidget"))
    .containerBackground(for: .widget) { Palette.surface(scheme) }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.9)
        .foregroundColor(Palette.text3(scheme))
      Spacer()
      Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
        .foregroundColor(Palette.text2(scheme))
    }
  }

  private func label(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.9)
        .foregroundColor(Palette.text3(scheme))
      Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1)
        .foregroundColor(Palette.text1(scheme))
    }
  }
}

struct TempoDayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TempoDayWidget", provider: DayProvider()) { entry in
      DayWidgetView(entry: entry)
    }
    .configurationDisplayName("Tempo · Day")
    .description("Today’s call, your three numbers, strain and steps against target, and bedtime.")
    .supportedFamilies([.systemLarge])
  }
}

/// Lock screen: a recovery gauge, the three numbers, or one line.
struct LockWidgetView: View {
  let entry: DayEntry
  @Environment(\.widgetFamily) var family
  var body: some View {
    let b = entry.base
    Group {
      switch family {
      case .accessoryCircular:
        Gauge(value: b.rec.fill) {
          Text("REC")
        } currentValueLabel: {
          Text(b.rec.value).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
      case .accessoryInline:
        Text("Rec \(b.rec.value)\(b.rec.unit) · Strain \(b.strain.value) · Sleep \(b.sleep.value)")
      default:
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 10) {
            mini("REC", b.rec.value + b.rec.unit)
            mini("STRAIN", b.strain.value)
            mini("SLEEP", b.sleep.value)
          }
          Text(entry.callLead + entry.callRest).font(.system(size: 12)).lineLimit(1)
        }
      }
    }
    .widgetURL(URL(string: "tempo://today?homeWidget"))
    .containerBackground(for: .widget) { Color.clear }
  }

  private func mini(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label).font(.system(size: 9, weight: .semibold))
      Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
    }
  }
}

struct TempoLockWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TempoLockWidget", provider: DayProvider()) { entry in
      LockWidgetView(entry: entry)
    }
    .configurationDisplayName("Tempo · Lock screen")
    .description("Recovery as a gauge, or recovery, strain and sleep.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

@main
struct TempoWidgets: WidgetBundle {
  var body: some Widget {
    TempoWidget()
    TempoSessionWidget()
    TempoDayWidget()
    TempoLockWidget()
    LiveWorkoutActivity()
  }
}
