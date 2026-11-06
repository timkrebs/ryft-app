// Who the caller is. Supabase Auth signs the user in with Apple (native
// ASAuthorization flow, no web view); the SDK persists the session in the
// Keychain and refreshes it, and every platform request carries its access
// token as the bearer (see APIClient). The app never stores tokens itself.
import AuthenticationServices
import CryptoKit
import Foundation
import GameplayKit
import Observation
import Auth

// MARK: - SDK seam

/// The Supabase calls the app makes, so tests and previews run without the
/// network. `SupabaseAuthClient` is the live implementation.
protocol AuthClientProtocol: Sendable {
    /// The stored session (possibly expired), read synchronously from the Keychain.
    var currentSession: Session? { get }
    /// Emits `.initialSession` first, then every sign-in, refresh and sign-out.
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> { get }
    /// A valid session; the SDK refreshes an expired one.
    func validSession() async throws -> Session
    /// Refreshes regardless of expiry (after the platform answered 401).
    func refreshSession() async throws -> Session
    func signInWithApple(idToken: String, nonce: String) async throws -> Session
    /// Stores the name as `user_metadata.full_name`.
    func setFullName(_ name: String) async throws
    /// `nil` session when the project requires email confirmation first.
    func signUp(email: String, password: String, fullName: String, redirectTo: URL) async throws -> Session?
    func signIn(email: String, password: String) async throws -> Session
    func resendSignUpConfirmation(email: String, redirectTo: URL) async throws
    func resetPassword(email: String, redirectTo: URL) async throws
    func updatePassword(_ password: String) async throws
    /// Completes a confirmation or reset link (PKCE code exchange).
    func session(from url: URL) async throws -> Session
    /// Removes the local session first, then revokes it on the server.
    func signOut() async throws
    /// The account's sign-in methods (Supabase identities: `apple`, `email`).
    func identities() async throws -> [SignInMethod]
    /// Adds Sign in with Apple to the signed-in account (Supabase "Manual Linking" must be on).
    func linkApple(idToken: String, nonce: String) async throws -> Session
}

/// One way into the account (a Supabase identity), for Profile → Sign-in methods.
struct SignInMethod: Hashable, Identifiable, Sendable {
    /// `apple`, `email`, …
    let provider: String
    /// The identity's email (an Apple private relay address, possibly).
    let email: String?
    let addedAt: Date?
    var id: String { provider + (email ?? "") }

    init(provider: String, email: String?, addedAt: Date?) {
        self.provider = provider
        self.email = email
        self.addedAt = addedAt
    }

    init(_ identity: UserIdentity) {
        var email: String?
        if case .string(let e) = identity.identityData?["email"] { email = e }
        self.init(provider: identity.provider, email: email, addedAt: identity.createdAt)
    }
}

struct SupabaseAuthClient: AuthClientProtocol {
    let client: AuthClient

    init(config: SupabaseConfig) {
        client = AuthClient(url: config.authURL,
                            headers: ["apikey": config.publishableKey],
                            flowType: .pkce,                      // links come back as ryft://auth/callback?code=…
                            redirectToURL: SupabaseConfig.redirectURL,
                            localStorage: KeychainLocalStorage(), // AfterFirstUnlock: readable in background sync
                            emitLocalSessionAsInitialSession: true)
    }

    var currentSession: Session? { client.currentSession }
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> { client.authStateChanges }
    func validSession() async throws -> Session { try await client.session }
    func refreshSession() async throws -> Session { try await client.refreshSession() }

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await client.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func setFullName(_ name: String) async throws {
        _ = try await client.update(user: UserAttributes(data: ["full_name": .string(name)]))
    }

    func signUp(email: String, password: String, fullName: String, redirectTo: URL) async throws -> Session? {
        let response = try await client.signUp(email: email, password: password,
                                               data: ["full_name": .string(fullName)], redirectTo: redirectTo)
        return response.session
    }

    func signIn(email: String, password: String) async throws -> Session {
        try await client.signIn(email: email, password: password)
    }

    func resendSignUpConfirmation(email: String, redirectTo: URL) async throws {
        try await client.resend(email: email, type: .signup, emailRedirectTo: redirectTo)
    }

    func resetPassword(email: String, redirectTo: URL) async throws {
        try await client.resetPasswordForEmail(email, redirectTo: redirectTo)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.update(user: UserAttributes(password: password))
    }

    func session(from url: URL) async throws -> Session { try await client.session(from: url) }

    func signOut() async throws { try await client.signOut(scope: .local) }

    func identities() async throws -> [SignInMethod] {
        try await client.userIdentities().map(SignInMethod.init)
    }

    func linkApple(idToken: String, nonce: String) async throws -> Session {
        try await client.linkIdentityWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }
}

// MARK: - nonce

