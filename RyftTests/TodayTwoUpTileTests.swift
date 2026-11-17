import SwiftUI
import Testing
import UIKit
@testable import Ryft

// VF3 and CR4: Today's 2-up tiles. The value sits on the same baseline in every state (scored, "Yesterday",
// "calibrating"): a caption shrinks to 80 % beside it, else goes above it, and never lifts it. The tiles are 124 at the
// default size and grow to the taller tile's content at larger text, nothing clipped. The tiles are one VoiceOver element
// each, so the parts are measured on the tile's own content (`TodayTwoUpBoard` in a `GlowTile`, laid out as `TodayTiles`
// lays the pair), and the real tiles are checked to be as tall.

/// Where the hosted views report their frames (window points).
@MainActor
final class TwoUpFrames {
    var byName: [String: CGRect] = [:]
}

extension View {
    /// Reports this view's window frame as `name`.
    @MainActor
    func reportFrame(_ name: String, to frames: TwoUpFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.byName[name] = $0 }
    }
}

/// One 2-up tile's content, as `TodayTwoUpTile` shows it below AX1.
struct TwoUpCase: Sendable, CustomStringConvertible {
    let name: String
    let title: String
    let value: String
    let unit: String?
    let caption: String?
    var description: String { name }

    var words: TodayTwoUpWords { TodayTwoUpWords(title: title, value: value, unit: unit, caption: caption) }

    static let scored = TwoUpCase(name: "scored", title: "Sleep", value: "7:48", unit: "h", caption: nil)
    static let high = TwoUpCase(name: "recovery High", title: "Recovery", value: "82", unit: "%", caption: "High")
    static let yesterday = TwoUpCase(name: "pending", title: "Sleep", value: "7:10", unit: "h", caption: "Yesterday")
    static let calibrating = TwoUpCase(name: "calibrating", title: "Sleep", value: "7:11", unit: "h", caption: "calibrating")
    static let all = [scored, high, yesterday, calibrating]
}

@MainActor
enum TwoUpHost {
    /// The tile as `TodayTwoUpTile` draws it below AX1, without the button that makes it one element: Recovery's
    /// sparkline, else Sleep's dots, reported as "`name`.series"; `partner`, the other tile's words.
    static func tile(_ c: TwoUpCase, partner: TwoUpCase? = nil, frames: TwoUpFrames, name: String) -> some View {
        GlowTile(Theme.metricSleep, kind: .twoUp, reduceTransparency: true) {
            TodayTwoUpBoard(words: c.words, partner: partner?.words) {
                Group {
                    if c.title == "Recovery" {
                        Sparkline(values: [57, 56, 55, 54, 53, 52, 51])
                    } else {
                        DotRow(TodaySleepWeek(nights: Array(repeating: .enough, count: 7)).marks,
                               accessibilityLabel: Text(verbatim: "week"))
                    }
                }
                .reportFrame("\(name).series", to: frames)
            }
        }
        .reportFrame(name, to: frames)
    }

