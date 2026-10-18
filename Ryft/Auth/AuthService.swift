// Who the caller is. Supabase Auth signs the user in with Apple (native
// ASAuthorization flow, no web view); the SDK persists the session in the
// Keychain and refreshes it, and every platform request carries its access
// token as the bearer (see APIClient). The app never stores tokens itself.
import AuthenticationServices
import CryptoKit
import Foundation
import Auth

// MARK: - SDK seam

/// The handful of Supabase calls the app makes, so tests and previews run
/// without the network. `SupabaseAuthClient` is the live implementation.
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
    /// Removes the local session first, then revokes it on the server.
    func signOut() async throws
}

struct SupabaseAuthClient: AuthClientProtocol {
    let client: AuthClient

    init(config: SupabaseConfig) {
        client = AuthClient(url: config.authURL,
                            headers: ["apikey": config.publishableKey],
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

    @Published private(set) var session: Session?
    @Published private(set) var user: Auth.User?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    /// `nil` when Supabase isn't configured (no Config/*.xcconfig values).
    private let client: AuthClientProtocol?
    private let settings: Settings
    private let defaults: UserDefaults
    /// Per-user local state to drop when the account ends or changes: cached
    /// responses, HealthKit anchors, last sync. AppState resets itself on
    /// `accountID` changes.
    private let wipeLocalData: @MainActor () -> Void
    private var observation: Task<Void, Never>?
    private var pendingNonce: String?

    init(client: AuthClientProtocol?, settings: Settings = .shared, defaults: UserDefaults = .standard,
         wipeLocalData: @escaping @MainActor () -> Void = AuthService.wipeSharedLocalData) {
        self.client = client
        self.settings = settings
        self.defaults = defaults
        self.wipeLocalData = wipeLocalData
        // Read the Keychain synchronously so a relaunch goes straight to Today
        // (no onboarding flash); the SDK refreshes an expired token in the background.
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

    /// What Profile shows: the Apple relay or real email, else "Apple ID".
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
                errorMessage = error.localizedDescription
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
        guard let client else {
            errorMessage = SupabaseConfig.problem ?? String(localized: "Sign-in isn't set up in this build.")
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            var session = try await client.signInWithApple(idToken: idToken, nonce: nonce)
            if let name = Self.displayName(fullName) {
                do {
                    try await client.setFullName(name)
                    session = try await client.refreshSession()
                } catch {
                    // Not fatal: the platform falls back to its own default name.
                }
            }
            apply(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func displayName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: sign out

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

    // MARK: state

    private func apply(_ newSession: Session?) {
        let previousID = session?.user.id ?? defaults.string(forKey: Self.lastUserKey).flatMap(UUID.init(uuidString:))
        if let newSession {
            // A different account on this phone starts from scratch.
            if let previousID, previousID != newSession.user.id { wipeLocalData() }
            defaults.set(newSession.user.id.uuidString, forKey: Self.lastUserKey)
        } else if session != nil {
            // Signed out (by the user, or the refresh token was revoked).
            wipeLocalData()
            defaults.removeObject(forKey: Self.lastUserKey)
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
