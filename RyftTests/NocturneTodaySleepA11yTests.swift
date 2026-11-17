import SwiftUI
import Testing
import UIKit
@testable import Ryft

// VoiceOver on Today and on Sleep → Day, read from the real accessibility tree of a hosted window (docs/work/2026-11-16-nocturne/
// design.md §P4-8's two reading-order tables and §P4-11 test 48): the order and the labels, one element each for a gauge,
// a ruler, a tile and the hypnogram, the header traits on the lock-up, the greeting and "Sleep", the buttons' labels and
// hints, and the disabled night buttons with the reason they give. Strings with a number or a date in them are matched
// by their fixed words: the simulator's region decides the decimal mark and the date's order, and the greeting follows
// the hour.

@MainActor
@Suite("Nocturne: VoiceOver on Today and Sleep", .serialized)
struct NocturneTodaySleepA11yTests {
    private static let width: CGFloat = 390

    // MARK: hosting

    private func today(_ scenario: TodayScenario = .watch, myDay: Bool = true, ax3: Bool = false,
                       body: (HostedWindow) async throws -> Void) async throws {
        let state = AppState.preview(flags: myDay ? [.todayMyDay: true] : [:], scenario: scenario)
        try await HostedWindow.run(width: Self.width, height: ax3 ? 6000 : 2600, typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large,
                                   TodayView().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("Today's ruler") { w.nodes().contains { $0.identifier == "today.ruler" } }
            try await w.settle()
            try await body(w)
        }
    }

