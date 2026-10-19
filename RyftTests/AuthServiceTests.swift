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
    final class Wipes { var count = 0 }

    private let defaults = UserDefaults(suiteName: "ryft.tests.\(UUID().uuidString)")!
    private let wipes = Wipes()

    final class AppleCodes { var sent: [String] = []; var error: Error? }
    private let appleCodes = AppleCodes()

    private static let deleted = AccountDeleted(status: "deleted", authUserDeleted: true, appleTokenRevoked: nil)

    private func make(_ client: MockAuthClient,
                      deleteRemote: @escaping () async throws -> AccountDeleted = { AuthServiceTests.deleted }) -> AuthService {
        let wipes = self.wipes, codes = self.appleCodes
        // Developer API key mode lives in the simulator's real defaults; these tests are about sessions.
        Settings.shared.apiKeyMode = false
        return AuthService(client: client, defaults: defaults, wipeLocalData: { wipes.count += 1 },
                           deleteRemoteAccount: deleteRemote,
                           postAppleAuthorization: { code in
                               codes.sent.append(code)
                               if let e = codes.error { throw e }
                           })
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
        #expect(wipes.count == 0)
    }

    @Test func noSessionMeansWelcome() {
        let auth = make(MockAuthClient())
        #expect(!auth.isSignedIn)
        #expect(auth.accountID == nil)
    }

    @Test func unconfiguredClientExplainsInsteadOfCrashing() async {
        Settings.shared.apiKeyMode = false
        let auth = AuthService(client: nil, defaults: defaults, wipeLocalData: {},
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
        let outcome = await auth.signUp(name: "  Tim Krebs ", email: " Tim@Example.com ", password: "0123456789")
        #expect(outcome == .signedIn)
        #expect(auth.isSignedIn)
        #expect(auth.provider == "email")
        #expect(client.signUps.first?.email == "tim@example.com")
        #expect(client.signUps.first?.fullName == "Tim Krebs")
    }

    @Test func signUpNeedingConfirmationWaitsForTheLink() async {
        let client = MockAuthClient()
        client.requiresEmailConfirmation = true
        let auth = make(client)
        let outcome = await auth.signUp(name: "Tim", email: "tim@example.com", password: "0123456789")
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
        #expect(await auth.logIn(email: "tim@example.com", password: "secret-password"))
        #expect(auth.isSignedIn)
        #expect(auth.errorMessage == nil)
    }

    @Test func wrongPasswordIsCalmAndRevealsNothing() async {
        let client = MockAuthClient()
        client.emailError = Self.apiError(.invalidCredentials, status: 400)
        let auth = make(client)
        #expect(await auth.logIn(email: "tim@example.com", password: "wrong") == false)
        #expect(!auth.isSignedIn)
        #expect(auth.errorMessage == "Email or password is wrong.")
    }

    @Test func networkErrorSaysSo() async {
        let client = MockAuthClient()
        client.emailError = URLError(.notConnectedToInternet)
        let auth = make(client)
        await auth.logIn(email: "tim@example.com", password: "whatever")
        #expect(auth.errorMessage == "No connection. Check your internet and try again.")
    }

    @Test func appleSignInSavesTheNameOnce() async {
        let client = MockAuthClient()
        let auth = make(client)
        var name = PersonNameComponents()
        name.givenName = "Tim"
        name.familyName = "Krebs"
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: name)
        #expect(auth.isSignedIn)
        #expect(client.savedFullNames == ["Tim Krebs"])
        #expect(client.refreshCount == 1) // the new token carries full_name

        // Later authorisations don't include the name.
        await auth.signInWithApple(idToken: "id", nonce: "n", fullName: nil)
        #expect(client.savedFullNames.count == 1)
    }

    // MARK: password reset

    @Test func resetLinkAsksForNewPassword() async {
        let client = MockAuthClient()
        let auth = make(client)
        #expect(await auth.sendPasswordReset(email: "Tim@example.com"))
        #expect(client.resetEmails == ["tim@example.com"])

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
        #expect(await auth.handle(URL(string: "https://ryftapp.de/privacy")!) == false)
        #expect(client.openedLinks.isEmpty)
    }

    @Test func universalLinkCallbackIsHandled() async {
        let client = MockAuthClient()
        let auth = make(client)
        #expect(await auth.handle(URL(string: "https://ryftapp.de/auth/callback?code=1")!))
        #expect(client.openedLinks.count == 1)
    }

    // MARK: sign out, account changes

    @Test func logOutWipesLocalData() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await auth.signOut()
        #expect(!auth.isSignedIn)
        #expect(client.signOutCount == 1)
        #expect(wipes.count == 1)
    }

    @Test func revokedSessionFromTheSDKSignsOut() async {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        await settle()
        client.emit(.signedOut, nil)
        await settle()
        #expect(!auth.isSignedIn)
        #expect(wipes.count == 1)
    }

    @Test func differentAccountStartsFromScratch() async {
        let first = make(MockAuthClient(session: .preview(id: UUID())))
        _ = first // remembers its user ID in `defaults`
        #expect(wipes.count == 0)
        _ = make(MockAuthClient(session: .preview(id: UUID())))
        #expect(wipes.count == 1)
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

    @Test func refreshedTokenIsReturned() async throws {
        let client = MockAuthClient(session: .preview())
        let auth = make(client)
        #expect(try await auth.accessToken() == "preview-token")
        #expect(try await auth.refreshedAccessToken() == "refreshed-token")
    }

    // MARK: delete account

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
        #expect(wipes.count == 1)
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
        await settle()
        #expect(auth.state == .signedOut)
        #expect(auth.signOutNotice != nil)
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
        #expect(await auth.logIn(email: "tim@example.com", password: "correct horse battery"))
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
