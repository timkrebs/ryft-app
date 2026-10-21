// Readiness on the home and lock screen: what Today shows, from the snapshot the app
// writes into the App Group container after each refresh (`ReadinessSnapshot`). The app
// reloads the widget when a new score lands; the timeline only turns the day over.
import SwiftUI
import WidgetKit

struct ReadinessEntry: TimelineEntry {
    let date: Date
    /// `nil`: the app hasn't written one (not opened yet, signed out, no App Group).
    let snapshot: ReadinessSnapshot?

    /// What it shows at `date` (yesterday's score is no score for today).
    var shown: ReadinessSnapshot? { snapshot?.asOf(date) }
    /// "Bed by 22:41" from 17:00 until then.
    var bedtime: Date? { snapshot?.bedtimeShown(at: date) }
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, snapshot: .preview(.score))
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        completion(ReadinessEntry(date: .now, snapshot: context.isPreview ? .preview(.score) : ReadinessSnapshot.load()))
    }

    /// Now, and the next midnight (the day turns over without the app); then ask again.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let now = Date.now
        let snapshot = ReadinessSnapshot.load()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        // 17:00 brings tonight's bedtime in; the bedtime itself takes it out again.
        let evening = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        let turns = [now, evening, snapshot?.bedtime, midnight].compactMap { $0 }.filter { $0 >= now && $0 <= midnight }
        completion(Timeline(entries: Set(turns).sorted().map { ReadinessEntry(date: $0, snapshot: snapshot) },
                            policy: .atEnd))
    }
}

struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ReadinessSnapshot.widgetKind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "ryft://today"))
        }
        .configurationDisplayName(Text("Readiness"))
        .description(Text("Today's readiness, or how far scoring your night is."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Graphite in dark, Mist in light, like the app.
private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View { scheme == .dark ? Brand.graphite : Brand.mist }
}

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: CircularReadiness(snapshot: entry.shown)
        case .accessoryRectangular: RectangularReadiness(snapshot: entry.shown, bedtime: entry.bedtime)
        case .accessoryInline: Text(Words.inline(entry.shown, bedtime: entry.bedtime))
        default: SmallReadiness(snapshot: entry.shown, bedtime: entry.bedtime)
        }
    }
}

// MARK: - words

enum Words {
    /// The gauge's band word on Today.
    static func band(_ readiness: Int) -> String {
        switch readiness {
        case 67...: return String(localized: "High")
        case 34...: return String(localized: "Moderate")
        default: return String(localized: "Low")
        }
    }

    /// Under the ring, or the rectangle's second line.
    static func status(_ s: ReadinessSnapshot?) -> String {
        guard let s else { return String(localized: "Open RYFT to see your readiness.") }
        switch s.kind {
        case .score: return s.readiness.map(band) ?? ""
        case .pending: return String(localized: "Scoring your night…")
        case .waitingForSleep: return String(localized: "Waiting for last night")
        case .calibrating:
            return String(localized: "Baselines \(s.baselineNights ?? 0) of \(ReadinessSnapshot.baselineNightsRequired)")
        }
    }

    static func inline(_ s: ReadinessSnapshot?, bedtime: Date? = nil) -> String {
        if let bedtime { return bedBy(bedtime) }
        if let r = s?.readiness, s?.kind == .score { return String(localized: "Readiness \(r) · \(band(r))") }
        return status(s)
    }

    /// "Bed by 22:41".
    static func bedBy(_ bedtime: Date) -> String {
        String(localized: "Bed by \(bedtime.formatted(date: .omitted, time: .shortened))")
    }

    /// For VoiceOver: the value and whether it's today's.
    static func spoken(_ s: ReadinessSnapshot?) -> String {
        guard let s else { return status(nil) }
        switch s.kind {
        case .score: return s.readiness.map { String(localized: "Readiness \($0), \(band($0))") } ?? ""
        case .pending, .waitingForSleep:
            let prefix = status(s)
            guard let previous = s.previousReadiness else { return prefix }
            return prefix + " " + String(localized: "Last readiness \(previous).")
        case .calibrating: return status(s)
        }
    }
}

// MARK: - home screen

