// Readiness on the home and lock screen: what Today shows, from the snapshot the app writes into the App Group container
// after each refresh (`Shared/ReadinessSnapshot.swift`). The orbit, the same drawing as Today's (`WidgetOrbitGauge`) from
// the snapshot's `gauge`: the scores, the baselines filling night by night, or the previous day dimmed while a night is
// scored. The app reloads the widget when a new score lands; the timeline only turns the day over. Nocturne (c-24, c-25):
// the system face, numbers Light, ink and its ladder, a 12 pt margin on the small tile, no teal outside the orbit; what
// each line says and in which ink is `ReadinessWidgetLook`'s (`Shared/WidgetLook.swift`). It shows only what the platform
// scored, and a snapshot the app didn't write today says how old it is.
import SwiftUI
import WidgetKit

struct ReadinessEntry: TimelineEntry {
    let date: Date
    /// `nil`: the app hasn't written one (not opened yet, signed out, no App Group).
    let snapshot: ReadinessSnapshot?
    /// The system's placeholder before the first timeline: tracks and redacted lines, never a sample score.
    var isPlaceholder = false

    /// What it shows at `date` (yesterday's score is no score for today).
    var shown: ReadinessSnapshot? { snapshot?.asOf(date) }
    /// "Bed by 22:41" from 17:00 until then.
    var bedtime: Date? { snapshot?.bedtimeShown(at: date) }
    /// "As of yesterday": the app last wrote the snapshot before `date`'s day.
    var age: WidgetAge? { WidgetAge.of(snapshot, at: date) }
}

struct ReadinessProvider: TimelineProvider {
    /// No values: the system shows it before the first timeline, so it must not look like anyone's score.
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, snapshot: nil, isPlaceholder: true)
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
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "ryft://today"))
        }
        .configurationDisplayName(Text("Readiness"))
        .description(Text("Today's readiness, or how far scoring your night is."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        // The small tile sets its own 12 pt (F24); the lock screen's families keep the system's margins (below).
        .contentMarginsDisabled()
    }
}

/// Graphite, like the app: the widget is dark-only.
private struct WidgetBackground: View {
    var body: some View { Brand.background }
}

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        if entry.isPlaceholder {
            content.redacted(reason: .placeholder)
        } else {
            content
        }
    }

    private var content: some View {
        ReadinessFamilyView(entry: entry, family: family)
            // The margins the system would have kept (`contentMarginsDisabled` is the configuration's, for every family).
            .padding(family == .systemSmall || family == .accessoryInline ? EdgeInsets() : margins)
    }
}

/// One family's view of an entry, out of the widget's environment (previews, the comparison shots).
struct ReadinessFamilyView: View {
    let entry: ReadinessEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: CircularReadiness(snapshot: entry.shown, age: entry.age)
        case .accessoryRectangular: RectangularReadiness(snapshot: entry.shown, bedtime: entry.bedtime, age: entry.age)
        case .accessoryInline: InlineReadiness(snapshot: entry.shown, bedtime: entry.bedtime, age: entry.age)
        default: SmallReadiness(snapshot: entry.shown, bedtime: entry.bedtime, age: entry.age)
        }
    }
}

// MARK: - words

enum Words {
    /// The gauge's band word on Today.
    static func band(_ readiness: Int) -> String {
        switch readiness {
        case OrbitGaugePalette.highFrom...: return String(localized: "High")
        case OrbitGaugePalette.moderateFrom...: return String(localized: "Moderate")
        default: return String(localized: "Low")
        }
    }

    /// Under the gauge, or the rectangle's second line.
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

    /// The small tile's caption for a score: "Readiness · High".
    static func bandCaption(_ readiness: Int) -> String {
        String(localized: "Readiness · \(band(readiness))", comment: "Widget, under the orbit: the readiness band, e.g. Readiness · High.")
    }