/// Sign in with Apple replay protection: Apple gets SHA-256(nonce) in the
/// request and echoes it in the ID token; Supabase gets the raw nonce and
/// checks that its hash matches.
enum Nonce {
    // 64 characters (no "W", as in Apple's and Supabase's samples), so a byte maps uniformly.
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in rng.next() }
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// Lower-case hex SHA-256, the format Apple's `request.nonce` expects.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - service

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService(client: SupabaseConfig.current.map(SupabaseAuthClient.init(config:)),
                                    ledger: .live)

    /// Accounts need at least this many characters (the Supabase project's
    /// minimum must not be higher).
    nonisolated static let minimumPasswordLength = 10

    /// What `RootView` switches on.
    enum State: Equatable {
        /// The SDK hasn't reported the stored session yet: splash, no Welcome flash.
        case restoring
        case signedOut
        case signedIn
    }

    /// Why the account ended, for the one-line notice on Welcome.
    enum SignOutReason: Equatable, Codable {
        case user
        /// A second 401, a revoked refresh token, or a deleted account elsewhere.
        case sessionExpired
        /// `DELETE /v1/me` succeeded; `background` when Supabase still has to finish.
        case accountDeleted(background: Bool)
    }

    /// One wipe of this phone's per-account data, and what it keeps (design.md §8.4).
    struct Wipe: Equatable {
        /// Why the session ended; nil when another account's session replaced it.
        var reason: SignOutReason?
        /// The account that's leaving, when known.
        let account: String?
        /// When this wipe was first owed: parked rows carry it as `parkedAt`, so a retry doesn't restart their 30 days.
        var since = Date()
        /// The device steps are done: a retry runs only the store step.
        var storeOnly = false

        /// Whose activities, manual sleep and privacy zones stay, parked and bound to their account for 30 days:
        /// the leaving account's after a session expiry (it may sign in again), nobody's otherwise.
        var parking: String? { reason == .sessionExpired ? account : nil }
    }

    private(set) var session: Session?
    private(set) var user: Auth.User?
    /// The session's phase (`AuthMachine`): restoring → signedOut / signingIn / signedIn
    /// / refreshing / expired. `state` is the coarser view `RootView` switches on.
    private(set) var phase: AuthPhase = .restoring
    @ObservationIgnored private var machine: GKTableMachine<AuthPhase>!
    /// The SDK hasn't reported the stored session yet.
    var isRestoring: Bool { phase == .restoring }
    /// Shown once on Welcome after a sign-out the user didn't ask for (or a deletion).
    var signOutNotice: String?
    /// Runs before a user-initiated sign-out and before account deletion, while
    /// the session still works (RyftApp: delete the push registration).
    @ObservationIgnored var beforeSignOut: (@MainActor () async -> Void)?
    /// Runs when the account changes (signed in, signed out, another account), before the new session (or none) is
    /// published: so before `accountID` observers, the first upload and the first read. `from` and `to` are the
    /// accounts; `reason` says why `from`'s session ended (nil for a sign-in). Activities purge other accounts' rows
    /// by `to` here (design.md §8.4); it doesn't rely on `lastUserKey`, which a sign-out removes unless its wipe failed.
    @ObservationIgnored var onAccountWillChange: (@MainActor (_ from: String?, _ to: String?, _ reason: SignOutReason?) -> Void)?
    /// Runs inside every wipe, right after the local data went: services stop the leaving account's work now, not a
    /// runloop later when the app's account-change handler runs.
    @ObservationIgnored var onWipe: (@MainActor (Wipe) -> Void)?
    /// Why the session is ending, from `signOut(reason:)` until it's applied: the SDK's own `.signedOut` event may
    /// arrive first.
    @ObservationIgnored private var endingReason: SignOutReason?
    /// Runs as an in-app account deletion starts, before the platform is asked: the account's uploads stop.
    @ObservationIgnored var onAccountDeletionStart: (@MainActor () -> Void)?
    /// The account `deleteAccount()` is deleting, while it runs. That account's session ending meanwhile (a
    /// concurrent final 401 or refresh failure) ends as the deletion: nothing of it is parked.
    private var deletingAccount: String?
    /// The signed-in account is being deleted: nothing more is uploaded for it. False for another account that
    /// signed in while an earlier one's deletion still runs.
    var isDeletingAccount: Bool { deletingAccount != nil && deletingAccount == accountID }
    /// Counts account changes (sign-in, sign-out, another account): work bound to an account checks it, so A, then
    /// B, then A again while it ran doesn't pass for "still A".
    @ObservationIgnored private(set) var accountChanges = 0
    /// A call that isn't a sign-in is running (reset link, new password, deletion).
    private var otherWork = false
    /// Busy: buttons show a spinner.
    var isWorking: Bool { phase == .signingIn || otherWork }
    var errorMessage: String?
    /// Status and request ID when a platform call (Delete account) failed.
    private(set) var errorDetails: String?
    /// A password-reset link was opened: show "Set new password".
    var needsNewPassword = false

    /// `nil` when Supabase isn't configured (see `SupabaseConfig.problem`).
    private let client: AuthClientProtocol?
    private let settings: Settings
    private let defaults: UserDefaults
    /// Per-user local state to drop when the account ends or changes: cached
    /// responses, HealthKit anchors, per-user defaults; after an expiry, all but
    /// what `Wipe.parking` keeps. AppState resets itself on `accountID` changes. False when the store may still hold
    /// the data: `lastUserKey` then keeps the account, so the next sign-in as another one wipes again.
    private let wipeLocalData: @MainActor (Wipe) -> Bool
    /// The wipe that was started and hasn't finished.
    private let ledger: WipeLedger
    /// Dates the ledger's entries.
    private let now: () -> Date
    /// This launch took an owed wipe up: what a wipe at launch can't reach still has to follow (`finishOwedWipe`).
    @ObservationIgnored private var resumedOwedWipe = false
    /// The ledger's retry had its one try in this process: another would only find the same refusal.
    @ObservationIgnored private var triedOwedWipe = false
    /// An interrupted sign-out's `client.signOut()` hasn't returned. The entry outlives a wipe meanwhile: without it a
    /// kill here would publish the session at the next launch.
    @ObservationIgnored private var endingStoredSession = false
    /// A wipe returned true while that ran, so the entry ends with it.
    @ObservationIgnored private var wipedWhileEnding = false
    /// `DELETE /v1/me`; injected so tests don't need the platform.
    private let deleteRemoteAccount: () async throws -> AccountDeleted
    /// `POST /v1/me/apple-authorization`; injected for tests.
    private let postAppleAuthorization: (String) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    private var pendingNonce: String?

    init(client: AuthClientProtocol?, settings: Settings = .shared, defaults: UserDefaults = .standard,
         wipeLocalData: @escaping @MainActor (Wipe) -> Bool = AuthService.wipeSharedLocalData,
         deleteRemoteAccount: @escaping () async throws -> AccountDeleted = { try await APIClient.shared.deleteMe() },
         postAppleAuthorization: @escaping (String) async throws -> Void = { try await APIClient.shared.postAppleAuthorization(code: $0) },
         ledger: WipeLedger? = nil, now: @escaping () -> Date = { Date() }) {
        self.client = client
        self.settings = settings
        self.defaults = defaults
        self.wipeLocalData = wipeLocalData
        self.deleteRemoteAccount = deleteRemoteAccount
        self.postAppleAuthorization = postAppleAuthorization
        self.ledger = ledger ?? WipeLedger(file: nil)
        self.now = now
        machine = AuthMachine.make { [weak self] to, _ in self?.phase = to }
        // Read the Keychain synchronously so a relaunch goes straight to Today; the
        // SDK refreshes an expired token in the background. Without a stored session
        // the splash stays until the SDK's first event (or a short timeout).
        let (stored, endsStoredSession) = resumeOwedWipe(stored: client?.currentSession)
        apply(stored)
        guard let client else {
            machine.enter(.signedOut)
            return
        }
        // Not restoring: an interrupted sign-out's session is never published, whatever the SDK reports for it.
        if endsStoredSession { machine.enter(.signedOut) }
        observation = Task { [weak self] in
            // Before the first event, so that none of them can carry the session this ends.
            if endsStoredSession {
                try? await client.signOut()
                self?.storedSessionEnded()
            }
            for await change in client.authStateChanges {
                guard let self else { return }
                if change.event == .initialSession {
                    // Only ends restoring: the stored session was applied above, and a
                    // late initial event must not undo a sign-out that happened since.
                    if self.isRestoring, let s = change.session { self.apply(s) }
                    if self.isRestoring { self.machine.enter(.signedOut) }
                    continue
                }
                // The SDK ended a session nobody signed out of: it expired. (A sign-out
                // the app started has already left `signedIn`, so it isn't read as one.)
                var reason: SignOutReason?
                if change.session == nil, self.session != nil, self.phase == .signedIn || self.phase == .refreshing {
                    self.signOutNotice = SignOutReason.sessionExpired.notice
                    self.machine.enter(.expired)
                    reason = .sessionExpired
                }
                self.apply(change.session, reason: reason)
            }
        }
        if isRestoring {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.isRestoring == true { self?.machine.enter(.signedOut) }
            }
        }
    }

    var state: State {
        if isRestoring { return .restoring }
        return isSignedIn ? .signedIn : .signedOut
    }

    deinit { observation?.cancel() }

    var isConfigured: Bool { client != nil }

    /// A session, or (Debug) API key mode.
    var isSignedIn: Bool { session != nil || staticBearer != nil }

    /// Changes whenever the caller does. Drives bootstrap and AppState resets.
    var accountID: String? {
        if let session { return session.user.id.uuidString }
        return staticBearer == nil ? nil : "apikey"
    }

    /// `apple`, `email`, … from the session (`app_metadata.provider`).
    var provider: String? {
        if case .string(let p) = user?.appMetadata["provider"] { return p }
        return nil
    }

    /// Fallback identity when the platform's `User` hasn't loaded: email, else "Apple ID".
    var identityDescription: String {
        if staticBearer != nil { return String(localized: "API key (developer)") }
        if let email = user?.email, !email.isEmpty { return email }
        return String(localized: "Apple ID")
    }

    private var staticBearer: String? {
        #if DEBUG
        let key = settings.devAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings.apiKeyMode && !key.isEmpty ? key : nil
        #else
        return nil
        #endif
    }

    // MARK: Sign in with Apple

    /// `SignInWithAppleButton`'s request hook: scopes plus a fresh hashed nonce.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(nonce)
    }

    /// `SignInWithAppleButton`'s completion hook.
    func complete(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = AuthMessage.text(for: error, during: .signIn)
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingNonce else {
                errorMessage = String(localized: "Apple didn't return a sign-in token. Please try again.")
                return
            }
            pendingNonce = nil
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            await signInWithApple(idToken: idToken, nonce: nonce, fullName: credential.fullName, authorizationCode: code)
        }
    }

    /// Exchanges Apple's ID token for a Supabase session. Apple sends the name
    /// only on the very first authorisation, so it's saved then as
    /// `full_name`. `signInWithIdToken` has no metadata parameter, so it goes
    /// through `update(user:)`, then a refresh puts it into the access token
    /// the platform reads.
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?,
                         authorizationCode: String? = nil) async {
        var signedIn = false
        await run(.signIn) { client in
            var session = try await client.signInWithApple(idToken: idToken, nonce: nonce)
            if let name = Self.displayName(fullName) {
                do {
                    try await client.setFullName(name)
                    session = try await client.refreshSession()
                } catch {
                    // Not fatal: the platform shows the email until a name is known.
                }
            }
            self.apply(session)
            signedIn = true
        }
        if signedIn, let authorizationCode { await sendAppleAuthorization(authorizationCode) }
    }

    /// `POST /v1/me/apple-authorization`, once per sign-in, right away: the code is
    /// single-use and valid for five minutes. It lets account deletion revoke the
    /// Apple grant. `422` (expired, used, other Apple ID) and `501` (not configured)
    /// are fine to ignore; APIClient retries a `503` once. Never logged.
    func sendAppleAuthorization(_ code: String) async {
        do {
            try await postAppleAuthorization(code)
        } catch {
            let status = (error as? APIError)?.status.map(String.init) ?? "-"
            APIStatus.log.notice("Apple authorization not stored (\(status, privacy: .public))")
        }
    }

    static func displayName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: sign-in methods (Profile → Account)

    /// The account's sign-in methods, once loaded.
    private(set) var signInMethods: [SignInMethod] = []
    /// Why adding Sign in with Apple failed, in one sentence.
    private(set) var linkError: String?
    private var pendingLinkNonce: String?

    var hasAppleSignIn: Bool { signInMethods.contains { $0.provider == "apple" } || provider == "apple" }

    func loadSignInMethods() async {
        guard let client, let account = accountID else { return }
        let methods = try? await client.identities()
        // Another account meanwhile: those were the previous one's.
        guard let methods, accountID == account else { return }
        signInMethods = methods
    }

    /// "Add Sign in with Apple"'s request hook: no scopes (the account has its name), a fresh nonce.
    func prepareLink(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        pendingLinkNonce = nonce
        request.requestedScopes = []
        request.nonce = Nonce.sha256(nonce)
    }

    /// Links the Apple ID to this account, so either sign-in opens the same data.
    @discardableResult
    func completeLink(_ result: Result<ASAuthorization, Error>) async -> Bool {
        linkError = nil
        guard let client else { return false }
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                linkError = AuthMessage.text(for: error, during: .link)
            }
            return false
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingLinkNonce else {
                linkError = String(localized: "Apple didn't return a sign-in token. Please try again.")
                return false
            }
            pendingLinkNonce = nil
            otherWork = true
            defer { otherWork = false }
            do {
                apply(try await client.linkApple(idToken: idToken, nonce: nonce))
                await loadSignInMethods()
                if let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
                    await sendAppleAuthorization(code)
                }
                return true
            } catch {
                linkError = AuthMessage.linkText(for: error)
                return false
            }
        }
    }

    // MARK: email + password

    enum SignUpOutcome: Equatable {
        case signedIn
        /// The project requires confirmation: show "Check your inbox".
        case confirmEmail
    }

    /// `nil` on failure (`errorMessage` says why).
    func signUp(name: String, email: String, password: String) async -> SignUpOutcome? {
        var outcome: SignUpOutcome?
        await run(.signUp) { client in
            let session = try await client.signUp(email: Self.normalized(email), password: password,
                                                  fullName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  redirectTo: SupabaseConfig.redirectURL)
            if let session {
                self.apply(session)
                outcome = .signedIn
            } else {
                outcome = .confirmEmail
            }
        }
        return outcome
    }

    @discardableResult
    func logIn(email: String, password: String) async -> Bool {
        var ok = false
        await run(.signIn) { client in
            self.apply(try await client.signIn(email: Self.normalized(email), password: password))
            ok = true
        }
        return ok
    }

    @discardableResult
    func resendConfirmation(email: String) async -> Bool {
        var ok = false
        await run(.emailLink) { client in
            try await client.resendSignUpConfirmation(email: Self.normalized(email), redirectTo: SupabaseConfig.redirectURL)
            ok = true
        }
        return ok
    }

    /// Sends the reset link. Reports success for unknown addresses too, so the
    /// screen never reveals whether an account exists.
    @discardableResult
    func sendPasswordReset(email: String) async -> Bool {
        var ok = false
        await run(.emailLink) { client in
            // PKCE links don't say they are for recovery; remember it until the link comes back.
            self.defaults.set(Date.now, forKey: Self.recoveryKey)
            try await client.resetPassword(email: Self.normalized(email), redirectTo: SupabaseConfig.redirectURL)
            ok = true
        }
        return ok
    }

    @discardableResult
    func updatePassword(_ password: String) async -> Bool {
        var ok = false
        await run(.newPassword) { client in
            try await client.updatePassword(password)
            self.needsNewPassword = false
            ok = true
        }
        return ok
    }

    // MARK: deep links

    /// `ryft://auth/callback?code=…` from a confirmation or reset email.
    /// Returns whether the URL was ours.
    @discardableResult
    func handle(_ url: URL) async -> Bool {
        guard SupabaseConfig.isAuthCallback(url) else { return false }
        await run(.link) { client in
            let session = try await client.session(from: url)
            let recovering = Self.isRecoveryLink(url) || self.recoveryRequestedRecently
            self.defaults.removeObject(forKey: Self.recoveryKey)
            self.apply(session)
            if recovering { self.needsNewPassword = true }
        }
        return true
    }

    private static let recoveryKey = "auth.recoveryRequestedAt"

    /// Supabase reset links are valid for an hour by default.
    private var recoveryRequestedRecently: Bool {
        guard let at = defaults.object(forKey: Self.recoveryKey) as? Date else { return false }
        return Date.now.timeIntervalSince(at) < 3600
    }

    private static func isRecoveryLink(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains { $0.name == "type" && $0.value == "recovery" } ?? false
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: log out, delete

    /// Log out: drops the session, cached responses, HealthKit anchors and
    /// per-user defaults, so another account on this phone starts from scratch.
    func signOut(reason: SignOutReason = .user) async {
        // Still authorised: let the app clean up remotely (the push registration).
        // An expired session can't; a deleted account took everything with it.
        if reason == .user, isSignedIn { await beforeSignOut?() }
        // Leave `signedIn` first, so the SDK's own `.signedOut` event isn't read as an expiry.
        machine.enter(reason == .sessionExpired ? .expired : .signedOut)
        signOutNotice = reason.notice
        endingReason = reason
        defer { endingReason = nil }
        #if DEBUG
        if settings.apiKeyMode {
            settings.apiKeyMode = false
            perform(Wipe(reason: reason, account: nil))
        }
        #endif
        // Written down while the session is still stored: from here a kill leaves a debt. Without a session `apply`
        // won't wipe, so nothing would ever end an entry.
        if let leaving = session?.user.id.uuidString {
            ledger.begin(Wipe(reason: leavingReason(reason, of: leaving), account: leaving), at: now())
        }
        // The SDK drops the local session before calling /logout, so this also works offline.
        try? await client?.signOut()
        apply(nil, reason: reason)
    }

    /// `DELETE /v1/me` (data, then the Supabase user), then the same as log out.
    /// The platform answers 503 when nothing was deleted; APIClient retries
    /// that after `Retry-After`. On failure the account stays signed in.
    @discardableResult
    func deleteAccount() async -> Bool {
        errorMessage = nil
        errorDetails = nil
        otherWork = true
        await beforeSignOut?()
        defer { otherWork = false }
        let account = session?.user.id.uuidString
        // From here this account's session ending for any reason ends as this deletion (no parking), and its uploads
        // stop.
        deletingAccount = account
        defer { deletingAccount = nil }
        let changesAtStart = accountChanges
        onAccountDeletionStart?()
        let result: AccountDeleted
        do {
            result = try await deleteRemoteAccount()
        } catch {
            // The account changed meanwhile, or the call was cancelled (a switch cuts its retries short): whoever is
            // here now didn't ask, so no message.
            guard !error.isCancellation, accountChanges == changesAtStart else { return false }
            // 503 (after APIClient's retries) means nothing was deleted.
            errorMessage = (error as? APIError)?.status == 503
                ? String(localized: "RYFT couldn't delete your account just now. Nothing was deleted. Try again in a moment.")
                : error.localizedDescription
            errorDetails = error.diagnosticDetails
            return false
        }
        let reason = SignOutReason.accountDeleted(background: !result.authUserDeleted)
        if session == nil {
            // The session ended while the platform deleted (a concurrent final 401), and nothing else happened since:
            // the deletion's notice and wipe. If another account came and went meanwhile, the notice isn't its, and a
            // wipe would take what it parked: the deleted account's data already went when its session ended.
            if accountChanges == changesAtStart + 1 {
                signOutNotice = reason.notice
                wipeLeaving(Wipe(reason: reason, account: account))
            }
        } else if session?.user.id.uuidString == account {
            await signOut(reason: reason)
        }
        // Otherwise another account signed in meanwhile (`DELETE /v1/me` retries 503s for up to about 90 s): the
        // deleted account's data went when its session ended as this deletion; the new account stays signed in, with
        // its data and without the notice.
        return true
    }

    // MARK: state

    /// Runs one Supabase call with the busy flag and calm error copy.
    private func run(_ context: AuthMessage.Context, _ body: (AuthClientProtocol) async throws -> Void) async {
        guard let client else {
            errorMessage = SupabaseConfig.problem ?? String(localized: "Sign-in isn't set up in this build.")
            return
        }
        errorMessage = nil
        // Sign-ins move the session machine; other calls only make the screen busy.
        let signsIn: Bool
        switch context {
        case .signIn, .signUp, .link: signsIn = true
        default: signsIn = false
        }
        if signsIn { machine.enter(.signingIn) } else { otherWork = true }
        defer {
            if signsIn {
                if phase == .signingIn { machine.enter(isSignedIn ? .signedIn : .signedOut) }
            } else {
                otherWork = false
            }
        }
        do {
            try await body(client)
        } catch {
            errorMessage = AuthMessage.text(for: error, during: context)
        }
    }

    /// `reason`: why a session that ends here ended. Without one (the SDK ended it on its own) it's an expiry,
    /// which keeps the account's unsent activities parked rather than deleting them.
    private func apply(_ newSession: Session?, reason: SignOutReason? = nil) {
        if newSession != nil, session == nil { signOutNotice = nil }
        let leaving = session?.user.id.uuidString
        let ending = newSession != nil ? nil : leavingReason(reason ?? endingReason ?? .sessionExpired, of: leaving)
        let previousID = session?.user.id ?? defaults.string(forKey: Self.lastUserKey).flatMap(UUID.init(uuidString:))
        if let newSession {
            // A different account on this phone starts from scratch.
            var wiped = true
            if let previousID, previousID != newSession.user.id {
                wiped = wipe(Wipe(reason: nil, account: previousID.uuidString))
            } else if !isRestoring, newSession.user.id != session?.user.id,
                      ledger.entry?.wipe.account == newSession.user.id.uuidString {
                // Its own account signed in and this sign-in doesn't wipe, so the rows are its work again. An entry left
                // standing would date this account's next expiry from the old one, and its parked rows would run out
                // early. Not a stored session at launch: that's a kill inside the sign-out, of a deletion too, and only
                // the entry can resume it. Not a token refresh during a sign-out: the session is still published.
                ledger.clear()
            }
            // Not on a token refresh, and not after a failed wipe: the id that stays makes the next launch wipe again.
            if wiped, newSession.user.id != session?.user.id {
                defaults.set(newSession.user.id.uuidString, forKey: Self.lastUserKey)
            }
        } else if session != nil {
            // Logged out (by the user, account deleted, or the session expired).
            wipeLeaving(Wipe(reason: ending, account: leaving))
            needsNewPassword = false
        }
        if newSession?.user.id != session?.user.id {
            // Sign-in methods belong to the account they were loaded for.
            signInMethods = []
            linkError = nil
            accountChanges += 1
            onAccountWillChange?(leaving, newSession?.user.id.uuidString, ending)
        }
        session = newSession
        user = newSession?.user
        // The machine follows the session (sign-outs set their phase before getting here).
        if newSession != nil {
            machine.enter(.signedIn)
        } else if phase == .signedIn || phase == .refreshing {
            machine.enter(.signedOut)
        }
    }

    private static let lastUserKey = AccountScope.defaultsKey

    /// While its deletion runs, the account's session ending for any reason ends as the deletion (its outcome isn't
    /// known yet; `Wipe.parking` is what matters). A deletion's own reason keeps its `background`.
    private func leavingReason(_ real: SignOutReason, of leaving: String?) -> SignOutReason {
        deletingAccount != nil && deletingAccount == leaving ? real.asDeletion : real
    }

    /// Written down first. A wipe that returned false leaves the entry.
    @discardableResult
    private func wipe(_ wipe: Wipe) -> Bool {
        let at = now()
        ledger.begin(wipe, at: at)
        // An entry this wipe doesn't park with is another debt, and its date isn't this wipe's.
        var stamped = wipe
        stamped.since = ledger.entry.flatMap { $0.wipe.parking == wipe.parking ? $0.since : nil } ?? at
        // Another account's device steps aren't done by these: that account's own state is still there.
        stamped.storeOnly = ledger.entry.map { $0.deviceStepsDone && $0.wipe.account == wipe.account } ?? false
        return settled(stamped)
    }

    /// The entry as it stands, with no new `begin`: its date is the first attempt's whatever the clock says now.
    private func retry(_ owed: OwedWipe) {
        var wipe = owed.wipe
        wipe.storeOnly = owed.deviceStepsDone
        keepOrForget(wipe.account, wiped: settled(wipe))
    }

    /// One pass. True ends the entry, and false leaves it with the device steps marked done, so a retry skips them.
    /// Files the replace left mean false, whatever the store answers.
    private func settled(_ wipe: Wipe) -> Bool {
        let wiped = perform(wipe) && !ledger.storeStepLeftFiles
        if wiped, !endingStoredSession {
            ledger.clear()
        } else {
            ledger.update { $0.deviceStepsDone = true }
        }
        wipedWhileEnding = wiped && endingStoredSession
        return wiped
    }

    private func storedSessionEnded() {
        endingStoredSession = false
        if wipedWhileEnding { ledger.clear() }
    }

    @discardableResult
    private func perform(_ wipe: Wipe) -> Bool {
        let wiped = wipeLocalData(wipe)
        onWipe?(wipe)
        return wiped
    }

    /// A wipe that leaves nobody signed in. Failed, the leaving account stays in `lastUserKey`: its data may still be
    /// in the store, and without the id the next account's sign-in wouldn't wipe and would get that data.
    private func wipeLeaving(_ wipe: Wipe) {
        keepOrForget(wipe.account, wiped: self.wipe(wipe))
    }

    private func keepOrForget(_ account: String?, wiped: Bool) {
        if wiped {
            defaults.removeObject(forKey: Self.lastUserKey)
        } else if let account {
            defaults.set(account, forKey: Self.lastUserKey)
        }
    }

    /// The launch table (design.md §4), before anything is published. Runs ahead of the store, which reads what it
    /// leaves in `forStoreStep`; a wipe here is what first opens it. Returns the session to publish, and whether the
    /// stored one is ended instead: an interrupted sign-out.
    private func resumeOwedWipe(stored: Session?) -> (publish: Session?, endsStored: Bool) {
        guard let owed = ledger.entry else { return (stored, false) }
        switch WipeResume.decide(owed, stored: stored?.user.id.uuidString, now: now()) {
        case .forget:
            ledger.clear()
            return (stored, false)
        case .scrub:
            ledger.forStoreStep = owed
            return (nil, false)
        case .wipeAfterFirstFrame(let endSession):
            ledger.forStoreStep = owed
            resumedOwedWipe = true
            endingStoredSession = endSession
            return (endSession ? nil : stored, endSession)
        case .wipeNow(let narrow, let endSession):
            if narrow { ledger.update { $0.wipe.reason = nil } }
            ledger.forStoreStep = ledger.entry
            resumedOwedWipe = true
            triedOwedWipe = true
            endingStoredSession = endSession
            if let entry = ledger.entry { retry(entry) }
            return (endSession ? nil : stored, endSession)
        }
    }

    /// After the first frame, and in the nightly compaction. An owed wipe taken up changes no account, so `onChange`
    /// doesn't run: a kill left the account's reminders and alarms scheduled, and its open workout on a row that's gone.
    func finishOwedWipe(train: TrainCoordinator, bedtime: BedtimePlanner) async {
        guard finishOwedWipe() else { return }
        train.accountChanged()
        await bedtime.accountChanged()
    }

    /// The parked wipe the launch left, or a retry of one that failed. True when a wipe was taken up, at this launch or
    /// now. Never over a session: a published one's rows are its own, and a stored one the launch couldn't read (the
    /// entry too, before the first unlock) goes through the launch table at the next launch. One this launch is ending
    /// isn't in the way.
    @discardableResult
    func finishOwedWipe() -> Bool {
        defer { resumedOwedWipe = false }
        guard session == nil, endingStoredSession || client?.currentSession == nil, !triedOwedWipe,
              let owed = ledger.entry else { return resumedOwedWipe }
        guard !owed.scrubOnly else {
            if !ledger.storeStepLeftFiles { ledger.clear() }
            return resumedOwedWipe
        }
        triedOwedWipe = true
        retry(owed)
        return true
    }

    /// Live wipe: cached API responses, HealthKit anchors (the next account
    /// re-syncs the full backfill) and per-user UserDefaults. False when the store may still hold the data.
    static func wipeSharedLocalData(_ wipe: Wipe) -> Bool {
        steps(of: wipe, before: {
            HealthKitManager.shared.resetAnchors()
            SyncEngineState.wipe(defaults: .standard)
            Settings.shared.clearPerUserState()
        }, store: wipeStoreStep, after: {
            RestActivityController.shared.end()
            // Bedtime & wake's schedules and planned nights (its reminders and alarms go with the
            // account change: `BedtimePlanner.accountChanged`).
            BedtimePlanner.wipe(defaults: .standard)
            // Whether to save workouts to Apple Health is the account's choice.
            WorkoutHealthExport.wipe(defaults: .standard)
            // So are the route default, auto-pause and recent sports.
            ActivityPreferences.wipe(defaults: .standard)
            // A sign-out while the export's share sheet is open (a final 401, or the account deleted): the file holds
            // all of the account's data.
            DataExport.removeFiles()
        })
    }

    /// A retry (`storeOnly`) leaves the device steps alone, so it doesn't restart the backfill.
    static func steps(of wipe: Wipe, before: () -> Void, store: (Wipe) -> Bool, after: () -> Void) -> Bool {
        if wipe.storeOnly { return store(wipe) }
        before()
        let wiped = store(wipe)
        after()
        return wiped
    }

    private static func wipeStoreStep(_ wipe: Wipe) -> Bool {
        storeStep(wipe, store: { TrainStore.shared.wipe($0) }, memory: {
            // Its replay stops now, not when the app's account-change handler runs a runloop later.
            TrainSyncService.shared.accountChanged()
            TrainLibrary.shared.wipe()
        })
    }

    /// The store, and what shows or holds its rows: every pass runs this, a retry too. The first pass's clear doesn't
    /// last when its store refused: `onWipe` can write the widget again from the row that survived.
    static func storeStep(_ wipe: Wipe, widget: URL? = ReadinessSnapshot.sharedFile, store: (Wipe) -> Bool,
                          memory: () -> Void) -> Bool {
        // The lock screen must not keep showing this account's readiness.
        ReadinessSnapshot.clear(widget)
        // Cached read models, logged sessions, the offline library and queued uploads are per account; after an
        // expiry the account's unconfirmed activities stay, parked (design.md §8.4).
        let wiped = store(wipe)
        memory()
        return wiped
    }
}

