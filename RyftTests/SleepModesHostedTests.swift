import SwiftUI
import Testing
import UIKit
@testable import Ryft

// Sleep → Week, Month and Bedtime in a window (docs/work/2026-11-16-nocturne/design.md §P5-7, §P5-12 tests 34 and 36, their
// hosted half): Day's numeral 12 higher than PR 4's, the modes' reading order and gaps, the go-to-bed tile as one element,
// the settings card's rows, and AX3. With `T55_SHOTS_DIR` set it also writes every state at 3x, paged.

@MainActor
@Suite(.serialized) struct SleepModesHostedTests {
    nonisolated private static let width: CGFloat = 390

    /// The accessibility sizes the AX tests run at: AX3, and AX5, where the validator's "AX3" shots were taken (its "vs 7 d"
    /// is 103 × 48, as here at AX5; at AX3 it is 79 × 36).
    enum Large: CaseIterable, Sendable {
        case ax3, ax5

        var typeSize: DynamicTypeSize { self == .ax3 ? .accessibility3 : .accessibility5 }
        var category: UIContentSizeCategory { self == .ax3 ? .accessibilityExtraLarge : .accessibilityExtraExtraExtraLarge }
    }

    private func host<Content: View>(_ view: Content, ready: String, height: CGFloat = 2400, ax3: Bool = false,
                                     large: Large? = nil, body: (HostedWindow) async throws -> Void) async throws {
        let large = large ?? (ax3 ? .ax3 : nil)
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: 0,
                                   typeSize: large?.typeSize ?? .large,
                                   category: large?.category ?? .large, view) { w in
            try await w.wait(ready) { w.nodes().contains { $0.identifier == ready || $0.label == ready } }
            try await w.settle()
            try await body(w)
        }
    }

    private func frame(_ w: HostedWindow, _ identifier: String) throws -> CGRect {
        try #require(w.nodes().first { $0.identifier == identifier }, "\(identifier) on screen").frame
    }

    /// "Sleep" in the header (its night buttons are hidden outside Day).
    private func title(_ w: HostedWindow) throws -> CGRect {
        try #require(w.nodes().first { $0.label == "Sleep" && $0.traits.contains(.header) }, "Sleep's title").frame
    }

    /// Day's numeral under the title: the place every mode's numeral takes.
    private func daysNumeralOffset() async throws -> CGFloat {
        var offset: CGFloat = .nan
        try await host(SleepPreviewPage(.latest), ready: "sleep.tile.restorative") { w in
            offset = try frame(w, "sleep.numeral").minY - title(w).minY
        }
        return offset
    }

    /// The nights list's rows, newest first.
    private func nightRows(_ w: HostedWindow) -> [HostedWindow.Node] {
        var rows: [HostedWindow.Node] = []
        for node in w.nodes() where node.identifier?.hasPrefix("sleep.night.") == true { rows.append(node) }
        return rows
    }

    // MARK: 34. Day moves up 12 pt

    /// PR 4 measured the numeral 128 under the Previous night button's top (`hosted-latest-default.png.frames.txt`: 173 − 45)
    /// with the 52 pt picker; the 40 pt one lifts it by 12.
    @Test func daysNumeralIs12Higher() async throws {
        try await host(SleepPreviewPage(.latest), ready: "sleep.tile.restorative") { w in
            let previous = try frame(w, "sleep.header.previous"), numeral = try frame(w, "sleep.numeral")
            #expect(abs(numeral.minY - previous.minY - (128 - 12)) < 0.5, "button→numeral \(numeral.minY - previous.minY)")
        }
    }

    // MARK: 34. Week and Month

    @Test("Week reads the picker, the numeral, the change, the bed and wake times, the tiles, the stages, the nights")
    func weekReadingOrder() async throws {
        try await host(SleepRangePreviewPage(.week), ready: "sleep.range.stages") { w in
            let nodes = w.nodes()
            let ids = nodes.map { $0.identifier ?? "" }
            let week = nodes.firstIndex { $0.label == "Week" && $0.isSelected } ?? -1
            let header = nodes.firstIndex { $0.label == "Time asleep per night" && $0.traits.contains(.header) } ?? -1
            let firstNight = ids.firstIndex { $0.hasPrefix("sleep.night.") } ?? -1
            let order = [week]
                + ["sleep.range.numeral", "sleep.range.delta", "sleep.range.bedtimes", "sleep.tile.quality",
                   "sleep.tile.consistency"].map { ids.firstIndex(of: $0) ?? -1 }
                + [header, firstNight]
            #expect(!order.contains(-1) && order == order.sorted(), "\(order) in \(nodes.map { $0.identifier ?? $0.label })")
            let numeral = try #require(nodes.first { $0.identifier == "sleep.range.numeral" })
            #expect(numeral.label.hasPrefix("Average sleep, "), "\(numeral.label)")
            let bedtimes = try #require(nodes.first { $0.identifier == "sleep.range.bedtimes" })
            #expect(bedtimes.label == "Bed and wake times" && (bedtimes.value ?? "").contains("nights. Mean bedtime"))
        }
    }

    @Test func weeksGaps() async throws {
        let day = try await daysNumeralOffset()
        try await host(SleepRangePreviewPage(.week), ready: "sleep.range.stages") { w in
            let numeral = try frame(w, "sleep.range.numeral"), offset = try numeral.minY - title(w).minY
            // The same place as Day's numeral.
            #expect(abs(offset - day) < 0.5, "title→numeral \(offset) vs Day's \(day)")
            let tile = try frame(w, "sleep.range.bedtimes"), quality = try frame(w, "sleep.tile.quality")
            let consistency = try frame(w, "sleep.tile.consistency"), stages = try frame(w, "sleep.range.stages")
            #expect(tile.height >= SleepModesLayout.bedWakeMinHeight && abs(tile.width - 350) < 0.5, "tile \(tile)")
            #expect(abs(quality.minY - tile.maxY - SleepModesLayout.tilesGap) < 1, "tile→tiles \(quality.minY - tile.maxY)")
            #expect(abs(quality.minY - consistency.minY) < 0.5 && abs(quality.height - SleepLayout.tileHeight) < 0.5)
            // The card's head is 14 under its top.
            let card = stages.minY - SleepModesLayout.stageCardPadding.top
            #expect(abs(card - quality.maxY - SleepModesLayout.cardGap) < 1.5, "tiles→stages \(card - quality.maxY)")
            let rows = nightRows(w)
            #expect(rows.count == MockData.sleepRange(.week).days.count)
            // 46 apart: one row each (the element's frame is its text's, so the pitch is measured).
            let pitches = zip(rows, rows.dropFirst()).map { $1.frame.midY - $0.frame.midY }
            #expect(pitches.allSatisfy { abs($0 - SleepModesLayout.nightRowHeight) < 0.5 }, "\(pitches)")
        }
    }

    @Test func weekAtAX3StacksTheTilesAndTheMenu() async throws {
        try await host(SleepRangePreviewPage(.week), ready: "sleep.range.stages", height: 4000, ax3: true) { w in
            #expect(w.nodes().contains { $0.identifier == "sleep.mode" }, "the picker is a menu")
            let quality = try frame(w, "sleep.tile.quality"), consistency = try frame(w, "sleep.tile.consistency")
            #expect(abs(quality.minX - consistency.minX) < 0.5 && consistency.minY > quality.maxY, "one column")
            for row in nightRows(w) {
                #expect(row.frame.width <= Self.width - 40 + 0.5, "\(row.identifier ?? "") \(row.frame)")
            }
            // The delta takes three lines (the night, the change, "vs 7 d"), the strip's tile 20 under it (a squeezed
            // "vs 7 d" once stood a letter per line).
            let delta = try frame(w, "sleep.range.delta"), tile = try frame(w, "sleep.range.bedtimes")
            #expect(delta.height < 180, "delta \(delta)")
            #expect(abs(tile.minY - delta.maxY - SleepModesLayout.tileGap) < 1, "delta→tile \(tile.minY - delta.maxY)")
        }
    }

    /// T5.8 S1: at AX5 "Last night ▼ −12m · −2 % vs 7 d" was the night over a change and "vs 7 d" 390 wide, which widened
    /// the column to about 394, so the picker and the tiles started 4 from the edge. From AX1 the change and "vs 7 d" go on
    /// their own lines.
    @Test("AX3 and AX5: Week and Month keep the 20 pt margins: the picker 20 in and the screen less 40 wide, nothing wider",
          arguments: [SleepRangePreviewPage.Scene.week, .month], Large.allCases)
    func rangeKeepsItsMarginsAtAX3(_ scene: SleepRangePreviewPage.Scene, _ large: Large) async throws {
        try await host(SleepRangePreviewPage(scene), ready: "sleep.range.stages", height: 8000, large: large) { w in
            let column = Self.width - 2 * Theme.Metrics.screenPadding
            let mode = try frame(w, "sleep.mode")
            #expect(abs(mode.minX - Theme.Metrics.screenPadding) < 0.5 && abs(mode.width - column) < 0.5, "sleep.mode \(mode)")
            let delta = try frame(w, "sleep.range.delta")
            #expect(delta.width <= column + 0.5, "sleep.range.delta \(delta)")
            for node in w.nodes() {
                #expect(node.frame.width <= column + 0.5 && node.frame.minX >= Theme.Metrics.screenPadding - 0.5,
                        "\(node.identifier ?? node.label) \(node.frame)")
            }
        }
    }

    /// T5.8 S1: from AX1 the range head is three centred lines: the night, the change, "vs 7 d". Before, the fallback put
    /// "vs 7 d" beside the change, squeezed into what the change left and broken over two lines at the right. Read from
    /// the pixels: the delta is one element.
    @Test("AX5: the range head is three centred lines, the night, the change and \"vs 7 d\"")
    func rangeHeadStacksAtAX5() async throws {
        try await host(SleepRangePreviewPage(.week), ready: "sleep.range.stages", height: 2400, large: .ax5) { w in
            let delta = try frame(w, "sleep.range.delta")
            let shot = try WindowPixels(w, scale: 2)
            let ground = shot.at(delta.minX + 1, delta.minY + 1)
            // The bands of pixel rows with ink in the delta's frame: its lines.
            var bands: [CGRect] = []
            var y = delta.minY
            while y < delta.maxY {
                if let ink = shot.box(in: CGRect(x: delta.minX, y: y, width: delta.width, height: 0.5),
                                      where: { !$0.near(ground, 24) }) {
                    if let last = bands.last, ink.minY - last.maxY < 1 { bands[bands.count - 1] = last.union(ink) } else { bands.append(ink) }
                }
                y += 0.5
            }
            #expect(bands.count == 3, "lines \(bands)")
            for band in bands {
                #expect(abs(band.midX - delta.midX) < 3, "line \(band) in \(delta)")
            }
        }
    }

    @Test func monthShowsEveryNight() async throws {
        try await host(SleepRangePreviewPage(.month), ready: "sleep.range.stages", height: 3200) { w in
            #expect(nightRows(w).count == MockData.sleepRange(.month).days.count)
        }
    }

    @Test("Offline: the cached week as it is and \"As of\" its day under the nights, no refresh card")
    func offlineSaysAsOf() async throws {
        try await host(SleepRangePreviewPage(.offline), ready: "sleep.range.asOf", height: 3000) { w in
            let note = try #require(w.nodes().first { $0.identifier == "sleep.range.asOf" })
            #expect(note.label.hasPrefix("As of "), "\(note.label)")
            let last = try #require(nightRows(w).last)
            #expect(note.frame.minY >= last.frame.maxY, "under the nights")
            #expect(!w.nodes().contains { ($0.identifier ?? "").hasPrefix("refreshIssue") || $0.identifier == "today.refreshIssue" },
                    "no refresh card: reads aren't failing offline")
        }
    }

    @Test("Read two days ago: the change names its night, not \"Last night\"")
    func anOlderWeekNamesItsNight() async throws {
        try await host(SleepRangePreviewPage(.older), ready: "sleep.range.delta", height: 3000) { w in
            let delta = try #require(w.nodes().first { $0.identifier == "sleep.range.delta" })
            #expect(!delta.label.contains("Last night") && delta.label.contains("day"), "\(delta.label)")
            #expect(w.nodes().contains { $0.identifier == "sleep.range.asOf" })
        }
    }

    @Test func emptyAndFailedSayWhy() async throws {
        try await host(SleepRangePreviewPage(.empty), ready: "No sleep data for this range yet.") { w in
            #expect(!w.nodes().contains { $0.identifier == "sleep.range.numeral" }, "the message says it")
        }
        try await host(SleepRangePreviewPage(.failed), ready: "sleep.range.failure.retry") { w in
            #expect(w.nodes().contains { $0.identifier == "sleep.range.failure.retry" }, "Try again")
            #expect(w.node("Details") != nil)
        }
    }

    // MARK: 36. Bedtime

    @Test("Bedtime: the numeral says the bedtime, the tile is one element with your goal, the settings card's three rows")
    func bedtime() async throws {
        let day = try await daysNumeralOffset()
        try await host(SleepBedtimePreviewPage(.perform), ready: "sleep.bedtime.goToBed") { w in
            let numeral = try #require(w.nodes().first { $0.identifier == "sleep.bedtime.numeral" })
            #expect(numeral.label.hasPrefix("Go to bed at "), "\(numeral.label)")
            let tile = try #require(w.nodes().first { $0.identifier == "sleep.bedtime.goToBed" })
            #expect(tile.label == "Go to bed" && (tile.value ?? "").contains("85\u{00A0}percent of your need, ")
                    && (tile.value ?? "").contains("your goal"), "\(tile.value ?? "")")
            #expect(w.nodes().filter { ($0.value ?? "").contains("your goal") }.count == 1)
            #expect(w.node("Planned sleep") != nil, "the ruler")
            for id in ["sleep.tile.need", "sleep.tile.timeInBed", "sleep.bedtime.why", "sleep.bedtime.schedule"] {
                #expect(w.nodes().contains { $0.identifier == id }, "\(id)")
            }
            let offset = try numeral.frame.minY - title(w).minY
            #expect(abs(offset - day) < 0.5, "title→numeral \(offset) vs Day's \(day)")
            let ruler = try frame(w, "sleep.bedtime.ruler"), goToBed = try frame(w, "sleep.bedtime.goToBed")
            #expect(abs(goToBed.minY - ruler.minY - RulerScale.Size.regular.height - SleepModesLayout.goToBedGap) < 1,
                    "ruler→tile \(goToBed.minY - ruler.minY)")
            #expect(goToBed.height >= SleepModesLayout.goToBedMinHeight)
        }
    }

    @Test func whyThisNeedOpensTheTerms() async throws {
        try await host(SleepBedtimePreviewPage(.planned), ready: "sleep.bedtime.why") { w in
            #expect(w.node("Tonight's need") == nil)
            let why = try #require(w.nodes().first { $0.identifier == "sleep.bedtime.why" })
            #expect(why.value == "Collapsed")
            #expect(why.activate())
            try await w.wait("the need's terms") { w.node("Tonight's need") != nil }
            #expect(w.nodes().first { $0.identifier == "sleep.bedtime.why" }?.value == "Expanded")
        }
    }

    @Test("No schedule: the invitation over the three bedtimes and the settings card; no ruler, no tiles, no goal")
    func noScheduleInvitesToSetUp() async throws {
        try await host(SleepBedtimePreviewPage(.noSchedule), ready: "sleep.bedtime.setUp") { w in
            let ids = w.nodes().compactMap(\.identifier)
            for id in ["sleep.bedtime.ruler", "sleep.tile.need", "sleep.tile.timeInBed", "sleep.bedtime.numeral"] {
                #expect(!ids.contains(id), "\(id)")
            }
            let setUp = try frame(w, "sleep.bedtime.setUp"), tile = try frame(w, "sleep.bedtime.goToBed")
            #expect(setUp.maxY < tile.minY, "the invitation above the bedtimes")
            let goToBed = try #require(w.nodes().first { $0.identifier == "sleep.bedtime.goToBed" })
            #expect(!(goToBed.value ?? "").contains("your goal") && (goToBed.value ?? "").contains("100\u{00A0}percent of your need"))
            for id in ["sleep.bedtime.why", "sleep.bedtime.schedule"] {
                #expect(ids.contains(id), "\(id)")
            }
            // The compact picker shows no identifier in the tree: its row's label.
            let wake = try #require(w.node("Wake up at"), "Wake up at")
            #expect(wake.frame.minY > tile.maxY, "the settings card under them")
        }
    }

    @Test func failedAndAlarmProblem() async throws {
        try await host(SleepBedtimePreviewPage(.failed), ready: "sleep.bedtime.failure.retry") { w in
            #expect(!w.nodes().contains { $0.identifier == "sleep.bedtime.goToBed" })
            #expect(w.node("Details") != nil, "the request ID behind Details")
            #expect(!w.nodes().contains { $0.label.contains("HTTP 503") }, "until Details opens")
        }
        try await host(SleepBedtimePreviewPage(.alarmProblem), ready: "sleep.bedtime.schedule") { w in
            let schedule = try frame(w, "sleep.bedtime.schedule")
            let alarm = try #require(w.nodes().first { $0.label.hasPrefix("The wake-up alarm is off") })
            #expect(alarm.frame.minY > schedule.maxY, "under the settings card")
        }
    }

    @Test func bedtimeAtAX3() async throws {
        try await host(SleepBedtimePreviewPage(.planned), ready: "sleep.bedtime.goToBed", height: 4000, ax3: true) { w in
            let need = try frame(w, "sleep.tile.need"), inBed = try frame(w, "sleep.tile.timeInBed")
            #expect(abs(need.minX - inBed.minX) < 0.5 && inBed.minY > need.maxY, "one column")
            let tile = try frame(w, "sleep.bedtime.goToBed")
            #expect(tile.width <= Self.width - 40 + 0.5 && tile.height > SleepModesLayout.goToBedMinHeight)
        }
    }

    // MARK: shots

    /// Every state at 402 wide (iPhone 17 Pro), 3x, paged, at the default size and AX3, into `T55_SHOTS_DIR`: Week and Month
    /// here, Bedtime in `writeBedtimeShots` (each within the time limit).
    @Test func writeShots() async throws {
        try await writeShots(SleepRangePreviewPage.Scene.allCases.map {
            let ready = switch $0 {
            case .empty: "No sleep data for this range yet."
            case .failed: "sleep.range.failure.retry"
            default: "sleep.range.numeral"
            }
            return ("range-\($0.rawValue)", AnyView(SleepRangePreviewPage($0)), ready)
        })
    }

    @Test func writeBedtimeShots() async throws {
        try await writeShots(SleepBedtimePreviewPage.Scene.allCases.map {
            ("bedtime-\($0.rawValue)", AnyView(SleepBedtimePreviewPage($0)), $0 == .noSchedule ? "sleep.bedtime.setUp" : "sleep.tile.need")
        })
    }

    private func writeShots(_ pages: [(name: String, view: AnyView, ready: String)]) async throws {
        guard let dir = ProcessInfo.processInfo.environment["T55_SHOTS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for page in pages {
            for ax3 in [false, true] {
                let ready = page.ready
                try await HostedWindow.run(width: 402, height: 874, bottomInset: 0,
                                           typeSize: ax3 ? .accessibility3 : .large,
                                           category: ax3 ? .accessibilityExtraLarge : .large, page.view) { w in
                    try await w.wait(ready) { w.nodes().contains { $0.identifier == ready || $0.label == ready } }
                    try await w.settle()
                    let image = try await PagedWindowShot.image(w)
                    let name = "\(page.name)-\(ax3 ? "ax3" : "default").png"
                    try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
                }
            }
        }
    }
}
