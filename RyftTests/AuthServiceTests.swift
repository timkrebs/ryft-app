import Foundation
import Testing
import Auth
@testable import Ryft

@Suite("Nonce")
struct NonceTests {
    @Test func randomHasLengthAndCharset() {
        let nonce = Nonce.random()
        #expect(nonce.count == 32)
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        #expect(nonce.allSatisfy(allowed.contains))
        #expect(Nonce.random(length: 64).count == 64)
    }

    @Test func randomIsFresh() {
        #expect(Nonce.random() != Nonce.random())
    }

    @Test func sha256IsLowercaseHex() {
        // FIPS 180-2 test vector.
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Nonce.sha256("").count == 64)
    }
}

/// AuthService state transitions against `MockAuthClient` (no network, no Keychain).
@MainActor
@Suite("AuthService")
struct AuthServiceTests {
    final class Wipes {
        var calls = 0
        var last: AuthService.Wipe?
    }

    private let defaults = UserDefaults(suiteName: "ryft.tests.\(UUID().uuidString)")!
    private let wipes = Wipes()

    final class AppleCodes { var sent: [String] = []; var error: Error? }
    private let appleCodes = AppleCodes()

    private static let deleted = AccountDeleted(status: "deleted", authUserDeleted: true, appleTokenRevoked: nil)

    private func make(_ client: MockAuthClient,
                      deleteRemote: @escaping () async throws -> AccountDeleted = { AuthServiceTests.deleted },
                      authEntry: AuthEntry = .legacy) -> AuthService {
        let wipes = self.wipes, codes = self.appleCodes
        // Developer API key mode lives in the simulator's real defaults; these tests are about sessions.
        Settings.shared.apiKeyMode = false
        return AuthService(client: client, defaults: defaults, wipeLocalData: { wipes.calls += 1; wipes.last = $0; return true },
                           deleteRemoteAccount: deleteRemote,
                           postAppleAuthorization: { code in
                               codes.sent.append(code)
                               if let e = codes.error { throw e }
                           }, authEntry: authEntry)
    }

