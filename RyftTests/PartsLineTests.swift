import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// R2 V1 S6: a summary or subtitle line of parts joins them below AX1 and stands them one per line from AX1, so no line ends
/// on a lone "·" (History's week totals and subtitle, the session and plan subtitles, My Day's summary, Profile's sources,
/// the import's counts). VoiceOver hears the joined line at every size.
@MainActor
@Suite("R2 V1: summary lines stack their parts from AX1", .serialized)
struct PartsLineTests {
    @Test("Below AX1 the parts are joined as My Day joins them, or as the caller draws them; from AX1 one per line")
    func joinedOrStacked() {
        let parts = ["2 sessions", "12.2 t", "load 126"]
        #expect(PartsLine.text(parts, stacked: false) == MyDayText.join(parts))
        #expect(PartsLine.text(parts, stacked: false) == "2\u{00A0}sessions\u{00A0}· 12.2\u{00A0}t\u{00A0}· load\u{00A0}126")
        #expect(PartsLine.text(parts, stacked: true) == "2 sessions\n12.2 t\nload 126", "no separator, no no-break space")
        // The caller's own one-line form (the import's " · ") is what shows below AX1.
        #expect(PartsLine.text(["7 matched", "1 to check"], joined: "7 matched · 1 to check", stacked: false)
            == "7 matched · 1 to check")
        #expect(PartsLine.text(["7 matched", "1 to check"], joined: "7 matched · 1 to check", stacked: true)
            == "7 matched\n1 to check")
        // An empty part leaves no empty line; without parts the line as given shows at every size.
        #expect(PartsLine.text(["Learned", "", "updated Wed"], stacked: true) == "Learned\nupdated Wed")
        #expect(PartsLine.text([], joined: "All 12 matched. Check them if you like.", stacked: true)
            == "All 12 matched. Check them if you like.")
        #expect(PartsLine.text(["Default"], stacked: true) == "Default")
    }

    @Test("The sites keep their one-line text: the parts joined give what they drew before")
    func sitesKeepTheirLine() {
        let summary = ImportSummary(ImportMockData.bundle(ImportMockData.plans)
            .merging(ImportMockData.bundle(ImportMockData.workouts, file: 1)))
        let zone = ImportMockData.zone
        #expect(ImportSummaryText.planParts(summary)?.joined(separator: " · ") == ImportSummaryText.plans(summary))
        #expect(ImportSummaryText.workoutParts(summary, zone: zone)?.count == 2)
        #expect(ImportSummaryText.workoutParts(summary, zone: zone)?.joined(separator: " · ")
            == ImportSummaryText.workouts(summary, zone: zone, spoken: false))
        #expect(MockTrain.upperLower.summaryParts.count == 3)
        #expect(MyDayText.join(MockTrain.upperLower.summaryParts) == MockTrain.upperLower.summaryText)
    }

    /// The size `text` takes on one line at AX3 in `font`.
    private func lineSize(_ text: String, _ font: Font) -> CGSize {
        let view = Text(verbatim: text).font(font).monospacedDigit().fixedSize()
            .environment(\.dynamicTypeSize, .accessibility3)
        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
    }

    /// History's week header at AX3: under "Week of …" the totals stand one per line, so their ink is no wider than the
    /// widest total and three lines tall; joined, the first line ran "2 sessions · 12.2 t ·" and the "·" dangled.
    @Test("History at AX3: a week's totals one per line under its title, the header still one element with the totals")
    func historyWeekAtAX3() async throws {
        let library = TrainHistoryFixtures.library()
        let view = NavigationStack { TrainHistoryView().trainDestinations() }.environment(library)
        try await HostedWindow.run(width: 390, height: 2_400, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   view) { w in
            try await w.wait("a week") { w.nodes().contains { $0.label.hasPrefix("Week of ") } }
            try await w.settle()
            let header = try #require(w.nodes().first { $0.label.hasPrefix("Week of ") })
            let model = TrainHistoryViewModel(library: library, sessions: library.cachedSessions(now: Date()), fresh: true)
            let week = try #require(model.weeks.first { $0.title() == header.label })
            let parts = week.summaryParts()
            #expect(header.value == week.spokenSummary(), "VoiceOver: the title, then the totals in words")
            #expect(header.traits.contains(.header))

            let title = lineSize(header.label, .ryft(.label))
            let widest = parts.map { lineSize($0, .ryft(.caption)).width }.max() ?? 0
            let line = lineSize(parts[0], .ryft(.caption)).height
            // Under the title: the totals' ink, from the column's edge to the window's.
            let below = CGRect(x: 0, y: header.frame.minY + title.height + 1, width: 390,
                               height: header.frame.maxY - header.frame.minY - title.height - 1)
            let pixels = try WindowPixels(w, scale: 2)
            let paper = pixels.at(2, below.midY)
            let ink = try #require(pixels.box(in: below) { abs($0.r - paper.r) + abs($0.g - paper.g) + abs($0.b - paper.b) > 0.3 },
                                   "the totals under \(header.frame)")
            #expect(ink.width <= widest + 2, "one total per line: ink \(ink.width) wide, widest total \(widest) (\(parts))")
            #expect(ink.height >= 2.4 * line, "three lines: ink \(ink.height) tall, a line \(line)")
            #expect(ink.minX >= header.frame.minX - 1, "from the column's edge: \(ink) in \(header.frame)")
        }
    }

    /// Profile's "Baseline sleep need" row (`GroupedRow.detailParts`): at AX3 the detail's first line is "Learned" alone,
    /// with no "·" after it ("Learned ·" / "updated Wed" before); VoiceOver still hears "7h 40m, Learned · updated Wed".
    @Test("A row's detail parts at AX3: one per line, the row's value for VoiceOver unchanged")
    func rowDetailPartsAtAX3() async throws {
        let detail = "Learned · updated Wed"
        let row = GroupedCard {
            // A title that stays on one line at AX3, so the detail's first line is where the test looks.
            GroupedRow.push(Text(verbatim: "Baseline"), value: Text(verbatim: "7h 40m"),
                            detail: Text(verbatim: detail), identifier: "row") {}
                .detailParts(["Learned", "updated Wed"])
        }
        .padding(.horizontal, 20)
        try await HostedWindow.run(width: 390, height: 900, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   row) { w in
            try await w.settle()
            let node = try #require(w.nodes().first { $0.identifier == "row" })
            #expect(node.label == "Baseline")
            #expect(node.value == "7h 40m, \(detail)", "VoiceOver as before: \(node.value ?? "nil")")

            // The detail's first line: under the title (10 above it, 2 under it), one caption line tall.
            let title = lineSize("Baseline", .ryft(.callout))
            let line = lineSize("Learned", .ryft(.caption))
            let band = CGRect(x: node.frame.minX, y: node.frame.minY + GroupedListSpec.textPadding + title.height
                                  + GroupedListSpec.detailGap + 2,
                              width: node.frame.width - 60, height: line.height - 4)
            let pixels = try WindowPixels(w, scale: 2)
            let paper = pixels.at(node.frame.minX + 4, band.midY)
            let ink = try #require(pixels.box(in: band) { abs($0.r - paper.r) + abs($0.g - paper.g) + abs($0.b - paper.b) > 0.3 },
                                   "the detail's first line in \(band)")
            #expect(ink.width <= line.width + 2, "\"Learned\" alone: ink \(ink.width) wide, the word \(line.width) (\(ink))")
            #expect(ink.width >= line.width - 6, "the band holds the word: \(ink.width) vs \(line.width)")
        }
    }
}