/// The ledger's file format. `since` has no safe default, and an entry without one is no entry.
extension AuthService.Wipe: Codable {
    private enum CodingKeys: String, CodingKey { case reason, account, since, storeOnly }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reason = try values.decodeIfPresent(AuthService.SignOutReason.self, forKey: .reason)
        account = try values.decodeIfPresent(String.self, forKey: .account)
        since = try values.decode(Date.self, forKey: .since)
        storeOnly = try values.decodeIfPresent(Bool.self, forKey: .storeOnly) ?? false
    }
}

extension AuthService.SignOutReason {
    var isDeletion: Bool {
        if case .accountDeleted = self { return true }
        return false
    }

    /// The reason as a deletion: a deletion's own as it is, any other end of a session being deleted as one.
    var asDeletion: Self { isDeletion ? self : .accountDeleted(background: false) }

    /// The one line Welcome shows, or nil for an ordinary log out.
    var notice: String? {
        switch self {
        case .user: return nil
        case .sessionExpired: return String(localized: "You were signed out. Log in again to continue.")
        case .accountDeleted(let background):
            return background
                ? String(localized: "Your RYFT data is deleted. Removing the sign-in will finish in the background.")
                : String(localized: "Your RYFT account and data are deleted.")
        }
    }
}

// MARK: - messages