    /// "As of yesterday", "As of Monday", "As of Nov 16": when the app last wrote what the widget shows.
    static func age(_ age: WidgetAge) -> String {
        switch age {
        case .yesterday:
            return String(localized: "As of yesterday", comment: "Widget: the app last updated it yesterday; what it shows is from then.")
        case .weekday(let date):
            return String(localized: "As of \(date.formatted(.dateTime.weekday(.wide)))",
                          comment: "Widget: the app last updated it on that day, a weekday (Monday) or a date (Nov 16).")
        case .date(let date):
            return String(localized: "As of \(date.formatted(.dateTime.month(.abbreviated).day()))",
                          comment: "Widget: the app last updated it on that day, a weekday (Monday) or a date (Nov 16).")
        }
    }

    /// The rectangle's value while the baselines count: "3 of 7".
    static func baselinesValue(_ counted: Int) -> String {
        String(localized: "\(counted) of \(ReadinessSnapshot.baselineNightsRequired)",
               comment: "Widget, lock screen rectangle: nights counted of the nights the baselines need, e.g. 3 of 7.")
    }

    /// The rectangle's line under "3 of 7".
    static var baselines: String {
        String(localized: "Baselines", comment: "Widget, lock screen rectangle: under the nights counted (3 of 7).")
    }

    /// The lock screen's line: on a locked device only "Readiness", whatever the state (`ReadinessSnapshot.*Slot`).
    static func inline(_ s: ReadinessSnapshot?, bedtime: Date? = nil, redacted: Bool = false) -> String {
        if case .bedtime(let bedtime) = ReadinessSnapshot.bedtimeSlot(bedtime, redacted: redacted) { return bedBy(bedtime) }
        switch ReadinessSnapshot.numberSlot(s, redacted: redacted) {
        case .locked: return lockedLine
        case .number(let r): return String(localized: "Readiness \(r) · \(band(r))")
        default: return status(s)
        }
    }

    /// What stands under a redaction on a locked device, the same in every state: a redaction keeps the width of
    /// its text, so the real number and words would show through by their length.
    static let lockedNumber = "00"
    /// The band word's or the status line's stand-in, and the inline family's line.
    static var lockedLine: String { String(localized: "Readiness") }

    /// "Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21": a missing score named as not scored, never skipped.
    static func scores(_ v: OrbitGaugeValues) -> String {
        let notScored = { (title: String) in String(localized: "\(title), not scored") }
        let percent = { (fraction: Double) in Int((fraction * 100).rounded()).formatted() }
        return [
            v.recoveryFraction.map { String(localized: "Recovery \(percent($0)) percent") } ?? notScored(String(localized: "Recovery")),
            v.sleepFraction.map { String(localized: "Sleep \(percent($0)) percent") } ?? notScored(String(localized: "Sleep")),
            v.strain.map { String(localized: "Strain \($0.formatted(.number.precision(.fractionLength(1)))) of 21") }
                ?? notScored(String(localized: "Strain")),
        ].joined(separator: ", ")
    }

    /// "Bed by 22:41".
    static func bedBy(_ bedtime: Date) -> String {
        String(localized: "Bed by \(bedtime.formatted(date: .omitted, time: .shortened))")
    }

    /// For VoiceOver: the value and whether it's today's; with the orbit, its three scores as Today reads them
    /// ("Readiness 71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21"), how old a snapshot of an earlier
    /// day is, and tonight's bedtime. On a locked device (`redacted`) only "Readiness" (`ReadinessSnapshot.speech`).
    static func spoken(_ s: ReadinessSnapshot?, bedtime: Date? = nil, age: WidgetAge? = nil, redacted: Bool = false) -> String {
        let spoken: String
        switch ReadinessSnapshot.speech(s, redacted: redacted) {
        case .name: return String(localized: "Readiness")
        case .openApp: spoken = status(nil)
        case .score(let readiness, let values):
            let r = readiness.map { String(localized: "Readiness \($0), \(band($0))") } ?? ""
            spoken = values.map { r + ". " + scores($0) } ?? r
        case .night(_, let previous):
            spoken = status(s) + (previous.map { " " + String(localized: "Last readiness \($0).") } ?? "")
        case .baselines:
            spoken = status(s)
        }
        let asOf = ReadinessWidgetLook.line(s, age: age, redacted: redacted).age.map { ". " + Words.age($0) } ?? ""
        return spoken + asOf + (bedtime.map { ". " + bedBy($0) } ?? "")
    }
}

