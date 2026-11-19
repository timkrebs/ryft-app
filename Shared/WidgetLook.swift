// The widget's look decided without words or fonts (ADR 0010): the ink each line takes in each state, where Volt may go,
// the small family's layout and how old a snapshot is. The extension can't be imported by the app's tests, so its
// decisions live here, where `WidgetNocturneTests` reaches them through the app target; the widget (`RyftWidgets/`) draws
// them in the system face with its own words and `Brand` colours. Nocturne PR 6 C §4.15, B §8 (D6B-11), F21, F24, L27.
import SwiftUI

/// The neutral ladder the widget draws its text in: `Brand.mist` at the strengths of the app's `textPrimary`,
/// `textSecondary` and `textTertiary`. Volt isn't on it: only the running rest's dot and bar take it
/// (`WorkoutActivityLook.restMarks`), and teal only the orbit's recovery (`OrbitGaugePalette`).
enum WidgetInk: Equatable, Sendable {
    /// A value, tonight's bedtime, a clock, the "Open" pill's fill.
    case primary
    /// The caption under the orbit, labels, a session title, a status line.
    case secondary
    /// A previous day's number and the dash.
    case tertiary

    /// Of `Brand.mist`.
    var opacity: Double {
        switch self {
        case .primary: return 1
        case .secondary: return 0.62
        case .tertiary: return 0.48
        }
    }

    /// The track under a bar: ink at 16 %, the pixel `SurfaceRaised` is.
    static let trackOpacity = 0.16
}

/// How old what the widget shows is, once the app hasn't written it on the day shown: "As of yesterday", "As of
/// Monday", "As of Nov 16".
enum WidgetAge: Equatable, Sendable {
    case yesterday
    /// Two to six days ago: the weekday.
    case weekday(Date)
    /// A week or more ago: the date.
    case date(Date)

