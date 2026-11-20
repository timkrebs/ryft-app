import Foundation
import Testing
@testable import Ryft

/// PR 6 security review N-3: the invite code and the consent go once, however often Continue or Agree is asked for while the
/// first is out. The coordinator holds this itself (`OnboardingCoordinator.perform`), not only its busy pill; the rule is the
/// account's, so another account's steps start free and A's late answer touches nothing of B's (review code N6). Synthetic
/// data only.
@MainActor
@Suite("Onboarding: one request at a time")
struct OnboardingSingleSendTests {
    /// What a call said once it returned; nil while it hasn't.
    @MainActor
    private final class Outcome {
        var value: Bool?
    }

    @Test("Invite code: a second Continue before the first answers sends nothing; the first goes through", .timeLimit(.minutes(1)))
    func inviteGoesOnce() async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        let gate = Gate()
        api.beforeInvite = { await gate.wait() }
        let model = OnboardingCoordinator(state: AppState(env: .test(api: api)), apiStatus: APIStatus()) {}
        model.inviteCode = "RYFT-7K3M-QX9P"
        let first = Task { await model.redeemInvite() }
        #expect(await eventually { api.count("redeemInvite") == 1 && model.isWorking })

        let second = Outcome()
        let again = Task { second.value = await model.redeemInvite() }
        #expect(await eventually { second.value != nil || api.count("redeemInvite") > 1 })
        #expect(second.value == false && api.count("redeemInvite") == 1, "\(api.calls)")
        #expect(model.isWorking && model.errorMessage == nil, "the first is still out, and nothing was said")

        await gate.open()
        #expect(await first.value)
        await again.value
        #expect(api.count("redeemInvite") == 1)
    }

    @Test("Consent: a second Agree before the first answers sends nothing; the first goes through", .timeLimit(.minutes(1)))
    func consentGoesOnce() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let model = OnboardingCoordinator(state: AppState(env: .test(api: api)), apiStatus: APIStatus()) {}
        await model.check()
        #expect(model.policyVersion == MockData.policyVersion)
        let gate = Gate()
        api.beforeConsent = { await gate.wait() }
        let first = Task { await model.agree() }
        #expect(await eventually { api.count("consent") == 1 && model.isWorking })

        let second = Outcome()
        let again = Task { second.value = await model.agree() }
        #expect(await eventually { second.value != nil || api.count("consent") > 1 })
        #expect(second.value == false && api.count("consent") == 1, "\(api.calls)")
        #expect(model.isWorking && model.errorMessage == nil, "the first is still out, and nothing was said")

        await gate.open()
        #expect(await first.value)
        await again.value
        #expect(api.consentPosts == [MockData.policyVersion])
    }

    // MARK: another account (review code N6)

    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000D1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000D2") ?? UUID()

    /// Holds each call open until its own gate opens: the first on `gates[0]`, the second on `gates[1]`.
    private actor InOrder {
        let gates: [Gate]
        private var calls = 0

        init(_ count: Int) { gates = (0..<count).map { _ in Gate() } }

        func hold() async {
            let n = calls
            calls += 1
            guard n < gates.count else { return }
            await gates[n].wait()
        }
    }

    @Test("Another account: A's invite still out doesn't keep B's step busy, B's Continue sends, and A's late answer touches nothing of B's",
          .timeLimit(.minutes(1)), arguments: [true, false])
    func anotherAccountsStepIsntBusy(aCodeWorks: Bool) async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        let holds = InOrder(2)
        api.beforeInvite = { await holds.hold() }
        let client = MockAuthClient(session: .preview(id: Self.a))
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let model = OnboardingCoordinator(state: AppState(env: .test(api: api, auth: auth)), apiStatus: APIStatus()) {}
        model.switchAccount(auth.accountID)
        model.inviteCode = aCodeWorks ? "RYFT-7K3M-QX9P" : "RYFT-0000-0000"
        let first = Task { await model.redeemInvite() }
        #expect(await eventually { api.count("redeemInvite") == 1 && model.isWorking })

        // Straight from A to B, then the app's account-change handler (RyftApp).
        client.signInSession = .preview(id: Self.b)
        _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
        #expect(auth.accountID == Self.b.uuidString)
        model.switchAccount(auth.accountID)
        #expect(!model.isWorking, "B's step isn't busy with A's request")

        model.inviteCode = "RYFT-7K3M-QX9P"
        let second = Task { await model.redeemInvite() }
        #expect(await eventually { api.count("redeemInvite") == 2 && model.isWorking }, "B's Continue sends: \(api.calls)")

        // A's answer lands while B's request is out.
        await holds.gates[0].open()
        #expect(await first.value == false)
        #expect(model.isWorking, "B's request is still out")
        #expect(model.errorMessage == nil && model.errorDetails == nil, "nothing of A's on B's step")
        #expect(model.inviteCode == "RYFT-7K3M-QX9P", "B's code is still in the field")

        await holds.gates[1].open()
        #expect(await second.value)
        #expect(!model.isWorking && model.inviteCode.isEmpty)
        #expect(api.inviteAttempts == [aCodeWorks ? "RYFT-7K3M-QX9P" : "RYFT-0000-0000", "RYFT-7K3M-QX9P"])
    }
}