/// The ring like Today's gauge: teal arc for a score; an outline with the last value dimmed
/// while the night isn't scored; a segment per night while the baselines are learned.
private struct SmallReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date? = nil
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? Brand.mist : Brand.graphite }

    var body: some View {
        VStack(spacing: 6) {
            Text("Readiness")
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(ink.opacity(0.6))
            ZStack {
                ring
                Text(number)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isFinal ? ink : ink.opacity(0.4))
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 84, height: 84)
            if let bedtime {
                Text(Words.bedBy(bedtime))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Brand.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(Words.status(snapshot))
                    .font(.caption2)
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot) + (bedtime.map { ". " + Words.bedBy($0) } ?? "")))
    }

    private var isFinal: Bool { snapshot?.kind == .score }

    private var number: String {
        switch snapshot?.kind {
        case .score: return snapshot?.readiness.map(String.init) ?? "–"
        case .calibrating: return "\(snapshot?.baselineNights ?? 0)"
        case .pending, .waitingForSleep: return snapshot?.previousReadiness.map(String.init) ?? "–"
        case nil: return "–"
        }
    }

    @ViewBuilder
    private var ring: some View {
        let stroke: CGFloat = 5
        switch snapshot?.kind {
        case .score:
            ZStack {
                Circle().stroke(ink.opacity(0.12), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: Double(snapshot?.readiness ?? 0) / 100)
                    .stroke(Brand.teal, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        case .calibrating:
            let n = ReadinessSnapshot.baselineNightsRequired
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .trim(from: Double(i) / Double(n) + 0.008, to: Double(i + 1) / Double(n) - 0.008)
                        .stroke(i < (snapshot?.baselineNights ?? 0) ? Brand.teal : ink.opacity(0.12),
                                style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
        default:
            ZStack {
                Circle().strokeBorder(ink.opacity(0.35), lineWidth: 1)
                Circle().strokeBorder(ink.opacity(0.35), lineWidth: 1).padding(stroke)
            }
        }
    }
}

// MARK: - lock screen

private struct CircularReadiness: View {
    let snapshot: ReadinessSnapshot?

    var body: some View {
        Group {
            if snapshot?.kind == .score, let r = snapshot?.readiness {
                Gauge(value: Double(r), in: 0...100) { Text(verbatim: "R") } currentValueLabel: { Text(verbatim: "\(r)") }
                    .gaugeStyle(.accessoryCircularCapacity)
            } else if snapshot?.kind == .calibrating {
                Gauge(value: Double(snapshot?.baselineNights ?? 0), in: 0...Double(ReadinessSnapshot.baselineNightsRequired)) {
                    Text(verbatim: "B")
                } currentValueLabel: {
                    Text(verbatim: "\(snapshot?.baselineNights ?? 0)/\(ReadinessSnapshot.baselineNightsRequired)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: snapshot == nil ? "circle.dashed" : "moon.zzz")
                        .font(.title3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot)))
    }
}

private struct RectangularReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Readiness")
                .font(.headline)
                .widgetAccentable()
            if snapshot?.kind == .score, let r = snapshot?.readiness {
                Text(verbatim: "\(r)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(Words.band(r))
                    .font(.caption)
            } else {
                Text(Words.status(snapshot))
                    .font(.callout)
                    .lineLimit(2)
            }
            if let bedtime {
                Text(Words.bedBy(bedtime))
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot) + (bedtime.map { ". " + Words.bedBy($0) } ?? "")))
    }
}

// MARK: - previews

extension ReadinessSnapshot {
    static func preview(_ kind: Kind) -> ReadinessSnapshot {
        ReadinessSnapshot(day: dayString(.now), kind: kind, readiness: kind == .score ? 84 : nil,
                          previousReadiness: 76, baselineNights: kind == .calibrating ? 3 : nil, updatedAt: .now,
                          bedtime: Calendar.current.date(bySettingHour: 22, minute: 41, second: 0, of: .now))
    }
}

#Preview("Small", as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: nil)
}

#Preview("Lock screen", as: .accessoryRectangular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
}

#Preview("Circular", as: .accessoryCircular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.waitingForSleep))
}

#Preview("Small · dark and light") {
    HStack(spacing: 16) {
        ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
            VStack(spacing: 16) {
                ForEach([ReadinessSnapshot.Kind.score, .pending, .calibrating], id: \.self) { kind in
                    SmallReadiness(snapshot: .preview(kind))
                        .padding(16)
                        .frame(width: 158, height: 158)
                        .background(scheme == .dark ? Brand.graphite : Brand.mist, in: RoundedRectangle(cornerRadius: 22))
                        .environment(\.colorScheme, scheme)
                }
            }
        }
    }
    .padding()
}

#Preview("Small · de") {
    SmallReadiness(snapshot: .preview(.pending))
        .padding(16)
        .frame(width: 158, height: 158)
        .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "de"))
}
