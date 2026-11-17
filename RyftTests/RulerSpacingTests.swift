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
