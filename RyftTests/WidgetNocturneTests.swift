import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// W, the widget and the Live Activities in Nocturne (PR 6 C §4.15, B §8 and D6B-11; F21, F24, L27). The extension can't be
/// imported here, so its decisions live in `Shared/WidgetLook.swift`, which the app compiles too: the ink of each line per
/// state, the centre's value, what a redaction leaves, how old a snapshot is, the families' layout and how far each grows
/// with Dynamic Type, and the rest timer's Volt. The heights below are the views' stacks measured in the system's line
/// heights (the views themselves are the extension's). The scans at the end read `RyftWidgets/` and `Shared/WidgetLook.swift`:
/// no teal, and the only Volt the extension draws itself is the running rest's dot and bar. The words stay the widget's
/// (`Words`): its previews and the comparison shots show them.
@Suite("W: the widget and the Live Activities")
struct WidgetNocturneTests {
    private static let calendar = WidgetAge.calendar

    /// Noon on 19 Nov 2026, `days` later (negative: earlier), and `hour` on such a day.
    private static func day(_ days: Int = 0, hour: Int = 12, minute: Int = 0) -> Date {
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: hour, minute: minute)) ?? .now
        return calendar.date(byAdding: .day, value: days, to: noon) ?? noon
    }

    private static let today = day()
    private static let bedtime = day(hour: 22, minute: 41)

    /// What the app writes for each state on `today` (the widget's previews' values: 71 / 71 % / 88 % / 9.6, 64 before).
    private static func snapshot(_ kind: ReadinessSnapshot.Kind, orbit: Bool = true, previous: Int? = 64,
                                 written: Date = today) -> ReadinessSnapshot {
        ReadinessSnapshot(day: ReadinessSnapshot.dayString(written), kind: kind, readiness: kind == .score ? 71 : nil,
                          previousReadiness: previous, baselineNights: kind == .calibrating ? 3 : nil, updatedAt: written,
                          bedtime: bedtime, orbit: orbit ? .init(recovery: 71, sleepPerformance: 88, strain: 9.6) : nil)
    }

    /// The app wrote today's score `days` ago at 21:40 and hasn't since; the widget shows it as of `today`.
    private static func written(daysAgo days: Int) -> ReadinessSnapshot {
        snapshot(.score, written: day(-days, hour: 21, minute: 40))
    }

    // MARK: the layout (C §4.15, F24, D6C-16)

    /// The small tile's dial with `caption` points of caption: the orbit fills what the inset and the caption leave of
    /// the tile, square (the view's `GeometryReader` hands `dial(inSide:)` the same side).
    private static func smallDial(tile: CGFloat, caption: CGFloat) -> CGFloat {
        let content = tile - 2 * ReadinessWidgetLook.smallInset
        return ReadinessWidgetLook.dial(inSide: min(content, content - ReadinessWidgetLook.captionGap - caption))
    }

    private static func font(_ style: UIFont.TextStyle, _ size: DynamicTypeSize) -> UIFont {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: category(size)))
    }

    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }

    /// The next Dynamic Type size up.
    private static func larger(_ size: DynamicTypeSize) throws -> DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        let index = try #require(sizes.firstIndex(of: size))
        return try #require(index + 1 < sizes.count ? sizes[index + 1] : nil)
    }

    @Test("the small tile: 12 pt in, dial 104 and frame 116 in the 158 pt tile, the orbit shrinking for more caption")
    func smallTileLayout() {
        let caption = Self.font(.caption2, .large).lineHeight
        #expect(ReadinessWidgetLook.smallInset == 12)
        #expect(ReadinessWidgetLook.captionGap == 4)
        let dial = Self.smallDial(tile: 158, caption: caption)
        #expect(dial == 104)
        #expect(OrbitGaugeSize.custom(dial: dial).frame == 116)
        // The larger iPhones' 170 pt tile: the orbit fills what is there, the inset and the caption stay.
        #expect(Self.smallDial(tile: 170, caption: caption) == 116)
        // A second line: the orbit shrinks and stays square, never below nothing.
        let twoLines = Self.smallDial(tile: 158, caption: 2 * caption)
        #expect(twoLines < dial && twoLines >= OrbitGaugeGeometry.minDialForNumber)
        #expect(Self.smallDial(tile: 158, caption: 500) == 0)
    }

    @Test("the circle keeps its number down to the SE's 68 pt: dial 62 in 76, 58 in 72, 56 in 68")
    func circleLayout() {
        typealias Look = ReadinessWidgetLook
        #expect(Look.circularDial(side: 76) == 62)
        #expect(Look.circularDial(side: 72) == 58)
        #expect(Look.circularDial(side: 68) == 56)
        for side: CGFloat in [76, 72, 68] {
            #expect(Look.circularDial(side: side) >= OrbitGaugeGeometry.minDialForNumber, "\(side)")
            // Never past the circle: the frame (dial + 12, the outer dot's room) fits.
            #expect(OrbitGaugeSize.custom(dial: Look.circularDial(side: side)).frame <= side, "\(side)")
        }
        // Where the air would cost the number the frame touches the edge; where it wouldn't, the air stays.
        #expect(OrbitGaugeSize.custom(dial: Look.circularDial(side: 68)).frame == 68)
        #expect(Look.circularDial(side: 72) == 72 - Look.circularAir)
        #expect(Look.circularDial(side: 0) == 0)
    }

    @Test("the rectangle: the orbit at 44, 10 from its lines, too small for a number (the value stands beside it)")
    func rectangleLayout() {
        #expect(ReadinessWidgetLook.rectangularDial == 44)
        #expect(ReadinessWidgetLook.rectangularGap == 10)
        #expect(ReadinessWidgetLook.rectangularDial < OrbitGaugeGeometry.minDialForNumber)
    }

    @Test("the centre number is Light in the small tile (20 pt and up), below it Regular (F21, D6C-8)")
    func numberWeight() {
        #expect(OrbitGaugeGeometry.numberPointSize(forDial: 104) >= ReadinessWidgetLook.lightNumberFrom)
        #expect(OrbitGaugeGeometry.numberPointSize(forDial: 62) < ReadinessWidgetLook.lightNumberFrom)
    }

    // MARK: Dynamic Type: less content before a cap

    @Test("Dynamic Type, small tile: up to AX1, where two caption lines still leave the number, in 158 and 148 pt")
    func smallTileType() {
        #expect(ReadinessWidgetLook.smallLargestType == .accessibility1)
        let ax1 = Self.font(.caption2, .accessibility1).lineHeight
        for tile: CGFloat in [158, 148] {
            #expect(Self.smallDial(tile: tile, caption: 2 * ax1) >= OrbitGaugeGeometry.minDialForNumber, "\(tile)")
        }
    }

    /// The rectangle's lines: "Readiness" (footnote), the value (title 2), then one line (folded) or two (caption 2).
    private static func rectangle(_ size: DynamicTypeSize, folded: Bool, value: Bool = true) -> CGFloat {
        let lines = CGFloat(folded ? ReadinessWidgetLook.rectangularLineLimit(hasValue: value, hasBedtime: true, folded: true) : 2)
        return font(.footnote, size).lineHeight + (value ? font(.title2, size).lineHeight : 0)
            + lines * font(.caption2, size).lineHeight
    }

    @Test("Dynamic Type, rectangle: four lines at the default size, folded to three above it, up to xxLarge in 72 pt")
    func rectangleType() throws {
        typealias Look = ReadinessWidgetLook
        #expect(!Look.rectangularFolds(.large))
        #expect(Look.rectangularFolds(.xLarge))
        #expect(Look.rectangularLargestType == .xxLarge)
        // Four lines fit the 72 pt slot at the default size; one size up they don't, so it folds there.
        #expect(Self.rectangle(.large, folded: false) <= 72)
        #expect(Self.rectangle(.xLarge, folded: false) > 72)
        // Folded: 72 pt up to the cap (the SE's 68 at xLarge), not one size past it.
        #expect(Self.rectangle(.xxLarge, folded: true) <= 72)
        #expect(Self.rectangle(.xLarge, folded: true) <= 68)
        let pastCap = try Self.larger(Look.rectangularLargestType)
        #expect(Self.rectangle(pastCap, folded: true) > 72)
        // Without a value, two status lines fit at the cap.
        #expect(Self.rectangle(.xxLarge, folded: true, value: false) <= 72)
        // On the SE at the default size the view tries four lines first and folds where they don't fit: folded fits.
        #expect(Self.rectangle(.large, folded: true) <= 68)
    }

    @Test("the rectangle's status: wraps before it truncates unfolded, one line under a value folded")
    func rectangleLineLimit() {
        typealias Look = ReadinessWidgetLook
        #expect(Look.rectangularLineLimit(hasValue: true, hasBedtime: true, folded: false) == 1)
        #expect(Look.rectangularLineLimit(hasValue: true, hasBedtime: false, folded: false) == 2)
        #expect(Look.rectangularLineLimit(hasValue: false, hasBedtime: false, folded: false) == 3)
        #expect(Look.rectangularLineLimit(hasValue: true, hasBedtime: true, folded: true) == 1)
        #expect(Look.rectangularLineLimit(hasValue: true, hasBedtime: false, folded: true) == 1)
        #expect(Look.rectangularLineLimit(hasValue: false, hasBedtime: false, folded: true) == 2)
        // Folded, tonight's bedtime takes the status's place, as on the small tile.
        let evening = Look.smallCaption(Self.snapshot(.score), bedtime: Self.bedtime, age: nil, redacted: false)
        #expect(evening == .slot(.bedtime(Self.bedtime)))
    }

    /// The resting card on the lock screen, its label's first baseline on the 40 pt clock's: padding, the top row, the
    /// rest's bar, the next set beside the 32 pt "Open"; condensed, no session title and one line of the next set.
    private static func card(_ size: DynamicTypeSize, condensed: Bool) -> CGFloat {
        typealias Look = WorkoutActivityLook
        let clock = UIFont.systemFont(ofSize: 40, weight: .light), label = font(.caption2, size)
        let labels = label.lineHeight + (condensed ? 0 : Look.labelGap + font(.caption1, size).lineHeight)
        let top = max(clock.lineHeight, clock.ascender - label.ascender + labels)
        let next = max(CGFloat(condensed ? 1 : Look.nextLines) * font(.subheadline, size).lineHeight, Look.openPill)
        return 2 * Look.padding + top + Look.rowGap + 4 + Look.rowGap + next
    }

    @Test("Dynamic Type, rest timer: the full card at the default size, condensed above it, up to its cap under 160 pt")
    func lockCardType() throws {
        typealias Look = WorkoutActivityLook
        #expect(!Look.condenses(.large))
        #expect(Look.condenses(.xLarge))
        #expect(Look.nextLineLimit(.large) == 2)
        #expect(Look.nextLineLimit(.xLarge) == 1)
        // iOS gives a Live Activity 160 pt on the lock screen: the full card fits at the default size, not one up.
        #expect(Self.card(.large, condensed: false) <= 160)
        #expect(Self.card(.xLarge, condensed: false) > 160)
        // Condensed, it fits at the cap, and the cap is the largest size that does.
        #expect(Self.card(Look.largestType, condensed: true) <= 160)
        if Look.largestType < .accessibility5 {
            let pastCap = try Self.larger(Look.largestType)
            #expect(Self.card(pastCap, condensed: true) > 160)
        }
        #expect(Look.glanceLargestType == .large)
    }

    // MARK: the ink per state

    @Test("the caption's words and ink in each state: bedtime in full ink, every other line secondary")
    func captionPerState() {
        typealias Look = ReadinessWidgetLook
        let rows: [(String, ReadinessWidgetLook.Line, WidgetInk)] = [
            ("score", Look.smallCaption(Self.snapshot(.score), bedtime: nil, age: nil, redacted: false), .secondary),
            ("evening", Look.smallCaption(Self.snapshot(.score), bedtime: Self.bedtime, age: nil, redacted: false), .primary),
            ("pending", Look.smallCaption(Self.snapshot(.pending), bedtime: nil, age: nil, redacted: false), .secondary),
            ("waiting", Look.smallCaption(Self.snapshot(.waitingForSleep), bedtime: nil, age: nil, redacted: false), .secondary),
            ("calibrating", Look.smallCaption(Self.snapshot(.calibrating), bedtime: nil, age: nil, redacted: false), .secondary),
            ("no snapshot", Look.smallCaption(nil, bedtime: nil, age: nil, redacted: false), .secondary),
            ("stale", Look.smallCaption(Self.snapshot(.score).asOf(Self.today), bedtime: nil, age: .yesterday, redacted: false),
             .secondary),
            ("locked", Look.smallCaption(Self.snapshot(.score), bedtime: Self.bedtime, age: .yesterday, redacted: true), .secondary),
        ]
        let expected: [String: ReadinessWidgetLook.Line] = [
            "score": .slot(.band(71)), "evening": .slot(.bedtime(Self.bedtime)), "pending": .slot(.status(.pending)),
            "waiting": .slot(.status(.waitingForSleep)), "calibrating": .slot(.status(.calibrating)),
            "no snapshot": .slot(.status(nil)), "stale": .age(.yesterday), "locked": .slot(.locked),
        ]
        for (name, line, ink) in rows {
            #expect(line == expected[name], "\(name)")
            #expect(ReadinessWidgetLook.ink(of: line) == ink, "\(name)")
            #expect(line.isBedtime == (name == "evening"), "\(name)")
        }
    }

    @Test("the ladder is the app's: textPrimary, textSecondary 62 %, textTertiary 48 %")
    @MainActor
    func ladder() {
        typealias T = NocturneTokenTests
        #expect(WidgetInk.primary.opacity == 1)
        #expect(abs(T.resolve(Theme.textSecondary).a - WidgetInk.secondary.opacity) < 0.005)
        #expect(abs(T.resolve(Theme.textTertiary).a - WidgetInk.tertiary.opacity) < 0.005)
        // Over the widget's graphite: the 11 pt caption reads at 4.5:1, the dimmed number (17 pt and up) at 3:1.
        let mist = T.rgba(0xF2F1EC), graphite = T.rgba(0x0A0C0B)
        func on(_ ink: WidgetInk) -> Double { T.ratio(T.RGBA(r: mist.r, g: mist.g, b: mist.b, a: ink.opacity), on: graphite) }
        #expect(on(.secondary) >= 4.5)
        #expect(on(.tertiary) >= 3)
    }

    // MARK: the gauge's value, what a redaction leaves, VoiceOver

    @Test("the centre: the day's number in full ink, a previous day's and the dash dimmed, the count, the constant")
    func centreValue() {
        typealias Look = ReadinessWidgetLook
        func centre(_ s: ReadinessSnapshot?, _ concealment: WidgetConcealment = .none) -> Look.Centre {
            Look.centre(s?.gauge, readiness: s?.readiness, previousReadiness: s?.previousReadiness, concealment: concealment)
        }
        var beforeOrbit = Self.snapshot(.score)
        beforeOrbit.orbit = nil
        let rows: [(String, Look.Centre, Look.Centre, WidgetInk)] = [
            ("score", centre(Self.snapshot(.score)), .readiness(71, dimmed: false), .primary),
            ("before the orbit", centre(beforeOrbit), .readiness(71, dimmed: false), .primary),
            ("pending", centre(Self.snapshot(.pending)), .readiness(64, dimmed: true), .tertiary),
            ("pending, no orbit", centre(Self.snapshot(.pending, orbit: false)), .readiness(64, dimmed: true), .tertiary),
            ("first night", centre(Self.snapshot(.waitingForSleep, orbit: false, previous: nil)), .dash, .tertiary),
            ("calibrating", centre(Self.snapshot(.calibrating)), .baselines(3), .primary),
            ("stale", centre(Self.written(daysAgo: 1).asOf(Self.today)), .readiness(71, dimmed: true), .tertiary),
            ("locked", centre(Self.snapshot(.score), .locked), .hidden, .primary),
            ("placeholder", centre(nil, .placeholder), .dash, .tertiary),
        ]
        for (name, actual, expected, ink) in rows {
            #expect(actual == expected, "\(name)")
            #expect(Look.ink(of: actual) == ink, "\(name)")
        }
    }

    @Test("the rectangle's value: today's, a previous day's dimmed, 3 of 7, the constant; none without a number")
    func rectangularValue() {
        typealias Look = ReadinessWidgetLook
        #expect(Look.rectangularValue(Self.snapshot(.score)) == .readiness(71, dimmed: false))
        #expect(Look.rectangularValue(Self.snapshot(.pending)) == .readiness(64, dimmed: true))
        #expect(Look.rectangularValue(Self.snapshot(.calibrating)) == .baselines(3))
        #expect(Look.rectangularValue(Self.snapshot(.waitingForSleep, orbit: false, previous: nil)) == nil)
        #expect(Look.rectangularValue(nil) == nil)
        for s in [Self.snapshot(.score), Self.snapshot(.calibrating), nil] {
            #expect(Look.rectangularValue(s, concealment: .locked) == .hidden)
        }
    }

    @Test("the placeholder shows no number at all (the dash, no value), never a score; the boxed 00 is a locked device's")
    func placeholder() {
        typealias Look = ReadinessWidgetLook
        #expect(WidgetConcealment(.placeholder) == .placeholder)
        #expect(WidgetConcealment(.privacy) == .locked)
        #expect(WidgetConcealment([.privacy, .placeholder]) == .placeholder)
        #expect(WidgetConcealment([]) == .none)
        #expect(WidgetConcealment.placeholder.hidesValues && WidgetConcealment.locked.hidesValues)
        #expect(!WidgetConcealment.none.hidesValues)
        // Whatever the snapshot (the system's placeholder has none), the centre is the dash and the rectangle has no
        // value; on a locked device both are the constant.
        for s in [Self.snapshot(.score), Self.snapshot(.pending), Self.snapshot(.calibrating), nil] {
            let name = s.map { "\($0.kind)" } ?? "none"
            #expect(Look.centre(s?.gauge, readiness: s?.readiness, previousReadiness: s?.previousReadiness,
                                concealment: .placeholder) == .dash, "\(name)")
            #expect(Look.rectangularValue(s, concealment: .placeholder) == nil, "\(name)")
            #expect(Look.centre(s?.gauge, readiness: s?.readiness, previousReadiness: s?.previousReadiness,
                                concealment: .locked) == .hidden, "\(name)")
        }
        // Its words are the constant ones, its speech the name.
        #expect(Look.smallCaption(nil, bedtime: Self.bedtime, age: .yesterday, redacted: true) == .slot(.locked))
        #expect(ReadinessSnapshot.speech(nil, redacted: true) == .name)
    }

    @Test("VoiceOver: a stale snapshot is a night awaited with the last readiness, and says its age; locked says neither")
    func spokenAge() {
        let stale = Self.written(daysAgo: 1)
        let shown = stale.asOf(Self.today)
        #expect(ReadinessSnapshot.speech(shown, redacted: false) == .night(.waitingForSleep, previous: 71))
        #expect(ReadinessSnapshot.speech(shown, redacted: true) == .name)
        let age = WidgetAge.of(stale, at: Self.today, calendar: Self.calendar)
        #expect(ReadinessWidgetLook.line(shown, age: age, redacted: false).age == .yesterday)
        #expect(ReadinessWidgetLook.line(shown, age: age, redacted: true).age == nil)
        #expect(ReadinessWidgetLook.line(shown, age: age, redacted: true) == .slot(.locked))
    }

    @Test("VoiceOver's sentences: one stop between parts, none doubled after a full stop or an ellipsis")
    func sentences() {
        #expect(WidgetSpeech.sentences(["Waiting for last night", "Last readiness 64.", "As of yesterday"])
            == "Waiting for last night. Last readiness 64. As of yesterday")
        #expect(WidgetSpeech.sentences(["Scoring your night…", "Last readiness 64.", nil, "Bed by 10:41 PM"])
            == "Scoring your night… Last readiness 64. Bed by 10:41 PM")
        #expect(WidgetSpeech.sentences([nil, "Recovery 71 percent"]) == "Recovery 71 percent")
        #expect(WidgetSpeech.sentences(["", "Open RYFT to see your readiness.", nil]) == "Open RYFT to see your readiness.")
        #expect(!WidgetSpeech.sentences(["Last readiness 64.", "As of Monday"]).contains(".."))
    }

    // MARK: "as of" ageing

    @Test("as of: nothing on the day the app wrote it; yesterday, a weekday within the week, then the date")
    func ageing() {
        func age(_ s: ReadinessSnapshot?, at date: Date = Self.today) -> WidgetAge? {
            WidgetAge.of(s, at: date, calendar: Self.calendar)
        }
        #expect(age(nil) == nil)
        #expect(age(Self.snapshot(.score)) == nil)
        #expect(age(Self.snapshot(.pending, written: Self.day(hour: 0, minute: 5))) == nil)
        #expect(age(Self.written(daysAgo: 1)) == .yesterday)
        // Just after midnight: the evening before is yesterday.
        #expect(age(Self.snapshot(.score, written: Self.day(-1, hour: 23, minute: 59)), at: Self.day(hour: 0, minute: 1))
            == .yesterday)
        #expect(age(Self.written(daysAgo: 2)) == .weekday(Self.day(-2, hour: 21, minute: 40)))
        #expect(age(Self.written(daysAgo: 6)) == .weekday(Self.day(-6, hour: 21, minute: 40)))
        #expect(age(Self.written(daysAgo: 7)) == .date(Self.day(-7, hour: 21, minute: 40), withYear: false))
        #expect(age(Self.written(daysAgo: 40)) == .date(Self.day(-40, hour: 21, minute: 40), withYear: false))
        // The day it compares is the one the snapshot is written with.
        for date in [Self.today, Self.day(hour: 0, minute: 1), Self.day(hour: 23, minute: 59)] {
            #expect(WidgetAge.day(of: date, in: WidgetAge.calendar) == ReadinessSnapshot.dayString(date))
        }
    }

    @Test("as of: never 'yesterday' for a snapshot the app wrote today or later, whatever its day says")
    func ageingNotBefore() {
        // An earlier day's snapshot written today (a clock or zone change) or in the future: no age.
        var writtenToday = Self.snapshot(.score, written: Self.day(hour: 0, minute: 10))
        writtenToday.day = ReadinessSnapshot.dayString(Self.day(-1))
        #expect(WidgetAge.of(writtenToday, at: Self.today, calendar: Self.calendar) == nil)
        var writtenLater = Self.snapshot(.score, written: Self.day(1, hour: 8))
        writtenLater.day = ReadinessSnapshot.dayString(Self.day(-1))
        #expect(WidgetAge.of(writtenLater, at: Self.today, calendar: Self.calendar) == nil)
    }

    @Test("as of: calendar days across daylight saving time (Berlin, March and October 2026)")
    func ageingAcrossDaylightSaving() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try #require(berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
        }
        func age(written: Date, at date: Date) -> WidgetAge? {
            let s = ReadinessSnapshot(day: WidgetAge.day(of: written, in: berlin), kind: .score, readiness: 71,
                                      previousReadiness: 64, baselineNights: nil, updatedAt: written, bedtime: nil, orbit: nil)
            return WidgetAge.of(s, at: date, calendar: berlin)
        }
        // 29 March has 23 hours: 23:30 the night before is still yesterday at 23:59, and two days at 00:01 after.
        let march28Late = try at(3, 28, 23, 30), march28Early = try at(3, 28, 0, 30)
        let march29End = try at(3, 29, 23, 59), march30Start = try at(3, 30, 0, 1)
        #expect(age(written: march28Late, at: march29End) == .yesterday)
        #expect(age(written: march28Late, at: march30Start) == .weekday(march28Late))
        #expect(age(written: march28Early, at: march29End) == .yesterday)
        // 25 October has 25 hours: 00:30 the day before is yesterday until 23:59, never two days.
        let october24Early = try at(10, 24, 0, 30), october24Late = try at(10, 24, 23, 30)
        let october25Night = try at(10, 25, 1, 30), october25Late = try at(10, 25, 23, 0), october25End = try at(10, 25, 23, 59)
        let october26Start = try at(10, 26, 0, 1)
        #expect(age(written: october24Early, at: october25End) == .yesterday)
        #expect(age(written: october24Late, at: october26Start) == .weekday(october24Late))
        // Written that day itself, across the change: no age.
        #expect(age(written: october25Night, at: october25Late) == nil)
    }

    @Test("as of: over the new year, a weekday within the week, then the date with its year")
    func ageingOverNewYear() throws {
        let calendar = Self.calendar
        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
        }
        func age(written: Date, at date: Date) -> WidgetAge? {
            WidgetAge.of(Self.snapshot(.score, written: written), at: date, calendar: calendar)
        }
        let newYearsEve = try at(2026, 12, 31, 23, 50), newYear = try at(2027, 1, 1, 0, 10)
        let december30 = try at(2026, 12, 30, 21, 40), january2 = try at(2027, 1, 2, 12, 0)
        let december20 = try at(2026, 12, 20, 21, 40), january5 = try at(2027, 1, 5, 12, 0)
        let november1 = try at(2026, 11, 1, 21, 40), november19 = try at(2026, 11, 19, 12, 0)
        #expect(age(written: newYearsEve, at: newYear) == .yesterday)
        #expect(age(written: december30, at: january2) == .weekday(december30))
        #expect(age(written: december20, at: january5) == .date(december20, withYear: true))
        #expect(age(written: november1, at: november19) == .date(november1, withYear: false))
    }

    @Test("a stale snapshot is turned over as Today shows it: the night awaited, the previous day's orbit dimmed")
    func staleTurnsOver() {
        let shown = Self.written(daysAgo: 3).asOf(Self.today)
        #expect(shown.kind == .waitingForSleep)
        #expect(shown.readiness == nil)
        #expect(shown.previousReadiness == 71)
        #expect(ReadinessSnapshot.numberSlot(shown, redacted: false) == .none)
        // Pending with the previous day's values: the shared drawing (Today's own) dims every mark of it, the readiness
        // marker's Volt included, to the same strength as on Today.
        guard case .pending(let previous)? = shown.gauge else {
            Issue.record("a stale score draws the previous day pending, not \(String(describing: shown.gauge))")
            return
        }
        #expect(previous?.readiness == 71)
        #expect(OrbitGaugeMarks.pendingOpacity == 0.6)
    }

    // MARK: the rest timer (b-16, c-26)

    @Test("a rest runs while resting, not stale and not over: only then the Volt dot and bar")
    func restRunning() {
        let now = Self.today
        typealias Look = WorkoutActivityLook
        #expect(Look.restRunning(resting: true, isStale: false, endsAt: now.addingTimeInterval(95), now: now))
        #expect(!Look.restRunning(resting: true, isStale: true, endsAt: now.addingTimeInterval(95), now: now))
        #expect(!Look.restRunning(resting: true, isStale: false, endsAt: now, now: now))
        #expect(!Look.restRunning(resting: true, isStale: false, endsAt: now.addingTimeInterval(-1), now: now))
        #expect(!Look.restRunning(resting: false, isStale: false, endsAt: now.addingTimeInterval(95), now: now))
    }

    @Test("the rest timer's inks: labels secondary, island and clock in ink, the dot and bar Volt only while resting")
    func restInks() {
        let resting = WorkoutActivityLook.inks(restRunning: true)
        let working = WorkoutActivityLook.inks(restRunning: false)
        #expect(resting.restMarks)
        #expect(!working.restMarks)
        for inks in [resting, working] {
            #expect(inks.label == .secondary)
            #expect(inks.islandLabel == .primary)
            #expect(inks.clock == .primary)
        }
        #expect(WorkoutActivityLook.dot == 6)
        #expect(WorkoutActivityLook.openPill == 32)
        #expect(WorkoutActivityLook.nextLines == 2)
        #expect(WorkoutActivityLook.islandNextLines == 1)
        #expect(WorkoutActivityLook.keylineOpacity == 0.5)
    }

    // MARK: the scans: teal and Volt in RyftWidgets/ and Shared/WidgetLook.swift

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The extension's sources and the widget's decisions in `Shared/`.
    private static func widgetSources() throws -> [(name: String, text: String)] {
        let folder = root.appendingPathComponent("RyftWidgets")
        let widget = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }.sorted()
            .map { ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)) }
        let look = try String(contentsOf: root.appendingPathComponent("Shared/WidgetLook.swift"), encoding: .utf8)
        return widget + [("Shared/WidgetLook.swift", look)]
    }

    @Test("no teal in RyftWidgets/ or Shared/WidgetLook.swift: the orbit's recovery takes it from the shared palette (L27)")
    func noTeal() throws {
        let teal = try Regex(#"Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)|\.(teal|mint|cyan)\b|accentColor|systemTeal"#)
        let sources = try Self.widgetSources()
        #expect(sources.count >= 9)
        #expect(sources.contains { $0.name == "Shared/WidgetLook.swift" })
        for (name, text) in sources {
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                #expect(line.firstMatch(of: teal) == nil, "\(name):\(n + 1): \(line)")
            }
        }
        // The widget's catalog: only the orbit's `Recovery` is teal.
        let catalog = Self.root.appendingPathComponent("RyftWidgets/Assets.xcassets")
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalog.path).filter { $0.hasSuffix(".colorset") }
        var tealSets: [String] = []
        for set in sets {
            let json = try String(contentsOf: catalog.appendingPathComponent("\(set)/Contents.json"), encoding: .utf8)
            if json.contains("0x63"), json.contains("0xD2"), json.contains("0xB4") { tealSets.append(set) }
        }
        #expect(tealSets == ["Recovery.colorset"])
    }

    @Test("the Volt the extension draws itself: Brand.signal (Theme.signal) for the running rest's dot and bar, nothing else")
    @MainActor
    func voltTheExtensionDraws() throws {
        // Out of this scan by design: the orbit's readiness marker, the shared drawing's `Signal` (`OrbitGaugePalette`),
        // which every family draws at the value, as Today does.
        let declaration = try Regex(#"^(?:private |fileprivate )?(?:struct|enum|extension|final class|class) ([\w.]+)"#)
        var uses: [String] = []
        for (name, text) in try Self.widgetSources() {
            var owner = ""
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if let match = line.firstMatch(of: declaration), let type = match.output[1].substring { owner = String(type) }
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                #expect(!code.contains("Theme.signal") && !code.contains(#"Color("Signal")"#) && !code.contains(#"Color("OnSignal")"#),
                        "\(name):\(n + 1): Volt spelled outside Brand.signal")
                if code.contains("static let signal = Color(") {
                    #expect(owner == "Brand", "\(name):\(n + 1)")
                } else if code.contains("Brand.signal") {
                    uses.append(owner)
                }
            }
        }
        #expect(uses.sorted() == ["RestTimerBar", "RestTimerDot"])

        // Its hex is the app's Volt (check-shared-types.py compares it with the Signal colorset, this with Theme.signal).
        let brand = try String(contentsOf: Self.root.appendingPathComponent("RyftWidgets/RyftWidgets.swift"), encoding: .utf8)
        let hex = try Regex(#"static let signal = Color\(red: 0x([0-9A-F]{2}) / 255, green: 0x([0-9A-F]{2}) / 255, blue: 0x([0-9A-F]{2}) / 255\)"#)
        let match = try #require(brand.firstMatch(of: hex))
        let channels = (1...3).compactMap { match.output[$0].substring.flatMap { Int($0, radix: 16) } }
        let theme = NocturneTokenTests.resolve(Theme.signal)
        #expect(channels == [theme.r, theme.g, theme.b].map { Int(($0 * 255).rounded()) })
    }
}
