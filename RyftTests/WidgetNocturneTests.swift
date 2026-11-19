import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// W, the widget and the Live Activities in Nocturne (PR 6 C §4.15, B §8 and D6B-11; F21, F24, L27). The extension can't be
/// imported here, so its decisions live in `Shared/WidgetLook.swift`, which the app compiles too: the ink of each line per
/// state, the centre's value, how old a snapshot is, the small tile's layout and the rest timer's Volt. The scan at the end
/// reads `RyftWidgets/` itself: no teal outside the orbit, and Volt only for the running rest's dot and bar. The words stay
/// the widget's (`Words`): its previews and the comparison shots show them.
@Suite("W: the widget and the Live Activities")
struct WidgetNocturneTests {
    private static let calendar = Calendar.current

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

    // MARK: the small tile's layout (C §4.15, F24, D6C-16)

    @Test("the small tile: 12 pt in, dial 104 and frame 116 in the 158 pt tile, the orbit shrinking for more caption")
    func smallTileLayout() {
        let caption = UIFont.preferredFont(forTextStyle: .caption2,
                                           compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).lineHeight
        #expect(ReadinessWidgetLook.smallInset == 12)
        #expect(ReadinessWidgetLook.captionGap == 4)
        let dial = ReadinessWidgetLook.smallDial(tile: 158, captionHeight: caption)
        #expect(dial == 104)
        #expect(OrbitGaugeSize.custom(dial: dial).frame == 116)
        // The larger iPhones' 170 pt tile: the orbit fills what is there, the inset and the caption stay.
        #expect(ReadinessWidgetLook.smallDial(tile: 170, captionHeight: caption) == 116)
        // A second line, or AX3's larger one: the orbit shrinks and stays square, never below nothing.
        let ax3 = UIFont.preferredFont(forTextStyle: .caption2,
                                       compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        let twoLines = ReadinessWidgetLook.smallDial(tile: 158, captionHeight: 2 * caption)
        let ax3Lines = ReadinessWidgetLook.smallDial(tile: 158, captionHeight: 2 * ax3.lineHeight)
        #expect(twoLines < dial && twoLines >= OrbitGaugeGeometry.minDialForNumber)
        #expect(ax3Lines < twoLines && ax3Lines > 0)
        #expect(ReadinessWidgetLook.smallDial(tile: 158, captionHeight: 500) == 0)
    }

    @Test("the lock screen: dial 62 in the 76 pt circle, 44 in the rectangle 10 from its lines")
    func lockScreenLayout() {
        #expect(76 - ReadinessWidgetLook.circularAir == 62)
        #expect(ReadinessWidgetLook.rectangularDial == 44)
        #expect(ReadinessWidgetLook.rectangularGap == 10)
        // The rectangle's orbit is too small for a number: the value stands beside it.
        #expect(ReadinessWidgetLook.rectangularDial < OrbitGaugeGeometry.minDialForNumber)
    }

    private static func font(_ style: UIFont.TextStyle, _ size: UIContentSizeCategory) -> UIFont {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: size))
    }

    @Test("Dynamic Type: each surface grows as far as its slot holds (small to AX1, the rectangle and activities not)")
    func typeCaps() {
        // The small tile at AX1: two caption lines still leave a dial with its number, in the 158 and the 148 pt tile.
        #expect(ReadinessWidgetLook.smallLargestType == .accessibility1)
        let ax1 = Self.font(.caption2, .accessibilityMedium).lineHeight
        for tile: CGFloat in [158, 148] {
            #expect(ReadinessWidgetLook.smallDial(tile: tile, captionHeight: 2 * ax1) >= OrbitGaugeGeometry.minDialForNumber)
        }
        // The rectangle: its four lines fit the 76 pt slot at the default size, not one size up.
        func stack(_ size: UIContentSizeCategory) -> CGFloat {
            ReadinessWidgetLook.rectangularStack(label: Self.font(.footnote, size).lineHeight,
                                                 value: Self.font(.title2, size).lineHeight,
                                                 line: Self.font(.caption2, size).lineHeight)
        }
        #expect(ReadinessWidgetLook.rectangularLargestType == .large)
        #expect(stack(.large) <= ReadinessWidgetLook.rectangularHeight)
        #expect(stack(.extraLarge) > ReadinessWidgetLook.rectangularHeight)
        // The resting card on the lock screen: within iOS's 160 pt at the default size, not one size up.
        func card(_ size: UIContentSizeCategory) -> CGFloat {
            let clock = UIFont.systemFont(ofSize: 40, weight: .light), label = Self.font(.caption2, size)
            return WorkoutActivityLook.lockScreenHeight(
                clockLine: clock.lineHeight, baselineDrop: clock.ascender - label.ascender,
                labelStack: label.lineHeight + WorkoutActivityLook.labelGap + Self.font(.caption1, size).lineHeight,
                nextLine: Self.font(.subheadline, size).lineHeight, restBar: true)
        }
        #expect(WorkoutActivityLook.largestType == .large)
        #expect(card(.large) <= WorkoutActivityLook.lockScreenLimit)
        #expect(card(.extraLarge) > WorkoutActivityLook.lockScreenLimit)
    }

    @Test("the centre number is Light in the small tile (20 pt and up), below it Regular (F21, D6C-8)")
    func numberWeight() {
        #expect(OrbitGaugeGeometry.numberPointSize(forDial: 104) >= ReadinessWidgetLook.lightNumberFrom)
        #expect(OrbitGaugeGeometry.numberPointSize(forDial: 62) < ReadinessWidgetLook.lightNumberFrom)
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

    @Test("the ladder is the app's: textPrimary, textSecondary 62 %, textTertiary 48 %, the track 16 %")
    @MainActor
    func ladder() {
        typealias T = NocturneTokenTests
        #expect(WidgetInk.primary.opacity == 1)
        #expect(abs(T.resolve(Theme.textSecondary).a - WidgetInk.secondary.opacity) < 0.005)
        #expect(abs(T.resolve(Theme.textTertiary).a - WidgetInk.tertiary.opacity) < 0.005)
        #expect(WidgetInk.trackOpacity == 0.16)
        // Over the widget's graphite: the 11 pt caption reads at 4.5:1, the dimmed number (17 pt and up) at 3:1.
        let mist = T.rgba(0xF2F1EC), graphite = T.rgba(0x0A0C0B)
        func on(_ ink: WidgetInk) -> Double { T.ratio(T.RGBA(r: mist.r, g: mist.g, b: mist.b, a: ink.opacity), on: graphite) }
        #expect(on(.secondary) >= 4.5)
        #expect(on(.tertiary) >= 3)
    }

    // MARK: the gauge's value and its VoiceOver

    @Test("the centre: the day's number in full ink, a previous day's and the dash dimmed, the count, the constant")
    func centreValue() {
        typealias Look = ReadinessWidgetLook
        func centre(_ s: ReadinessSnapshot?, hidden: Bool = false) -> Look.Centre {
            Look.centre(s?.gauge, readiness: s?.readiness, previousReadiness: s?.previousReadiness, hidden: hidden)
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
            ("locked", centre(Self.snapshot(.score), hidden: true), .hidden, .primary),
        ]
        for (name, actual, expected, ink) in rows {
            #expect(actual == expected, "\(name)")
            #expect(Look.ink(of: actual) == ink, "\(name)")
        }
    }

    @Test("the rectangle's value: today's, a previous day's dimmed, 3 of 7, the constant; none without a number")
    func rectangularValue() {
        typealias Look = ReadinessWidgetLook
        #expect(Look.rectangularValue(Self.snapshot(.score), redacted: false) == .readiness(71, dimmed: false))
        #expect(Look.rectangularValue(Self.snapshot(.pending), redacted: false) == .readiness(64, dimmed: true))
        #expect(Look.rectangularValue(Self.snapshot(.calibrating), redacted: false) == .baselines(3))
        #expect(Look.rectangularValue(Self.snapshot(.waitingForSleep, orbit: false, previous: nil), redacted: false) == nil)
        #expect(Look.rectangularValue(nil, redacted: false) == nil)
        for s in [Self.snapshot(.score), Self.snapshot(.calibrating), nil] {
            #expect(Look.rectangularValue(s, redacted: true) == .hidden)
        }
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
        #expect(age(Self.written(daysAgo: 7)) == .date(Self.day(-7, hour: 21, minute: 40)))
        #expect(age(Self.written(daysAgo: 40)) == .date(Self.day(-40, hour: 21, minute: 40)))
    }

    @Test("a stale snapshot is turned over the way the widget shows it: the night awaited, the last readiness dimmed")
    func staleTurnsOver() {
        let shown = Self.written(daysAgo: 3).asOf(Self.today)
        #expect(shown.kind == .waitingForSleep)
        #expect(shown.readiness == nil)
        #expect(shown.previousReadiness == 71)
        #expect(ReadinessSnapshot.numberSlot(shown, redacted: false) == .none)
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
        #expect(WorkoutActivityLook.bar == 4)
        #expect(WorkoutActivityLook.openPill == 32)
        #expect(WorkoutActivityLook.nextLines == 2)
        #expect(WorkoutActivityLook.islandNextLines == 1)
        #expect(WorkoutActivityLook.keylineOpacity == 0.5)
    }

    // MARK: the scan: teal and Volt in RyftWidgets/

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func widgetSources() throws -> [(name: String, text: String)] {
        let folder = root.appendingPathComponent("RyftWidgets")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }.sorted()
            .map { ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)) }
    }

    @Test("no teal in RyftWidgets/: the orbit's recovery takes it from the shared palette, nothing else does (L27)")
    func noTeal() throws {
        let teal = try Regex(#"Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)|\.teal\b"#)
        let sources = try Self.widgetSources()
        #expect(sources.count >= 8)
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

    @Test("Volt in RyftWidgets/ only as the running rest's dot and bar, Brand.signal the app's Theme.signal")
    @MainActor
    func voltOnlyForTheRest() throws {
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

    @Test("the placeholder carries no snapshot and hides values like a locked device (never a sample score)")
    func honestPlaceholder() throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent("RyftWidgets/ReadinessWidget.swift"), encoding: .utf8)
        #expect(source.contains("ReadinessEntry(date: .now, snapshot: nil, isPlaceholder: true)"))
        #expect(source.contains("var hidesValues: Bool { contains(.privacy) || contains(.placeholder) }"))
        #expect(ReadinessWidgetLook.centre(.scored(OrbitGaugeValues(readiness: 71)), readiness: 71, previousReadiness: nil,
                                           hidden: true) == .hidden)
    }
}
