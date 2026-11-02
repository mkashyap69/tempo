import SwiftUI
import WidgetKit

// Home-screen and lock-screen widgets. Flutter writes the values through
// home_widget into the shared app group (lib/src/core/home_widgets.dart).
// Older than 2 h: dim and say when instead of showing old numbers as
// current. Every widget carries the Tempo lockup (mark + wordmark), the
// same geometry as TempoMark in lib/src/design/components.dart.
// Links must carry `?homeWidget` or home_widget ignores them.

private let appGroup = "group.dev.tempo.tempo"

// MARK: - Brand

/// The Tempo mark: one tall stroke, three measured ones (48 × 48 grid).
struct TempoMarkShape: Shape {
  func path(in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) / 48
    let ox = rect.minX + (rect.width - 48 * k) / 2
    let oy = rect.minY + (rect.height - 48 * k) / 2
    var p = Path()
    for (x, y, h) in [(5.5, 8.0, 32.0), (16, 27, 13), (26.5, 27, 13), (37, 27, 13)] {
      p.addRoundedRect(
        in: CGRect(x: ox + x * k, y: oy + y * k, width: 5.5 * k, height: h * k),
        cornerSize: CGSize(width: 2.75 * k, height: 2.75 * k))
    }
    return p
  }
}

/// Mark + "tempo", as in the app's TempoLockup.
struct TempoLockup: View {
  var size: CGFloat = 13
  var color: Color
  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: size * 0.3) {
      TempoMarkShape().fill(color).frame(width: size, height: size)
        .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - size * 0.06 }
      Text("tempo").font(.system(size: size * 1.15, weight: .semibold)).kerning(-0.4)
        .foregroundColor(color)
    }
  }
}

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
  let updated: Date?
}

enum Palette {
  static func dark(_ scheme: ColorScheme) -> Bool { scheme == .dark }
  static func surface(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x121417) : .white }
  static func surfaceHi(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x1C1F24) : Color(hex: 0xF6F4F0) }
  static func text1(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0xF3F2EF) : Color(hex: 0x121316) }
  static func text2(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0xA9ADB4) : Color(hex: 0x575B62) }
  static func text3(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x858A92) : Color(hex: 0x6B6F76) }
  static func track(_ s: ColorScheme) -> Color { dark(s) ? Color(hex: 0x2A2E35) : Color(hex: 0xE6E3DD) }
  static let recHigh = Color(hex: 0x3CCBC0)
  static let recMid = Color(hex: 0xF0C24B)
  static let recLow = Color(hex: 0xEE4F6C)
  static let strain = Color(hex: 0xFFB066)
  static let sleep = Color(hex: 0x9AA4FF)

  /// The widget surface: a soft top-left glow over the card colour.
  static func background(_ s: ColorScheme, tint: Color) -> some View {
    ZStack {
      LinearGradient(
        colors: [surfaceHi(s), surface(s)], startPoint: .topLeading, endPoint: .bottomTrailing)
      RadialGradient(
        colors: [tint.opacity(dark(s) ? 0.16 : 0.10), .clear], center: .topTrailing,
        startRadius: 0, endRadius: 180)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

/// "updated 12 min ago" for the header.
private func agoText(_ d: Date?) -> String {
  guard let d = d else { return "" }
  let m = Int(Date().timeIntervalSince(d) / 60)
  if m < 1 { return "now" }
  if m < 60 { return "\(m) min ago" }
  return "\(m / 60) h ago"
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> TempoEntry { read(placeholder: true) }

  func getSnapshot(in context: Context, completion: @escaping (TempoEntry) -> Void) {
    completion(read(placeholder: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TempoEntry>) -> Void) {
    // Re-read every 30 min (the "ago" line moves); the app also reloads on
    // every sync.
    let entry = read(placeholder: false)
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(next)))
  }

  func entry(placeholder: Bool) -> TempoEntry { read(placeholder: placeholder) }

  private func read(placeholder: Bool) -> TempoEntry {
    let d = UserDefaults(suiteName: appGroup)
    func s(_ k: String, _ fallback: String) -> String { placeholder ? fallback : (d?.string(forKey: k) ?? fallback) }
    func pct(_ k: String, _ fallback: Double) -> Double {
      placeholder ? fallback : Double(d?.integer(forKey: k) ?? 0) / 100
    }
    let updatedMs = Double(d?.string(forKey: "updated_at") ?? "") ?? 0
    let age = Date().timeIntervalSince1970 - updatedMs / 1000
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
      stale: stale,
      updated: placeholder || updatedMs == 0 ? nil : Date(timeIntervalSince1970: updatedMs / 1000))
  }
}

