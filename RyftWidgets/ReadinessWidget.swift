// Readiness on the home and lock screen: what Today shows, from the snapshot the app
// writes into the App Group container after each refresh (`Shared/ReadinessSnapshot.swift`).
// The orbit, the same drawing as Today's (`WidgetOrbitGauge`) from the snapshot's `gauge`: the
// scores, the baselines filling night by night, or the previous day dimmed while a night is
// scored. The app reloads the widget when a new score lands; the timeline only turns the day over.
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

    var body: some View { Brand.background(scheme) }
}

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: CircularReadiness(snapshot: entry.shown)
        case .accessoryRectangular: RectangularReadiness(snapshot: entry.shown, bedtime: entry.bedtime)
        case .accessoryInline: InlineReadiness(snapshot: entry.shown, bedtime: entry.bedtime)
        default: SmallReadiness(snapshot: entry.shown, bedtime: entry.bedtime)
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
    /// ("Readiness 71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21"), and tonight's bedtime. On a
    /// locked device (`redacted`) only "Readiness" (`ReadinessSnapshot.speech`).
    static func spoken(_ s: ReadinessSnapshot?, bedtime: Date? = nil, redacted: Bool = false) -> String {
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
        return spoken + (bedtime.map { ". " + bedBy($0) } ?? "")
    }
}

/// The lock screen hides the values until the device is unlocked (`.privacy` redaction): the orbit's tracks only,
/// the number and words redacted, VoiceOver "Readiness".
private extension RedactionReasons {
    var hidesValues: Bool { contains(.privacy) }
}

/// Whether a family draws the orbit for `s`: a readiness, the baselines counting, a night pending or awaited (the
/// previous day dimmed, or tracks and hollow dots without one). Not without a snapshot, nor for a scored day without
/// a readiness: those keep their symbol or their words. A locked device always draws it (tracks only).
private func drawsOrbit(_ s: ReadinessSnapshot?) -> Bool {
    guard let s else { return false }
    return s.kind != .score || s.readiness != nil
}

/// A line slot in words: the constant placeholder on a locked device, else the band word or the status.
private struct SlotLine: View {
    let slot: ReadinessSnapshot.TextSlot
    let snapshot: ReadinessSnapshot?

    var body: some View {
        switch slot {
        case .locked: Text(Words.lockedLine)
        case .band(let r): Text(Words.band(r))
        case .bedtime(let bedtime): Text(Words.bedBy(bedtime))
        case .number(let r): Text(verbatim: "\(r)")
        case .status: Text(Words.status(snapshot))
        case .none: EmptyView()
        }
    }
}

// MARK: - home screen

/// The orbit as large as the tile allows (it is the mark: no header): the scores with the band word under them, the
/// baselines' segments with "Baselines 3 of 7", or the previous day dimmed with "Scoring your night…".
private struct SmallReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.redactionReasons) private var redaction

    private var ink: Color { Brand.ink(scheme) }
    private var locked: Bool { redaction.hidesValues }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                WidgetOrbitGauge(mode: snapshot?.gauge, size: .custom(dial: max(side - 12, 0)), readiness: snapshot?.readiness,
                                 previousReadiness: snapshot?.previousReadiness)
                    .frame(width: g.size.width, height: g.size.height)
            }
            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, redacted: locked)))
    }

    /// Tonight's bedtime in the evening, else the band word or the status; one constant line when locked.
    @ViewBuilder
    private var caption: some View {
        let bedtimeSlot = ReadinessSnapshot.bedtimeSlot(bedtime, redacted: locked)
        if bedtimeSlot != .none {
            SlotLine(slot: bedtimeSlot, snapshot: snapshot)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Brand.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacySensitive()
        } else {
            SlotLine(slot: ReadinessSnapshot.lineSlot(snapshot, redacted: locked), snapshot: snapshot)
                .font(.caption2)
                .foregroundStyle(ink.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .privacySensitive()
        }
    }
}

// MARK: - lock screen

private struct CircularReadiness: View {
    let snapshot: ReadinessSnapshot?
    @Environment(\.redactionReasons) private var redaction

    private var locked: Bool { redaction.hidesValues }

    var body: some View {
        Group {
            if drawsOrbit(snapshot) || locked {
                // The orbit filling the circle; the frame's 6 pt on each side take the outer dot. The baselines' count
                // or the previous day's number (dimmed) in the centre.
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height)
                    ZStack {
                        AccessoryWidgetBackground()
                        WidgetOrbitGauge(mode: snapshot?.gauge, size: .custom(dial: max(side - 12, 0)),
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
        .accessibilityLabel(Text(Words.spoken(snapshot, redacted: locked)))
    }
}

private struct RectangularReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    @Environment(\.redactionReasons) private var redaction

    private var locked: Bool { redaction.hidesValues }

    var body: some View {
        HStack(spacing: 8) {
            // The number or the status is beside it: the orbit alone, the size of the app icon's 44 pt check. Locked,
            // always the tracks, so whether today is scored doesn't show either.
            if locked || drawsOrbit(snapshot) {
                WidgetOrbitGauge(mode: snapshot?.gauge, size: .custom(dial: 44), readiness: snapshot?.readiness,
                                 previousReadiness: snapshot?.previousReadiness, showsNumber: false)
            }
            lines
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, redacted: locked)))
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Readiness")
                .font(.headline)
                .widgetAccentable()
            let number = ReadinessSnapshot.numberSlot(snapshot, redacted: locked)
            if number != .none {
                Group {
                    if case .number(let r) = number { Text(verbatim: "\(r)") } else { Text(verbatim: Words.lockedNumber) }
                }
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .privacySensitive()
                SlotLine(slot: ReadinessSnapshot.lineSlot(snapshot, redacted: locked), snapshot: snapshot)
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            } else {
                SlotLine(slot: ReadinessSnapshot.lineSlot(snapshot, redacted: locked), snapshot: snapshot)
                    .font(.callout)
                    .lineLimit(2)
                    .privacySensitive()
            }
            SlotLine(slot: ReadinessSnapshot.bedtimeSlot(bedtime, redacted: locked), snapshot: snapshot)
                .font(.caption)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineReadiness: View {
    let snapshot: ReadinessSnapshot?
    var bedtime: Date?
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        // Locked: one constant line ("Readiness") under the redaction, whatever the state.
        Text(Words.inline(snapshot, bedtime: bedtime, redacted: redaction.hidesValues))
            .privacySensitive()
            .accessibilityLabel(Text(Words.spoken(snapshot, bedtime: bedtime, redacted: redaction.hidesValues)))
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
}

#Preview("Small", as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .previewSleepMissing)
    ReadinessEntry(date: .now, snapshot: .previewBeforeOrbit)
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .previewWaitingWithoutOrbit)
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: nil)
}