    /// `nil` while the snapshot is of `date`'s day: what it says is the day's. The app writes the file on the first
    /// refresh of every day (its `day` changes), so a snapshot of an earlier day means the app hasn't refreshed since,
    /// and the widget (which turns it over, `ReadinessSnapshot.asOf`) says when it last did. The words are the widget's;
    /// a locked device never shows the age (`ReadinessWidgetLook.line`).
    static func of(_ snapshot: ReadinessSnapshot?, at date: Date, calendar: Calendar = .current) -> WidgetAge? {
        guard let snapshot, snapshot.day != ReadinessSnapshot.dayString(date) else { return nil }
        let written = snapshot.updatedAt
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: written),
                                           to: calendar.startOfDay(for: date)).day ?? 1
        switch days {
        case ...1: return .yesterday
        case 2...6: return .weekday(written)
        default: return .date(written)
        }
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

    /// The small tile's words grow up to AX1: two caption lines there still leave the orbit room for its number
    /// (`OrbitGaugeGeometry.minDialForNumber`), down to the smallest iPhones' 148 pt tile. Larger, the caption would
    /// take the number's place.
    static let smallLargestType: DynamicTypeSize = .accessibility1
    /// The rectangle is 76 pt high, and its four lines (13, 22, 11 and 11 pt) fill it at the default size, so they keep
    /// it; the line family, VoiceOver and the app say the same at any size.
    static let rectangularLargestType: DynamicTypeSize = .large
    static let rectangularHeight: CGFloat = 76

    /// The rectangle's tallest stack: "Readiness", the value and two 11 pt lines.
    static func rectangularStack(label: CGFloat, value: CGFloat, line: CGFloat) -> CGFloat { label + value + 2 * line }

    /// The dial that fits a square of `side`: the frame's 6 pt for the outer dot on each side come off.
    static func dial(inSide side: CGFloat) -> CGFloat { max((side - 12).rounded(.down), 0) }

    /// The small family's dial: the orbit fills what the caption leaves of the tile, square (104 in the 158 pt tile
    /// with one 11 pt line, frame 116; it shrinks for a second line or a larger text size).
    static func smallDial(tile: CGFloat, captionHeight: CGFloat) -> CGFloat {
        let content = tile - 2 * smallInset
        return dial(inSide: min(content, content - captionGap - captionHeight))
    }

    // MARK: the centre

    /// What the orbit's centre holds.
    enum Centre: Equatable {
        /// A locked device or the placeholder: one constant ("00"), since a redaction keeps its text's width.
        case hidden
        /// A readiness; `dimmed`: a previous day's, while the night is scored or awaited.
        case readiness(Int, dimmed: Bool)
        /// The baselines counted (the caption or the line beside says "of 7").
        case baselines(Int)
        /// No number known: the dash.
        case dash
    }

    /// The day's readiness for a score; the previous day's (the drawing's, else `previousReadiness`) while pending or
    /// awaited; the nights counted while calibrating; `readiness` when the mode is unknown (a file from before the orbit).
    static func centre(_ mode: OrbitGaugeMode?, readiness: Int?, previousReadiness: Int?, hidden: Bool) -> Centre {
        if hidden { return .hidden }
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
    /// has come since); otherwise the band word for a score, else the status. One constant on a locked device.
    static func line(_ shown: ReadinessSnapshot?, age: WidgetAge?, redacted: Bool) -> Line {
        if !redacted, let age { return .age(age) }
        return .slot(ReadinessSnapshot.lineSlot(shown, redacted: redacted))
    }

    /// The small family's one caption: tonight's bedtime in the evening, else `line`.
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
    /// baselines' count ("3 of 7"), the constant when locked; none without a snapshot or a number.
    static func rectangularValue(_ shown: ReadinessSnapshot?, redacted: Bool) -> Centre? {
        if redacted { return .hidden }
        guard let shown else { return nil }
        let value = centre(shown.gauge, readiness: shown.readiness, previousReadiness: shown.previousReadiness, hidden: false)
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
        /// The 6 pt dot before "Rest" and the rest's bar, in Volt. The only Volt in the extension (L27: "now"); neither is
        /// drawn otherwise.
        var restMarks: Bool
    }

    static func inks(restRunning: Bool) -> Inks {
        Inks(label: .secondary, islandLabel: .primary, clock: .primary, restMarks: restRunning)
    }

    /// The dot before "Rest", the bar's height, the "Open" pill's height (D6C-10: the activity's height is the system's,
    /// so not the app's 52), the padding and the gap between rows.
    static let dot: CGFloat = 6, bar: CGFloat = 4, openPill: CGFloat = 32, padding: CGFloat = 16, rowGap: CGFloat = 12
    /// The next set may take two lines on the lock screen (D6B-11: one line cut it at the load); one in the island.
    static let nextLines = 2, islandNextLines = 1
    /// Between the label and the session title on the lock screen.
    static let labelGap: CGFloat = 2
    /// The island's keyline: ink at half strength, never Volt or teal (C §4.15).
    static let keylineOpacity = 0.5

    /// iOS truncates a Live Activity taller than 160 pt on the lock screen.
    static let lockScreenLimit: CGFloat = 160
    /// The activities' words keep the default size: the resting card takes about 154 of the lock screen's 160 pt there
    /// (one size up passes it), and the island's compact and minimal regions are fixed. The clocks and "Open" have fixed
    /// sizes anyway; VoiceOver reads every word.
    static let largestType: DynamicTypeSize = .large

    /// The lock screen card's height for its lines: the padding; the top row, where the label's first baseline sits on
    /// the clock's (so the label drops by `baselineDrop`); the rest's bar while it runs; the next set's two lines beside
    /// "Open".
    static func lockScreenHeight(clockLine: CGFloat, baselineDrop: CGFloat, labelStack: CGFloat, nextLine: CGFloat,
                                 restBar: Bool) -> CGFloat {
        let top = max(clockLine, baselineDrop + labelStack)
        let bar = restBar ? rowGap + self.bar : 0
        let next = max(CGFloat(nextLines) * nextLine, openPill)
        return 2 * padding + top + bar + rowGap + next
    }
}