// MARK: - Pieces

/// A ring filled to [fill] with the value in the middle.
struct Ring: View {
  let m: Metric
  let size: CGFloat
  let line: CGFloat
  let stale: Bool
  @Environment(\.colorScheme) var scheme
  var body: some View {
    let color = stale ? Palette.text3(scheme) : m.color
    ZStack {
      Circle().stroke(Palette.track(scheme), lineWidth: line)
      Circle().trim(from: 0, to: max(0.001, min(1, m.fill)))
        .stroke(
          AngularGradient(
            colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0),
            endAngle: .degrees(360 * max(0.05, min(1, m.fill)))),
          style: StrokeStyle(lineWidth: line, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(m.value).font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
          .monospacedDigit()
        Text(m.unit).font(.system(size: size * 0.13, weight: .medium))
          .foregroundColor(Palette.text3(scheme))
      }
      .foregroundColor(stale ? Palette.text2(scheme) : Palette.text1(scheme))
      .minimumScaleFactor(0.5).lineLimit(1)
      .padding(line * 1.4)
    }
    .frame(width: size, height: size)
  }
}

/// Label, ring and state for one score.
struct RingColumn: View {
  let m: Metric
  let size: CGFloat
  let stale: Bool
  @Environment(\.colorScheme) var scheme
  var body: some View {
    VStack(spacing: 6) {
      Text(m.label.uppercased()).font(.system(size: 9.5, weight: .semibold)).kerning(0.8)
        .foregroundColor(Palette.text3(scheme))
      Ring(m: m, size: size, line: size * 0.11, stale: stale)
      Text(m.state).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
        .foregroundColor(stale ? Palette.text2(scheme) : m.color)
    }
    .frame(maxWidth: .infinity)
  }
}

/// Lockup on the left, a quiet note on the right.
struct Header: View {
  let note: String
  @Environment(\.colorScheme) var scheme
  var body: some View {
    HStack {
      TempoLockup(size: 12, color: Palette.text1(scheme))
      Spacer(minLength: 4)
      Text(note).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
        .foregroundColor(Palette.text3(scheme))
    }
  }
}

// MARK: - Recovery (small) and the three scores (medium)

