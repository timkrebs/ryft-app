// The seams `AppAttestor` stands on (ADR 0023): Apple's App Attest service and the Keychain item that keeps the
// attested key's ID with its account. Tests replace both (a fake service, an in-memory store).
import DeviceCheck
import Foundation

/// Whose run a renewal is: the account it was started for and the `APIStatus.epoch` of its requests. A renewal saves
/// a key or publishes a token only while the stamp is still this one (design.md §2).
struct AttestStamp: Equatable, Sendable {
    let account: String
    let epoch: Int
}

/// The Keychain item: one key per account on this install. `attested`: `POST /v1/app-attest/keys` answered `201`.
/// The key ID identifies the install: never logged, recorded or shown.
struct StoredAppAttestKey: Codable, Equatable, Sendable {
    let account: String
    let keyId: String
    var attested: Bool
}

/// `DCAppAttestService`, behind a protocol (live: `DeviceAppAttestService`).
protocol AppAttestService: Sendable {
    /// False on the Simulator and on devices without the Secure Enclave support App Attest needs.
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// The device's App Attest service. `DCAppAttestService.shared` is read per call, never stored.
struct DeviceAppAttestService: AppAttestService {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

/// Where the attested key's ID is kept (live: `KeychainAppAttestKeys`).
protocol AppAttestKeyStore: Sendable {
    /// The stored key, or nil when there is none. Throws when the store can't be read (before the first unlock),
    /// which is not "no key".
    func load() throws -> StoredAppAttestKey?
    func save(_ key: StoredAppAttestKey) throws
    func remove()
}

/// One generic-password item, `ryft.appAttest.key`, holding `StoredAppAttestKey` as JSON:
/// `AfterFirstUnlockThisDeviceOnly` (background runs read it; never restored onto another device, where the key
/// doesn't exist) and never synchronizable.
struct KeychainAppAttestKeys: AppAttestKeyStore {
    static let item = "ryft.appAttest.key"

    func load() throws -> StoredAppAttestKey? {
        guard let json = try Keychain.read(Self.item) else { return nil }
        // An item this build can't read is no key: the next attestation replaces it.
        return try? JSONDecoder().decode(StoredAppAttestKey.self, from: Data(json.utf8))
    }

    func save(_ key: StoredAppAttestKey) throws {
        let json = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
        let status = Keychain.set(json, for: Self.item, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        guard status == errSecSuccess else { throw Keychain.Failure(status: status) }
    }

    func remove() {
        Keychain.set(nil, for: Self.item)
    }
}