/// The lock screen hides the values until the device is unlocked (`.privacy` redaction), and the placeholder has none:
/// the orbit's tracks only, the number and words redacted, VoiceOver "Readiness".
extension RedactionReasons {
    var hidesValues: Bool { contains(.privacy) || contains(.placeholder) }
}

/// Whether a family draws the orbit for `s`: a readiness, the baselines counting, a night pending or awaited (the
/// previous day dimmed, or tracks and hollow dots without one). Not without a snapshot, nor for a scored day without
/// a readiness: those keep their symbol or their words. A locked device always draws it (tracks only).
private func drawsOrbit(_ s: ReadinessSnapshot?) -> Bool {
    guard let s else { return false }
    return s.kind != .score || s.readiness != nil
}

/// A line in words: the constant on a locked device, else the band word ("Readiness · High" under the small orbit),
/// a status, tonight's bedtime or how old the snapshot is.
private struct LineText: View {
    let line: ReadinessWidgetLook.Line
    let snapshot: ReadinessSnapshot?
    /// The small tile's caption: the band word with "Readiness ·" before it.
    var caption = false
    /// The rectangle beside "3 of 7": "Baselines".
    var besideCount = false

    var body: some View {
        switch line {
        case .age(let age): Text(Words.age(age))
        case .slot(let slot):
            switch slot {
            case .locked: Text(Words.lockedLine)
            case .band(let r): Text(caption ? Words.bandCaption(r) : Words.band(r))
            case .bedtime(let bedtime): Text(Words.bedBy(bedtime))
            case .number(let r): Text(verbatim: "\(r)")
            case .status(.calibrating) where besideCount: Text(Words.baselines)
            case .status: Text(Words.status(snapshot))
            case .none: EmptyView()
            }
        }
    }
}

// MARK: - home screen

/// The orbit as large as the tile allows (it is the mark: no header), 12 pt from the edges (F24), and one caption under
/// it: "Readiness · High", tonight's bedtime, a status, or how old the snapshot is. Without a snapshot an outline and
/// what to do, never an empty tile.
private struct SmallReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    var age: WidgetAge?
    @Environment(\.redactionReasons) private var redaction

    private var hidden: Bool { redaction.hidesValues }

    var body: some View {
        Group {
            if snapshot == nil, !hidden {
                openApp
            } else {
                VStack(spacing: ReadinessWidgetLook.captionGap) {
                    GeometryReader { g in
                        WidgetOrbitGauge(mode: snapshot?.gauge,
                                         size: .custom(dial: ReadinessWidgetLook.dial(inSide: min(g.size.width, g.size.height))),
                                         readiness: snapshot?.readiness, previousReadiness: snapshot?.previousReadiness)
                            .frame(width: g.size.width, height: g.size.height)
                    }
                    caption
                }
            }
        }
        .padding(ReadinessWidgetLook.smallInset)
        .dynamicTypeSize(...ReadinessWidgetLook.smallLargestType)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, age: age, redacted: hidden)))
    }

    private var caption: some View {
        let line = ReadinessWidgetLook.smallCaption(snapshot, bedtime: bedtime, age: age, redacted: hidden)
        return LineText(line: line, snapshot: snapshot, caption: true)
            .font(line.isBedtime ? .caption2.weight(.medium) : .caption2)
            .foregroundStyle(ReadinessWidgetLook.ink(of: line).colour)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .privacySensitive()
    }

    /// No snapshot: a dashed outline where the orbit goes and the one thing to do.
    private var openApp: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 30, weight: .ultraLight))
            Text(Words.status(nil))
                .font(.caption)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(WidgetInk.secondary.colour)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - lock screen