struct TempoWidgetView: View {
  let entry: TempoEntry
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var scheme
  var body: some View {
    Group {
      if family == .systemSmall {
        VStack(spacing: 8) {
          Header(note: entry.stale ? agoText(entry.updated) : "")
          Ring(m: entry.rec, size: 86, line: 9, stale: entry.stale)
          Text(entry.rec.state).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            .foregroundColor(entry.stale ? Palette.text2(scheme) : entry.rec.color)
        }
      } else {
        VStack(spacing: 10) {
          Header(note: agoText(entry.updated))
          HStack(spacing: 6) {
            Link(destination: URL(string: "tempo://recovery?homeWidget")!) {
              RingColumn(m: entry.rec, size: 64, stale: entry.stale)
            }
            Link(destination: URL(string: "tempo://strain?homeWidget")!) {
              RingColumn(m: entry.strain, size: 64, stale: entry.stale)
            }
            Link(destination: URL(string: "tempo://sleep?homeWidget")!) {
              RingColumn(m: entry.sleep, size: 64, stale: entry.stale)
            }
          }
        }
      }
    }
    .widgetURL(URL(string: family == .systemSmall ? "tempo://recovery?homeWidget" : "tempo://today?homeWidget"))
    .containerBackground(for: .widget) { Palette.background(scheme, tint: entry.rec.color) }
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
      Header(note: "TODAY")
      Spacer(minLength: 2)
      Text(entry.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
        .foregroundColor(Palette.text1(scheme))
      Text(entry.detail).font(.system(size: 12)).lineLimit(1)
        .foregroundColor(Palette.text2(scheme))
      Spacer(minLength: 0)
      HStack {
        if !entry.status.isEmpty {
          HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(entry.status).font(.system(size: 13, weight: .semibold)).lineLimit(1)
              .foregroundColor(statusColor)
          }
        }
        Spacer()
        if entry.level != "rest" && !entry.stale {
          Link(destination: URL(string: "tempo://start?homeWidget")!) {
            HStack(spacing: 5) {
              Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
              Text("Start").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Palette.text1(scheme)))
            .foregroundColor(Palette.surface(scheme))
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetURL(URL(string: "tempo://coach?homeWidget"))
    .containerBackground(for: .widget) { Palette.background(scheme, tint: statusColor) }
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

/// A bar with today's value and, when given, its target band shaded.
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
        Capsule()
          .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
          .frame(width: max(8, g.size.width * min(1, fill)))
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
      Header(note: Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
      (Text(entry.callLead).foregroundColor(toneColor(entry.callTone, scheme))
        + Text(entry.callRest).foregroundColor(Palette.text1(scheme)))
        .font(.system(size: 17, weight: .semibold)).lineLimit(3)
      HStack(spacing: 6) {
        Link(destination: URL(string: "tempo://recovery?homeWidget")!) {
          RingColumn(m: b.rec, size: 70, stale: b.stale)
        }
        Link(destination: URL(string: "tempo://strain?homeWidget")!) {
          RingColumn(m: b.strain, size: 70, stale: b.stale)
        }
        Link(destination: URL(string: "tempo://sleep?homeWidget")!) {
          RingColumn(m: b.sleep, size: 70, stale: b.stale)
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        row("Strain", "\(b.strain.value) · \(b.strain.state)")
        TargetBar(fill: b.strain.fill, lo: entry.strainLo, hi: entry.strainHi, color: Palette.strain)
      }
      VStack(alignment: .leading, spacing: 6) {
        row("Steps", "\(entry.steps) of \(entry.stepsGoal)")
        TargetBar(fill: entry.stepsFill, lo: 0, hi: 0, color: Palette.recHigh)
      }
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        chip("figure.run", "Today", entry.session)
        chip("moon.fill", "In bed by", "\(entry.bedTime) · \(entry.sleepNeed)")
      }
    }
    .widgetURL(URL(string: "tempo://today?homeWidget"))
    .containerBackground(for: .widget) {
      Palette.background(scheme, tint: toneColor(entry.callTone, scheme))
    }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).kerning(0.8)
        .foregroundColor(Palette.text3(scheme))
      Spacer()
      Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        .foregroundColor(Palette.text2(scheme))
    }
  }

  private func chip(_ icon: String, _ title: String, _ value: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 12, weight: .semibold))
        .foregroundColor(Palette.text2(scheme))
      VStack(alignment: .leading, spacing: 1) {
        Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).kerning(0.6)
          .foregroundColor(Palette.text3(scheme))
        Text(value).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
          .foregroundColor(Palette.text1(scheme))
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.track(scheme).opacity(0.55)))
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
          TempoMarkShape().frame(width: 10, height: 10)
        } currentValueLabel: {
          Text(b.rec.value).monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
      case .accessoryInline:
        Text("Recovery \(b.rec.value)\(b.rec.unit) · Strain \(b.strain.value)")
      default:
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            TempoMarkShape().frame(width: 10, height: 10)
            Text("tempo").font(.system(size: 11, weight: .semibold))
          }
          HStack(spacing: 10) {
            mini("REC", b.rec.value + b.rec.unit)
            mini("STRAIN", b.strain.value)
            mini("SLEEP", b.sleep.value)
          }
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
