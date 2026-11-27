import Foundation

protocol DirectConnectionsAPI {
    func directConnections() async throws -> DirectConnectionsResponse
    func startDirectConnection(_ provider: String) async throws -> DirectConnectionStart
    func confirmDirectConnection(_ provider: String, ticket: String) async throws -> DirectConnection
    func deleteDirectConnection(_ provider: String) async throws -> DirectConnectionDeleted
}

extension APIClient: DirectConnectionsAPI {
    /// The Platform keeps disconnect and direct-data deletion open for any signed-in account.
    static func isDirectConnectionDelete(_ method: String, _ path: String) -> Bool {
        let prefix = "/v1/me/connections/"
        let route = Self.route(path)
        guard method == "DELETE", route.hasPrefix(prefix) else { return false }
        return DirectConnectionLink.validProvider(String(route.dropFirst(prefix.count)))
    }

    func directConnections() async throws -> DirectConnectionsResponse {
        try await send("GET", path: "/v1/me/connections", body: Optional<Int>.none)
    }

    func startDirectConnection(_ provider: String) async throws -> DirectConnectionStart {
        try await send("POST", path: connectionPath(provider) + "/start", body: Optional<Int>.none)
    }

    func confirmDirectConnection(_ provider: String, ticket: String) async throws -> DirectConnection {
        try await send("POST", path: connectionPath(provider) + "/confirm", body: DirectConnectionConfirmation(ticket: ticket))
    }

    func deleteDirectConnection(_ provider: String) async throws -> DirectConnectionDeleted {
        try await send("DELETE", path: connectionPath(provider), body: Optional<Int>.none)
    }

    private func connectionPath(_ provider: String) throws -> String {
        guard DirectConnectionLink.validProvider(provider) else { throw DirectConnectionFailure.invalidResponse }
        return "/v1/me/connections/\(provider)"
    }
}
