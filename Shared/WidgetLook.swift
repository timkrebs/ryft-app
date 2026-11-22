// The widget's look decided without words or fonts (ADR 0010): the ink each line takes in each state, what a redaction
// leaves, the families' layout, how each grows with Dynamic Type, and how old a snapshot is. The extension can't be
// imported by the app's tests, so its decisions live here, where `WidgetNocturneTests` reaches them through the app
// target; the widget (`RyftWidgets/`) draws them in the system face with its own words and `Brand` colours. Nocturne
// PR 6 C §4.15, B §8 (D6B-11), F21, F24, L27.
import SwiftUI

/// The neutral ladder the widget draws its text in: `Brand.textPrimary` at the strengths of the app's `textPrimary`,
/// `textSecondary` and `textTertiary`. No colour is on it. Volt is the orbit's readiness marker (the shared drawing's
/// `Signal`, in every family, as on Today) and the running rest's dot and bar (`Brand.signal`, `Inks.restMarks`); teal
/// is only the orbit's recovery (`OrbitGaugePalette`).
enum WidgetInk: Equatable, Sendable {
    /// A value, tonight's bedtime, a clock, the "Open" pill's fill.
    case primary
    /// The caption under the orbit, labels, a session title, a status line.
    case secondary
    /// A previous day's number and the dash.
    case tertiary

    /// Of `Brand.textPrimary`.
    var opacity: Double {
        switch self {
        case .primary: return 1
        case .secondary: return 0.62
        case .tertiary: return 0.48
        }
    }
}

/// What a redaction leaves of the widget's values. A locked device (`.privacy`) and the system's placeholder
/// (`.placeholder`) both draw the orbit's tracks only and say only "Readiness"; they differ in the number. `.privacy`
/// boxes the `privacySensitive` views, so the centre holds a constant ("00") whose width gives nothing away. The
/// placeholder doesn't box them (`privacySensitive` exempts its subtree from `.placeholder`), so it holds no number:
/// the dash, and no value beside the rectangle's orbit.
enum WidgetConcealment: Equatable, Sendable {
    case none
    case locked
    case placeholder

    init(_ reasons: RedactionReasons) {
        if reasons.contains(.placeholder) {
            self = .placeholder
        } else if reasons.contains(.privacy) {
            self = .locked
        } else {
            self = .none
        }
    }

    /// The tracks only, and the constant words.
    var hidesValues: Bool { self != .none }
}

/// VoiceOver's sentences in the widget: the parts joined by ". ", or by a space after one that already ends ("." or
/// "…"), so nothing is read with a double stop; missing and empty parts are skipped.
enum WidgetSpeech {
    static func sentences(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.reduce("") { text, part in
            if text.isEmpty { return part }
            return text + (text.hasSuffix(".") || text.hasSuffix("…") ? " " : ". ") + part
        }
    }
}

/// How old what the widget shows is, once the app hasn't written it on the day shown: "As of yesterday", "As of
/// Monday", "As of Nov 16", "As of Dec 20, 2026".
enum WidgetAge: Equatable, Sendable {
    case yesterday
    /// Two to six days ago: the weekday.
    case weekday(Date)
    /// A week or more ago: the date, with its year when that isn't the year of the day shown.
    case date(Date, withYear: Bool)

    /// The calendar the snapshot's `day` is written in (`ReadinessSnapshot.dayString`): Gregorian, the device's zone.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// `nil` while what the widget shows is the day's: the snapshot is of `date`'s day, or the app wrote it on that day
    /// (or later, after a change of clock or zone). The app writes the file on the first refresh of every day (its `day`
    /// changes), so a snapshot of an earlier day means the app hasn't refreshed since, and the widget (which turns it
    /// over, `ReadinessSnapshot.asOf`) says when it last did. One calendar decides both, in calendar days, so a change to
    /// or from daylight saving time doesn't move a day. The words are the widget's; a locked device never shows the age
    /// (`ReadinessWidgetLook.line`).
    static func of(_ snapshot: ReadinessSnapshot?, at date: Date, calendar: Calendar = WidgetAge.calendar) -> WidgetAge? {
        guard let snapshot, snapshot.day != day(of: date, in: calendar) else { return nil }
        let written = snapshot.updatedAt
        guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: written),
                                                 to: calendar.startOfDay(for: date)).day, days > 0 else { return nil }
        switch days {
        case 1: return .yesterday
        case 2...6: return .weekday(written)
        default:
            return .date(written, withYear: calendar.component(.year, from: written) != calendar.component(.year, from: date))
        }
    }

    /// `date`'s day the way `ReadinessSnapshot.dayString` writes it ("2026-11-19"), in `calendar`.
    static func day(of date: Date, in calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}

/// The readiness widget: home screen small (c-24) and the lock screen's circle, rectangle and line (c-25).
enum ReadinessWidgetLook {
    // MARK: layout