    /// Lets the `authStateChanges` observation task run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private static func apiError(_ code: ErrorCode, status: Int) -> AuthError {
        .api(message: code.rawValue, errorCode: code, underlyingData: Data(),
             underlyingResponse: HTTPURLResponse(url: URL(string: "https://x.supabase.co")!, statusCode: status,
                                                 httpVersion: nil, headerFields: nil)!)
    }

    // MARK: launch

    @Test func restoresStoredSessionSynchronously() {
        let auth = make(MockAuthClient(session: .preview()))
        #expect(auth.isSignedIn)
        #expect(auth.accountID == Session.preview().user.id.uuidString)
        #expect(auth.provider == "apple")
        #expect(wipes.calls == 0)
    }

    @Test func noSessionMeansWelcome() {
        let auth = make(MockAuthClient())
        #expect(!auth.isSignedIn)
        #expect(auth.accountID == nil)
    }

    @Test func unconfiguredClientExplainsInsteadOfCrashing() async {
        Settings.shared.apiKeyMode = false
        let auth = AuthService(client: nil, defaults: defaults, wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AuthServiceTests.deleted })
        #expect(!auth.isConfigured)
        await auth.logIn(email: "a@b.de", password: "0123456789")
        #expect(auth.errorMessage != nil)
        #expect(!auth.isSignedIn)
    }

    // MARK: sign up / log in

    @Test func signUpWithSessionSignsIn() async {
        let client = MockAuthClient(signInSession: .preview(provider: "email"))
        let auth = make(client)
        let outcome = await auth.signUp(name: "  Alex Doe ", email: " Alex@Example.com ", password: "0123456789")
        #expect(outcome == .signedIn)
        #expect(auth.isSignedIn)
        #expect(auth.provider == "email")
        #expect(client.signUps.first?.email == "alex@example.com")
        #expect(client.signUps.first?.fullName == "Alex Doe")
    }

    @Test func signUpNeedingConfirmationWaitsForTheLink() async {
        let client = MockAuthClient()
        client.requiresEmailConfirmation = true
        let auth = make(client)
        let outcome = await auth.signUp(name: "Alex", email: "alex@example.com", password: "0123456789")
        #expect(outcome == .confirmEmail)
        #expect(!auth.isSignedIn)

        // The confirmation link opens the app and completes the session.
        #expect(await auth.handle(URL(string: "ryft://auth/callback?code=abc")!))
        #expect(auth.isSignedIn)
        #expect(!auth.needsNewPassword)
        #expect(client.openedLinks.count == 1)
    }

    @Test func logIn() async {
        let auth = make(MockAuthClient())
        #expect(await auth.logIn(email: "alex@example.com", password: "secret-password"))
        #expect(auth.isSignedIn)
        #expect(auth.errorMessage == nil)
    }

    @Test func wrongPasswordIsCalmAndRevealsNothing() async {
        let client = MockAuthClient()
        client.emailError = Self.apiError(.invalidCredentials, status: 400)
        let auth = make(client)
        #expect(await auth.logIn(email: "alex@example.com", password: "wrong") == false)
        #expect(!auth.isSignedIn)
        #expect(auth.errorMessage == "Email or password is wrong.")
    }

    @Test func networkErrorSaysSo() async {
        let client = MockAuthClient()
        client.emailError = URLError(.notConnectedToInternet)
        let auth = make(client)
        await auth.logIn(email: "alex@example.com", password: "whatever")
        #expect(auth.errorMessage == "No connection. Check your internet and try again.")
    }

    @Test func appleSignInSavesTheNameOnce() async {
        let client = MockAuthClient()
        let auth = make(client)
        var name = PersonNameComponents()
        name.givenName = "Alex"
        name.familyName = "Doe"
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: name)
        #expect(auth.isSignedIn)
        #expect(client.savedFullNames == ["Alex Doe"])
        #expect(client.refreshCount == 1) // the new token carries full_name

        // Later authorisations don't include the name.
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: nil)
        #expect(client.savedFullNames.count == 1)
    }

    // MARK: Google OAuth and the account transition

    @Test func authEntryDefaultsToLegacyAndSocialHidesEmail() {
        #expect(AuthEntry(nil) == .legacy)
        #expect(AuthEntry("unknown") == .legacy)
        #expect(!AuthEntry.legacy.googleEnabled && AuthEntry.legacy.emailEnabled)
        #expect(AuthEntry.transition.googleEnabled && AuthEntry.transition.emailEnabled)
        #expect(AuthEntry.social.googleEnabled && !AuthEntry.social.emailEnabled)
    }

    @Test func googleOnlyExchangesTheActivePKCECallback() async {
        let client = MockAuthClient(signInSession: .preview(provider: "google"))
        let auth = make(client, authEntry: .social)
        let callback = URL(string: "ryft://auth/oauth/callback?code=test-code")!
        #expect(await auth.handle(callback))
        #expect(await auth.handle(URL(string: "ryft://auth/callback?code=old-email-code")!))
        #expect(client.openedLinks.isEmpty)
        #expect(await auth.continueWithGoogle { _ in callback })
        #expect(client.googleLinkRequests == [false])
        #expect(client.openedLinks == [callback] && auth.provider == "google" && !auth.needsNewPassword)
    }

    @Test func malformedCancelledAndDisabledGoogleFlowsDoNotExchange() async {
        let legacy = MockAuthClient()
        #expect(await make(legacy).continueWithGoogle { _ in
            Issue.record("Disabled Google opened the browser")
            throw CancellationError()
        } == false)
        #expect(legacy.googleLinkRequests.isEmpty)

        let client = MockAuthClient()
        let auth = make(client, authEntry: .transition)
        let wrongPath = URL(string: "ryft://auth/callback?code=test-code")!
        let duplicate = URL(string: "ryft://auth/oauth/callback?code=one&code=two")!
        let injection = URL(string: "ryft://auth/oauth/callback?code=one&access_token=unexpected")!
        for url in [wrongPath, duplicate, injection] {
            #expect(await auth.continueWithGoogle { _ in url } == false)
        }
        #expect(await auth.continueWithGoogle { _ in throw CancellationError() } == false)
        #expect(auth.errorMessage == nil && client.openedLinks.isEmpty && !auth.isSignedIn)
    }

    @Test func explicitGoogleLinkKeepsTheEmailAccountsUUID() async {
        let before = Session.preview(provider: "email")
        let client = MockAuthClient(session: before, signInSession: .preview(id: before.user.id))
        client.methods.append(.init(provider: "google", email: "different@example.com", addedAt: nil))
        let auth = make(client, authEntry: .transition)
        let callback = URL(string: "ryft://auth/oauth/callback?code=test-code")!
        #expect(await auth.continueWithGoogle(linking: true) { _ in callback })
        #expect(client.googleLinkRequests == [true])
        #expect(auth.accountID == before.user.id.uuidString && auth.hasGoogleSignIn && wipes.calls == 0)
    }

    @Test func accountSwitchWhileGoogleLinkIsOpenStopsBeforeExchange() async {
        let client = MockAuthClient(session: .preview(provider: "email"))
        let auth = make(client, authEntry: .transition)
        let other = Session.preview(id: UUID(), provider: "email")
        let callback = URL(string: "ryft://auth/oauth/callback?code=test-code")!
        #expect(await auth.continueWithGoogle(linking: true) { _ in
            client.emit(.signedIn, other)
            return callback
        } == false)
        await settle()
        #expect(client.googleLinkRequests == [true] && client.openedLinks.isEmpty)
        #expect(auth.accountID == other.user.id.uuidString && auth.linkError == nil)
    }

    @Test func unexpectedSubjectFromGoogleLinkIsDiscardedBeforePublication() async {
        let before = Session.preview(provider: "email")
        let other = Session.preview(id: UUID(), provider: "google")
        let client = MockAuthClient(session: before, signInSession: other)
        let auth = make(client, authEntry: .transition)
        var published: [String] = []
        auth.onAccountWillChange = { _, to, _ in if let to { published.append(to) } }
        let callback = URL(string: "ryft://auth/oauth/callback?code=test-code")!
        #expect(await auth.continueWithGoogle(linking: true) { _ in callback } == false)
        await settle()
        #expect(client.openedLinks == [callback] && client.currentSession == nil)
        #expect(auth.accountID == nil && published.isEmpty)
    }

    @Test func googleStartsOnlyFromTheConfiguredAuthorizationService() {
        let auth = URL(string: "https://auth.example.invalid/auth/v1")!
        #expect(GoogleOAuth.acceptsAuthorization(auth.appendingPathComponent("authorize"), authURL: auth))
        #expect(GoogleOAuth.acceptsAuthorization(URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!, authURL: auth))
        for value in [
            "http://auth.example.invalid/auth/v1/authorize",
            "https://auth.example.invalid/unrelated",
            "https://accounts.google.com.other.invalid/",
            "https://accounts.google.com:8443/",
            "https://name@accounts.google.com/",
        ] {
            #expect(!GoogleOAuth.acceptsAuthorization(URL(string: value)!, authURL: auth))
        }
    }

    // MARK: password reset

    @Test func resetLinkAsksForNewPassword() async {
        let client = MockAuthClient()
        let auth = make(client)
        #expect(await auth.sendPasswordReset(email: "Alex@example.com"))
        #expect(client.resetEmails == ["alex@example.com"])

        await auth.handle(URL(string: "ryft://auth/callback?code=xyz")!)
        #expect(auth.isSignedIn)
        #expect(auth.needsNewPassword)

        #expect(await auth.updatePassword("a-new-password"))
        #expect(!auth.needsNewPassword)
        #expect(client.updatedPasswords == ["a-new-password"])
    }

    @Test func expiredLinkExplains() async {
        let client = MockAuthClient()
        client.emailError = AuthError.pkceGrantCodeExchange(message: "otp_expired")
        let auth = make(client)
        await auth.handle(URL(string: "ryft://auth/callback?error=access_denied&error_code=otp_expired")!)
        #expect(!auth.isSignedIn)
        #expect(auth.errorMessage == "This link has expired or was already used. Request a new one.")
    }

    @Test func foreignURLsAreIgnored() async {
        let client = MockAuthClient()
        let auth = make(client)
        #expect(await auth.handle(URL(string: "https://example.com/auth/callback?code=1")!) == false)
        #expect(await auth.handle(URL(string: "https://ryftlab.de/privacy")!) == false)
        #expect(client.openedLinks.isEmpty)
    }

    @Test func universalLinkCallbackIsHandled() async {
        let client = MockAuthClient()
        let auth = make(client)
        #expect(await auth.handle(URL(string: "https://ryftlab.de/auth/callback?code=1")!))
        #expect(client.openedLinks.count == 1)
    }

    // MARK: sign out, account changes

    @Test func logOutWipesLocalData() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await auth.signOut()
        #expect(!auth.isSignedIn)
        #expect(client.signOutCount == 1)
        #expect(wipes.calls == 1)
    }

    @Test func revokedSessionFromTheSDKSignsOut() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await settle()
        client.emit(.signedOut, nil)
        await settle()
        #expect(!auth.isSignedIn)
        #expect(wipes.calls == 1)
    }

    @Test func differentAccountStartsFromScratch() async {
        let first = make(MockAuthClient(session: .preview(id: UUID())))
        _ = first // remembers its user ID in `defaults`
        #expect(wipes.calls == 0)
        _ = make(MockAuthClient(session: .preview(id: UUID())))
        #expect(wipes.calls == 1)
    }

    @Test func authFailureOnTokenSignsOut() async {
        let client = MockAuthClient(session: .preview())
        client.validSessionError = AuthError.sessionMissing
        let auth = make(client)
        await #expect(throws: APIError.self) { try await auth.accessToken() }
        #expect(!auth.isSignedIn)
    }

    @Test func supabaseOutageKeepsTheSession() async {
        let client = MockAuthClient(session: .preview())
        client.validSessionError = Self.apiError(.unexpectedFailure, status: 503)
        let auth = make(client)
        await #expect(throws: AuthError.self) { try await auth.accessToken() }
        #expect(auth.isSignedIn)
    }

    /// A refresh failure that keeps the session is transient for the read pipeline; one that ends
    /// it never reaches it (it becomes `APIError.signedOut`).
    @Test func refreshFailuresThatKeepTheSessionAreTransient() {
        #expect(FailureKind.of(Self.apiError(.unexpectedFailure, status: 503)) == .transient)
        #expect(FailureKind.of(Self.apiError(.overRequestRateLimit, status: 429)) == .transient)
        #expect(FailureKind.of(Self.apiError(.unexpectedFailure, status: 408)) == .transient)
        #expect(FailureKind.of(AuthError.refreshDiscarded) == .transient)
        #expect(FailureKind.of(Self.apiError(.refreshTokenNotFound, status: 400)) == .other)
    }

    @Test func refreshedTokenIsReturned() async throws {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        #expect(try await auth.accessToken() == "preview-token")
        #expect(try await auth.refreshedAccessToken() == "refreshed-token")
    }

    @Test func theSDKBearerMustStillBelongToThePublishedAccount() async {
        let departing = Session.preview(id: UUID())
        let incoming = Session.preview(id: UUID())
        let client = MockAuthClient(session: departing)
        let auth = make(client)

        // The SDK has persisted the new session but has not yet delivered its signed-in event.
        client.unlock(incoming)
        await #expect(throws: CancellationError.self) { try await auth.accessToken() }
        await #expect(throws: CancellationError.self) { try await auth.refreshedAccessToken() }
        #expect(auth.accountID == departing.user.id.uuidString)
        #expect(client.refreshCount == 0)
        #expect(client.signOutCount == 0)
    }

    @Test func accountBoundRequestOnlyUsesTheConfirmingAccountsBearer() async throws {
        let departing = Session.preview(id: UUID())
        let incoming = Session.preview(id: UUID())
        let client = MockAuthClient(session: departing, signInSession: incoming)
        let auth = make(client)
        let env = AppEnvironment.test(auth: auth)
        let binding = AccountBinding(env)

        let token = try await auth.withBoundAccount(binding) { try await auth.accessToken() }
        #expect(token == "preview-token")
        await #expect(throws: CancellationError.self) {
            try await auth.withBoundAccount(binding) {
                _ = await auth.handle(SupabaseConfig.redirectURL)
                return try await auth.accessToken()
            }
        }
        var started = false
        await #expect(throws: CancellationError.self) {
            try await auth.withBoundAccount(binding) { started = true }
        }
        #expect(!started)
        #expect(auth.accountID == incoming.user.id.uuidString)
    }

    // MARK: delete account

    @Test func confirmedDeletionStopsIfPushCleanupChangesTheAccount() async {
        let departing = Session.preview(id: UUID())
        let incoming = Session.preview(id: UUID())
        let client = MockAuthClient(session: departing, signInSession: incoming)
        var deletions = 0
        let auth = make(client) {
            deletions += 1
            return AuthServiceTests.deleted
        }
        auth.beforeSignOut = { _ = await auth.handle(SupabaseConfig.redirectURL) }

        #expect(await auth.deleteAccount() == false)
        #expect(deletions == 0)
        #expect(auth.accountID == incoming.user.id.uuidString)
        #expect(client.signOutCount == 0)
    }

    @Test func confirmedDeletionCannotUseTheNewAccountsBearer() async {
        let departing = Session.preview(id: UUID())
        let incoming = Session.preview(id: UUID())
        let client = MockAuthClient(session: departing, signInSession: incoming)
        var auth: AuthService!
        var deletions = 0
        auth = make(client) {
            // The asynchronous API path has started, before it obtains its bearer.
            _ = await auth.handle(SupabaseConfig.redirectURL)
            _ = try await auth.accessToken()
            deletions += 1
            return AuthServiceTests.deleted
        }

        #expect(await auth.deleteAccount() == false)
        #expect(deletions == 0)
        #expect(auth.accountID == incoming.user.id.uuidString)
        #expect(client.signOutCount == 0)
    }

    @Test func deleteAccountThenLogsOut() async {
        var deleted = false
        let client = MockAuthClient(session: .preview())
        let auth = make(client) {
            deleted = true
            return AuthServiceTests.deleted
        }
        #expect(await auth.deleteAccount())
        #expect(deleted)
        #expect(!auth.isSignedIn)
        #expect(wipes.calls == 1)
        #expect(auth.signOutNotice == "Your RYFT account and data are deleted.")
    }

    @Test func deletionFinishingInTheBackgroundSaysSo() async {
        let auth = make(MockAuthClient(session: .preview())) {
            AccountDeleted(status: "deleted", authUserDeleted: false, appleTokenRevoked: false)
        }
        #expect(await auth.deleteAccount())
        #expect(auth.signOutNotice == "Your RYFT data is deleted. Removing the sign-in will finish in the background.")
    }

    @Test func failedDeleteKeepsTheAccount() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client) { throw APIError.http(503, "database unavailable", requestID: "rid-1") }
        #expect(await auth.deleteAccount() == false)
        #expect(auth.isSignedIn)
        #expect(client.signOutCount == 0)
        #expect(auth.errorMessage == "RYFT couldn't delete your account just now. Nothing was deleted. Try again in a moment.")
        #expect(auth.errorDetails == "HTTP 503 · Request ID rid-1")
    }

    // MARK: state, notices, Apple code

    @Test func storedSessionIsSignedInWithoutSplash() {
        let auth = make(MockAuthClient(session: .preview()))
        #expect(auth.state == .signedIn)
    }

    @Test func noStoredSessionRestoresThenSignsOut() async {
        let auth = make(MockAuthClient())
        #expect(auth.state == .restoring)
        await settle()
        #expect(auth.state == .signedOut)
    }

    @Test func lateInitialEventDoesNotUndoASignOut() async {
        let client = MockAuthClient(session: .preview())
        client.validSessionError = AuthError.sessionMissing
        let auth = make(client)
        _ = try? await auth.accessToken() // ends the session before the observation task runs
        await settle()
        #expect(auth.state == .signedOut)
    }

    @Test func expiredSessionSignsOutWithANotice() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await auth.rejectedAfterRefresh()
        #expect(auth.state == .signedOut)
        #expect(auth.signOutNotice == "You were signed out. Log in again to continue.")
    }

    @Test func revokedRefreshTokenShowsTheNotice() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await settle()
        client.emit(.signedOut, nil)
        // The observation task runs on its own schedule; on a loaded CI runner 20 yields aren't always enough.
        for _ in 0..<200 where auth.state != .signedOut || auth.signOutNotice == nil {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(auth.state == .signedOut)
        #expect(auth.signOutNotice != nil)
    }

    @Test func aWipeSaysWhyAndOnlyAnExpiryParks() async {
        let id = Session.preview().user.id.uuidString
        let auth = make(MockAuthClient(session: .preview()))
        await auth.rejectedAfterRefresh()
        #expect(wipes.calls == 1)
        #expect(wipes.last?.reason == .sessionExpired && wipes.last?.account == id && wipes.last?.parking == id)
        #expect(AuthService.Wipe(reason: .user, account: id).parking == nil)
        #expect(AuthService.Wipe(reason: .accountDeleted(background: true), account: id).parking == nil)
        #expect(AuthService.Wipe(reason: nil, account: id).parking == nil)
    }

    @Test func aUserLogOutIsNotReadAsAnExpiry() async {
        let auth = make(MockAuthClient(session: .preview()))
        await settle()
        await auth.signOut() // the SDK's own `.signedOut` event may be applied first
        await settle()
        #expect(wipes.calls == 1 && wipes.last?.reason == .user && wipes.last?.parking == nil)
    }

    @Test func ordinaryLogOutHasNoNotice() async {
        let auth = make(MockAuthClient(session: .preview()))
        await settle()
        await auth.signOut()
        await settle()
        #expect(auth.signOutNotice == nil)
    }

    @Test func noticeClearsOnTheNextSignIn() async {
        let auth = make(MockAuthClient(session: .preview()))
        await auth.rejectedAfterRefresh()
        #expect(await auth.logIn(email: "alex@example.com", password: "correct horse battery"))
        #expect(auth.signOutNotice == nil)
    }

    @Test func appleSignInSendsTheAuthorizationCodeOnce() async {
        let auth = make(MockAuthClient())
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: nil, authorizationCode: "c1b2")
        #expect(auth.isSignedIn)
        #expect(appleCodes.sent == ["c1b2"])
    }

    @Test func rejectedAppleCodeIsIgnored() async {
        appleCodes.error = APIError.http(422, "code expired")
        let auth = make(MockAuthClient())
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: nil, authorizationCode: "used")
        #expect(auth.isSignedIn) // carry on; deletion just can't revoke at Apple
        #expect(auth.errorMessage == nil)
        #expect(appleCodes.sent == ["used"])
    }

    @Test func failedAppleSignInSendsNoCode() async {
        let client = MockAuthClient()
        client.emailError = nil
        client.signInError = AuthError.sessionMissing
        let auth = make(client)
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: nil, authorizationCode: "c")
        #expect(!auth.isSignedIn)
        #expect(appleCodes.sent.isEmpty)
    }
}
