import Foundation
import Testing
@testable import Ryft

@MainActor
struct DirectConnectionsTests {
    private let now = Date(timeIntervalSince1970: 1_795_537_800)
    private let fixtureTicket = String(repeating: "a1", count: 16)

    @Test func decodesProductionCatalogAndKeepsOnboardingDisabled() async throws {
        let raw = """
        {"connections":[],"available":[],"providers":[
          {"provider":"garmin","availability":"partner_onboarding"},
          {"provider":"suunto","availability":"partner_onboarding"}
        ]}
        """
        let response = try APIClient.jsonDecoder.decode(DirectConnectionsResponse.self, from: Data(raw.utf8))
        let api = DirectConnectionTestAPI(response: response)
        let model = DirectConnectionsModel()
        model.setAccount("athlete")
        await model.refresh(api)
        #expect(model.providers.map(\.name) == ["Garmin", "Suunto"])
        #expect(model.providers.allSatisfy { $0.status == .comingSoon && !$0.canConnect && !$0.canDisconnect })
        await model.link("garmin", api: api, browser: DirectConnectionTestBrowser(), now: { now })
        #expect(api.starts == 0)
    }

    @Test func decodesDirectHealthProvenanceAndIgnoresUnknownCapabilities() throws {
        let raw = """
        {"name":"Suunto","bundle_id":null,"kinds":["sleep","future_value"],"last_seen":"2026-11-24T15:00:00Z"}
        """
        let direct = raw.replacingOccurrences(of: "{", with: #"{"origin":"direct","#)
        let decoder = APIClient.jsonDecoder
        #expect(try decoder.decode(UserSource.self, from: Data(raw.utf8)).origin == .healthkit)
        let source = try decoder.decode(UserSource.self, from: Data(direct.utf8))
        #expect(source.origin == .direct)
        #expect(source.kinds == [.sleep])
        let row = DirectProviderRow(id: "suunto", availability: "available",
                                    offer: .init(provider: "suunto", provides: ["sleep", "future_value"], history: "none", accepting: true),
                                    connection: nil)
        #expect(row.kinds == [.sleep])
    }

    @Test func validatesAccountLinkAndStructuredErrors() throws {
        let valid = try #require(URL(string: "ryft://connect/garmin?status=ok&ticket=\(fixtureTicket)"))
        #expect(try DirectConnectionLink.ticket(from: valid, provider: "garmin") == fixtureTicket)
        for path in [
            "https://connect/garmin?status=ok&ticket=\(fixtureTicket)",
            "ryft://other/garmin?status=ok&ticket=\(fixtureTicket)",
            "ryft://connect/suunto?status=ok&ticket=\(fixtureTicket)",
            "ryft://connect/%67armin?status=ok&ticket=\(fixtureTicket)",
            "ryft://connect/garmin?status=ok&status=ok&ticket=\(fixtureTicket)",
            "ryft://connect/garmin?status=ok&ticket=\(fixtureTicket)&ticket=\(fixtureTicket)",
            "ryft://user@connect/garmin?status=ok&ticket=\(fixtureTicket)",
            "ryft://connect/garmin?status=ok&ticket=\(fixtureTicket)#fragment",
            "ryft://connect/garmin?status=ok&ticket=other",
        ] {
            let url = try #require(URL(string: path))
            #expect(throws: DirectConnectionFailure.invalidResponse) { try DirectConnectionLink.ticket(from: url, provider: "garmin") }
        }
        let expired = try #require(URL(string: "ryft://connect/garmin?status=expired"))
        #expect(throws: DirectConnectionFailure.expired) { try DirectConnectionLink.ticket(from: expired, provider: "garmin") }
        let url = try #require(URL(string: "https://partner.example/auth"))
        let form = DirectConnectionStart(authorizeUrl: url, expiresAt: now)
        #expect(throws: DirectConnectionFailure.expired) { try DirectConnectionLink.authorizeURL(form, now: now) }
        #expect(DirectConnectionFailure.from(APIError.http(409, "", code: .connectTicketInvalid)) == .invalidResponse)
        #expect(DirectConnectionFailure.from(APIError.http(409, "", code: .connectionLimit)) == .capacity)
        #expect(DirectConnectionFailure.from(APIError.http(403, "", code: .consentRequired)) == .consent)
    }

    @Test func verifiesLinkAndDeletionWithServer() async {
        let api = DirectConnectionTestAPI(response: available(), now: now)
        let model = DirectConnectionsModel()
        model.setAccount("athlete")
        await model.refresh(api)
        let browser = DirectConnectionTestBrowser()
        browser.callback = URL(string: "ryft://connect/garmin?status=ok&ticket=\(fixtureTicket)")
        browser.onStart = { #expect(model.providers.first?.status == .available) }
        await model.link("garmin", api: api, browser: browser, now: { now })
        #expect(api.confirmations == [fixtureTicket])
        #expect(model.providers.first?.status == .waitingForData)
        #expect(model.providers.first?.canDisconnect == true)
        await model.unlink("garmin", api: api)
        #expect(api.deletions == 1)
        #expect(model.providers.first?.status == .available)
    }

    @Test func cancellationAndAccountChangeDiscardPendingAuthorization() async {
        let api = DirectConnectionTestAPI(response: available(), now: now)
        let model = DirectConnectionsModel()
        model.setAccount("one")
        await model.refresh(api)
        let browser = DirectConnectionTestBrowser()
        await model.link("garmin", api: api, browser: browser, now: { now })
        #expect(model.activeProvider == nil && model.actionFailure == nil)
        #expect(api.confirmations.isEmpty)
        browser.callback = URL(string: "ryft://connect/garmin?status=ok&ticket=\(fixtureTicket)")
        browser.onStart = { model.setAccount("two") }
        await model.link("garmin", api: api, browser: browser, now: { now })
        #expect(browser.cancelled)
        #expect(api.confirmations.isEmpty)
        #expect(model.current == nil && model.providers.isEmpty)
    }

    @Test func retainingStatusOnTemporaryFailureNeverCrossesAccounts() async {
        let api = DirectConnectionTestAPI(response: available())
        let model = DirectConnectionsModel()
        model.setAccount("one")
        await model.refresh(api)
        api.listError = APIError.transport(URLError(.notConnectedToInternet))
        await model.refresh(api)
        #expect(model.loadFailure == .offline)
        #expect(model.providers.first?.status == .available)
        model.setAccount("two")
        #expect(model.current == nil && model.loadFailure == nil)
    }

    @Test func reauthorizationUsesServerOfferAndExistingConnection() {
        let conn = DirectConnection(provider: "garmin", status: "needs_reauth", connectedAt: now, lastDataAt: now,
                                    provides: ["hr"], history: "none")
        let offer = DirectConnectionOffer(provider: "garmin", provides: ["hr"], history: "none", accepting: false)
        let row = DirectProviderRow(id: "garmin", availability: "full", offer: offer, connection: conn)
        #expect(row.status == .reauthorize && row.canConnect && row.canDisconnect)
        let unavailable = DirectProviderRow(id: "garmin", availability: "unavailable", offer: nil, connection: conn)
        #expect(!unavailable.canConnect && unavailable.canDisconnect)
    }

    private func available() -> DirectConnectionsResponse {
        DirectConnectionsResponse(connections: [],
                                  available: [.init(provider: "garmin", provides: ["sleep"], history: "none", accepting: true)],
                                  providers: [.init(provider: "garmin", availability: "available")])
    }
}

private final class DirectConnectionTestAPI: DirectConnectionsAPI {
    var response: DirectConnectionsResponse
    var listError: Error?
    let now: Date
    var starts = 0
    var confirmations: [String] = []
    var deletions = 0

    init(response: DirectConnectionsResponse, now: Date = Date(timeIntervalSince1970: 0)) {
        self.response = response
        self.now = now
    }

    func directConnections() async throws -> DirectConnectionsResponse {
        if let listError { throw listError }
        return response
    }

    func startDirectConnection(_: String) async throws -> DirectConnectionStart {
        starts += 1
        guard let url = URL(string: "https://partner.example/auth") else { throw DirectConnectionFailure.invalidResponse }
        return DirectConnectionStart(authorizeUrl: url, expiresAt: now.addingTimeInterval(300))
    }

    func confirmDirectConnection(_ provider: String, ticket: String) async throws -> DirectConnection {
        confirmations.append(ticket)
        let result = DirectConnection(provider: provider, status: "connected", connectedAt: now, lastDataAt: nil,
                                      provides: ["sleep"], history: "none")
        response = .init(connections: [result], available: response.available, providers: response.providers)
        return result
    }

    func deleteDirectConnection(_: String) async throws -> DirectConnectionDeleted {
        deletions += 1
        response = .init(connections: [], available: response.available, providers: response.providers)
        return .init(status: "disconnected", deregistered: nil, dataDeleted: true)
    }
}

@MainActor
private final class DirectConnectionTestBrowser: DirectConnectionBrowser {
    var callback: URL?
    var onStart: (() -> Void)?
    var cancelled = false

    func authorize(_: URL) async throws -> URL {
        onStart?()
        guard let callback else { throw CancellationError() }
        return callback
    }

    func cancel() { cancelled = true }
}