    /// The small family's inset, with the system's content margins off (F24, D6C-16; the system's was 16).
    static let smallInset: CGFloat = 12
    /// Between the orbit's frame and the caption.
    static let captionGap: CGFloat = 4
    /// The rectangle's orbit (no number: the value stands beside it) and the gap to its lines.
    static let rectangularDial: CGFloat = 44
    static let rectangularGap: CGFloat = 10
    /// What the circle keeps free around the dial: the frame's 12 for the outer dot and 1 more on each side, so the dot
    /// stays clear of the system's circle (62 in the 76 pt circle).
    static let circularAir: CGFloat = 14
    /// The centre number is Light from this size up and Regular below it (C §4.15, F21); the lock screen's circle sets
    /// Medium, since a Light stroke vanishes in the vibrant rendering.
    static let lightNumberFrom: CGFloat = 20

    /// The dial that fits a square of `side`: the frame's 6 pt for the outer dot on each side come off.
    static func dial(inSide side: CGFloat) -> CGFloat { max((side - 12).rounded(.down), 0) }

    /// The circle's dial: `circularAir` clear of the circle's edge (62 in the 76 pt circle, 58 in the 72), but never
    /// so small that it loses the number where the frame alone leaves room for it: the SE's 68 pt circle keeps 56
    /// (`OrbitGaugeGeometry.minDialForNumber`), its outer dot at the edge.
    static func circularDial(side: CGFloat) -> CGFloat {
        max(side - circularAir, min(side - 12, OrbitGaugeGeometry.minDialForNumber), 0)
    }

    // MARK: Dynamic Type

    /// The small tile's words grow up to AX1: two caption lines there still leave the orbit room for its number
    /// (`OrbitGaugeGeometry.minDialForNumber`), down to the smallest iPhones' 148 pt tile. Larger, the caption would
    /// take the number's place.
    static let smallLargestType: DynamicTypeSize = .accessibility1
    /// The rectangle grows to xxLarge (it is 72 pt high, 68 on the SE, 76 on the largest iPhones): folded, it measures
    /// 66 pt there, in 72 and in the SE's 68. Larger, its value and one line no longer fit 72 pt.
    static let rectangularLargestType: DynamicTypeSize = .xxLarge

    /// Above the default size the rectangle folds its four lines into three: "Readiness", the value, and one line,
    /// tonight's bedtime taking the status's place as on the small tile (`smallCaption`). At the default size it folds
    /// too where four lines don't fit (the view tries them first).
    static func rectangularFolds(_ size: DynamicTypeSize) -> Bool { size > .large }

    /// The lines the rectangle's status may take: unfolded, it wraps before it truncates (two lines under a value, three
    /// without one, one beside tonight's bedtime); folded, one under a value and two without.
    static func rectangularLineLimit(hasValue: Bool, hasBedtime: Bool, folded: Bool) -> Int {
        if folded { return hasValue ? 1 : 2 }
        if hasBedtime { return 1 }
        return hasValue ? 2 : 3
    }

    // MARK: the centre

    /// What the orbit's centre holds.
    enum Centre: Equatable {
        /// A locked device: one constant ("00") under the box, since a redaction keeps its text's width.
        case hidden
        /// A readiness; `dimmed`: a previous day's, while the night is scored or awaited.
        case readiness(Int, dimmed: Bool)
        /// The baselines counted (the caption or the line beside says "of 7").
        case baselines(Int)
        /// No number known, or the placeholder, which has none: the dash.
        case dash
    }

    /// The day's readiness for a score; the previous day's (the drawing's, else `previousReadiness`) while pending or
    /// awaited; the nights counted while calibrating; `readiness` when the mode is unknown (a file from before the orbit).
    /// The constant on a locked device, the dash in the placeholder.
    static func centre(_ mode: OrbitGaugeMode?, readiness: Int?, previousReadiness: Int?,
                       concealment: WidgetConcealment = .none) -> Centre {
        switch concealment {
        case .locked: return .hidden
        case .placeholder: return .dash
        case .none: break
        }
        switch mode {
        case .scored(let values, _)?: return values.readiness.map { .readiness($0, dimmed: false) } ?? .dash
        case .pending(let previous)?: return (previous?.readiness ?? previousReadiness).map { .readiness($0, dimmed: true) } ?? .dash
        case .calibrating(let calibration)?: return .baselines(calibration.counted)
        case nil: return readiness.map { .readiness($0, dimmed: false) } ?? .dash
        }
    }

    /// Full ink for the day's number, the count and the constant; `textTertiary` for a previous day's and the dash.
    static func ink(of centre: Centre) -> WidgetInk {
        switch centre {
        case .hidden, .baselines: return .primary
        case .readiness(_, let dimmed): return dimmed ? .tertiary : .primary
        case .dash: return .tertiary
        }
    }

    // MARK: the lines

    /// A line of words under the orbit (small) or beside it (the rectangle).
    enum Line: Equatable {
        /// A slot `ReadinessSnapshot` decides: the band word, a status, tonight's bedtime, the locked constant.
        case slot(ReadinessSnapshot.TextSlot)
        /// How old a snapshot of an earlier day is.
        case age(WidgetAge)
    }