#Preview("Lock screen", as: .accessoryRectangular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.pending))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
}

#Preview("Circular", as: .accessoryCircular) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
    ReadinessEntry(date: .now, snapshot: .preview(.calibrating))
    ReadinessEntry(date: .now, snapshot: .preview(.waitingForSleep))
    ReadinessEntry(date: .now, snapshot: .previewWaitingWithoutOrbit)
}

#Preview("Inline", as: .accessoryInline) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .preview(.score))
}

/// The families side by side in dark and light, outside the system's widget chrome (for screenshots).
struct ReadinessWidgetGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                VStack(spacing: 16) {
                    let snapshots: [ReadinessSnapshot] = [.preview(.score), .previewHundred, .previewSleepMissing,
                                                          .previewBeforeOrbit, .preview(.pending), .previewWaitingWithoutOrbit,
                                                          .preview(.calibrating)]
                    ForEach(snapshots.indices, id: \.self) { i in
                        SmallReadiness(snapshot: snapshots[i])
                            .padding(16)
                            .frame(width: 158, height: 158)
                            .background(Brand.background(scheme), in: RoundedRectangle(cornerRadius: 22))
                    }
                    HStack(spacing: 12) {
                        CircularReadiness(snapshot: .preview(.score))
                            .frame(width: 72, height: 72)
                        CircularReadiness(snapshot: .previewHundred)
                            .frame(width: 68, height: 68)
                    }
                    HStack(spacing: 12) {
                        CircularReadiness(snapshot: .preview(.calibrating))
                            .frame(width: 68, height: 68)
                        CircularReadiness(snapshot: .preview(.pending))
                            .frame(width: 68, height: 68)
                        CircularReadiness(snapshot: .previewWaitingWithoutOrbit)
                            .frame(width: 68, height: 68)
                    }
                    ForEach([ReadinessSnapshot.Kind.score, .calibrating, .pending], id: \.self) { kind in
                        RectangularReadiness(snapshot: .preview(kind))
                            .padding(8)
                            .frame(width: 170, height: 76)
                            .background(Brand.background(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    InlineReadiness(snapshot: .preview(.score))
                        .font(.caption)
                }
                .padding(16)
                .background(Brand.background(scheme).opacity(0.5))
                .environment(\.colorScheme, scheme)
            }
        }
        .padding()
    }
}

#Preview("Families · dark and light") {
    ReadinessWidgetGallery()
}

/// A locked device: every family for a score, a hundred, a night being scored, the baselines and no snapshot, with
/// and without tonight's bedtime. Each column must look the same in every row.
struct ReadinessWidgetLockedGallery: View {
    var scheme: ColorScheme = .dark

    private static let bedtime = Calendar.current.date(bySettingHour: 22, minute: 41, second: 0, of: .now)
    private static let rows: [(ReadinessSnapshot?, Date?)] = [
        (.preview(.score), nil), (.previewHundred, bedtime), (.preview(.pending), nil),
        (.preview(.calibrating), bedtime), (.preview(.waitingForSleep), nil), (nil, nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.rows.indices, id: \.self) { i in
                let (snapshot, bedtime) = Self.rows[i]
                HStack(spacing: 12) {
                    SmallReadiness(snapshot: snapshot, bedtime: bedtime)
                        .padding(12)
                        .frame(width: 120, height: 120)
                        .background(Brand.background(scheme), in: RoundedRectangle(cornerRadius: 18))
                    CircularReadiness(snapshot: snapshot)
                        .frame(width: 68, height: 68)
                    RectangularReadiness(snapshot: snapshot, bedtime: bedtime)
                        .padding(8)
                        .frame(width: 170, height: 76)
                        .background(Brand.background(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    InlineReadiness(snapshot: snapshot, bedtime: bedtime)
                        .font(.caption)
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Brand.background(scheme).opacity(0.5))
        .environment(\.colorScheme, scheme)
        .redacted(reason: .privacy)
    }
}

#Preview("Families · locked (values hidden)") {
    HStack(alignment: .top, spacing: 16) {
        ReadinessWidgetLockedGallery(scheme: .dark)
        ReadinessWidgetLockedGallery(scheme: .light)
    }
    .padding()
}

#Preview("Small · de") {
    VStack(spacing: 16) {
        ForEach([ReadinessSnapshot.Kind.score, .pending, .calibrating], id: \.self) { kind in
            SmallReadiness(snapshot: .preview(kind))
                .padding(16)
                .frame(width: 158, height: 158)
                .background(Brand.graphite, in: RoundedRectangle(cornerRadius: 22))
        }
    }
    .environment(\.colorScheme, .dark)
    .environment(\.locale, Locale(identifier: "de"))
}
