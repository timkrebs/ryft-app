import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Profile's measurements (docs/work/2026-11-16-nocturne/design.md §P5-12 test 3; §P5-6.1): the board's numbers as values,
/// the avatar's geometry, and the hosted page at 390: the gaps between its rows, the rows, the buttons, and AX3.
@MainActor
@Suite("T5.4: Profile layout", .serialized)
struct ProfileLayoutTests {
    typealias L = ProfileLayout

    @Test("Spec 3: header 40, → identity 18, avatar 72, ring r 34 / 1.6, end dot 3.4 / 1.6, inset 8, row gap 16, name → status 6")
    func identityNumbers() {
        #expect(L.header == 40 && L.header == ScreenHeaderSpec.height)
        #expect(L.headerToIdentity == 18)
        #expect(L.avatar == 72 && L.ringRadius == 34 && L.ringStroke == 1.6)
        #expect(L.endDotRadius == 3.4 && L.endDotRing == 1.6)
        #expect(L.discInset == 8 && L.discDiameter == 56)
        #expect(L.identitySpacing == 16 && L.nameToStatus == 6)
        #expect(L.statusDot == 6 && L.statusDotGap == 6 && L.nameSize == 20)
        #expect(L.initialsSize == 20 && abs(L.initialsTracking - 0.8) < 0.0001)
        #expect(L.trackOpacity == 0.10)
    }

    @Test("Spec 3: title → card 8, identity → first group 24, groups 18, card radius 22, rows ≥ 46, Log out 18 below / 52 high")
    func groupNumbers() {
        #expect(L.titleToCard == 8 && L.titleToCard == GroupedListSpec.titleGap)
        #expect(L.identityToFirstGroup == 24)
        #expect(L.groupGap == 18 && L.groupGap == GroupedListSpec.groupSpacing)
        #expect(L.cardRadius == 22 && L.cardRadius == GroupedListSpec.cardRadius)
        #expect(L.rowMinHeight == 46 && L.rowMinHeight == GroupedListSpec.rowMinHeight)
        #expect(L.buttonsTop == 18 && L.buttonsHeight == 52 && L.buttonsHeight == PillButton.minHeight)
        #expect(L.buttonsToMessage == GroupedListSpec.footerGap)
    }

    @Test("The ring's end: on the ring's centre line, from 12 o'clock clockwise")
    func endPoint() {
        func near(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool { abs(p.x - x) < 0.0001 && abs(p.y - y) < 0.0001 }
        #expect(near(L.endPoint(degrees: 0), 36, 2), "12 o'clock")
        #expect(near(L.endPoint(degrees: 90), 70, 36), "3 o'clock")
        #expect(near(L.endPoint(degrees: 180), 36, 70), "6 o'clock")
        #expect(near(L.endPoint(degrees: 270), 2, 36), "9 o'clock")
        // The dot and its ring reach 3 pt past the 72 frame at most (the gauges' end dots do the same): less than the gaps
        // around the avatar, so nothing overlaps it and nothing clips it.
        let overflow = L.ringRadius + L.endDotRadius + L.endDotRing - L.avatar / 2
        #expect(abs(overflow - 3) < 0.0001 && overflow < L.identitySpacing && overflow < L.headerToIdentity)
    }

    // MARK: hosted

    private func page(_ name: String = "signed-in", typeSize: DynamicTypeSize = .large,
                      category: UIContentSizeCategory = .large,
                      _ body: (HostedWindow) async throws -> Void) async throws {
        let graph = try await ProfileShotGraph.make(name)
        defer { graph.tearDown() }
        try await HostedWindow.run(width: 390, height: 4400, typeSize: typeSize, category: category, graph.view) { w in
            try await w.settle()
            try await body(w)
        }
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "\(id)")
    }