    /// Two tiles side by side in a `width` window, as `TodayTiles` lays the pair: one height, the taller tile's, each
    /// with the other's words.
    static func pair(_ a: TwoUpCase, _ b: TwoUpCase, frames: TwoUpFrames) -> some View {
        HStack(alignment: .top, spacing: TodayLayout.tileGap) {
            tile(a, partner: b, frames: frames, name: "a")
            tile(b, partner: a, frames: frames, name: "b")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
@Suite(.serialized) struct TodayTwoUpTileTests {
    // MARK: the arrangement (pure)

    @Test func theCaptionShrinksBeforeItLeavesTheValuesLine() {
        // 137 of content in a 169 tile: a 60 pt value leaves 69 beside it (8 apart).
        #expect(TodayTwoUpValueRow.arrangement(width: 137, value: 60, caption: 69) == .beside)
        // Scaled with 1 pt of slack (R2-N4): 85 × 0.8 + 1 = 69 fits, 86 × 0.8 + 1 = 69.8 doesn't.
        #expect(TodayTwoUpValueRow.arrangement(width: 137, value: 60, caption: 85) == .besideScaled, "85 × 0.8 + 1 = 69")
        #expect(TodayTwoUpValueRow.arrangement(width: 137, value: 60, caption: 86) == .above, "86 × 0.8 + 1 = 69.8")
        #expect(TodayTwoUpValueRow.minimumScale >= 0.8)
    }

    // MARK: the value's baseline (VF3)

    /// The value's frame in each state, relative to its tile, in a pair at the default size.
    private func valueFrames(width: CGFloat, typeSize: DynamicTypeSize = .large,
                             category: UIContentSizeCategory = .large) async throws -> [String: (value: CGRect, tile: CGRect)] {
        var result: [String: (CGRect, CGRect)] = [:]
        for c in TwoUpCase.all {
            let frames = TwoUpFrames()
            try await HostedWindow.run(width: width, height: 600, typeSize: typeSize, category: category,
                                       TwoUpHost.pair(c, c, frames: frames)) { w in
                try await w.wait("the tiles") { frames.byName["a"] != nil && w.node(c.value) != nil }
                try await w.settle()
                let tile = try #require(frames.byName["a"])
                let value = try #require(w.nodes().first { $0.label == c.value && tile.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) })
                result[c.name] = (value.frame.offsetBy(dx: -tile.minX, dy: -tile.minY), tile)
            }
        }
        return result
    }

    @Test("The value sits on one baseline in every state, the tile 124", arguments: [CGFloat(390), 402])
    func theValueNeverMoves(_ width: CGFloat) async throws {
        let frames = try await valueFrames(width: width)
        let scored = try #require(frames["scored"])
        for (name, f) in frames {
            #expect(abs(f.tile.height - TodayLayout.twoUpHeight) < 0.5, "\(name): the tile \(f.tile)")
            #expect(abs(f.value.maxY - scored.value.maxY) < 0.5, "\(name): the value's line ends at \(f.value.maxY), scored \(scored.value.maxY)")
            // On the bottom padding: 12 above the tile's bottom.
            #expect(abs(f.tile.height - f.value.maxY - 12) < 0.5, "\(name): \(f.value) in \(f.tile)")
        }
    }

    // MARK: the value's baseline (R2-N4)

    /// The value sits by its baseline at the row's bottom less the line's deeper descent: a caption that hangs deeper
    /// than the value (here a 40 pt "g" beside a 12 pt "7") stays inside the row, on the value's baseline.
    @Test func aDeeperCaptionStaysInsideTheRow() async throws {
        let frames = TwoUpFrames()
        let row = TodayTwoUpValueRow {
            Text(verbatim: "7").font(.system(size: 12))
            Text(verbatim: "gy").font(.system(size: 40))
        }
        .frame(width: 200)
        .reportFrame("row", to: frames)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        try await HostedWindow.run(width: 390, height: 400, row) { w in
            try await w.wait("the row") { frames.byName["row"] != nil && w.node("gy", exactly: true) != nil }
            try await w.settle()
            let bounds = try #require(frames.byName["row"])
            let caption = try #require(w.node("gy", exactly: true)).frame
            let value = try #require(w.node("7", exactly: true)).frame
            #expect(caption.maxY <= bounds.maxY + 0.5, "the caption \(caption) hangs out of the row \(bounds)")
            #expect(value.maxY < bounds.maxY - 3, "the value's baseline is lifted by the caption's descent: \(value) in \(bounds)")
        }
    }

    // MARK: no caption cut (R2-N4)

    /// A label's or caption's one-line width at `typeSize`, as the tile styles it.
    private func idealWidth(_ caption: String, typeSize: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(rootView: Text(verbatim: caption).ryftGlowLabelStyle().fixedSize()
            .environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: 2_000, height: 2_000)).width
    }

    /// A cut caption ("calibrat…") keeps its whole string as its VoiceOver label, so the label can't show the cut; its
    /// frame can: shrunk at most to 0.8, a caption is never narrower than 0.8 of its one-line width.
    @Test("No caption is cut", arguments: [(CGFloat(390), DynamicTypeSize.large), (402, .large), (390, .xxxLarge)])
    func noCaptionIsCut(_ c: (width: CGFloat, typeSize: DynamicTypeSize)) async throws {
        let category: UIContentSizeCategory = c.typeSize == .large ? .large : .extraExtraExtraLarge
        for tile in TwoUpCase.all + [TwoUpCase(name: "earlier day", title: "Sleep", value: "7:10", unit: "h", caption: "Sat, Nov 14")] {
            guard let caption = tile.caption else { continue }
            let frames = TwoUpFrames()
            try await HostedWindow.run(width: c.width, height: 600, typeSize: c.typeSize, category: category,
                                       TwoUpHost.pair(tile, tile, frames: frames)) { w in
                try await w.wait("the tiles") { frames.byName["a"] != nil && w.node(caption, exactly: true) != nil }
                try await w.settle()
                let a = try #require(frames.byName["a"])
                let node = try #require(w.nodes().first {
                    $0.label == caption && a.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                })
                let ideal = idealWidth(caption, typeSize: c.typeSize)
                #expect(node.frame.width >= ideal * TodayTwoUpValueRow.minimumScale - 0.5,
                        "\(tile) at \(c.width), \(c.typeSize): '\(caption)' \(node.frame.width) wide, one line \(ideal)")
            }
        }
    }

    // MARK: the label is never cut (B)

    struct SizeCase: Sendable, CustomStringConvertible {
        let width: CGFloat
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        var description: String { "\(width), \(typeSize)" }

        static let all = [CGFloat(375), 390, 402].flatMap { width in
            [SizeCase(width: width, typeSize: .large, category: .large),
             SizeCase(width: width, typeSize: .xLarge, category: .extraLarge),
             SizeCase(width: width, typeSize: .xxLarge, category: .extraExtraLarge),
             SizeCase(width: width, typeSize: .xxxLarge, category: .extraExtraExtraLarge)]
        }
    }

    /// Recovery's label ("Recov…" at xxxLarge, its sparkline beside it) is whole at every size below AX1: the series
    /// goes under the label when the label needs the room, in both tiles alike, never over it.
    @Test("The label is whole and the series clear of it, alike in both tiles", arguments: SizeCase.all)
    func theLabelIsNeverCut(_ c: SizeCase) async throws {
        let recovery = TwoUpCase(name: "recovery", title: "Recovery", value: "82", unit: "%", caption: "High")
        let sleep = TwoUpCase.scored
        let frames = TwoUpFrames()
        try await HostedWindow.run(width: c.width, height: 600, typeSize: c.typeSize, category: c.category,
                                   TwoUpHost.pair(recovery, sleep, frames: frames)) { w in
            try await w.wait("the tiles") { frames.byName["a.series"] != nil && w.node("Recovery", exactly: true) != nil }
            try await w.settle()
            var under: [Bool] = []
            for (tile, name) in [(recovery, "a"), (sleep, "b")] {
                let box = try #require(frames.byName[name])
                let series = try #require(frames.byName["\(name).series"])
                let title = try #require(w.nodes().first {
                    $0.label == tile.title && box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                }).frame
                let ideal = idealWidth(tile.title, typeSize: c.typeSize)
                #expect(title.width >= ideal - 0.5, "\(c): '\(tile.title)' \(title.width) wide, one line \(ideal)")
                #expect(series.minX >= title.maxX - 0.5 || series.minY >= title.maxY - 0.5,
                        "\(c): the series \(series) clear of '\(tile.title)' \(title)")
                #expect(series.maxX <= box.maxX - 16 + 0.5 && series.minX >= box.minX + 16 - 0.5, "\(c): inside \(box): \(series)")
                under.append(series.minY >= title.maxY - 0.5)
            }
            #expect(Set(under).count == 1, "\(c): the series beside or under the label in both tiles: \(under)")
            if c.width == 390, c.typeSize == .large { #expect(under == [false, false], "beside at the default size") }
            if c.width == 390, c.typeSize == .xxxLarge { #expect(under == [true, true], "Recovery needs the room at xxxLarge") }
        }
    }

    // MARK: the pair's captions alike (C)

    struct PairCase: Sendable, CustomStringConvertible {
        let name: String
        let recovery: Int?
        let caption: String
        let width: CGFloat
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        var description: String { "\(name) at \(width), \(typeSize)" }

        /// Both tiles with `caption`; without a recovery, Recovery's "–" beside Sleep's "7:11 h".
        @MainActor var content: TodayTilesContent {
            TodayTilesContent(recovery: recovery, recoveryCaption: caption, hrvWeek: [57, 56, 55, 54, 53, 52, 51],
                              sleepMinutes: recovery == nil ? 431 : 430, caption: caption,
                              sleepWeek: TodaySleepWeek(nights: Array(repeating: .enough, count: 7)), strain: 9,
                              isEarlierDay: false)
        }

        private static let large = (DynamicTypeSize.large, UIContentSizeCategory.large)
        private static let xxxLarge = (DynamicTypeSize.xxxLarge, UIContentSizeCategory.extraExtraExtraLarge)

        private init(_ name: String, _ recovery: Int?, _ caption: String, _ width: CGFloat,
                     _ size: (DynamicTypeSize, UIContentSizeCategory)) {
            self.name = name
            self.recovery = recovery
            self.caption = caption
            self.width = width
            typeSize = size.0
            category = size.1
        }

        static let all = [
            // The validator's: "calibrating" beside Recovery's "–", above Sleep's "7:11 h".
            PairCase("calibrating", nil, "calibrating", 390, large),
            PairCase("calibrating", nil, "calibrating", 402, large),
            PairCase("calibrating", nil, "calibrating", 390, xxxLarge),
            // And "Yesterday" at xxxLarge: beside "75 %", above "7:10 h".
            PairCase("yesterday", 75, "Yesterday", 390, xxxLarge),
            PairCase("an earlier day", 75, "Sat, Nov 14", 390, large),
            PairCase("an earlier day", 75, "Sat, Nov 14", 390, xxxLarge),
        ]
    }

    /// Where a tile's caption sits: above the value (its line ends over the value's top), or beside it.
    private enum Placement { case beside, above }

    /// When one tile's caption goes above its value, the other's does too: the pair reads alike.
    @Test("The pair's captions sit alike, above in both when either needs it", arguments: PairCase.all)
    func thePairsCaptionsSitAlike(_ c: PairCase) async throws {
        let pair = cases(c.content)
        let frames = TwoUpFrames()
        try await HostedWindow.run(width: c.width, height: 700, typeSize: c.typeSize, category: c.category,
                                   TwoUpHost.pair(pair.0, pair.1, frames: frames)) { w in
            try await w.wait("the tiles") { frames.byName["a"] != nil && frames.byName["b"] != nil }
            try await w.settle()
            var placements: [Placement] = []
            for (tile, name) in [(pair.0, "a"), (pair.1, "b")] {
                let box = try #require(frames.byName[name])
                let inside = w.nodes().filter { box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                let value = try #require(inside.first { $0.label == tile.value }, "\(c): \(inside.map(\.label))").frame
                let caption = try #require(inside.first { $0.label == tile.caption }, "\(c): \(inside.map(\.label))").frame
                if caption.maxY <= value.minY + 0.5 {
                    placements.append(.above)
                } else {
                    #expect(caption.minX >= value.maxX, "\(c): '\(tile.caption ?? "")' \(caption) beside the value \(value)")
                    placements.append(.beside)
                }
            }
            #expect(placements[0] == placements[1], "\(c): Recovery's caption \(placements[0]), Sleep's \(placements[1])")
        }
    }

    // MARK: nothing clipped at larger text (CR4)

    /// The pair `TodayTiles` shows for `content`, as cases: Recovery, then Sleep.
    private func cases(_ content: TodayTilesContent) -> (TwoUpCase, TwoUpCase) {
        (TwoUpCase(name: "recovery", title: "Recovery", value: content.recoveryText, unit: content.recovery == nil ? nil : "%",
                   caption: content.recoveryCaption),
         TwoUpCase(name: "sleep", title: "Sleep", value: content.sleepText, unit: content.sleepMinutes == nil ? nil : "h",
                   caption: content.caption))
    }

    @Test("At xxxLarge nothing in the pair passes the bottom padding, and the real pair is as tall",
          // The captions there are, an earlier day's, and one long enough to wrap above the value: the pair grows.
          arguments: ["calibrating", "Yesterday", "High", "Sat, Nov 14", "Recalculating your baselines"])
    func atXXXLargeNothingIsClipped(_ caption: String) async throws {
        let content = TodayTilesContent(recovery: 75, recoveryCaption: caption, hrvWeek: [57, 56, 55, 54, 53, 52, 51],
                                        sleepMinutes: 431, caption: caption == "High" ? nil : caption,
                                        sleepWeek: TodaySleepWeek(nights: Array(repeating: .enough, count: 7)), strain: 9,
                                        isEarlierDay: false)
        let pair = cases(content)
        let frames = TwoUpFrames()
        var height: CGFloat = 0
        try await HostedWindow.run(width: 390, height: 800, typeSize: .xxxLarge, category: .extraExtraExtraLarge,
                                   TwoUpHost.pair(pair.0, pair.1, frames: frames)) { w in
            try await w.wait("the tiles") { frames.byName["a"] != nil && frames.byName["b"] != nil }
            try await w.settle()
            let a = try #require(frames.byName["a"]), b = try #require(frames.byName["b"])
            #expect(abs(a.height - b.height) < 0.5 && a.height >= TodayLayout.twoUpHeight - 0.5, "one height: \(a) \(b)")
            height = a.height
            for tile in [a, b] {
                let inside = w.nodes().filter { tile.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                #expect(inside.count >= 3, "label, value, unit at least: \(inside.map(\.label))")
                for node in inside {
                    #expect(node.frame.maxY <= tile.maxY - 12 + 0.5, "'\(node.label)' \(node.frame) past the bottom padding of \(tile)")
                    #expect(node.frame.minY >= tile.minY + 14 - 0.5, "'\(node.label)' \(node.frame) above the top padding of \(tile)")
                    #expect(node.frame.maxX <= tile.maxX - 16 + 0.5, "'\(node.label)' \(node.frame) past the side of \(tile)")
                }
            }
        }
        // The real tiles (one element each) are as tall as their content asks.
        try await HostedWindow.run(width: 390, height: 800, typeSize: .xxxLarge, category: .extraExtraExtraLarge,
                                   TodayTiles(content: content) { _ in }
                                       .padding(.horizontal, Theme.Metrics.screenPadding)
                                       .frame(maxHeight: .infinity, alignment: .top)) { w in
            try await w.settle()
            let recovery = try #require(w.nodes().first { $0.identifier == "today.tile.recovery" }).frame
            let sleep = try #require(w.nodes().first { $0.identifier == "today.tile.sleep" }).frame
            #expect(abs(recovery.height - sleep.height) < 0.5, "one height: \(recovery) \(sleep)")
            #expect(abs(sleep.height - height) < 0.5, "the real pair (\(sleep.height)) is as tall as its content asks (\(height))")
        }
    }
}