private struct CircularReadiness: View {
    let snapshot: ReadinessSnapshot?
    var age: WidgetAge?
    @Environment(\.redactionReasons) private var redaction

    private var hidden: Bool { redaction.hidesValues }

    var body: some View {
        Group {
            if drawsOrbit(snapshot) || hidden {
                // The orbit filling the circle, 1 pt clear of its edge: the baselines' count, or the previous day's number
                // (dimmed), in the centre.
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height)
                    ZStack {
                        AccessoryWidgetBackground()
                        WidgetOrbitGauge(mode: snapshot?.gauge,
                                         size: .custom(dial: max(side - ReadinessWidgetLook.circularAir, 0)),
                                         readiness: snapshot?.readiness, previousReadiness: snapshot?.previousReadiness,
                                         prominentNumber: true)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: snapshot == nil ? "circle.dashed" : "moon.zzz")
                        .font(.title3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot, age: age, redacted: hidden)))
    }
}

/// The orbit at 44 without a number, then "Readiness" (13 Medium, accentable), the value (22 Light), the band word, a
/// status or how old the snapshot is (11), and tonight's bedtime (11): at most three lines under "Readiness".
private struct RectangularReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    var age: WidgetAge?
    @Environment(\.redactionReasons) private var redaction

    private var hidden: Bool { redaction.hidesValues }

    var body: some View {
        HStack(spacing: ReadinessWidgetLook.rectangularGap) {
            // Locked, always the tracks, so whether today is scored doesn't show either.
            if hidden || drawsOrbit(snapshot) {
                WidgetOrbitGauge(mode: snapshot?.gauge, size: .custom(dial: ReadinessWidgetLook.rectangularDial),
                                 readiness: snapshot?.readiness, previousReadiness: snapshot?.previousReadiness,
                                 showsNumber: false)
            }
            lines
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...ReadinessWidgetLook.rectangularLargestType)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, age: age, redacted: hidden)))
    }

    private var lines: some View {
        let value = ReadinessWidgetLook.rectangularValue(snapshot, redacted: hidden)
        let bedtimeSlot = ReadinessSnapshot.bedtimeSlot(bedtime, redacted: hidden)
        // The status wraps before it truncates: two lines under a value with no bedtime, three without a value.
        let lineLimit = bedtimeSlot != .none ? 1 : (value == nil ? 3 : 2)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Readiness")
                .font(.footnote.weight(.medium))
                .widgetAccentable()
            if let value {
                valueText(value)
                    .font(.title2.weight(.light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
            }
            Group {
                LineText(line: ReadinessWidgetLook.line(snapshot, age: age, redacted: hidden), snapshot: snapshot,
                         besideCount: true)
                    .lineLimit(lineLimit)
                LineText(line: .slot(bedtimeSlot), snapshot: snapshot)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueText(_ value: ReadinessWidgetLook.Centre) -> some View {
        let words: String
        switch value {
        case .hidden: words = Words.lockedNumber
        case .readiness(let readiness, _): words = String(readiness)
        case .baselines(let counted): words = Words.baselinesValue(counted)
        case .dash: words = "–"
        }
        return Text(verbatim: words)
            .foregroundStyle(ReadinessWidgetLook.ink(of: value) == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
}

private struct InlineReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    var age: WidgetAge?
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        // Locked: one constant line ("Readiness") under the redaction, whatever the state.
        Text(Words.inline(snapshot, bedtime: bedtime, redacted: redaction.hidesValues))
            .privacySensitive()
            .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, age: age, redacted: redaction.hidesValues)))
    }
}

// MARK: - previews (synthetic values only: 71 / 71 % / 88 % / 9.6)