    @Test("Hosted: header → identity 18, the avatar 72 on the inset, → the first group's title 24, its card 8 below")
    func hostedTop() async throws {
        try await page { w in
            let title = try #require(w.node("Profile", exactly: true), "the header's title")
            let identity = try node(w, id: "profile.identity")
            // The element's frame is what it draws: the ring's outer edge (1.2 inside the avatar's 72 frame) at the top and
            // leading side, and the status line's 44 pt target below. So the avatar's frame is the ring's, 1.2 out.
            let ringInset = L.avatar / 2 - L.ringRadius - L.ringStroke / 2
            let avatarTop = identity.frame.minY - ringInset
            // The header row is 40 and its title sits in its middle: the row's bottom is the title's centre + 20.
            #expect(abs(avatarTop - (title.frame.midY + L.header / 2 + L.headerToIdentity)) < 0.5, "\(title.frame) / \(identity.frame)")
            #expect(abs(identity.frame.minX - ringInset - Theme.Metrics.screenPadding) < 0.5, "\(identity.frame)")
            #expect(identity.frame.maxX <= 390 - Theme.Metrics.screenPadding + 0.5)
            let you = try #require(w.node("You", exactly: true), "the first group's title")
            #expect(abs(you.frame.minY - (avatarTop + L.avatar + L.identityToFirstGroup)) < 0.5, "\(you.frame)")
            // The card's first row is 8 below the title's line (the title's text frame is 1 pt taller).
            let body = try node(w, id: "profile.bodyAndBaselines")
            #expect(abs(body.frame.minY - (you.frame.maxY + L.titleToCard)) <= 1.01, "\(you.frame) / \(body.frame)")
        }
    }

    @Test("Hosted: every row at least 46 high and as wide as the card; groups 18 apart")
    func hostedRows() async throws {
        try await page { w in
            let nodes = w.nodes()
            let rows = nodes.filter { node in
                guard let id = node.identifier, id.hasPrefix("profile.") else { return false }
                return ProfileRow.allCases.contains { $0.identifier == id }
            }
            #expect(rows.count >= 11, "\(rows.count) rows")
            let card = 390 - 2 * Theme.Metrics.screenPadding
            for row in rows {
                #expect(row.frame.height >= L.rowMinHeight - 0.5, "\(row.identifier ?? ""): \(row.frame)")
                // A switch's element is inside the row's 16 pt insets; every other row's is the card's width.
                #expect(abs(row.frame.width - card) < 0.5 || abs(row.frame.width - (card - 2 * GroupedListSpec.rowInset)) < 0.5,
                        "\(row.identifier ?? ""): \(row.frame)")
                #expect(row.frame.minX >= Theme.Metrics.screenPadding - 0.5 && row.frame.maxX <= 390 - Theme.Metrics.screenPadding + 0.5)
            }
            let devices = try node(w, id: "profile.devices")
            let privacy = try node(w, id: "profile.privacyAndData")
            #expect(abs(privacy.frame.minY - devices.frame.minY - L.rowMinHeight) < 0.5)
            let resources = try #require(w.node("Resources", exactly: true))
            #expect(abs(resources.frame.minY - (privacy.frame.maxY + L.groupGap)) <= 1.01)
        }
    }

    @Test("Hosted: Log out spans the card width 18 below the last group")
    func hostedButtons() async throws {
        try await page { w in
            let logOut = try node(w, id: "profile.logOut")
            let footer = try #require(w.node("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns.",
                                             exactly: true))
            #expect(abs(logOut.frame.minY - (footer.frame.maxY + L.buttonsTop)) < 0.5, "\(footer.frame) / \(logOut.frame)")
            #expect(abs(logOut.frame.height - L.buttonsHeight) < 0.5)
            #expect(abs(logOut.frame.width - (390 - 2 * Theme.Metrics.screenPadding)) < 0.5, "\(logOut.frame)")
            #expect(!w.nodes().contains { $0.identifier == "profile.export" })
        }
    }

    @Test("Hosted at AX3: the avatar over the name, everything inside the window and Log out at full width")
    func hostedAX3() async throws {
        try await page(typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            let identity = try node(w, id: "profile.identity")
            #expect(identity.frame.height > L.avatar + L.identityStackedSpacing, "stacked: \(identity.frame)")
            for node in w.nodes() where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label): \(node.frame)")
            }
            let logOut = try node(w, id: "profile.logOut")
            #expect(abs(logOut.frame.width - (390 - 2 * Theme.Metrics.screenPadding)) < 0.5, "\(logOut.frame)")
        }
    }
}
