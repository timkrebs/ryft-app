import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The busy rule (docs/work/2026-11-16-nocturne/build-plan.md §2, the `PillButton` row; lead decision M3b): a busy button
/// shows the pill's spinner, keeps its title, takes no tap, and VoiceOver reads the title with "In progress". Area A's pills
/// that used to swap in a gerund ("Logging in…", "Checking…", "Saving your consent…"), hosted and read from the
/// accessibility tree. Area C's (Check again, Send, Rescore, Turn off) are in their pages' suites.
@MainActor
@Suite("The busy rule: area A's pills keep their titles", .serialized)
struct BusyKeepsTitleTests {
    private static let wait: Duration = .seconds(15)

    private func run(_ content: some View, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: 390, height: 844, content, body: body)
    }

    private func pill(_ w: HostedWindow, _ id: String) -> HostedWindow.Node? {
        w.nodes().first { $0.identifier == id }
    }

    /// Busy: the title it has at rest, not enabled (no tap reaches it), and "In progress" after the title.
    private func expectBusy(_ w: HostedWindow, _ id: String, title: String) throws {
        let node = try #require(pill(w, id), "\(id) in \(w.nodes().map(\.label))")
        #expect(node.label == title, "\(id): \(node.label)")
        #expect(!node.isEnabled, "\(id) takes no tap while busy")
        #expect(node.value == "In progress", "\(id): \(node.value ?? "nil")")
    }

    // MARK: the forms (their busy flag for previews and shots: `AuthService` is busy only during a request)

    enum Form: String, CaseIterable, Sendable { case logIn, createAccount, resetPassword, newPassword }

    private struct FormCase {
        let view: AnyView
        let id: String
        let title: String
    }

    private func formCase(_ form: Form) -> FormCase {
        let signedOut = AuthService.preview(signedIn: false)
        switch form {
        case .logIn:
            return FormCase(view: AnyView(NavigationStack { LogInView(path: .constant([]), showsBusy: true) }.environment(signedOut)),
                            id: "logIn.submit", title: "Log in")
        case .createAccount:
            return FormCase(view: AnyView(NavigationStack { CreateAccountView(path: .constant([]), showsBusy: true) }
                                .environment(signedOut)),
                            id: "createAccount.submit", title: "Create account")
        case .resetPassword:
            return FormCase(view: AnyView(NavigationStack {
                ForgotPasswordView(path: .constant([]), email: "alex@example.com", showsBusy: true)
            }.environment(signedOut)), id: "resetPassword.submit", title: "Send reset link")
        case .newPassword:
            return FormCase(view: AnyView(SetNewPasswordView(mode: .change, showsBusy: true).environment(AuthService.preview())),
                            id: "newPassword.save", title: "Save password")
        }
    }

    @Test("Log in, Create account, Send reset link, Save password: busy keeps the title, takes no tap, says In progress",
          arguments: Form.allCases)
    func forms(_ form: Form) async throws {
        let c = formCase(form)
        try await run(c.view.environment(\.appEnvironment, AppEnvironment.test())) { w in
            try await w.wait("the pill", timeout: Self.wait) { pill(w, c.id) != nil }
            try await w.settle()
            try expectBusy(w, c.id, title: c.title)
        }
    }

    // MARK: Check your inbox

    @Test("Resend while it sends: still Resend, takes no tap, says In progress; then Sent again")
    func resend() async throws {
        let model = InboxResendModel { _ in }
        let gate = Gate()
        let view = NavigationStack { CheckInboxView(reason: .confirmSignUp, email: "alex@example.com", resend: model) }
            .environment(AuthService.preview(signedIn: false))
        try await run(view) { w in
            try await w.wait("Resend", timeout: Self.wait) { pill(w, "checkInbox.resend") != nil }
            try await w.settle()
            let idle = try #require(pill(w, "checkInbox.resend"))
            #expect(idle.label == "Resend" && idle.isEnabled && idle.value != "In progress")

            let sending = Task {
                await model.resend {
                    await gate.wait()
                    return true
                }
            }
            try await w.wait("busy", timeout: Self.wait) { pill(w, "checkInbox.resend")?.value == "In progress" }
            try expectBusy(w, "checkInbox.resend", title: "Resend")

            await gate.open()
            await sending.value
            try await w.wait("Sent again", timeout: Self.wait) { pill(w, "checkInbox.resend")?.label == "Sent again" }
        }
    }

    // MARK: onboarding

    @Test("Invite code: Continue while the code is checked keeps Continue, takes no tap, says In progress")
    func inviteContinue() async throws {
        let api = MockPlatformAPI()
        let gate = Gate()
        api.beforeInvite = { await gate.wait() }
        let state = AppState(env: .test(api: api))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        // A code already there: the field doesn't take the keyboard, and Continue is on.
        model.inviteCode = "RYFT-7K3M-QX9P"
        try await run(InviteCodeView(model: model).previewEnvironment(state)) { w in
            try await w.wait("Continue", timeout: Self.wait) { pill(w, "invite.continue") != nil }
            try await w.settle()
            let idle = try #require(pill(w, "invite.continue"))
            #expect(idle.label == "Continue" && idle.isEnabled && idle.value != "In progress")

            idle.activate()
            try await w.wait("busy", timeout: Self.wait) { pill(w, "invite.continue")?.value == "In progress" }
            try expectBusy(w, "invite.continue", title: "Continue")
            try #require(pill(w, "invite.continue")).activate()
            try await w.settle()
            #expect(api.calls.filter { $0 == "redeemInvite" }.count == 1, "\(api.calls)")

            await gate.open()
            try await w.wait("done", timeout: Self.wait) { !model.isWorking }
        }
    }

    @Test("Consent: Agree and continue while it saves keeps its title, takes no tap, says In progress")
    func consentAgree() async throws {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let gate = Gate()
        api.beforeConsent = { await gate.wait() }
        let state = AppState(env: .test(api: api))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        let caption = String(localized: "Nothing is synced until you agree. Privacy policy version \(MockData.policyVersion).")
        try await run(ConsentView(model: model).previewEnvironment(state)) { w in
            try await w.wait("the version", timeout: Self.wait) { w.node(caption) != nil }
            try #require(pill(w, "consent.checkbox")).activate()
            try await w.wait("ticked", timeout: Self.wait) { pill(w, "consent.agree")?.isEnabled == true }
            let idle = try #require(pill(w, "consent.agree"))
            #expect(idle.label == "Agree and continue" && idle.value != "In progress")

            idle.activate()
            try await w.wait("busy", timeout: Self.wait) { pill(w, "consent.agree")?.value == "In progress" }
            try expectBusy(w, "consent.agree", title: "Agree and continue")
            try #require(pill(w, "consent.agree")).activate()
            try await w.settle()
            #expect(api.calls.filter { $0 == "consent" }.count == 1, "\(api.calls)")

            await gate.open()
            try await w.wait("saved", timeout: Self.wait) { !model.isWorking }
            #expect(api.consentPosts == [MockData.policyVersion])
        }
    }

    @Test("Apple Health: Continue while the system sheet is up keeps Continue, takes no tap, says In progress; Not now is off")
    func healthContinue() async throws {
        let view = HealthPermissionView(showsBusy: true).environment(\.appEnvironment, AppEnvironment.test())
        try await run(view) { w in
            try await w.wait("Continue", timeout: Self.wait) { pill(w, "health.continue") != nil }
            try await w.settle()
            try expectBusy(w, "health.continue", title: "Continue")
            #expect(pill(w, "health.notNow")?.isEnabled == false)
        }
    }
}