/// Calm, inline error copy. Never says whether an email has an account.
enum AuthMessage {
    /// Adding Sign in with Apple to an account.
    static func linkText(for error: Error) -> String {
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return String(localized: "No connection. Check your internet and try again.")
        }
        guard case .api(_, let code, _, _) = error as? AuthError else {
            return String(localized: "Something went wrong. Please try again.")
        }
        switch code {
        case .identityAlreadyExists:
            return String(localized: "This Apple ID already belongs to another RYFT account. Log out and continue with Apple to use that one.")
        case .manualLinkingDisabled:
            return String(localized: "Adding Sign in with Apple isn't switched on for RYFT yet. Try again later.")
        default:
            return String(localized: "Something went wrong. Please try again.")
        }
    }

    enum Context { case signIn, signUp, emailLink, newPassword, link }

    static func text(for error: Error, during context: Context) -> String {
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return String(localized: "No connection. Check your internet and try again.")
        }
        if context == .link {
            return String(localized: "This link has expired or was already used. Request a new one.")
        }
        guard case .api(_, let code, _, let response) = error as? AuthError else {
            return String(localized: "Something went wrong. Please try again.")
        }
        switch code {
        case .invalidCredentials:
            return String(localized: "Email or password is wrong.")
        case .emailNotConfirmed:
            return String(localized: "Confirm your email first: open the link we sent you.")
        case .weakPassword:
            return String(localized: "Choose a stronger password with at least \(AuthService.minimumPasswordLength) characters.")
        case .samePassword:
            return String(localized: "Choose a password you haven't used before.")
        case .userAlreadyExists, .emailExists:
            return String(localized: "This email can't be used for a new account. Log in instead, or reset your password.")
        case .signupDisabled:
            return String(localized: "New accounts can't be created right now.")
        case .overRequestRateLimit, .overEmailSendRateLimit:
            return String(localized: "Too many attempts. Wait a minute and try again.")
        case .validationFailed where context == .signUp || context == .emailLink:
            return String(localized: "Check the email address.")
        default:
            if response.statusCode == 429 { return String(localized: "Too many attempts. Wait a minute and try again.") }
            if context == .signIn && response.statusCode == 400 { return String(localized: "Email or password is wrong.") }
            return String(localized: "Something went wrong. Please try again.")
        }
    }
}