    /// The line under a value: a snapshot of an earlier day says how old it is (the widget doesn't know whether the night
    /// has come since); otherwise the band word for a score, else the status. One constant when values are hidden.
    static func line(_ shown: ReadinessSnapshot?, age: WidgetAge?, redacted: Bool) -> Line {
        if !redacted, let age { return .age(age) }
        return .slot(ReadinessSnapshot.lineSlot(shown, redacted: redacted))
    }

    /// The small family's one caption, and the folded rectangle's one line: tonight's bedtime in the evening, else `line`.
    static func smallCaption(_ shown: ReadinessSnapshot?, bedtime: Date?, age: WidgetAge?, redacted: Bool) -> Line {
        let bedtime = ReadinessSnapshot.bedtimeSlot(bedtime, redacted: redacted)
        return bedtime == .none ? line(shown, age: age, redacted: redacted) : .slot(bedtime)
    }

    /// Tonight's bedtime in full ink and Medium (it says what to do next); every other line `textSecondary`.
    static func ink(of line: Line) -> WidgetInk {
        if case .slot(.bedtime) = line { return .primary }
        return .secondary
    }

    /// The rectangle's value beside the orbit, decided like the centre: today's readiness, a previous day's dimmed, the
    /// baselines' count ("3 of 7"), the constant when locked; none without a snapshot or a number, nor in the placeholder.
    static func rectangularValue(_ shown: ReadinessSnapshot?, concealment: WidgetConcealment = .none) -> Centre? {
        switch concealment {
        case .locked: return .hidden
        case .placeholder: return nil
        case .none: break
        }
        guard let shown else { return nil }
        let value = centre(shown.gauge, readiness: shown.readiness, previousReadiness: shown.previousReadiness)
        return value == .dash ? nil : value
    }
}

extension ReadinessWidgetLook.Line {
    /// Tonight's bedtime: Medium, in full ink.
    var isBedtime: Bool {
        if case .slot(.bedtime) = self { return true }
        return false
    }

    /// How old the snapshot is, when that is what the line says.
    var age: WidgetAge? {
        if case .age(let age) = self { return age }
        return nil
    }
}

/// The workout's Live Activity (b-16, c-26): D6B-11 and F24.
enum WorkoutActivityLook {
    /// A rest is counting down: resting, not stale (its end passed with the app not running) and not over.
    static func restRunning(resting: Bool, isStale: Bool, endsAt: Date, now: Date) -> Bool {
        resting && !isStale && endsAt > now
    }

    /// The inks of one presentation.
    struct Inks: Equatable {
        /// "Rest" or "Workout" and the session title on the lock screen.
        var label: WidgetInk
        /// The label and its glyph in the Dynamic Island.
        var islandLabel: WidgetInk
        /// The clock and the next set.
        var clock: WidgetInk
        /// The 6 pt dot before "Rest" and the rest's bar, in Volt (L27: "now"), the activity's only colour; neither is
        /// drawn otherwise.
        var restMarks: Bool
    }

    static func inks(restRunning: Bool) -> Inks {
        Inks(label: .secondary, islandLabel: .primary, clock: .primary, restMarks: restRunning)
    }

    /// The dot before "Rest", the "Open" pill's height (D6C-10: the activity's height is the system's, so not the app's
    /// 52), the padding and the gap between rows.
    static let dot: CGFloat = 6, openPill: CGFloat = 32, padding: CGFloat = 16, rowGap: CGFloat = 12
    /// The next set may take two lines on the lock screen (D6B-11: one line cut it at the load); one in the island.
    static let nextLines = 2, islandNextLines = 1
    /// Between the label and the session title on the lock screen.
    static let labelGap: CGFloat = 2
    /// The island's keyline: ink at half strength, never Volt or teal (C §4.15).
    static let keylineOpacity = 0.5

    /// The lock screen card stays within the 160 pt iOS gives a Live Activity there in two steps: above the default size
    /// the next set keeps one line (`nextLineLimit`), and only from the accessibility sizes the session title goes too.
    static func condenses(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    /// The lines the lock screen's next set may take at `size`: two at the default size and below, else one. Either way it
    /// is cut at its end, so the exercise's name at its start stays ("Next: Bench press · set 3 of 4 · 5 × 8…").
    static func nextLineLimit(_ size: DynamicTypeSize) -> Int { size > .large ? 1 : nextLines }

    /// What VoiceOver hears of the session title where the card doesn't draw it (condensed): the title, unless a
    /// redaction hides values (a locked screen, the placeholder), as it hides the drawn title (`privacySensitive`).
    static func spokenTitle(_ title: String, size: DynamicTypeSize, concealment: WidgetConcealment) -> String? {
        condenses(size) && !concealment.hidesValues && !title.isEmpty ? title : nil
    }

    /// The lock screen card and the expanded island grow to AX4: condensed, the resting card measures 158 pt there (151
    /// at AX3) and 167 at AX5, past the lock screen's 160.
    static let largestType: DynamicTypeSize = .accessibility4
    /// The island's compact and minimal regions are fixed (37 pt high): their glyph keeps the default size.
    static let glanceLargestType: DynamicTypeSize = .large
}
