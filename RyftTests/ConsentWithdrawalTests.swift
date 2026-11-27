import Foundation
import Testing
@testable import Ryft

/// PR 6 security review N-B: a consent withdrawal is never dropped. While a step's request is out (an Agree's re-check,
/// an invite, About you) it waits for that one's answer and then goes, so it's the last word on the platform and on this
/// phone; a failure shows under Profile → Privacy with its request ID; and a withdrawal still waiting when the account
/// changes never goes out with the next account's session. Synthetic data only.
@MainActor
@Suite("Consent withdrawal: always sent, or said")
struct ConsentWithdrawalTests {
    /// What a call said once it returned; nil while it hasn't.
    @MainActor
    private final class Outcome {
        var value: Bool?
    }

    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000E1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000E2") ?? UUID()

    @Test("Withdraw while a consent post is out: it waits for that answer, then sends once, and stays the last word",
          .timeLimit(.minutes(1)))
    func aWithdrawalDuringAConsentPostGoesAfterIt() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let model = OnboardingCoordinator(state: AppState(env: .test(api: api)), apiStatus: APIStatus()) {}
        await model.check()
        let gate = Gate()
        api.beforeConsent = { await gate.wait() }
        let agreeing = Task { await model.agree() }
        #expect(await eventually { api.count("consent") == 1 && model.isWorking })

        let withdrew = Outcome()
        let withdrawing = Task { withdrew.value = await model.withdrawConsent() }
        #expect(await eventually { model.isWithdrawing })
        #expect(api.count("revokeConsent") == 0 && withdrew.value == nil, "it waits for the consent's answer")

        await gate.open()
        #expect(await agreeing.value)
        await withdrawing.value
        #expect(withdrew.value == true && api.count("revokeConsent") == 1, "\(api.calls)")
        #expect(api.calls.filter { $0 == "consent" || $0 == "revokeConsent" } == ["consent", "revokeConsent"])
        #expect(api.accountConsent == nil, "withdrawn on the platform")
        #expect(model.uploadGate(for: .healthKit) == .gate(.consentRequired), "and on this phone")
        #expect(!model.isWithdrawing && !model.isWorking && model.errorMessage == nil)
    }

    @Test("A failed withdrawal says so under Privacy and data's consent card, with the request ID behind Details",
          .timeLimit(.minutes(1)))
    func aFailedWithdrawalShowsItsMessage() async throws {
        let graph = try await ProfileShotGraph.make("signed-in")
        defer { graph.tearDown() }
        let api = try #require(graph.state.env.api as? MockPlatformAPI)
        api.faults["revokeConsent"] = .init(.status(500, retryAfter: nil))
        let message = String(localized: "Something went wrong on RYFT's side. Try again later.")
        // Since P1 the consent card is on Privacy and data, where Withdraw consent is.
        try await HostedWindow.run(width: 390, height: 4400, graph.page(.privacyAndData)) { w in
            try await w.settle()
            #expect(w.node(message, exactly: true) == nil)
            await graph.screens.profile.withdrawConsent()
            #expect(api.count("revokeConsent") == 1)
            try await w.wait("the message") { w.node(message, exactly: true) != nil }
            // The page's only Details: the inline toggle has no identifier of its own.
            let details = try #require(w.node("Details", exactly: true), "\(w.nodes().map(\.label))")
            #expect(details.activate())
            try await w.wait("the request ID") {
                w.nodes().contains { $0.label.contains("HTTP 500 · Request ID fault-revokeConsent") }
            }
        }
    }

    @Test("A withdrawal still waiting for A's request when B signs in ends unsent; nothing is withdrawn for B",
          .timeLimit(.minutes(1)))
    func aWaitingWithdrawalNeverGoesOutAsTheNextAccount() async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        let gate = Gate()
        api.beforeInvite = { await gate.wait() }
        let client = MockAuthClient(session: .preview(id: Self.a))
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let state = AppState(env: .test(api: api, auth: auth))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.switchAccount(auth.accountID)
        model.inviteCode = "RYFT-7K3M-QX9P"
        let inviting = Task { await model.redeemInvite() }
        #expect(await eventually { api.count("redeemInvite") == 1 && model.isWorking })
        let withdrew = Outcome()
        let withdrawing = Task { withdrew.value = await model.withdrawConsent() }
        #expect(await eventually { model.isWithdrawing })

        // Straight from A to B, then the app's account-change handler (RyftApp).
        client.signInSession = .preview(id: Self.b)
        _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
        #expect(auth.accountID == Self.b.uuidString)
        model.switchAccount(auth.accountID)
        await withdrawing.value
        #expect(withdrew.value == false && !model.isWithdrawing)
        #expect(api.count("revokeConsent") == 0, "A's withdrawal never goes out with B's session: \(api.calls)")

        await gate.open()
        #expect(await inviting.value == false)
        #expect(api.count("revokeConsent") == 0)
        #expect(state.env.consent.withdrawnAt == nil, "nothing withdrawn for B on this phone")
        #expect(model.errorMessage == nil)
    }
}
