import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// D6 (security review N-2): while a consent withdrawal is on its way, the Demo data switch and Log out would end it unsent,
/// so Profile holds them: dimmed, no tap, and one sentence says why, as the switch's detail and under the buttons row (Log
/// out's VoiceOver hint; the line itself is hidden from VoiceOver, so it is read once). Everything else works. Confirmed,
/// failed or ended unsent by an account change, both are live again; only a confirmation is announced. Hosted, read from the
/// accessibility tree and the drawn pixels. Synthetic data only (Alex Doe).
@MainActor
@Suite("D6: Profile holds Demo data and Log out while a consent withdrawal runs", .serialized)
struct ProfileWithdrawalHoldTests {
    private let reason = ProfileViewModel.withdrawalHoldReason
    private static let demo = ProfileRow.demoMode.identifier
    private static let logOut = ProfileButton.logOut.identifier
    private static let export = ProfileButton.export.identifier

    private static var shotFormat: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return format
    }

    /// Under the ~2,700 pt a window can draw (`PagedWindowShot`); most of the page on screen at once.
    private static let height: CGFloat = 2_600

    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000F2") ?? UUID()

    /// What the model handed VoiceOver, in order.
    @MainActor
    private final class Spoken {
        var lines: [String] = []
    }

    private func find(_ w: HostedWindow, _ id: String) -> HostedWindow.Node? {
        w.nodes().first { $0.identifier == id }
    }

    private func node(_ w: HostedWindow, _ id: String) throws -> HostedWindow.Node {
        try #require(find(w, id), "\(id) in \(w.nodes().map(\.label))")
    }

    /// Draws the window with the buttons row on screen, `above` points under the window's top, and reads `probe` from it
    /// (with Log out's frame as drawn): a window over about 2,700 pt draws black (`PagedWindowShot`), so the page is
    /// scrolled to the row, then back to the top.
    private func atButtons<T>(_ w: HostedWindow, above: CGFloat = 200,
                              _ probe: (WindowPixels, CGRect) throws -> T) async throws -> T {
        let scroll = try #require(w.pageScrollView(), "the page's scroll view")
        // Frames as they are now: the last call scrolled back to the top.
        try await w.settle()
        let top = -scroll.adjustedContentInset.top
        let end = max(top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        let pill = try node(w, Self.logOut).frame
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(max(top, scroll.contentOffset.y + pill.minY - above), end)),
                                animated: false)
        try await w.settle()
        defer { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false) }
        return try probe(try WindowPixels(w, scale: 2), try node(w, Self.logOut).frame)
    }

    /// The lit pixels where the line under the buttons row goes, from 8 under Log out (the last pill, side by side or
    /// stacked), `depth` deep. Live, 9: above where the Developer group (Debug builds) starts, 18 under the row. Held, down
    /// to the next node VoiceOver reads: the line and nothing else.
    private static func litUnderButtons(_ pixels: WindowPixels, _ pill: CGRect, depth: CGFloat) -> Int {
        let band = CGRect(x: 0, y: pill.maxY + ProfileLayout.buttonsToMessage, width: 390, height: depth)
        return pixels.count(in: band) { max($0.r, $0.g, $0.b) > 0.3 }
    }

    /// The brightest ink of Log out's title, 0…1: `textPrimary` live, about a third of it at 35 %.
    private static func logOutInk(_ pixels: WindowPixels, _ pill: CGRect) -> Double {
        var brightest = 0.0
        _ = pixels.count(in: pill.insetBy(dx: 12, dy: 10)) { brightest = max(brightest, $0.r, $0.g, $0.b); return false }
        return brightest
    }

    /// Held: both untappable, the reason in the switch's label and Log out's hint, nothing else reads it out, the line drawn
    /// under the buttons, Log out drawn dimmed, and Export still live.
    private func expectHeld(_ w: HostedWindow) async throws {
        let demo = try node(w, Self.demo)
        #expect(!demo.isEnabled, "the Demo data switch takes no tap")
        #expect(demo.label.contains(reason) || demo.value?.contains(reason) == true,
                "the reason is the switch's detail: \(demo.label) / \(demo.value ?? "nil")")
        #expect(!demo.label.contains(String(localized: "Show a realistic sample history instead of your server.")))
        let logOut = try node(w, Self.logOut)
        #expect(logOut.label == String(localized: "Log out") && !logOut.isEnabled, "Log out takes no tap")
        #expect(logOut.hint == reason, "Log out's hint: \(logOut.hint ?? "nil")")
        // Read once: the switch carries it, the line under the buttons doesn't.
        let saying = w.nodes().filter { $0.label.contains(reason) || ($0.value ?? "").contains(reason) }
        #expect(saying.map(\.identifier) == [Self.demo], "\(saying.map(\.label))")
        #expect(try node(w, Self.export).isEnabled, "Export still works")
        // The band ends above the next thing VoiceOver reads under the row (the Developer group in Debug builds). The line
        // is hidden from VoiceOver, so only it can be lit there: without it the band is the live gap (`expectLive`).
        let (lit, ink, pill, depth) = try await atButtons(w) { pixels, pill in
            let next = w.nodes().map(\.frame.minY).filter { $0 > pill.maxY }.min() ?? pill.maxY + 120
            let depth = next - pill.maxY - ProfileLayout.buttonsToMessage - 1
            return (Self.litUnderButtons(pixels, pill, depth: depth), Self.logOutInk(pixels, pill), pill, depth)
        }
        #expect(lit > 200, "the reason drawn under the buttons row: \(lit) lit in \(depth) under \(pill)")
        #expect(ink < 0.5, "Log out dimmed: \(ink)")
    }

    /// Live: both take taps, no reason anywhere, no line under the buttons, Log out at full ink.
    private func expectLive(_ w: HostedWindow) async throws {
        let demo = try node(w, Self.demo)
        #expect(demo.isEnabled)
        #expect(!(demo.label + (demo.value ?? "")).contains(reason))
        let logOut = try node(w, Self.logOut)
        #expect(logOut.isEnabled && (logOut.hint ?? "").isEmpty, "hint: \(logOut.hint ?? "nil")")
        let depth = ProfileLayout.buttonsToDeveloper - ProfileLayout.buttonsToMessage - 1
        let (lit, ink, pill) = try await atButtons(w) { (Self.litUnderButtons($0, $1, depth: depth), Self.logOutInk($0, $1), $1) }
        #expect(lit == 0, "nothing under the buttons row: \(lit) lit under \(pill)")
        #expect(ink > 0.8, "Log out at full ink: \(ink) in \(pill)")
    }

    @Test("Withdrawing: Demo data and Log out held with the reason, taps do nothing; live again and announced once RYFT confirms",
          .timeLimit(.minutes(2)))
    func heldUntilConfirmed() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let api = try #require(graph.state.env.api as? MockPlatformAPI)
        let gate = Gate()
        api.beforeRevokeConsent = { await gate.wait() }
        let profile = graph.screens.profile
        let spoken = Spoken()
        profile.announce = { spoken.lines.append($0) }
        try await HostedWindow.run(width: 390, height: Self.height, graph.view) { w in
            try await w.settle()
            try await expectLive(w)

            let withdrawing = Task { await profile.withdrawConsent() }
            try await w.wait("held") { find(w, Self.logOut)?.isEnabled == false }
            try await w.settle()
            try await expectHeld(w)
            let footer = String(localized: "Withdrawing your consent. Syncing stops once RYFT confirms.")
            #expect(w.node(footer) != nil, "the Privacy footer says what is happening")

            // A tap on either does nothing: Demo data stays off, no Log out confirmation, still signed in.
            try node(w, Self.demo).activate()
            try node(w, Self.logOut).activate()
            try await w.settle()
            #expect(!graph.settings.demoMode, "Demo data stays off")
            #expect(w.presentedView == nil, "no Log out confirmation")
            #expect(graph.state.env.auth.isSignedIn)
            #expect(spoken.lines.isEmpty, "nothing announced while it runs")

            await gate.open()
            await withdrawing.value
            try await w.wait("live") { find(w, Self.logOut)?.isEnabled == true }
            try await w.settle()
            try await expectLive(w)
            #expect(api.count("revokeConsent") == 1)
            #expect(spoken.lines == [ProfileViewModel.consentWithdrawnAnnouncement], "\(spoken.lines)")
            #expect(w.node(footer) == nil)
        }
    }

    @Test("A failed withdrawal: live again, the failure under Privacy, nothing announced", .timeLimit(.minutes(2)))
    func liveAgainAfterAFailure() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let api = try #require(graph.state.env.api as? MockPlatformAPI)
        let gate = Gate()
        api.beforeRevokeConsent = { await gate.wait() }
        api.faults["revokeConsent"] = .init(.status(500, retryAfter: nil))
        let profile = graph.screens.profile
        let spoken = Spoken()
        profile.announce = { spoken.lines.append($0) }
        let message = String(localized: "Something went wrong on RYFT's side. Try again later.")
        try await HostedWindow.run(width: 390, height: Self.height, graph.view) { w in
            try await w.settle()
            let withdrawing = Task { await profile.withdrawConsent() }
            try await w.wait("held") { find(w, Self.logOut)?.isEnabled == false }
            try await w.settle()
            try await expectHeld(w)

            await gate.open()
            await withdrawing.value
            try await w.wait("the message") { w.node(message, exactly: true) != nil }
            try await w.settle()
            try await expectLive(w)
            #expect(profile.consentError == message)
            #expect(spoken.lines.isEmpty, "a failure announces itself through its message: \(spoken.lines)")
        }
    }

    @Test("A withdrawal waiting for a step's request ends unsent when another account signs in: live again, nothing said",
          .timeLimit(.minutes(2)))
    func liveAgainWhenItEndsUnsent() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let api = try #require(graph.state.env.api as? MockPlatformAPI)
        let auth = graph.state.env.auth
        let onboarding = graph.screens.onboarding
        let profile = graph.screens.profile
        let spoken = Spoken()
        profile.announce = { spoken.lines.append($0) }
        // The app's account-change handler (RyftApp) knows the account; an invite's request is out.
        onboarding.switchAccount(auth.accountID)
        let invite = Gate()
        api.beforeInvite = { await invite.wait() }
        onboarding.inviteCode = "RYFT-7K3M-QX9P"
        let inviting = Task { await onboarding.redeemInvite() }
        #expect(await eventually { api.count("redeemInvite") == 1 && onboarding.isWorking })
        try await HostedWindow.run(width: 390, height: Self.height, graph.view) { w in
            try await w.settle()
            let withdrawing = Task { await profile.withdrawConsent() }
            try await w.wait("held") { find(w, Self.logOut)?.isEnabled == false }
            try await w.settle()
            try await expectHeld(w)
            #expect(api.count("revokeConsent") == 0, "it waits for the invite's answer")

            // Straight from Alex to another account, then the app's handler: the withdrawal ends unsent.
            graph.client.signInSession = .preview(id: Self.b)
            _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
            #expect(auth.accountID == Self.b.uuidString)
            onboarding.switchAccount(auth.accountID)
            await withdrawing.value
            try await w.wait("live") { find(w, Self.logOut)?.isEnabled == true }
            try await w.settle()
            try await expectLive(w)
            #expect(api.count("revokeConsent") == 0, "\(api.calls)")
            #expect(spoken.lines.isEmpty && profile.consentError == nil)
        }
        await invite.open()
        #expect(await inviting.value == false)
    }

    @Test("Held at the default size and at AX3 (the buttons stacked): the same hold, the line under the last pill",
          arguments: [false, true])
    func heldAtBothSizes(ax3: Bool) async throws {
        let graph = try await ProfileShotGraph.make("withdrawing")
        defer { graph.tearDown() }
        try await HostedWindow.run(width: 390, height: Self.height, typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, graph.view) { w in
            try await w.wait("held") { find(w, Self.logOut)?.isEnabled == false }
            try await w.settle()
            try await expectHeld(w)
            if ax3 {
                let export = try node(w, Self.export).frame, logOut = try node(w, Self.logOut).frame
                #expect(logOut.minY > export.maxY, "stacked from AX1: Log out under Export")
            }
            // With `PROFILE_SHOTS_DIR`: one screen around the buttons row, clear of a paged shot's seams (the paged
            // `profile-withdrawing-*` shots can cut through the pill).
            if let dir = ProcessInfo.processInfo.environment["PROFILE_SHOTS_DIR"] {
                let image = try await atButtons(w, above: 520) { _, pill in
                    // One screen (844) of the window, the pill 520 under its top.
                    UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: max(0, pill.minY - 520), width: 390, height: 844),
                                            format: Self.shotFormat).image { _ in
                        w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
                    }
                }
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/profile-withdrawing-buttons-\(ax3 ? "ax3" : "default").png"))
            }
        }
        await graph.releaseWithdrawal()
    }
}