    private func sleep(_ night: SleepPreviewScene.Night, ax3: Bool = false,
                       body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: ax3 ? 6000 : 2000, bottomInset: 0,
                                   typeSize: ax3 ? .accessibility3 : .large, category: ax3 ? .accessibilityExtraLarge : .large,
                                   SleepPreviewPage(night)) { w in
            try await w.wait("Sleep's numeral") { w.nodes().contains { $0.identifier == "sleep.numeral" } }
            try await w.settle()
            try await body(w)
        }
    }

    /// The node with this identifier, or a failed expectation that names what the screen had.
    private func node(_ w: HostedWindow, _ identifier: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == identifier }, "\(identifier) in \(w.nodes().compactMap(\.identifier))")
    }

    /// Where each of the screen's elements is in the tree, by `matching`; -1 when it is missing.
    private func positions(_ nodes: [HostedWindow.Node], _ matching: [(HostedWindow.Node) -> Bool]) -> [Int] {
        matching.map { test in nodes.firstIndex(where: test) ?? -1 }
    }

    private func isAscending(_ order: [Int]) -> Bool { !order.contains(-1) && order == order.sorted() && Set(order).count == order.count }

    /// The elements whose centre lies inside `frame`: the element itself, and any part of it that VoiceOver would read
    /// on its own (a sparkline, a dot row, a ruler's labels).
    private func elements(in frame: CGRect, of w: HostedWindow) -> [String] {
        w.nodes().filter { frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map { $0.identifier ?? $0.label }
    }

    private func hint(_ node: HostedWindow.Node) -> String { node.hint ?? "" }

    // MARK: Today: reading order (§P4-8, the table)

    @Test("Today reads lock-up, Calendar, greeting, status, gauge, ruler, the attention card, three tiles, then the cards below",
          arguments: [false, true])
    func todayReadsInTheTablesOrder(ax3: Bool) async throws {
        try await today(ax3: ax3) { w in
            let nodes = w.nodes()
            let order = positions(nodes, [
                { $0.label == "RYFT" },
                { $0.identifier == "today.header.calendar" },
                { $0.label.hasPrefix("Good ") },
                { $0.identifier == "today.syncLine.line" },
                { $0.identifier == "today.readinessGauge" },
                { $0.identifier == "today.ruler" },
                { $0.identifier == "today.watchHint.action" },
                { $0.identifier == "today.tile.recovery" },
                { $0.identifier == "today.tile.sleep" },
                { $0.identifier == "today.tile.strain" },
                { $0.identifier == "myday.title" },
            ])
            #expect(isAscending(order), "\(order) in \(nodes.map { $0.identifier ?? $0.label })")
            // Nothing else is read between the header and the ruler, nor between the tiles: the label row is hidden, the
            // gauge and the tiles are one element each.
            #expect(order[5] - order[0] == 5, "lock-up … ruler: \(order)")
            #expect(order[9] - order[7] == 2, "the three tiles follow each other: \(order)")
        }
    }

    @Test("The label row under the gauge is hidden: the gauge says the band and the change itself")
    func theLabelRowIsNotRead() async throws {
        try await today { w in
            let labels = w.nodes().map(\.label)
            // (The Trends card further down says "Up 11 vs 7 d" inside its own label; the row under the gauge would lead with it.)
            #expect(!labels.contains { $0.hasPrefix("Readiness ·") || $0.hasPrefix("Up 11") || $0.hasPrefix("▲") || $0 == "vs 7 d" },
                    "\(labels)")
            let gauge = try node(w, "today.readinessGauge")
            #expect(gauge.value?.hasPrefix("84, High, Up 11 vs 7 d. Recovery 82 percent, Sleep 94 percent, Strain 12") == true,
                    "\(gauge.value ?? "nil")")
        }
    }

    // MARK: Today: traits

    @Test("The lock-up and the greeting are headers; the buttons are not")
    func todayHeaderTraits() async throws {
        try await today { w in
            let lockUp = try #require(w.nodes().first { $0.label == "RYFT" })
            #expect(lockUp.traits.contains(.header), "the lock-up")
            let greeting = try #require(w.nodes().first { $0.label.hasPrefix("Good ") })
            #expect(greeting.traits.contains(.header), "the greeting")
            #expect(!greeting.traits.contains(.button))
            for id in ["today.header.calendar", "today.syncLine.line", "today.tile.recovery", "today.tile.sleep", "today.tile.strain"] {
                let button = try node(w, id)
                #expect(button.traits.contains(.button) && !button.traits.contains(.header), "\(id)")
            }
            let headers = w.nodes().filter { $0.traits.contains(.header) }.map(\.label)
            #expect(headers.prefix(2).map { $0 == "RYFT" || $0.hasPrefix("Good ") } == [true, true], "\(headers)")
        }
    }

    // MARK: Today: labels, values and hints

    @Test("The greeting is one element: the greeting with the first name, the date in full, then the sentence")
    func theGreetingIsOneSentence() async throws {
        try await today { w in
            let greeting = try #require(w.nodes().first { $0.label.hasPrefix("Good ") })
            let parts = greeting.label.components(separatedBy: ". ")
            #expect(parts.count == 3, "greeting, date, sentence: \(greeting.label)")
            #expect(parts[0].hasSuffix(", Tim"), "\(parts[0])")
            #expect(["Good morning", "Good afternoon", "Good evening"].contains { parts[0].hasPrefix($0) })
            #expect(greeting.label.hasSuffix("Your health is in balance."), "\(greeting.label)")
            // The visible sub-line has the date short and the sentence after a dot; neither is a second element.
            #expect(!w.nodes().contains { $0.label.hasPrefix("Your health is in balance") })
        }
    }

    @Test("Calendar is a button with its hint; the status line is a button that opens the sync details")
    func theHeaderButtonsAndTheStatusRow() async throws {
        try await today { w in
            let calendar = try node(w, "today.header.calendar")
            #expect(calendar.label == "Calendar" && hint(calendar) == "Opens My Day" && calendar.isEnabled)
            let status = try node(w, "today.syncLine.line")
            #expect(status.label.hasPrefix("Demo data") && hint(status) == "Opens sync details")
        }
    }

    @Test("Without My Day there is no Calendar in the tree")
    func noCalendarWithoutMyDay() async throws {
        try await today(myDay: false) { w in
            #expect(!w.nodes().contains { $0.identifier == "today.header.calendar" || $0.label == "Calendar" })
        }
    }

    @Test("The three tiles are buttons with their label, value and hint",
          arguments: [("recovery", "Recovery", "Opens Insights"), ("sleep", "Sleep", "Opens Sleep"), ("strain", "Strain", "Opens Strain")])
    func theTilesAreButtonsWithHints(_ tile: (id: String, label: String, hint: String)) async throws {
        try await today { w in
            let node = try node(w, "today.tile.\(tile.id)")
            #expect(node.label == tile.label && hint(node) == tile.hint)
            #expect(node.traits.contains(.button) && node.isEnabled)
            #expect(node.frame.width > 150 && node.frame.height > 90, "a whole tile: \(node.frame)")
        }
    }

    @Test("The tiles' values say the number, the band and what the sparkline and the dots show")
    func theTilesSpeakTheirSeries() async throws {
        try await today { w in
            let recovery = try node(w, "today.tile.recovery").value
            #expect(recovery == "82 percent, High. HRV 66 milliseconds, lowest 51 and highest 66 over the last 7 days")
            let sleep = try #require(try node(w, "today.tile.sleep").value)
            #expect(sleep.hasPrefix("7 hours 48 minutes. Slept enough on 4 of the last 7 nights; the last is the night shown"), "\(sleep)")
            let strain = try #require(try node(w, "today.tile.strain").value)
            #expect(strain.contains("Moderate strain, on a scale from 0 to 21. The moderate range is 10 to 14."), "\(strain)")
        }
    }

    @Test("A day shown instead of today's says so in the tiles' values")
    func aDimmedDayIsSpoken() async throws {
        try await today(.pending) { w in
            for id in ["recovery", "sleep", "strain"] {
                let value = try #require(try node(w, "today.tile.\(id)").value)
                #expect(value.contains("Yesterday, not today's score"), "\(id): \(value)")
            }
        }
    }

    @Test("The ruler and the gauge say what there is to say in each state",
          arguments: [
              (TodayScenario.watch, "today.readinessGauge", "84, high, on a scale from 0 to 100"),
              (.learningHRV, "today.readinessGauge", "78, on a scale from 0 to 100"),
              (.calibrating, "today.baselineGauge", "No readiness yet, on a scale from 0 to 100"),
              (.pending, "today.pendingGauge", "No readiness yet, on a scale from 0 to 100"),
              (.pendingNoPrevious, "today.pendingGauge", "No readiness yet, on a scale from 0 to 100"),
          ])
    func theRulerAndTheGaugePerState(_ row: (scenario: TodayScenario, gauge: String, ruler: String)) async throws {
        try await today(row.scenario) { w in
            let nodes = w.nodes()
            let ruler = try node(w, "today.ruler")
            #expect(ruler.label == "Readiness scale" && ruler.value == row.ruler, "\(ruler.value ?? "nil")")
            let gauge = try node(w, row.gauge)
            #expect(gauge.label.isEmpty == false)
            let order = positions(nodes, [{ $0.identifier == row.gauge }, { $0.identifier == "today.ruler" }])
            #expect(isAscending(order), "the gauge before its ruler: \(order)")
        }
    }

    // MARK: Today: one element each

    @Test("The gauge, the ruler and each tile are one element; nothing inside them is read on its own")
    func todayHasOneElementPerGaugeRulerAndTile() async throws {
        try await today { w in
            for id in ["today.readinessGauge", "today.ruler", "today.tile.recovery", "today.tile.sleep", "today.tile.strain"] {
                #expect(w.nodes().filter { $0.identifier == id }.count == 1, "\(id) once")
                let inside = elements(in: try node(w, id).frame, of: w)
                #expect(inside == [id], "\(id) holds \(inside)")
            }
        }
    }

    // MARK: Today at AX3 (test 49, Today's half)

    @Test("At AX3 nothing leaves the screen, the tiles stack in one column and the header and the gauge keep their size")
    func todayAtAX3() async throws {
        var normal: CGRect?, lockUp: CGRect?, gauge: CGRect?
        try await today { w in
            normal = w.nodes().first { $0.label == "RYFT" }?.frame
            gauge = try node(w, "today.readinessGauge").frame
        }
        try await today(ax3: true) { w in
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5, "\(node.label) \(node.frame)")
            }
            lockUp = w.nodes().first { $0.label == "RYFT" }?.frame
            let before = try #require(normal), after = try #require(lockUp)
            #expect(abs(after.width - before.width) < 1 && abs(after.height - before.height) < 1,
                    "the header lock-up does not grow: \(after) vs \(before)")
            let gaugeAtAX3 = try node(w, "today.readinessGauge").frame.size
            let gaugeSize = try #require(gauge?.size)
            #expect(abs(gaugeAtAX3.width - gaugeSize.width) < 1 && abs(gaugeAtAX3.height - gaugeSize.height) < 1,
                    "the gauge keeps its size: \(gaugeAtAX3) vs \(gaugeSize)")
            let (recovery, sleep, strain) = try (node(w, "today.tile.recovery").frame, node(w, "today.tile.sleep").frame,
                                                 node(w, "today.tile.strain").frame)
            #expect(abs(recovery.minX - sleep.minX) < 0.5 && sleep.minY > recovery.maxY, "one column: \(recovery) \(sleep)")
            #expect(abs(recovery.width - 350) < 0.5 && abs(sleep.width - 350) < 0.5 && abs(strain.width - 350) < 0.5)
            #expect(strain.minY > sleep.maxY)
        }
    }

    // MARK: Sleep: reading order (§P4-8)

    @Test("Sleep reads Previous night, Sleep, Next night, the picker, the numeral, its caption, the ruler, the hypnogram, the four tiles, the cards",
          arguments: [false, true])
    func sleepReadsInTheTablesOrder(ax3: Bool) async throws {
        try await sleep(.latest, ax3: ax3) { w in
            let nodes = w.nodes()
            let order = positions(nodes, [
                { $0.identifier == "sleep.header.previous" },
                { $0.label == "Sleep" && $0.traits.contains(.header) },
                { $0.identifier == "sleep.header.next" },
                { $0.identifier == "sleep.mode" || $0.label == "Day" || $0.label == "Day ▾" },
                { $0.identifier == "sleep.numeral" },
                { $0.label == "94 percent of your need" },
                { $0.identifier == "sleep.ruler" },
                { $0.identifier == "sleep.hypnogram" },
                { $0.identifier == "sleep.tile.consistency" },
                { $0.identifier == "sleep.tile.debt" },
                { $0.identifier == "sleep.tile.efficiency" },
                { $0.identifier == "sleep.tile.restorative" },
                { $0.identifier == "sleep.need" },
            ])
            #expect(isAscending(order), "\(order) in \(nodes.map { $0.identifier ?? $0.label })")
            // The numeral, its caption, the ruler, the hypnogram and the four tiles follow each other with nothing between.
            #expect(order[11] - order[4] == 7, "numeral … Restorative: \(order)")
        }
    }

    @Test("The picker is four buttons in the Day mode, Day selected, one menu from AX1")
    func theMode() async throws {
        try await sleep(.latest) { w in
            let segments = ["Day", "Week", "Month", "Bedtime"].compactMap { name in w.nodes().first { $0.label == name } }
            #expect(segments.map(\.label) == ["Day", "Week", "Month", "Bedtime"])
            #expect(segments.allSatisfy { $0.traits.contains(.button) })
            #expect(segments.map(\.isSelected) == [true, false, false, false])
        }
        try await sleep(.latest, ax3: true) { w in
            let menu = try node(w, "sleep.mode")
            #expect(menu.traits.contains(.button))
            #expect(!w.nodes().contains { $0.label == "Week" }, "the segments are folded into the menu")
        }
    }

    // MARK: Sleep: traits, values, hints

    @Test("\"Sleep\" is a header whose value is the night, with \"not scored yet\" on a pending one",
          arguments: [(SleepPreviewScene.Night.latest, "Last night, ", false), (.older, "", false), (.pending, "Last night, ", true)])
    func theTitleIsAHeaderWithTheNight(_ row: (night: SleepPreviewScene.Night, prefix: String, pending: Bool)) async throws {
        try await sleep(row.night) { w in
            let title = try #require(w.nodes().first { $0.label == "Sleep" && $0.traits.contains(.header) })
            let value = try #require(title.value)
            #expect(value.hasPrefix(row.prefix) && !value.isEmpty, "\(value)")
            if row.prefix.isEmpty { #expect(!value.hasPrefix("Last night") && !value.hasPrefix("Yesterday"), "\(value)") }
            #expect(value.hasSuffix(", not scored yet") == row.pending, "\(value)")
            #expect(!title.traits.contains(.button))
        }
    }

    @Test("The latest night: Next is disabled and says why, Previous is a plain button")
    func atTheLatestNight() async throws {
        try await sleep(.latest) { w in
            let next = try node(w, "sleep.header.next")
            #expect(next.label == "Next night" && !next.isEnabled && hint(next) == "No newer night to show")
            #expect(next.traits.contains(.button))
            let previous = try node(w, "sleep.header.previous")
            #expect(previous.label == "Previous night" && previous.isEnabled && hint(previous).isEmpty)
        }
    }

    @Test("The oldest night: Previous is disabled and says why, Next is a plain button")
    func atTheOldestNight() async throws {
        try await sleep(.oldest) { w in
            let previous = try node(w, "sleep.header.previous")
            #expect(previous.label == "Previous night" && !previous.isEnabled && hint(previous) == "No older night to show")
            #expect(previous.traits.contains(.button))
            let next = try node(w, "sleep.header.next")
            #expect(next.label == "Next night" && next.isEnabled && hint(next).isEmpty)
        }
    }

    @Test("In between both buttons are enabled and carry no hint")
    func inBetween() async throws {
        try await sleep(.older) { w in
            for id in ["sleep.header.previous", "sleep.header.next"] {
                let button = try node(w, id)
                #expect(button.isEnabled && hint(button).isEmpty, "\(id)")
            }
        }
    }

    @Test("Outside Day mode the night buttons are not in the tree, and the title still is")
    func theWeekHasNoNightButtons() async throws {
        let today = Calendar.current.startOfDay(for: .now)
        let content = SleepHeaderContent(mode: .week, night: today, today: today, marker: nil, canStepBack: true, canStepForward: false)
        try await HostedWindow.run(width: Self.width, height: 200, bottomInset: 0, SleepHeader(content: content, step: { _ in })) { w in
            try await w.wait("the title") { w.nodes().contains { $0.label == "Sleep" } }
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Sleep"], "\(w.nodes().map(\.label))")
            #expect(w.nodes().first?.traits.contains(.header) == true)
        }
    }

    @Test("The numeral, its caption, the ruler and the tiles speak the board's night")
    func sleepSpeaksTheBoardNight() async throws {
        try await sleep(.latest) { w in
            let numeral = try node(w, "sleep.numeral")
            #expect(numeral.label == "7 hours 48 minutes asleep")
            #expect(w.nodes().contains { $0.label == "94 percent of your need" })
            let ruler = try node(w, "sleep.ruler")
            #expect(ruler.label == "Sleep duration scale")
            #expect(ruler.value == "7 hours 48 minutes, on a scale from 0 to 10 hours. Your need is 8 hours 18 minutes.")
            let hypnogram = try node(w, "sleep.hypnogram")
            #expect(hypnogram.label.hasPrefix("Hypnogram, ") && hypnogram.label.contains(" to "), "\(hypnogram.label)")
            #expect(hypnogram.value == "Deep 1 hour 35 minutes, REM 1 hour 45 minutes, Light 4 hours 28 minutes, Awake 22 minutes")
            let (debt, efficiency, restorative) = try (node(w, "sleep.tile.debt"), node(w, "sleep.tile.efficiency"),
                                                       node(w, "sleep.tile.restorative"))
            #expect(debt.value == "30 minutes, down 42 minutes from the night before")
            #expect(efficiency.value == "95 percent")
            #expect(restorative.value == "3 hours 20 minutes of deep and REM sleep, 100 percent of the target")
            let consistency = try #require(try node(w, "sleep.tile.consistency").value)
            #expect(consistency.hasPrefix("86 percent. 5 of the last 7 nights were regular, 1 was not, 1 night has no data;"), "\(consistency)")
            #expect(consistency.hasSuffix("the last is the night shown"), "\(consistency)")
        }
    }

    @Test("The four tiles are information, not buttons")
    func theSleepTilesAreNotButtons() async throws {
        try await sleep(.latest) { w in
            for id in ["consistency", "debt", "efficiency", "restorative"] {
                let tile = try node(w, "sleep.tile.\(id)")
                #expect(!tile.traits.contains(.button) && !tile.traits.contains(.header), "\(id)")
            }
        }
    }

    // MARK: Sleep: one element each

    @Test("The numeral, the ruler, the hypnogram and each tile are one element; nothing inside them is read on its own")
    func sleepHasOneElementPerNumeralRulerHypnogramAndTile() async throws {
        try await sleep(.latest) { w in
            for id in ["sleep.numeral", "sleep.ruler", "sleep.hypnogram", "sleep.tile.consistency", "sleep.tile.debt",
                       "sleep.tile.efficiency", "sleep.tile.restorative"] {
                #expect(w.nodes().filter { $0.identifier == id }.count == 1, "\(id) once")
                let inside = elements(in: try node(w, id).frame, of: w)
                #expect(inside == [id], "\(id) holds \(inside)")
            }
        }
    }

    @Test("A night without a timeline still has the hypnogram as one element, with the reason as its value")
    func theHypnogramWithoutATimeline() async throws {
        try await sleep(.noTimeline) { w in
            let hypnogram = try node(w, "sleep.hypnogram")
            #expect(elements(in: hypnogram.frame, of: w) == ["sleep.hypnogram"])
        }
    }
}
