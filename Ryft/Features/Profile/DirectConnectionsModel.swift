import Foundation
import Observation

struct DirectProviderRow: Identifiable {
    enum Status: Equatable {
        case comingSoon, unavailable, full, available, waitingForData, connected, reauthorize, revoked

        var title: String {
            switch self {
            case .comingSoon: String(localized: "Coming soon")
            case .unavailable: String(localized: "Currently unavailable")
            case .full: String(localized: "Connection slots full")
            case .available: String(localized: "Available to connect")
            case .waitingForData: String(localized: "Connected · Waiting for data")
            case .connected: String(localized: "Connected")
            case .reauthorize: String(localized: "Reconnect required")
            case .revoked: String(localized: "Authorization revoked")
            }
        }
    }

    let id: String
    let availability: String
    let offer: DirectConnectionOffer?
    let connection: DirectConnection?

    var name: String {
        switch id {
        case "garmin": "Garmin"
        case "suunto": "Suunto"
        default: id.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    var status: Status {
        switch connection?.status {
        case "connected": return connection?.lastDataAt == nil ? .waitingForData : .connected
        case "needs_reauth": return .reauthorize
        case "revoked": return .revoked
        case .some: return .unavailable
        case .none: break
        }
        switch availability {
        case "partner_onboarding": return .comingSoon
        case "full": return .full
        case "available" where offer?.accepting == true: return .available
        default: return .unavailable
        }
    }

    var canConnect: Bool {
        status == .available || (status == .reauthorize && offer != nil) || (status == .revoked && offer?.accepting == true)
    }

    var canDisconnect: Bool { connection != nil && status != .revoked }
    var kinds: [SourceKind] { (connection?.provides ?? offer?.provides ?? []).compactMap(SourceKind.init(rawValue:)) }
}

@MainActor
@Observable
final class DirectConnectionsModel {
    private(set) var account: String?
    private(set) var current: DirectConnectionsResponse?
    private(set) var loading = false
    private(set) var loadFailure: DirectConnectionFailure?
    private(set) var actionFailure: DirectConnectionFailure?
    private(set) var activeProvider: String?
    private(set) var revocationPending = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeBrowser: DirectConnectionBrowser?

    var providers: [DirectProviderRow] {
        guard let current else { return [] }
        let ids = (current.providers.map(\.provider) + current.available.map(\.provider) + current.connections.map(\.provider))
            .filter(DirectConnectionLink.validProvider)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.map { id in
            DirectProviderRow(id: id, availability: current.providers.first(where: { $0.provider == id })?.availability ?? "unavailable",
                              offer: current.available.first(where: { $0.provider == id }),
                              connection: current.connections.first(where: { $0.provider == id }))
        }
    }

    func setAccount(_ value: String?) {
        guard account != value else { return }
        generation = UUID()
        account = value
        current = nil
        loading = false
        loadFailure = nil
        clearActionFeedback()
        activeProvider = nil
        activeBrowser?.cancel()
        activeBrowser = nil
    }

    func clearActionFeedback() {
        actionFailure = nil
        revocationPending = false
    }

    func refresh(_ api: any DirectConnectionsAPI) async {
        guard account != nil, !loading, activeProvider == nil else { return }
        let scope = generation
        loading = true
        loadFailure = nil
        defer { if generation == scope { loading = false } }
        do {
            let response = try await api.directConnections()
            try Task.checkCancellation()
            if generation == scope { current = response }
        } catch {
            if generation == scope, !error.isCancellation { loadFailure = .from(error) }
        }
    }

    func link(_ provider: String, api: any DirectConnectionsAPI, browser: DirectConnectionBrowser, now: @escaping () -> Date) async {
        guard account != nil, !loading, activeProvider == nil, providers.first(where: { $0.id == provider })?.canConnect == true else { return }
        let scope = generation
        activeProvider = provider
        activeBrowser = browser
        clearActionFeedback()
        do {
            let start = try await api.startDirectConnection(provider)
            try check(scope)
            let callback = try await browser.authorize(DirectConnectionLink.authorizeURL(start, now: now()))
            try check(scope)
            let ticket = try DirectConnectionLink.ticket(from: callback, provider: provider)
            let result = try await api.confirmDirectConnection(provider, ticket: ticket)
            try check(scope)
            guard result.provider == provider, result.status == "connected" else { throw DirectConnectionFailure.invalidResponse }
            apply(result, to: provider)
        } catch {
            if generation == scope, !error.isCancellation { actionFailure = .from(error) }
        }
        guard generation == scope else { return }
        activeBrowser = nil
        activeProvider = nil
        await refresh(api)
    }

    func unlink(_ provider: String, api: any DirectConnectionsAPI) async {
        guard account != nil, !loading, activeProvider == nil, providers.first(where: { $0.id == provider })?.canDisconnect == true else { return }
        let scope = generation
        activeProvider = provider
        clearActionFeedback()
        do {
            let result = try await api.deleteDirectConnection(provider)
            try check(scope)
            guard result.status == "disconnected", result.dataDeleted else { throw DirectConnectionFailure.invalidResponse }
            apply(nil, to: provider)
            revocationPending = result.deregistered == false
        } catch {
            if generation == scope, !error.isCancellation { actionFailure = .from(error) }
        }
        guard generation == scope else { return }
        activeProvider = nil
        await refresh(api)
    }

    private func apply(_ connection: DirectConnection?, to provider: String) {
        guard let current else { return }
        var updated = current.connections.filter { $0.provider != provider }
        if let connection { updated.append(connection) }
        self.current = DirectConnectionsResponse(connections: updated, available: current.available, providers: current.providers)
    }

    private func check(_ scope: UUID) throws {
        try Task.checkCancellation()
        guard scope == generation else { throw CancellationError() }
    }
}
