// An in-memory AuthClientProtocol for previews and unit tests: no network,
// no Keychain. Tests script it (errors, events) and read back what was called.
import Foundation
import Auth

final class MockAuthClient: AuthClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Session?
    private var continuations: [AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation] = []

    // Scripted behaviour.
    var signInSession: Session
    var validSessionError: Error?
    var refreshError: Error?
    var refreshedToken = "refreshed-token"
    /// Sign in with Apple failures.
    var signInError: Error?
    /// Email sign-in/sign-up/reset/link failures.
    var emailError: Error?
    /// `true` models a project with "Confirm email" on: sign-up returns no session.
    var requiresEmailConfirmation = false
    /// The account's sign-in methods; linking Apple adds one.
    var methods = [SignInMethod(provider: "email", email: "tim@example.com", addedAt: nil)]
    /// Linking failures (`identity_already_exists`, `manual_linking_disabled`).
    var linkError: Error?

    // What happened.
    private(set) var refreshCount = 0
    private(set) var signOutCount = 0
    private(set) var savedFullNames: [String] = []
    private(set) var signUps: [(email: String, fullName: String)] = []
    private(set) var resetEmails: [String] = []
    private(set) var resentEmails: [String] = []
    private(set) var updatedPasswords: [String] = []
    private(set) var openedLinks: [URL] = []

    init(session: Session? = nil, signInSession: Session = .preview()) {
        stored = session
        self.signInSession = signInSession
    }

    var currentSession: Session? { locked { stored } }

    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        let (stream, continuation) = AsyncStream<(event: AuthChangeEvent, session: Session?)>.makeStream()
        locked {
            continuations.append(continuation)
            continuation.yield((.initialSession, stored))
        }
        return stream
    }

    /// Simulates the SDK reporting a change (e.g. a revoked refresh token → `.signedOut`).
    func emit(_ event: AuthChangeEvent, _ session: Session?) {
        let targets = locked { () -> [AsyncStream<(event: AuthChangeEvent, session: Session?)>.Continuation] in
            stored = session
            return continuations
        }
        for c in targets { c.yield((event, session)) }
    }

    func validSession() async throws -> Session {
        try locked {
            if let validSessionError { throw validSessionError }
            guard let stored else { throw AuthError.sessionMissing }
            return stored
        }
    }

    func refreshSession() async throws -> Session {
        try locked {
            refreshCount += 1
            if let refreshError { throw refreshError }
            guard var s = stored else { throw AuthError.sessionMissing }
            s.accessToken = refreshedToken
            stored = s
            return s
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        if !idToken.isEmpty, let e = locked({ signInError }) { throw e }
        let s = locked { stored = signInSession; return signInSession }
        emit(.signedIn, s)
        return s
    }

    func setFullName(_ name: String) async throws {
        locked { savedFullNames.append(name) }
    }

    func signUp(email: String, password: String, fullName: String, redirectTo: URL) async throws -> Session? {
        try locked { () throws -> Void in
            if let emailError { throw emailError }
            signUps.append((email, fullName))
        }
        if requiresEmailConfirmation { return nil }
        return try await signInWithApple(idToken: "", nonce: "")
    }

    func signIn(email: String, password: String) async throws -> Session {
        if let e = locked({ emailError }) { throw e }
        return try await signInWithApple(idToken: "", nonce: "")
    }

    func resendSignUpConfirmation(email: String, redirectTo: URL) async throws {
        try locked {
            if let emailError { throw emailError }
            resentEmails.append(email)
        }
    }

    func resetPassword(email: String, redirectTo: URL) async throws {
        try locked {
            if let emailError { throw emailError }
            resetEmails.append(email)
        }
    }

    func updatePassword(_ password: String) async throws {
        try locked {
            if let emailError { throw emailError }
            updatedPasswords.append(password)
        }
    }

    func session(from url: URL) async throws -> Session {
        try locked { () throws -> Void in
            openedLinks.append(url)
            if let emailError { throw emailError }
        }
        return try await signInWithApple(idToken: "", nonce: "")
    }

    func signOut() async throws {
        locked { signOutCount += 1 }
        emit(.signedOut, nil)
    }

    func identities() async throws -> [SignInMethod] { locked { methods } }

    func linkApple(idToken: String, nonce: String) async throws -> Session {
        try locked {
            if let linkError { throw linkError }
            methods.append(SignInMethod(provider: "apple", email: "tim@privaterelay.appleid.com", addedAt: .now))
            guard let stored else { throw AuthError.sessionMissing }
            return stored
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension Session {
    /// A non-expiring fake session for previews and tests.
    static func preview(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        email: String? = "tim@privaterelay.appleid.com",
                        accessToken: String = "preview-token", provider: String = "apple") -> Session {
        let user = Auth.User(id: id, appMetadata: ["provider": .string(provider)],
                             userMetadata: ["full_name": "Tim Krebs"], aud: "authenticated",
                             email: email, createdAt: .now, updatedAt: .now)
        return Session(accessToken: accessToken, tokenType: "bearer", expiresIn: 3600,
                       expiresAt: Date.distantFuture.timeIntervalSince1970, refreshToken: "preview-refresh",
                       user: user)
    }
}

extension AuthService {
    /// Signed in with a fake session (or signed out, for onboarding previews).
    static func preview(signedIn: Bool = true, provider: String = "apple") -> AuthService {
        AuthService(client: MockAuthClient(session: signedIn ? .preview(provider: provider) : nil),
                    defaults: UserDefaults(suiteName: "ryft.preview.auth") ?? .standard,
                    wipeLocalData: {},
                    deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                    postAppleAuthorization: { _ in })
    }
}
