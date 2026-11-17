import SwiftUI
import Testing
import UIKit
@testable import Ryft

// VF1: the block under a ruler is measured from the ruler's 36 pt box, not from its labels. On the board the label row
// starts 2 under the tick row (the ruler's top + 32) and overflows the box; Today's tiles sit at the ruler's top + 58
// (36 + 22) and Sleep's hypnogram at + 56 (36 + 20). Where the labels grow (large text) the next block keeps 8 pt
// under them: `max(top + 36 + gap, labels' bottom + 8)`. Pure, drawn, and in a window.

@MainActor
struct RulerSpacingTests {
    // MARK: the rule

    @Test func theNextBlockIsMeasuredFromTheBoxUnlessTheLabelsReachIt() {
        #expect(RulerScale.Size.regular.height == 36 && RulerScale.Size.regular.labelTop == 32)
        // A default-size label row (about 15 pt): the box, so the gap starts at 36.
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 15, followingGap: TodayLayout.rulerToTiles) == 36)
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 15, followingGap: SleepLayout.hypnogramGap) == 36)
        // A card 12 under the box would touch the labels: it keeps 8 under them (32 + 15 + 8 = 55, the ruler 43).
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 15, followingGap: TodayLayout.rulerToCards) == 43)
        // AX: two wrapped lines of 29 under a 22 pt gap: 32 + 58 + 8 − 22.
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 58, followingGap: 22) == 76)
        // No labels: the box. No gap given: the ruler encloses its labels.
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 0, followingGap: 22) == 36)
        #expect(RulerScale.layoutHeight(size: .compact, labelsHeight: 0, followingGap: nil) == 32)
        #expect(RulerScale.layoutHeight(size: .regular, labelsHeight: 15, followingGap: nil) == 47)
    }

    @Test func todaysGapUnderTheRuler() {
        #expect(TodayLayout.belowRuler(hasAttentionCard: true, showsTiles: true) == TodayLayout.rulerToCards)
        #expect(TodayLayout.belowRuler(hasAttentionCard: false, showsTiles: true) == TodayLayout.rulerToTiles)
        #expect(TodayLayout.belowRuler(hasAttentionCard: false, showsTiles: false) == TodayLayout.glowToCards)
    }

    // MARK: drawn

    private static let labels = ["0", "low", "moderate", "high", "100"]

    /// Today's ruler over a red block `gap` under it, 350 wide: where the block starts, and the lowest label ink above it.
    private func drawn(_ typeSize: DynamicTypeSize, gap: CGFloat) throws -> (block: Double, labelsBottom: Double) {
        let view = VStack(spacing: 0) {
            RulerScale(range: 0...100, value: 84, zone: 67...100, tickCount: RulerScale.Ticks.today, labels: Self.labels,
                       accessibilityLabel: Text(verbatim: "Scale"), accessibilityValue: Text(verbatim: "value"),
                       reduceMotion: true, followingGap: gap)
            Color(red: 1, green: 0, blue: 0).frame(height: 20).padding(.top, gap)
        }
        .frame(width: 350)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, typeSize)
        let shot = try #require(KindShot.render(view, scale: 3))
        let ground = shot.at(1, 2)
        func isRed(_ p: NocturneTokenTests.RGBA) -> Bool { p.r > 0.9 && p.g < 0.1 && p.b < 0.1 }
        func isInk(_ p: NocturneTokenTests.RGBA) -> Bool {
            max(abs(p.r - ground.r), abs(p.g - ground.g), abs(p.b - ground.b)) > 0.08 && !isRed(p)
        }
        let block = try #require((0..<shot.height).first { isRed(shot.px(shot.width / 2, $0)) }, "the block")
        // Under the tick row's ink (it ends at 28): only the labels.
        let start = Int(30 * shot.scale)
        let inked = (start..<block).last { iy in (0..<shot.width).contains { isInk(shot.px($0, iy)) } }
        let bottom = try #require(inked, "label ink under the ticks")
        return (Double(block) / Double(shot.scale), Double(bottom + 1) / Double(shot.scale))
    }

    @Test("The labels keep 8 pt to the next block at every size",
          arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3], [CGFloat(12), 20, 22])
    func theLabelsNeverComeWithin8OfTheNextBlock(_ typeSize: DynamicTypeSize, _ gap: CGFloat) throws {
        let (block, labelsBottom) = try drawn(typeSize, gap: gap)
        #expect(block - labelsBottom >= RulerScale.labelClearance, "\(typeSize), gap \(gap): ink ends \(labelsBottom), block \(block)")
        #expect(block >= 36 + gap - 0.34, "never closer than the box plus the gap: \(block)")
        if typeSize == .large, gap >= 20 {
            #expect(abs(block - (36 + gap)) < 0.34, "at the default size the block is at the box plus the gap: \(block)")
        }
    }
}

/// The same on the screens: Today's tiles at the ruler's top + 58 (390 and 402 wide), Sleep's hypnogram at + 56.
@MainActor
@Suite(.serialized) struct RulerSpacingHostedTests {
    @Test(arguments: [CGFloat(390), 402])
    func todaysTilesAre58UnderTheRulersTop(_ width: CGFloat) async throws {
        let state = AppState.preview(flags: [.todayMyDay: true])
        try await HostedWindow.run(width: width, height: 2600,
                                   TodayView().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.wait("Today's tiles") { w.nodes().contains { $0.identifier == "today.tile.recovery" } }
            try await w.settle()
            let ruler = try #require(w.nodes().first { $0.identifier == "today.ruler" }).frame
            let tile = try #require(w.nodes().first { $0.identifier == "today.tile.recovery" }).frame
            #expect(abs(tile.minY - ruler.minY - 58) < 0.5, "tiles at the ruler's top + \(tile.minY - ruler.minY)")
            // The element's frame takes in the labels it overflows into (box 36, labels from 32): 8 or more above the tiles.
            #expect(ruler.height > 36 && tile.minY - ruler.maxY >= RulerScale.labelClearance - 0.5, "\(ruler) over \(tile)")
        }
    }