// MARK: - bearer for APIClient

extension AuthService: AccessTokenProvider {
    /// The SDK refreshes an expired token. An auth failure (refresh token
    /// revoked, session missing) signs out, which shows onboarding.
    func accessToken() async throws -> String {
        try await token { try await $0.validSession() }
    }

    /// After a 401: one forced refresh, in the `refreshing` phase.
    func refreshedAccessToken() async throws -> String {
        machine.enter(.refreshing)
        defer { if phase == .refreshing { machine.enter(.signedIn) } }
        return try await token { try await $0.refreshSession() }
    }

    /// The platform rejected even a freshly refreshed token.
    func rejectedAfterRefresh() async {
        guard staticBearer == nil else { return } // a wrong dev key: surface the 401, stay in API key mode
        await signOut(reason: .sessionExpired)
    }

    private func token(_ fetch: (AuthClientProtocol) async throws -> Session) async throws -> String {
        if let staticBearer { return staticBearer }
        guard let client, session != nil else { throw APIError.signedOut }
        do {
            return try await fetch(client).accessToken
        } catch let error as AuthError where error.endsSession {
            await signOut(reason: .sessionExpired)
            throw APIError.signedOut
        }
    }
}

/// A refresh failure that keeps the session (`endsSession` false) is transient for the read
/// pipeline: retried and counted like a `503`, never "something went wrong".
extension AuthError: TransientClassifiable {
    var isTransientFailure: Bool { !endsSession }
}

extension AuthError {
    /// Whether the session is unusable, as opposed to Supabase being briefly
    /// unreachable or overloaded (keep the session and try again later).
    var endsSession: Bool {
        switch self {
        case .refreshDiscarded:
            return false // a concurrent refresh replaced the session; it's still valid
        case .api(_, _, _, let response):
            return (400..<500).contains(response.statusCode) && ![408, 429].contains(response.statusCode)
        default:
            return true
        }
    }
}
