import Foundation
import Testing
@testable import Ryft

/// PR 6 security review N-1: the invite field is the account's. A code A typed or a link filled in, sent or not, is gone
/// when A goes, so B never finds it and never redeems it; a link that arrived signed out, or before the launch's first
/// check, is still there for the account it's for. Each switch runs as RyftApp's account-change handler does it
/// (`switchAccount`, then the router's `openPending`). Synthetic data only.
@MainActor
@Suite("The invite field is the account's")
struct InviteFieldAccountTests {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-0000000000F1") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-0000000000F2") ?? UUID()
    static let code = "RYFT-7K3M-QX9P"

    /// An invite-gated platform, an auth that signs in as `signInAs` next, and the app's router for the coordinator.
    @MainActor
    struct Rig {
        let api: MockPlatformAPI
        let client: MockAuthClient
        let auth: AuthService
        let model: OnboardingCoordinator
        let router: DeepLinkRouter

        init(signedInAs account: UUID?) {
            let api = MockPlatformAPI()
            api.betaAccess = false
            self.api = api
            let client = account.map { MockAuthClient(session: .preview(id: $0)) } ?? MockAuthClient()
            self.client = client
            let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
            let auth = AuthService(client: client, settings: Settings(defaults: defaults), defaults: defaults,
                                   wipeLocalData: { _ in true },
                                   deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                                   postAppleAuthorization: { _ in })
            self.auth = auth
            let state = AppState(env: .test(api: api, auth: auth))
            model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
            router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state), onboarding: model)
        }

        /// Signs in as `account`, then RyftApp's account-change handler.
        func signIn(_ account: UUID) async {
            client.signInSession = .preview(id: account)
            _ = await auth.logIn(email: "alex@example.com", password: "0123456789")
            #expect(auth.accountID == account.uuidString)
            model.switchAccount(auth.accountID)
            router.openPending()
        }

        /// Signs out, then RyftApp's account-change handler.
        func signOut() async {
            await auth.signOut()
            #expect(!auth.isSignedIn)
            model.switchAccount(auth.accountID)
        }

        func openLink() async throws {
            #expect(await router.open(try #require(URL(string: "ryft://invite/\(InviteFieldAccountTests.code)"))))
        }
    }

    @Test("A code A typed and never sent is gone when A signs out: B finds an empty field, and Continue sends nothing")
    func aCodeANeverSentIsntB() async {
        let rig = Rig(signedInAs: Self.a)
        await rig.model.check()
        rig.model.inviteCode = Self.code
        await rig.signOut()
        #expect(rig.model.inviteCode.isEmpty, "signed out: nobody's code")

        await rig.signIn(Self.b)
        await rig.model.check()
        #expect(rig.model.inviteCode.isEmpty, "B's field is empty")
        #expect(await rig.model.redeemInvite() == false)
        #expect(rig.api.inviteAttempts.isEmpty, "A's code never goes out as B's: \(rig.api.calls)")
    }

    @Test("A link that arrived signed out fills the field of the account that signs in next, the first or after another's sign-out",
          arguments: [false, true])
    func aSignedOutLinkIsTheNextAccounts(afterAnother: Bool) async throws {
        let rig = Rig(signedInAs: afterAnother ? Self.a : nil)
        await rig.model.check()
        if afterAnother {
            rig.model.inviteCode = "RYFT-0000-0000"
            await rig.signOut()
        }
        try await rig.openLink()
        #expect(rig.router.pending == .invite(code: Self.code), "kept until someone signs in")
        #expect(rig.model.inviteCode.isEmpty)

        await rig.signIn(Self.b)
        #expect(rig.router.pending == nil)
        #expect(rig.model.inviteCode == Self.code, "the link's code, for the account now signed in")
        await rig.model.check()
        #expect(rig.model.inviteCode == Self.code, "the sign-in's check keeps it")
        #expect(await rig.model.redeemInvite())
        #expect(rig.api.inviteAttempts == [Self.code])
    }

    @Test("A link opened at launch, before the first check, stays for the account the app launched with")
    func aLaunchLinkStaysForTheLaunchAccount() async throws {
        let rig = Rig(signedInAs: Self.a)
        #expect(rig.auth.accountID == Self.a.uuidString, "the session restored at launch")
        try await rig.openLink()
        #expect(rig.router.pending == nil, "signed in: routed at once")
        #expect(rig.model.inviteCode == Self.code)
        // The launch's first check learns the account (nil → A): not another account's switch.
        await rig.model.check()
        #expect(rig.model.inviteCode == Self.code, "still the launch account's")
        #expect(await rig.model.redeemInvite())
        #expect(rig.api.inviteAttempts == [Self.code])
    }
}