    @Test func sleepsHypnogramIs56UnderTheRulersTop() async throws {
        try await HostedWindow.run(width: 390, height: 2000, bottomInset: 0, SleepPreviewPage(.latest)) { w in
            try await w.wait("the hypnogram") { w.nodes().contains { $0.identifier == "sleep.hypnogram" } }
            try await w.settle()
            let ruler = try #require(w.nodes().first { $0.identifier == "sleep.ruler" }).frame
            let hypnogram = try #require(w.nodes().first { $0.identifier == "sleep.hypnogram" }).frame
            #expect(abs(hypnogram.minY - ruler.minY - 56) < 0.5, "the hypnogram at the ruler's top + \(hypnogram.minY - ruler.minY)")
            #expect(hypnogram.minY - ruler.maxY >= RulerScale.labelClearance - 0.5, "the labels 8 or more above: \(ruler)")
        }
    }
}

/// D: at large text the labels go on lines of whole labels ("0 · low · moderate", "high · 100"), never a joined line
/// wrapped between a label and its separator ("· high · 100").
@MainActor
@Suite(.serialized) struct RulerLabelLinesTests {
    @Test func theLinesAreTriedFewestFirstTheEarlierLinesFuller() {
        #expect(RulerScale.labelLines(count: 3) == [[0..<3], [0..<2, 2..<3], [0..<1, 1..<3], [0..<1, 1..<2, 2..<3]])
        let five = RulerScale.labelLines(count: 5)
        #expect(five.count == 16, "every way to cut 5 labels into runs")
        #expect(five.first == [0..<5] && five.last == [0..<1, 1..<2, 2..<3, 3..<4, 4..<5])
        #expect(five[1] == [0..<4, 4..<5] && five[2] == [0..<3, 3..<5], "two lines, the first the fuller first")
        for lines in five {
            #expect(lines.first?.lowerBound == 0 && lines.last?.upperBound == 5, "all of them: \(lines)")
            #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound }, "in order: \(lines)")
        }
        #expect(RulerScale.labelLines(count: 0).isEmpty)
    }

    struct LabelCase: Sendable, CustomStringConvertible {
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        var description: String { "\(typeSize)" }
    }

    /// The board's label sets: Today's readiness, Sleep's need, Strain's target.
    static let labelSets = [["0", "low", "moderate", "high", "100"], ["0 h", "need 8:18", "10 h"], ["0", "target 10–14", "21"]]

    /// One line of the labels' font at `typeSize`.
    private func lineHeight(_ typeSize: DynamicTypeSize) -> CGFloat {
        UIHostingController(rootView: Text(verbatim: "0").font(.ryft(.axis)).fixedSize().environment(\.dynamicTypeSize, typeSize))
            .sizeThatFits(in: CGSize(width: 2_000, height: 2_000)).height
    }

    @Test("Every line is whole labels: none starts or ends with a separator, none wraps",
          arguments: [CGFloat(390), 402],
          [LabelCase(typeSize: .large, category: .large),
           LabelCase(typeSize: .xxxLarge, category: .extraExtraExtraLarge),
           LabelCase(typeSize: .accessibility1, category: .accessibilityMedium),
           LabelCase(typeSize: .accessibility3, category: .accessibilityExtraLarge),
           LabelCase(typeSize: .accessibility5, category: .accessibilityExtraExtraExtraLarge)])
    func everyLineIsWholeLabels(_ width: CGFloat, _ c: LabelCase) async throws {
        let line = lineHeight(c.typeSize)
        for labels in Self.labelSets {
            let frames = TwoUpFrames()
            // The ruler's width on Today and Sleep: the window less the screen padding.
            let row = RulerLabels(labels: labels)
                .font(.ryft(.axis))
                .reportFrame("row", to: frames)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .frame(maxHeight: .infinity, alignment: .top)
            try await HostedWindow.run(width: width, height: 900, typeSize: c.typeSize, category: c.category, row) { w in
                try await w.wait("the labels") { frames.byName["row"] != nil && !w.nodes().isEmpty }
                try await w.settle()
                let box = try #require(frames.byName["row"])
                let nodes = w.nodes().sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
                let where_ = "\(labels) at \(width), \(c.typeSize): \(nodes.map { "'\($0.label)' \($0.frame)" })"
                #expect(nodes.map(\.label).joined(separator: " · ") == labels.joined(separator: " · "), "all, in order: \(where_)")
                for node in nodes {
                    let text = node.label.trimmingCharacters(in: .whitespaces)
                    #expect(!text.hasPrefix("·") && !text.hasSuffix("·"), "'\(node.label)' starts or ends with a separator: \(where_)")
                    #expect(node.frame.height < line * 1.5, "'\(node.label)' is one line (\(line)): \(where_)")
                    #expect(node.frame.maxX <= box.maxX + 0.5 && node.frame.minX >= box.minX - 0.5, "inside the row \(box): \(where_)")
                }
                if c.typeSize == .large {
                    #expect(nodes.count == labels.count && abs(nodes.last!.frame.maxX - box.maxX) < 0.5,
                            "one line, edge to edge, at the default size: \(where_)")
                }
            }
        }
    }
}
