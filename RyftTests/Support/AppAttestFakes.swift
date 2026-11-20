import DeviceCheck
import Foundation
@testable import Ryft

/// `DCAppAttestService` in memory: hands out `key-1`, `key-2` …, records every call with its `clientDataHash`, and
/// throws what `failNext` scripts (per method, first in, first out).
final class FakeAppAttestService: AppAttestService, @unchecked Sendable {
    enum Call: Equatable {
        case generateKey
        case attestKey(String, Data)
        case generateAssertion(String, Data)
    }

    private let lock = NSLock()
    private var _supported: Bool
    private var _calls: [Call] = []
    private var keys = 0
    private var failures: [String: [Error]] = [:]

    init(supported: Bool = true) {
        _supported = supported
    }

    var isSupported: Bool { lock.withLock { _supported } }
    var calls: [Call] { lock.withLock { _calls } }

    /// The next call of `method` ("generateKey", "attestKey", "generateAssertion") throws `error`.
    func failNext(_ method: String, with error: Error) {
        lock.withLock { failures[method, default: []].append(error) }
    }

    private func record(_ call: Call, _ method: String) throws {
        let failure: Error? = lock.withLock {
            _calls.append(call)
            return failures[method]?.isEmpty == false ? failures[method]?.removeFirst() : nil
        }
        if let failure { throw failure }
    }

    func generateKey() async throws -> String {
        try record(.generateKey, "generateKey")
        return lock.withLock {
            keys += 1
            return "key-\(keys)"
        }
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try record(.attestKey(keyId, clientDataHash), "attestKey")
        return Data("attestation-\(keyId)".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try record(.generateAssertion(keyId, clientDataHash), "generateAssertion")
        return Data("assertion-\(keyId)".utf8)
    }
}

/// The Keychain item in memory. `locked`: `load()` throws, as before the first unlock.
final class MemoryAppAttestKeys: AppAttestKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: StoredAppAttestKey?
    private var _locked = false

    init(_ stored: StoredAppAttestKey? = nil) {
        _stored = stored
    }

    var stored: StoredAppAttestKey? { lock.withLock { _stored } }
    var locked: Bool {
        get { lock.withLock { _locked } }
        set { lock.withLock { _locked = newValue } }
    }

    func load() throws -> StoredAppAttestKey? {
        try lock.withLock {
            if _locked { throw Keychain.Failure(status: errSecInteractionNotAllowed) }
            return _stored
        }
    }

    func save(_ key: StoredAppAttestKey) throws {
        lock.withLock { _stored = key }
    }

    func remove() {
        lock.withLock { _stored = nil }
    }
}
