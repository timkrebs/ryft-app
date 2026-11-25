#if DEBUG
import CryptoKit
import Security
import Foundation

struct LocalGarminPairing {
    let endpoint: URL
    let fingerprint: String
    let token: String

    init?(_ link: String) {
        guard var url = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.user == nil, url.password == nil, url.query == nil,
              url.path.isEmpty || url.path == "/", url.port == 8785,
              let host = url.host, Self.isLocal(host), let fragment = url.fragment else { return nil }
        let fields = fragment.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 2, fields.allSatisfy(Self.isHexKey) else { return nil }
        url.fragment = nil
        url.path = "/v1/local/garmin/activities"
        guard let endpoint = url.url else { return nil }
        self.endpoint = endpoint
        fingerprint = String(fields[0])
        token = String(fields[1])
    }

    private static func isHexKey(_ value: Substring) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func isLocal(_ host: String) -> Bool {
        let fields = host.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4 else { return false }
        let octets = fields.compactMap { field -> UInt8? in
            guard let value = UInt8(field), String(value) == field else { return nil }
            return value
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
}

private final class LocalGarminTrust: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    private let fingerprint: String

    init(host: String, fingerprint: String) {
        self.host = host
        self.fingerprint = fingerprint
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == fingerprint,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LocalGarminSnapshot: Decodable {
    struct Activity: Decodable {
        let sport: String?
        let startedAtLocal: String?
        let durationSeconds: Double?
        let distanceMeters: Double?
    }

    let provider: String
    let fetchedAt: Date
    let activities: [Activity]

    static func loadUSB() throws -> Self {
        let file = URL.temporaryDirectory.appending(path: "ryft-garmin-preview.json")
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw LocalGarminFailure.usbMissing }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: file)
        }
        let maximumBytes = 16 * 1024
        guard let data = try handle.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else {
            throw LocalGarminFailure.response
        }
        return try decodeUSB(data, now: .now)
    }

    static func decodeUSB(_ data: Data, now: Date) throws -> Self {
        let snapshot = try decodePreview(data)
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard (-60...30 * 60).contains(age) else { throw LocalGarminFailure.usbExpired }
        return snapshot
    }

    private static func decodePreview(_ data: Data) throws -> Self {
        guard let snapshot = try? APIClient.jsonDecoder.decode(Self.self, from: data),
              snapshot.provider == "garmin", snapshot.activities.count <= 5 else { throw LocalGarminFailure.response }
        return snapshot
    }

    static func fetch(_ pairing: LocalGarminPairing) async throws -> Self {
        guard let host = pairing.endpoint.host else { throw URLError(.badURL) }
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 35
        let session = URLSession(configuration: config,
                                 delegate: LocalGarminTrust(host: host, fingerprint: pairing.fingerprint),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: pairing.endpoint)
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            try Task.checkCancellation()
            throw LocalGarminFailure(transport: error.code)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw LocalGarminFailure.response }
        switch status {
        case 200: return try decodePreview(data)
        case 401: throw LocalGarminFailure.pairing
        case 502: throw LocalGarminFailure.garmin
        default: throw LocalGarminFailure.http(status)
        }
    }
}

enum LocalGarminFailure: LocalizedError, Equatable {
    case link, network, certificate, pairing, garmin, response, usbMissing, usbExpired
    case transport(Int), http(Int)

    init(transport code: URLError.Code) {
        switch code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut,
             .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed:
            self = .network
        case .cancelled, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .appTransportSecurityRequiresSecureConnection:
            self = .certificate
        default:
            self = .transport(code.rawValue)
        }
    }

    var errorDescription: String? {
        switch self {
        case .link: String(localized: "Paste the complete pairing link printed by the local API.")
        case .network: String(localized: "RYFT couldn’t reach the Mac. Allow Local Network access in Settings, use the same Wi-Fi and keep the Mac terminal running.")
        case .certificate: String(localized: "RYFT couldn’t verify the Mac’s certificate. Paste the full pairing link from the running terminal session.")
        case .pairing: String(localized: "Use the pairing link from the current terminal session.")
        case .garmin: String(localized: "The Mac reached the Garmin API but couldn’t load activities. Check the Mac terminal for details.")
        case .response: String(localized: "The Mac returned an unexpected Garmin response. Restart the test with the current script.")
        case .usbMissing: String(localized: "No USB preview found. Run the Garmin test with --usb-device on the connected Mac first.")
        case .usbExpired: String(localized: "This USB preview expired. Run the Garmin test on the Mac again.")
        case .transport(let code): String(localized: "The connection to the Mac failed (code \(code)).")
        case .http(let status): String(localized: "The local API returned HTTP \(status). Check that the Garmin test is running.")
        }
    }
}

#endif