extension ReadinessSnapshot {
    static func preview(_ kind: Kind) -> ReadinessSnapshot {
        ReadinessSnapshot(day: dayString(.now), kind: kind, readiness: kind == .score ? 71 : nil,
                          previousReadiness: 64, baselineNights: kind == .calibrating ? 3 : nil, updatedAt: .now,
                          bedtime: Calendar.current.date(bySettingHour: 22, minute: 41, second: 0, of: .now),
                          orbit: Orbit(recovery: 71, sleepPerformance: 88, strain: 9.6))
    }

    /// A file the app wrote before the orbit: no `orbit` key, so the widget draws the tracks only.
    static var previewBeforeOrbit: ReadinessSnapshot {
        var s = preview(.score)
        s.orbit = nil
        return s
    }

    /// Waiting for the night with no orbit (row A's tiles, or a calibrating file turned over at midnight): the
    /// tracks and hollow dots with the latest readiness, 64, dimmed in the centre.
    static var previewWaitingWithoutOrbit: ReadinessSnapshot {
        var s = preview(.waitingForSleep)
        s.orbit = nil
        return s
    }

    /// Waiting for the night with no readiness before it (a new account): tracks and hollow dots, the dash.
    static var previewWaitingFirst: ReadinessSnapshot {
        var s = previewWaitingWithoutOrbit
        s.previousReadiness = nil
        return s
    }

    /// Three digits: the number must still fit the centre ring.
    static var previewHundred: ReadinessSnapshot {
        var s = preview(.score)
        s.readiness = 100
        s.orbit = Orbit(recovery: 100, sleepPerformance: 100, strain: 21)
        return s
    }

    /// A watch without HRV and no sleep yet: Recovery from what was scored, Sleep a hollow dot.
    static var previewSleepMissing: ReadinessSnapshot {
        var s = preview(.score)
        s.readiness = 64
        s.orbit = Orbit(recovery: 62, sleepPerformance: nil, strain: 6.2)
        return s
    }

    /// Today's score as the app wrote it `days` ago at 21:40 and hasn't since: the widget turns it over and says how old.
    static func previewWritten(daysAgo days: Int) -> ReadinessSnapshot {
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 21, minute: 40, second: 0, of: .now) ?? .now
        let then = calendar.date(byAdding: .day, value: -days, to: evening) ?? evening
        var s = preview(.score)
        s.day = dayString(then)
        s.updatedAt = then
        s.bedtime = nil
        return s
    }
}

extension ReadinessEntry {
    /// 18:00 today: tonight's bedtime shows.
    static func evening(_ s: ReadinessSnapshot?) -> ReadinessEntry {
        ReadinessEntry(date: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now, snapshot: s)
    }
}

#Preview("Small", as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry.evening(.preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .previewWaitingFirst)
    ReadinessEntry(date: .now, snapshot: .previewWaitingWithoutOrbit)
    ReadinessEntry(date: .now, snapshot: .previewWritten(daysAgo: 1))
    ReadinessEntry(date: .now, snapshot: .previewWritten(daysAgo: 4))
    ReadinessEntry(date: .now, snapshot: .previewSleepMissing)
    ReadinessEntry(date: .now, snapshot: .previewBeforeOrbit)
    ReadinessEntry(date: .now, snapshot: .previewHundred)
    ReadinessEntry(date: .now, snapshot: nil)
    ReadinessEntry(date: .now, snapshot: nil, isPlaceholder: true)
}

#Preview("Lock screen", as: .accessoryRectangular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry.evening(.preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: .previewWritten(daysAgo: 1))
    ReadinessEntry(date: .now, snapshot: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .previewWaitingWithoutOrbit)
    ReadinessEntry(date: .now, snapshot: .previewHundred)
    ReadinessEntry(date: .now, snapshot: nil)
}

