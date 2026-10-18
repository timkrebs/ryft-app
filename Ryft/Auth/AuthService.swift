// Who the caller is. Supabase Auth signs the user in with Apple (native
// ASAuthorization flow, no web view); the SDK persists the session in the
// Keychain and refreshes it, and every platform request carries its access
// token as the bearer (see APIClient). The app never stores tokens itself.
import AuthenticationServices
import CryptoKit
import Foundation
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
final class AuthService: ObservableObject {
    static let shared = AuthService(client: SupabaseConfig.current.map(SupabaseAuthClient.init(config:)))

    /// Accounts need at least this many characters (the Supabase project's
    /// minimum must not be higher).
    nonisolated static let minimumPasswordLength = 10

    @Published private(set) var session: Session?
    @Published private(set) var user: Auth.User?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Status and request ID when a platform call (Delete account) failed.
    @Published private(set) var errorDetails: String?
    /// A password-reset link was opened: show "Set new password".
    @Published var needsNewPassword = false

    /// `nil` when Supabase isn't configured (see `SupabaseConfig.problem`).
    private let client: AuthClientProtocol?
    private let settings: Settings
    private let defaults: UserDefaults
    /// Per-user local state to drop when the account ends or changes: cached
    /// responses, HealthKit anchors, per-user defaults. AppState resets itself
    /// on `accountID` changes.
    private let wipeLocalData: @MainActor () -> Void
    /// `DELETE /v1/me`; injected so tests don't need the platform.
    private let deleteRemoteAccount: () async throws -> Void
    private var observation: Task<Void, Never>?
    private var pendingNonce: String?

    init(client: AuthClientProtocol?, settings: Settings = .shared, defaults: UserDefaults = .standard,
         wipeLocalData: @escaping @MainActor () -> Void = AuthService.wipeSharedLocalData,
         deleteRemoteAccount: @escaping () async throws -> Void = { _ = try await APIClient.shared.deleteMe() }) {
        self.client = client
        self.settings = settings
        self.defaults = defaults
        self.wipeLocalData = wipeLocalData
        self.deleteRemoteAccount = deleteRemoteAccount
        // Read the Keychain synchronously so a relaunch goes straight to Today
        // (no Welcome flash); the SDK refreshes an expired token in the background.
        apply(client?.currentSession)
        guard let client else { return }
        observation = Task { [weak self] in
            for await change in client.authStateChanges {
                self?.apply(change.session)
            }
        }
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
            await signInWithApple(idToken: idToken, nonce: nonce, fullName: credential.fullName)
        }
    }

    /// Exchanges Apple's ID token for a Supabase session. Apple sends the name
    /// only on the very first authorisation, so it's saved then as
    /// `full_name`. `signInWithIdToken` has no metadata parameter, so it goes
    /// through `update(user:)`, then a refresh puts it into the access token
    /// the platform reads.
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
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
        }
    }

    static func displayName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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
        guard url.scheme == SupabaseConfig.redirectURL.scheme, url.host == SupabaseConfig.redirectURL.host else {
            return false
        }
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
    func signOut() async {
        #if DEBUG
        if settings.apiKeyMode {
            settings.apiKeyMode = false
            wipeLocalData()
        }
        #endif
        // The SDK drops the local session before calling /logout, so this also works offline.
        try? await client?.signOut()
        apply(nil)
    }

    /// `DELETE /v1/me` (data, then the Supabase user), then the same as log out.
    /// The platform answers 503 when nothing was deleted; APIClient retries
    /// that after `Retry-After`. On failure the account stays signed in.
    @discardableResult
    func deleteAccount() async -> Bool {
        errorMessage = nil
        errorDetails = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await deleteRemoteAccount()
        } catch {
            errorMessage = error.localizedDescription
            errorDetails = error.diagnosticDetails
            return false
        }
        await signOut()
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
        isWorking = true
        defer { isWorking = false }
        do {
            try await body(client)
        } catch {
            errorMessage = AuthMessage.text(for: error, during: context)
        }
    }

    private func apply(_ newSession: Session?) {
        let previousID = session?.user.id ?? defaults.string(forKey: Self.lastUserKey).flatMap(UUID.init(uuidString:))
        if let newSession {
            // A different account on this phone starts from scratch.
            if let previousID, previousID != newSession.user.id { wipeLocalData() }
            defaults.set(newSession.user.id.uuidString, forKey: Self.lastUserKey)
        } else if session != nil {
            // Logged out (by the user, account deleted, or the refresh token was revoked).
            wipeLocalData()
            defaults.removeObject(forKey: Self.lastUserKey)
            needsNewPassword = false
        }
        session = newSession
        user = newSession?.user
    }

    private static let lastUserKey = "auth.lastUserID"

    /// Live wipe: cached API responses, HealthKit anchors (the next account
    /// re-syncs the full backfill) and per-user UserDefaults.
    static func wipeSharedLocalData() {
        ResponseCache.shared.clear()
        HealthKitManager.shared.resetAnchors()
        Settings.shared.clearPerUserState()
    }
}

// MARK: - messages

/// Calm, inline error copy. Never says whether an email has an account.
enum AuthMessage {
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

    func refreshedAccessToken() async throws -> String {
        try await token { try await $0.refreshSession() }
    }

    /// The platform rejected even a freshly refreshed token.
    func rejectedAfterRefresh() async {
        guard staticBearer == nil else { return } // a wrong dev key: surface the 401, stay in API key mode
        await signOut()
    }

    private func token(_ fetch: (AuthClientProtocol) async throws -> Session) async throws -> String {
        if let staticBearer { return staticBearer }
        guard let client, session != nil else { throw APIError.signedOut }
        do {
            return try await fetch(client).accessToken
        } catch let error as AuthError where error.endsSession {
            await signOut()
            throw APIError.signedOut
        }
    }
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
