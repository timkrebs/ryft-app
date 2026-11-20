import Foundation
import Testing
@testable import Ryft

/// PR 6 security review N-3: the invite code and the consent go once, however often Continue or Agree is asked for while the
/// first is out. The coordinator holds this itself (`OnboardingCoordinator.perform`), not only its busy pill. Synthetic data
/// only.
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
}