#Preview("Inline", as: .accessoryInline) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry.evening(.preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
}

/// The families side by side, outside the system's widget chrome (for screenshots): the small tile in each state, the
/// circles, the rectangles and the line.
struct ReadinessWidgetGallery: View {
    var body: some View {
        VStack(spacing: 16) {
            let entries: [ReadinessEntry] = [
                ReadinessEntry(date: .now, snapshot: .preview(.score)), .evening(.preview(.score)),
                ReadinessEntry(date: .now, snapshot: .preview(.calibrating)), ReadinessEntry(date: .now, snapshot: .preview(.pending)),
                ReadinessEntry(date: .now, snapshot: .previewWaitingFirst), ReadinessEntry(date: .now, snapshot: nil),
                ReadinessEntry(date: .now, snapshot: .previewWritten(daysAgo: 1)),
                ReadinessEntry(date: .now, snapshot: .previewHundred),
            ]
            LazyVGrid(columns: [GridItem(.fixed(158)), GridItem(.fixed(158))], spacing: 16) {
                ForEach(entries.indices, id: \.self) { i in
                    ReadinessFamilyView(entry: entries[i], family: .systemSmall)
                        .frame(width: 158, height: 158)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 22))
                }
            }
            HStack(spacing: 12) {
                ForEach([ReadinessSnapshot.preview(.score), .preview(.calibrating), .preview(.pending)], id: \.kind) { s in
                    ReadinessFamilyView(entry: ReadinessEntry(date: .now, snapshot: s), family: .accessoryCircular)
                        .frame(width: 76, height: 76)
                }
            }
            ForEach([ReadinessEntry.evening(.preview(.score)), ReadinessEntry(date: .now, snapshot: .preview(.calibrating)),
                     ReadinessEntry(date: .now, snapshot: .preview(.pending))], id: \.snapshot?.kind) { entry in
                ReadinessFamilyView(entry: entry, family: .accessoryRectangular)
                    .padding(8)
                    .frame(width: 172, height: 76)
                    .background(Brand.mist.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            ReadinessFamilyView(entry: ReadinessEntry(date: .now, snapshot: .preview(.score)), family: .accessoryInline)
                .font(.caption)
        }
        .padding(16)
        .background(Brand.background.opacity(0.5))
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Families") {
    ReadinessWidgetGallery()
}

/// A locked device: every family for a score, a hundred, a night being scored, the baselines and no snapshot, with
/// and without tonight's bedtime. Each column must look the same in every row.
struct ReadinessWidgetLockedGallery: View {
    private static let bedtime = Calendar.current.date(bySettingHour: 22, minute: 41, second: 0, of: .now)
    private static let rows: [(ReadinessSnapshot?, Date?)] = [
        (.preview(.score), nil), (.previewHundred, bedtime), (.preview(.pending), nil),
        (.preview(.calibrating), bedtime), (.preview(.waitingForSleep), nil), (.previewWritten(daysAgo: 1), nil), (nil, nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.rows.indices, id: \.self) { i in
                let (snapshot, bedtime) = Self.rows[i]
                HStack(spacing: 12) {
                    SmallReadiness(snapshot: snapshot, bedtime: bedtime)
                        .frame(width: 120, height: 120)
                        .background(Brand.background, in: RoundedRectangle(cornerRadius: 18))
                    CircularReadiness(snapshot: snapshot)
                        .frame(width: 68, height: 68)
                    RectangularReadiness(snapshot: snapshot, bedtime: bedtime)
                        .padding(8)
                        .frame(width: 170, height: 76)
                        .background(Brand.mist.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    InlineReadiness(snapshot: snapshot, bedtime: bedtime)
                        .font(.caption)
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Brand.background.opacity(0.5))
        .environment(\.colorScheme, .dark)
        .redacted(reason: .privacy)
    }
}

#Preview("Families · locked (values hidden)") {
    ReadinessWidgetLockedGallery()
        .padding()
}
