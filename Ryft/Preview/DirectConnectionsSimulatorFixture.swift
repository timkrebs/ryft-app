#if DEBUG && targetEnvironment(simulator)
import Foundation

/// In-memory UI test data, available only with an explicit simulator launch argument.
final class DirectConnectionsSimulatorFixture: DirectConnectionsAPI {
    private var linked = true
    private static let received = Date(timeIntervalSince1970: 1_795_537_800)

    static func requested() -> DirectConnectionsSimulatorFixture? {
        ProcessInfo.processInfo.arguments.contains("-RyftDirectConnectionsFixture") ? DirectConnectionsSimulatorFixture() : nil
    }

    func directConnections() async throws -> DirectConnectionsResponse {
        let connection = DirectConnection(provider: "suunto", status: "connected", connectedAt: Self.received,
                                          lastDataAt: Self.received, provides: ["workout"], history: "none")
        return .init(connections: linked ? [connection] : [],
                     available: [.init(provider: "suunto", provides: ["workout"], history: "none", accepting: true)],
                     providers: [.init(provider: "garmin", availability: "partner_onboarding"),
                                 .init(provider: "suunto", availability: "available")])
    }

    func startDirectConnection(_: String) async throws -> DirectConnectionStart {
        throw DirectConnectionFailure.provider
    }

    func confirmDirectConnection(_: String, ticket _: String) async throws -> DirectConnection {
        throw DirectConnectionFailure.invalidResponse
    }

    func deleteDirectConnection(_ provider: String) async throws -> DirectConnectionDeleted {
        guard provider == "suunto", linked else { throw DirectConnectionFailure.unavailable }
        linked = false
        return .init(status: "disconnected", deregistered: false, dataDeleted: true)
    }
}

@MainActor
final class OnboardingConnectionsSimulatorFixture: DirectConnectionsAPI, DirectConnectionBrowser {
    private var connected: [DirectConnection] = []
    private let ticket = String(repeating: "a", count: 32)

    static func requested() -> OnboardingConnectionsSimulatorFixture? {
        ProcessInfo.processInfo.arguments.contains("-RyftOnboardingConnectionsFixture") ? .init() : nil
    }

    func directConnections() async throws -> DirectConnectionsResponse {
        .init(connections: connected,
              available: [.init(provider: "garmin", provides: ["workout"], history: "none", accepting: true)],
              providers: [.init(provider: "garmin", availability: "available"),
                          .init(provider: "suunto", availability: "partner_onboarding")])
    }

    func startDirectConnection(_ provider: String) async throws -> DirectConnectionStart {
        guard provider == "garmin", let url = URL(string: "https://connection-fixture.invalid/garmin") else {
            throw DirectConnectionFailure.unavailable
        }
        return .init(authorizeUrl: url, expiresAt: .distantFuture)
    }

    func authorize(_ url: URL) async throws -> URL {
        guard url.host == "connection-fixture.invalid", url.path == "/garmin",
              let callback = URL(string: "ryft://connect/garmin?status=ok&ticket=\(ticket)") else {
            throw DirectConnectionFailure.invalidResponse
        }
        return callback
    }

    func cancel() {}

    func confirmDirectConnection(_ provider: String, ticket: String) async throws -> DirectConnection {
        guard provider == "garmin", ticket == self.ticket else { throw DirectConnectionFailure.invalidResponse }
        let connection = DirectConnection(provider: provider, status: "connected", connectedAt: .now,
                                          lastDataAt: nil, provides: ["workout"], history: "none")
        connected = [connection]
        return connection
    }

    func deleteDirectConnection(_: String) async throws -> DirectConnectionDeleted {
        throw DirectConnectionFailure.unavailable
    }
}
#endif
