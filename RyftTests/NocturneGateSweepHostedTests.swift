import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The Nocturne gate's sweep (G1, docs/work/2026-11-20-nocturne-gate/design.md §5.1) in real windows, read from the accessibility
/// tree and the pixels (`HostedWindow`, `WindowPixels`): nothing teal on Today's setup and import cards, the push card, the coach
/// marks and the analytics prompt (default and AX3); the import's current step as the inverse chip; the old teal buttons as
/// pills; the prompt's equal outline pills, its reading order, pinned below AX1 and inline from AX1; the insight tile's legend
/// colour (D1); the 22 pt card corner (D8). Synthetic data only.
@MainActor
@Suite("Nocturne gate G1: the swept screens, hosted", .serialized)
struct NocturneGateSweepHostedTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    struct SizeCase: Sendable, CustomTestStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var testDescription: String { "\(size)" }
    }

    nonisolated static let standard = SizeCase(size: .large, category: .large)
    nonisolated static let ax3 = SizeCase(size: .accessibility3, category: .accessibilityExtraLarge)
    private nonisolated static let width: CGFloat = 390, height: CGFloat = 844, bottomInset: CGFloat = 34
    private static let english = Locale(identifier: "en_US")

    private var teal: RGBA { Tokens.resolve(Theme.recovery) }
    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }
    private var surface: RGBA { Tokens.resolve(Theme.surface) }

    private func run(_ s: SizeCase, height: CGFloat = NocturneGateSweepHostedTests.height, _ content: some View,
                     body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: Self.bottomInset, typeSize: s.size,
                                   category: s.category, content, body: body)
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "\(id) in \(w.nodes().compactMap(\.identifier))")
    }

    private func node(_ w: HostedWindow, prefix: String) throws -> HostedWindow.Node {
        try #require(w.node(prefix), "'\(prefix)…' in \(w.nodes().map(\.label))")
    }

    /// The pixels near the recovery teal (within 24 of 255 a channel, the glow's edge included) in `rect`, drawn at 1x.
    private func tealPixels(_ w: HostedWindow, in rect: CGRect? = nil) throws -> Int {
        let px = try WindowPixels(w, scale: 1)
        return px.count(in: rect ?? w.window.bounds) { $0.near(teal, 24) }
    }

    /// The sum of the channels' differences.
    private func distance(_ a: RGBA, _ b: RGBA) -> Double { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    /// The primary pill: at least 52 high, as wide as `width` (its container's column), filled with `textPrimary` (left of the
    /// title, which starts 20 in).
    private func expectPrimaryPill(_ w: HostedWindow, _ pill: HostedWindow.Node, width: CGFloat, _ context: String) throws {
        #expect(pill.frame.height >= PillButton.minHeight - 0.5, "\(context): \(pill.frame)")
        #expect(abs(pill.frame.width - width) <= 1, "\(context): \(pill.frame.width) wide, the column is \(width)")
        let fill = try WindowPixels(w).at(pill.frame.minX + 10, pill.frame.midY)
        #expect(fill.near(ink, 3), "\(context): the fill is \(Tokens.describe(fill))")
    }

    /// From the top-left corner of the shape in `region` (its pixels nearer `surface` than `background`), the distance along the
    /// 45° diagonal to its first pixel: it grows with the corner radius.
    private func cornerInset(_ px: WindowPixels, in region: CGRect) -> CGFloat? {
        let isShape: (RGBA) -> Bool = { distance($0, surface) < distance($0, screen) }
        guard let box = px.box(in: region, where: isShape) else { return nil }
        var t: CGFloat = 0
        while t < 20 {
            if isShape(px.at(box.minX + t, box.minY + t)) { return t }
            t += 1 / px.scale
        }
        return nil
    }

    /// Two plain `surface` shapes with D8's radius (22, not `CardSpec.radius`: a change there is caught too) and the old 18, as
    /// the probe's own scale.
    private struct ReferenceCorners: View {
        var body: some View {
            VStack(spacing: 40) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface).frame(height: 100)
                    .accessibilityElement().accessibilityLabel(Text(verbatim: "ref.22"))
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface).frame(height: 100)
                    .accessibilityElement().accessibilityLabel(Text(verbatim: "ref.18"))
            }
        }
    }

    // MARK: the probe

    @Test("The probe: a recovery swatch is seen as teal, the screen colour isn't")
    func probeSeesTeal() async throws {
        let swatch = Rectangle().fill(Theme.recovery).frame(width: 40, height: 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        try await run(Self.standard, height: 300, swatch) { w in
            try await w.settle()
            #expect(try tealPixels(w) > 1_000, "the swatch")
            #expect(try tealPixels(w, in: CGRect(x: 0, y: 0, width: Self.width, height: 100)) == 0, "above it")
        }
    }

    // MARK: Today: the setup card

    @Test("Today not set up: the setup card draws no teal; \"Open Profile\" is the primary pill across the card",
          arguments: [standard, ax3])
    func setupCard(_ s: SizeCase) async throws {
        let today = TodayView().previewEnvironment(.preview(empty: true)).environment(\.locale, Self.english)
        try await run(s, height: 2_600, today) { w in
            try await w.wait("the setup card") { w.nodes().contains { $0.identifier == "today.setup.openProfile" } }
            try await w.settle()
            let title = try node(w, prefix: "Connect RYFT")
            let open = try node(w, id: "today.setup.openProfile")
            #expect(open.label == "Open Profile" && open.traits.contains(.button), "\(open.label)")
            let card = CGRect(x: 0, y: title.frame.minY - 80, width: Self.width, height: open.frame.maxY + 24 - (title.frame.minY - 80))
            #expect(try tealPixels(w, in: card) == 0, "teal in the setup card")
            let column = Self.width - 2 * Theme.Metrics.screenPadding - 2 * CardSpec.padding
            try expectPrimaryPill(w, open, width: column, "Open Profile")
        }
    }

    // MARK: Today: the first import's card

    @Test("Today importing: the import card and its push question draw no teal; Allow is the primary pill, Not now the quiet action",
          arguments: [standard, ax3])
    func importCard(_ s: SizeCase) async throws {
        let today = TodayView().previewEnvironment(.preview(scenario: .importing)).environment(\.locale, Self.english)
        try await run(s, height: 2_600, today) { w in
            try await w.wait("the import card") { w.nodes().contains { $0.identifier == "today.importCard.push.allow" } }
            try await w.settle()
            let header = try node(w, prefix: "Setting up RYFT")
            let allow = try node(w, id: "today.importCard.push.allow")
            let later = try node(w, id: "today.importCard.push.notNow")
            #expect(allow.label == "Allow" && later.label == "Not now", "\(allow.label) / \(later.label)")
            #expect(later.frame.minY >= allow.frame.maxY && later.frame.height >= Theme.Metrics.minHitTarget, "\(later.frame)")
            let top = header.frame.minY - 40
            let card = CGRect(x: 0, y: top, width: Self.width, height: later.frame.maxY + 24 - top)
            #expect(try tealPixels(w, in: card) == 0, "teal in the import card")
            let column = Self.width - 2 * Theme.Metrics.screenPadding - 2 * CardSpec.padding
            try expectPrimaryPill(w, allow, width: column, "Allow")
        }
    }

    @Test("Today importing: the current step is the inverse chip, background ink on a textPrimary capsule")
    func importCurrentStepIsTheInverseChip() async throws {
        let today = TodayView().previewEnvironment(.preview(scenario: .importing)).environment(\.locale, Self.english)
        try await run(Self.standard, height: 1_600, today) { w in
            try await w.wait("the steps") { w.node("Step ") != nil }
            try await w.settle()
            let steps = try node(w, prefix: "Step ")
            let px = try WindowPixels(w)
            let capsule = try #require(px.box(in: steps.frame) { $0.near(ink, 6) }, "an ink fill in the steps \(steps.frame)")
            #expect(capsule.height >= 14 && capsule.width >= 30, "the capsule \(capsule)")
            let fill = px.at(capsule.minX + 4, capsule.midY)
            #expect(fill.near(ink, 3), "the capsule's fill \(Tokens.describe(fill))")
            let letters = px.count(in: capsule) { $0.near(screen, 3) }
            #expect(letters > 20, "the step's name in background ink: \(letters) pixels")
        }
    }

    // MARK: the push card

    @Test("The push card draws no teal; Allow is the primary pill across the card, Not now the quiet action under it",
          arguments: [standard, ax3])
    func pushCard(_ s: SizeCase) async throws {
        let card = PushPrePromptCard(enable: {}, dismiss: {})
            .padding(Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
        try await run(s, height: 1_000, card) { w in
            try await w.wait("the card") { w.nodes().contains { $0.identifier == "push.allow" } }
            try await w.settle()
            #expect(try tealPixels(w) == 0, "teal on the push card")
            let allow = try node(w, id: "push.allow"), later = try node(w, id: "push.notNow")
            #expect(allow.label == "Allow" && later.label == "Not now")
            #expect(later.frame.minY >= allow.frame.maxY && later.frame.height >= Theme.Metrics.minHitTarget, "\(later.frame)")
            let column = Self.width - 2 * Theme.Metrics.screenPadding - 2 * CardSpec.padding
            try expectPrimaryPill(w, allow, width: column, "Allow")
        }
    }

    // MARK: the coach marks

    /// Today's coach marks over a stand-in page: the target at the top, nothing drawn under it.
    private func coachMarks(defaults: UserDefaults) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 160).coachMarkTarget(.gauges)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .coachMarks(CoachMarks(defaults: defaults), enabled: true)
    }

    @Test("The coach-mark card draws no teal; Next is the compact primary pill; the card's corner is 22 (D8)",
          arguments: [standard, ax3])
    func coachMarkCard(_ s: SizeCase) async throws {
        let defaults = try #require(UserDefaults(suiteName: "gate.g1.coach.\(s.size)"))
        defaults.removePersistentDomain(forName: "gate.g1.coach.\(s.size)")
        let view = VStack(spacing: 0) {
            coachMarks(defaults: defaults).frame(height: Self.height)
            ReferenceCorners().padding(Theme.Metrics.screenPadding)
        }
        try await run(s, height: Self.height + 300, view) { w in
            try await w.wait("the card") { w.nodes().contains { $0.identifier == "coach.next" } }
            try await w.settle()
            #expect(try tealPixels(w) == 0, "teal on the coach marks")
            let next = try node(w, id: "coach.next")
            #expect(next.label == "Next" && next.frame.height >= Theme.Metrics.minHitTarget - 0.5, "\(next.label) \(next.frame)")
            let px = try WindowPixels(w)
            let fill = px.at(next.frame.minX + 8, next.frame.midY)
            #expect(fill.near(ink, 3), "Next's fill \(Tokens.describe(fill))")
            guard s.size == .large else { return }
            let position = try node(w, prefix: "1 of 3")
            let region = CGRect(x: 0, y: position.frame.minY - 20, width: Self.width,
                                height: next.frame.maxY + 24 - (position.frame.minY - 20))
            let card = try #require(cornerInset(px, in: region), "the card in \(region)")
            // The coach marks are modal: the references aren't in the tree. They are the two shapes under the page.
            let below = CGRect(x: 0, y: Self.height + 1, width: Self.width, height: w.window.bounds.height - Self.height - 1)
            let refs = try #require(px.box(in: below) { distance($0, surface) < distance($0, screen) }, "the references")
            let ref22 = try #require(cornerInset(px, in: CGRect(x: 0, y: refs.minY - 4, width: Self.width, height: 108)))
            let ref18 = try #require(cornerInset(px, in: CGRect(x: 0, y: refs.minY + 120, width: Self.width, height: 128)))
            #expect(ref22 - ref18 >= 0.6, "the probe tells 22 from 18: \(ref22) vs \(ref18)")
            #expect(abs(card - ref22) <= 0.4, "the card's corner \(card), 22's \(ref22), 18's \(ref18)")
        }
    }

    // MARK: Today's quiet-tracker card

    @Test("D8: the quiet-tracker card's corner is 22, as every card's on Today")
    func watchHintCorner() async throws {
        let hint = WatchSyncHint(source: "Garmin Connect", since: Date(timeIntervalSinceReferenceDate: 815_000_000), isApp: true)
        let view = VStack(spacing: 40) {
            WatchSyncHintCard(hint: hint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "card"))
            ReferenceCorners()
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .environment(\.locale, Self.english)
        try await run(Self.standard, height: 700, view) { w in
            try await w.wait("the card") { w.node("card", exactly: true) != nil }
            try await w.settle()
            let px = try WindowPixels(w)
            let frame = try #require(w.node("card", exactly: true)).frame
            let card = try #require(cornerInset(px, in: frame.insetBy(dx: -4, dy: -4)), "the card \(frame)")
            let ref22 = try #require(cornerInset(px, in: node(w, prefix: "ref.22").frame.insetBy(dx: -4, dy: -4)))
            let ref18 = try #require(cornerInset(px, in: node(w, prefix: "ref.18").frame.insetBy(dx: -4, dy: -4)))
            #expect(ref22 - ref18 >= 0.6, "the probe tells 22 from 18: \(ref22) vs \(ref18)")
            #expect(abs(card - ref22) <= 0.4, "the card's corner \(card), 22's \(ref22), 18's \(ref18)")
        }
    }

    // MARK: the analytics prompt (D2)

    @Test("D2: the analytics prompt, presented as its sheet, draws no teal (default and AX3)", arguments: [standard, ax3])
    func promptDrawsNoTeal(_ s: SizeCase) async throws {
        let presenter = Theme.background.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) { AnalyticsOptInSheet { _ in }.presentedRoot() }
        try await run(s, presenter) { w in
            try await w.wait("the sheet") { (w.presentedNodes() ?? []).contains { $0.label == "Share usage analytics?" } }
            try await w.settle()
            let nodes = w.presentedNodes() ?? []
            #expect(nodes.contains { $0.identifier == "analytics.share" } && nodes.contains { $0.identifier == "analytics.decline" },
                    "\(nodes.compactMap(\.identifier))")
            #expect(try tealPixels(w) == 0, "teal on the prompt")
        }
    }

    @Test("D2: the prompt's two answers are the same outline pill, the same size, and keep their identifiers")
    func promptAnswersAreEqualOutlines() async throws {
        try await run(Self.standard, AnalyticsOptInSheet { _ in }) { w in
            try await w.wait("the answers") { w.nodes().contains { $0.identifier == "analytics.decline" } }
            try await w.settle()
            let share = try node(w, id: "analytics.share"), decline = try node(w, id: "analytics.decline")
            #expect(share.label == "Share usage analytics" && decline.label == "Don't share")
            #expect(abs(share.frame.width - decline.frame.width) < 0.5 && abs(share.frame.height - decline.frame.height) < 0.5,
                    "\(share.frame.size) vs \(decline.frame.size)")
            #expect(share.frame.height >= PillButton.minHeight - 0.5)
            let px = try WindowPixels(w)
            for pill in [share, decline] {
                // Not filled: the screen colour inside, left of the centred title; an outline at the edge.
                let inside = px.at(pill.frame.minX + 12, pill.frame.midY)
                #expect(inside.near(screen, 3), "\(pill.label): inside \(Tokens.describe(inside))")
                let edge = stride(from: pill.frame.minX - 1, through: pill.frame.minX + 2, by: 1 / px.scale)
                    .map { distance(px.at($0, pill.frame.midY), screen) }.max() ?? 0
                #expect(edge > 0.08, "\(pill.label): the outline at its edge \(edge)")
            }
        }
    }

    @Test("D2: VoiceOver reads the title (a header), the lead, the four points, the footnote, Share, Don't share")
    func promptReadingOrder() async throws {
        try await run(Self.standard, AnalyticsOptInSheet { _ in }) { w in
            try await w.wait("the answers") { w.nodes().contains { $0.identifier == "analytics.decline" } }
            try await w.settle()
            let nodes = w.nodes()
            func index(_ match: (HostedWindow.Node) -> Bool, _ what: String) throws -> Int {
                let found = nodes.firstIndex(where: match)
                return try #require(found, "\(what) in \(nodes.map(\.label))")
            }
            let title = try index({ $0.label == "Share usage analytics?" }, "the title")
            #expect(nodes[title].traits.contains(.header))
            let lead = try index({ $0.label.hasPrefix("This is separate from your health-data consent.") }, "the lead")
            let points = try ["What is counted", "What is not", "Your ID", "Where it goes"].map { heading in
                try index({ $0.label.hasPrefix(heading) && $0.label.count > heading.count + 20 }, heading)
            }
            let footnote = try index({ $0.label == "Change this any time in Profile → Privacy." }, "the footnote")
            let share = try index({ $0.identifier == "analytics.share" }, "Share")
            let decline = try index({ $0.identifier == "analytics.decline" }, "Don't share")
            let order = [title, lead] + points + [footnote, share, decline]
            #expect(order == order.sorted() && Set(order).count == order.count, "\(order)")
            #expect(points.last.map { $0 - points[0] } == 3, "one element per point: \(points)")
            #expect(footnote - title == 6, "nothing else between the title and the footnote: \(nodes.map(\.label))")
        }
    }

    @Test("D2: below AX1 the answers are pinned under the page, both on screen; from AX1 they end the page, reached by scrolling",
          arguments: [standard, ax3])
    func promptAnswersPinnedOrInline(_ s: SizeCase) async throws {
        try await run(s, AnalyticsOptInSheet { _ in }) { w in
            try await w.wait("the answers") { w.nodes().contains { $0.identifier == "analytics.decline" } }
            try await w.settle()
            let limit = Self.height - Self.bottomInset
            let scroll = try #require(w.pageScrollView(), "the page's scroll view")
            let share = try node(w, id: "analytics.share"), decline = try node(w, id: "analytics.decline")
            let barTop = share.frame.minY - PinnedBarSpec.topPadding
            if s.size.isAccessibilitySize {
                // No bar: the page's inset is the home indicator's (and a few points), not a pill's; the answers start below
                // the window.
                #expect(scroll.adjustedContentInset.bottom < Self.bottomInset + PillButton.minHeight / 2, "\(scroll.adjustedContentInset)")
                #expect(share.frame.minY >= limit, "Share starts below the fold: \(share.frame)")
            } else {
                #expect(share.frame.minY >= 0 && decline.frame.maxY <= limit + 0.5, "\(share.frame) \(decline.frame)")
                #expect(scroll.adjustedContentInset.bottom >= limit - barTop + Self.bottomInset - 1,
                        "the page's inset \(scroll.adjustedContentInset.bottom) covers the bar from \(barTop)")
            }
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, end)), animated: false)
            try await w.settle()
            let shown = try node(w, id: "analytics.share"), declined = try node(w, id: "analytics.decline")
            let footnote = try node(w, prefix: "Change this any time")
            if s.size.isAccessibilitySize {
                #expect(shown.frame.minY > footnote.frame.maxY, "under the footnote: \(shown.frame) \(footnote.frame)")
                #expect(shown.frame.minY >= 0 && declined.frame.maxY <= limit + 0.5, "scrolled into view: \(shown.frame) \(declined.frame)")
            } else {
                #expect(abs(shown.frame.minY - share.frame.minY) < 0.5, "pinned: Share stays at \(share.frame.minY), now \(shown.frame.minY)")
                #expect(footnote.frame.maxY <= barTop + 0.5, "the page's end at \(footnote.frame.maxY), the bar at \(barTop)")
            }
        }
    }

    /// The prompt's text size, changed while it is up.
    @MainActor @Observable final class TypeSizeBox {
        var size: DynamicTypeSize = .large
    }

    private struct ResizablePrompt: View {
        let box: TypeSizeBox
        var body: some View { AnalyticsOptInSheet { _ in }.dynamicTypeSize(box.size) }
    }

    @Test("D2 (part 1 review nit 5): across AX1 the prompt keeps its page, the same scroll view still scrolled; the answers leave the bar")
    func promptKeepsItsPageAcrossAX1() async throws {
        let box = TypeSizeBox()
        // Short enough that the page scrolls at the default size.
        try await run(Self.standard, height: 560, ResizablePrompt(box: box)) { w in
            try await w.wait("the answers") { w.nodes().contains { $0.identifier == "analytics.decline" } }
            try await w.settle()
            let scroll = try #require(w.pageScrollView(), "the page's scroll view")
            #expect(scroll.adjustedContentInset.bottom >= PillButton.minHeight * 2, "pinned: \(scroll.adjustedContentInset)")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            #expect(end > 60, "the page scrolls: \(end)")
            let by = min(80, end)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + by), animated: false)
            try await w.settle()
            let scrolled = scroll.contentOffset.y

            box.size = .accessibility3
            try await w.settle()
            let now = try #require(w.pageScrollView(), "the page's scroll view at AX3")
            #expect(now.adjustedContentInset.bottom < Self.bottomInset + PillButton.minHeight / 2, "no bar at AX3: \(now.adjustedContentInset)")
            #expect(now === scroll, "the same page: its scroll view was rebuilt")
            #expect(abs(now.contentOffset.y - scrolled) < 1, "still scrolled \(scrolled), now \(now.contentOffset.y)")
        }
    }

    // MARK: the insight tile (D1)

    private func tile(_ metric: String?) -> some View {
        InsightTile(insight: Insight(id: "x", severity: .info, title: "Best HRV in 30 days",
                                     body: "Last night's HRV of 66 ms is your highest in a month.", metric: metric),
                    onDismiss: {}, onOpen: {}, reduceTransparency: false)
            .padding(Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
    }

    /// How much of `colour` over the screen colour the pixel is (the glow is the colour under a `background` overlay), or nil
    /// when the pixel isn't a mix of those two (the text, another colour).
    private func share(of colour: RGBA, in p: RGBA) -> Double? {
        let d = [colour.r - screen.r, colour.g - screen.g, colour.b - screen.b]
        let v = [p.r - screen.r, p.g - screen.g, p.b - screen.b]
        let dd = zip(d, d).map(*).reduce(0, +)
        guard dd > 0 else { return nil }
        let a = zip(v, d).map(*).reduce(0, +) / dd
        let residual = zip(v, d).map { ($0 - a * $1) * ($0 - a * $1) }.reduce(0, +).squareRoot()
        return residual < 0.025 ? a : nil
    }

    @Test("D1: an HRV insight glows teal; a time-asleep one violet and not teal; a steps one is flat, neither colour",
          arguments: ["hrv", "sleep_min", "steps"])
    func insightTileColour(_ metric: String) async throws {
        try await run(Self.standard, height: 400, tile(metric)) { w in
            try await w.wait("the tile") { w.nodes().contains { $0.identifier == "insights.tile.dismiss" } }
            try await w.settle()
            let px = try WindowPixels(w, scale: 1)
            // The pixels at least 30 % the colour: the glow's corners are ~60 %, its core a few per cent.
            let count: (Color) -> Int = { colour in
                let target = Tokens.resolve(colour)
                return px.count(in: w.window.bounds) { (share(of: target, in: $0) ?? 0) >= 0.3 }
            }
            let (recovery, sleep, strain) = (count(Theme.recovery), count(Theme.metricSleep), count(Theme.metricStrain))
            switch metric {
            case "hrv":
                #expect(recovery > 1_000 && sleep == 0 && strain == 0, "teal \(recovery), violet \(sleep), blue \(strain)")
            case "sleep_min":
                #expect(sleep > 1_000 && recovery == 0 && strain == 0, "violet \(sleep), teal \(recovery), blue \(strain)")
            default:
                #expect(recovery == 0 && sleep == 0 && strain == 0, "teal \(recovery), violet \(sleep), blue \(strain)")
                let flat = px.count(in: w.window.bounds) { $0.near(Tokens.resolve(Theme.surface), 2) }
                #expect(flat > 20_000, "the flat surface tile: \(flat) pixels")
            }
        }
    }
}
