import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Gate part 2, round 3: the part 2 UI validation found Sleep's stage rows breaking their names and numbers at AX5
/// ("20" / "%", "Awak" / "e", "1h" / "35m"). From AX1 a row stacks: the name on its line, the duration and share under it.
@MainActor
@Suite("Gate part 2 round 3: the stage rows at AX5", .serialized)
struct StageRowAXHostedTests {
    private typealias Tokens = NocturneTokenTests
    private static let width: CGFloat = 402
    /// The card's text column: the screen's padding and the card's.
    private static let column = (Theme.Metrics.screenPadding + CardSpec.padding)...(width - Theme.Metrics.screenPadding - CardSpec.padding)

    /// Sleep's stage card (`SleepView`): the rows in a `Card`, 14 apart, at the screen's padding.
    private func card(_ shares: [StageShare]) -> some View {
        Card {
            VStack(spacing: 14) {
                ForEach(shares) { StageRow(share: $0) }
            }
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    /// `text` alone, in the row's font at AX5, on `surface`, drawn at `scale`: its ink's pixel count and box.
    private func alone(_ text: String, ink: Color, digits: Bool, scale: CGFloat) throws -> (pixels: Int, size: CGSize) {
        let plain = Text(verbatim: text).font(.ryft(.callout))
        let view = (digits ? plain.monospacedDigit() : plain).foregroundStyle(ink).fixedSize()
            .padding(8).background(Theme.surface).environment(\.dynamicTypeSize, .accessibility5)
        let render = try #require(ControlRender(view, scale: scale), "\(text) drawn alone")
        let target = Tokens.over(Tokens.resolve(ink), Tokens.resolve(Theme.surface))
        var (n, minX, minY, maxX, maxY) = (0, Int.max, Int.max, Int.min, Int.min)
        for iy in 0..<render.height {
            for ix in 0..<render.width where render.px(ix, iy).near(target, 6) {
                n += 1
                minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
            }
        }
        #expect(n > 100, "\(text) alone drew \(n) pixels")
        return (n, CGSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale))
    }

    /// The lines of ink in `rect`: runs of pixel rows that hold a pixel `match` takes, in points.
    private func lines(_ px: WindowPixels, in rect: CGRect, match: (Tokens.RGBA) -> Bool) -> [CGRect] {
        var found: [CGRect] = []
        var start: Int?
        let rows = Int(rect.minY * px.scale)..<Int(rect.maxY * px.scale)
        for iy in rows {
            let strip = CGRect(x: rect.minX, y: (CGFloat(iy) + 0.5) / px.scale, width: rect.width, height: 1 / px.scale)
            let inked = px.count(in: strip, where: match) > 0
            if inked, start == nil { start = iy }
            if !inked || iy == rows.upperBound - 1, let first = start {
                let last = inked ? iy : iy - 1
                found.append(CGRect(x: rect.minX, y: CGFloat(first) / px.scale, width: rect.width,
                                    height: CGFloat(last - first + 1) / px.scale))
                start = nil
            }
        }
        return found
    }

    /// The ink box `drawn` is `whole`'s: as many pixels and the same box, so not cut, shrunk or broken across lines.
    private func expectWhole(_ drawn: CGRect?, pixels: Int, _ whole: (pixels: Int, size: CGSize), _ what: String) {
        guard let drawn else {
            Issue.record("\(what): not drawn")
            return
        }
        #expect(abs(drawn.width - whole.size.width) < 1.5 && abs(drawn.height - whole.size.height) < 1.5,
                "\(what) on one line, whole: \(drawn.size), alone \(whole.size)")
        #expect(Double(pixels) >= 0.9 * Double(whole.pixels), "\(what): \(pixels) of its \(whole.pixels) pixels")
    }

    @Test("At AX5 each stage's name is whole on its own line, its duration and share whole under it, inside the card")
    func stageRowsWholeAtAX5() async throws {
        let shares = try #require(MockData.todayDetail.sleep?.displayStages).filter { $0.min > 0 }
        try #require(shares.count == 4, "Deep, Light, REM and Awake: \(shares.map(\.stage))")
        try await HostedWindow.run(width: Self.width, height: 1_800, typeSize: .accessibility5,
                                   category: .accessibilityExtraExtraExtraLarge, card(shares)) { w in
            try await w.wait("the rows") { shares.allSatisfy { s in w.nodes().contains { $0.label.hasPrefix(s.stage.title) } } }
            try await w.settle()
            let px = try WindowPixels(w)
            let surface = Tokens.resolve(Theme.surface)
            let cardBox = try #require(px.box(in: w.window.bounds) { $0.near(surface, 2) }, "the card")
            let primary = Tokens.over(Tokens.resolve(Theme.textPrimary), surface)
            let secondary = Tokens.over(Tokens.resolve(Theme.textSecondary), surface)
            for share in shares {
                let row = try #require(w.nodes().first { $0.label.hasPrefix(share.stage.title) }, "\(share.stage.title)'s row")
                let what = share.stage.title
                #expect(cardBox.insetBy(dx: CardSpec.padding - 0.5, dy: -0.5).contains(row.frame), "\(what)'s row \(row.frame) in the card \(cardBox)")
                // Across the window's width, so ink past the card counts too.
                let band = CGRect(x: 0, y: row.frame.minY - 2, width: Self.width, height: row.frame.height + 4)
                let ink = px.box(in: band) { $0.near(primary, 6) || $0.near(secondary, 6) }
                #expect(ink.map { $0.minX >= Self.column.lowerBound - 0.5 && $0.maxX <= Self.column.upperBound + 0.5 } == true,
                        "\(what)'s words inside the card's column \(Self.column): \(String(describing: ink))")
                let found = lines(px, in: band) { $0.near(primary, 6) }
                try #require(found.count >= 2, "\(what): the name's line and the duration's: \(found)")
                // The name alone on the first line.
                let name = try alone(share.stage.title, ink: Theme.textPrimary, digits: false, scale: px.scale)
                expectWhole(px.box(in: found[0]) { $0.near(primary, 6) }, pixels: px.count(in: found[0]) { $0.near(primary, 6) },
                            name, "\(what): the name")
                // The duration on the next.
                let durationText = Fmt.duration(minutes: share.min)
                let duration = try alone(durationText, ink: Theme.textPrimary, digits: true, scale: px.scale)
                let durationBox = px.box(in: found[1]) { $0.near(primary, 6) }
                expectWhole(durationBox, pixels: px.count(in: found[1]) { $0.near(primary, 6) }, duration, "\(what): \(durationText)")
                // The share beside it (right of the duration's ink, so its anti-aliased edges don't count), or under it.
                let shareText = Fmt.percent(share.pct)
                let percent = try alone(shareText, ink: Theme.textSecondary, digits: true, scale: px.scale)
                let after = (durationBox?.maxX ?? 0) + 2
                let beside = CGRect(x: after, y: found[1].minY - 2, width: Self.width - after, height: found[1].height + 4)
                let under = CGRect(x: 0, y: found[1].maxY + 1, width: Self.width, height: band.maxY - found[1].maxY - 1)
                let place = px.box(in: beside) { $0.near(secondary, 6) } != nil ? beside : under
                expectWhole(px.box(in: place) { $0.near(secondary, 6) }, pixels: px.count(in: place) { $0.near(secondary, 6) },
                            percent, "\(what): \(shareText)")
            }
        }
    }
}
