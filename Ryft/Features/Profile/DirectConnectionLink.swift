import AuthenticationServices
import SwiftUI

enum DirectConnectionFailure: Error, Equatable {
    case denied, expired, invalidResponse, provider, capacity, unavailable, session, consent, invite, retry, offline

    var message: String {
        switch self {
        case .denied: String(localized: "Authorization was declined. You can try again when you're ready.")
        case .expired: String(localized: "This authorization session expired. Start the connection again.")
        case .invalidResponse: String(localized: "RYFT couldn't verify the connection response. Try again.")
        case .provider: String(localized: "The provider couldn't complete the connection. Try again later.")
        case .capacity: String(localized: "The provider has no open connection slots right now.")
        case .unavailable: String(localized: "This provider is currently unavailable for your account.")
        case .session: String(localized: "Your session has ended. Log in again to continue.")
        case .consent: String(localized: "RYFT needs your consent before it can sync your health data.")
        case .invite: String(localized: "RYFT is invite-only during the beta. Enter your invite code to continue.")
        case .retry: String(localized: "RYFT couldn't update the connection. Try again.")
        case .offline: String(localized: "Connect to the internet to update the connection.")
        }
    }

    static func from(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        guard let api = error as? APIError else { return .retry }
        switch api {
        case .signedOut, .http(401, _, _, _, _): return .session
        case .http(_, _, _, .consentRequired?, _): return .consent
        case .http(_, _, _, .inviteRequired?, _): return .invite
        case .http(_, _, _, .connectTicketInvalid?, _): return .invalidResponse
        case .http(_, _, _, .connectionLimit?, _): return .capacity
        case .http(404, _, _, _, _): return .unavailable
        case .http(410, _, _, _, _): return .expired
        case .transport(let error) where (error as? URLError)?.code == .notConnectedToInternet: return .offline
        default: return .retry
        }
    }
}

enum DirectConnectionLink {
    static func validProvider(_ value: String) -> Bool {
        (1...32).contains(value.utf8.count) && value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }
    }

    static func authorizeURL(_ session: DirectConnectionStart, now: Date) throws -> URL {
        guard now < session.expiresAt else { throw DirectConnectionFailure.expired }
        let url = session.authorizeUrl
        guard url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw DirectConnectionFailure.invalidResponse
        }
        return url
    }

    static func ticket(from url: URL, provider: String) throws -> String {
        guard validProvider(provider), let link = URLComponents(url: url, resolvingAgainstBaseURL: false),
              link.scheme == "ryft", link.host == "connect", link.percentEncodedPath == "/\(provider)",
              link.user == nil, link.password == nil, link.port == nil, link.fragment == nil,
              let items = link.queryItems,
              items.filter({ $0.name == "status" }).count == 1
        else { throw DirectConnectionFailure.invalidResponse }

        let tickets = items.filter { $0.name == "ticket" }
        switch items.first(where: { $0.name == "status" })?.value {
        case "ok":
            guard tickets.count == 1, let ticket = tickets.first?.value, ticket.utf8.count == 32,
                  ticket.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { throw DirectConnectionFailure.invalidResponse }
            return ticket
        case "denied" where tickets.isEmpty: throw DirectConnectionFailure.denied
        case "expired" where tickets.isEmpty: throw DirectConnectionFailure.expired
        case "error" where tickets.isEmpty: throw DirectConnectionFailure.provider
        default: throw DirectConnectionFailure.invalidResponse
        }
    }
}

@MainActor
protocol DirectConnectionBrowser: AnyObject {
    func authorize(_ url: URL) async throws -> URL
    func cancel()
}

@MainActor
final class DirectConnectionWebSession: NSObject, DirectConnectionBrowser, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var completion: CheckedContinuation<URL, Error>?
    private var anchor: ASPresentationAnchor?
    private var sessionID: UUID?

    func authorize(_ url: URL) async throws -> URL {
        guard completion == nil,
              let window = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .first(where: { $0.activationState == .foregroundActive })?.keyWindow
        else { throw DirectConnectionFailure.provider }

        let attemptID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                anchor = window
                sessionID = attemptID
                let request = ASWebAuthenticationSession(url: url, callbackURLScheme: "ryft") { [weak self] callback, error in
                    Task { @MainActor in
                        guard let self, self.sessionID == attemptID else { return }
                        if let callback {
                            self.finish(.success(callback))
                        } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self.finish(.failure(CancellationError()))
                        } else {
                            self.finish(.failure(DirectConnectionFailure.provider))
                        }
                    }
                }
                request.presentationContextProvider = self
                session = request
                if !request.start() { finish(.failure(DirectConnectionFailure.provider)) }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.sessionID == attemptID else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        let pending = session
        finish(.failure(CancellationError()))
        pending?.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        let waiting = completion
        completion = nil
        session = nil
        anchor = nil
        sessionID = nil
        waiting?.resume(with: result)
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
