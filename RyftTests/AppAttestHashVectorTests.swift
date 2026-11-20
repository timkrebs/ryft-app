import CommonCrypto
import Foundation
import Testing
@testable import Ryft

/// AC1: `clientDataHash` is SHA-256 of the challenge's UTF-8 bytes, as received. Checked against NIST's published
/// vectors for the function and against CommonCrypto for the contract's example challenges, so CryptoKit isn't its
/// own witness.
@Suite("App Attest: clientDataHash (AC1)")
struct AppAttestHashVectorTests {
    /// The contract's example challenges (API.md → App Attest; `Fixtures/app_attest_*.json`).
    static let challenge1 = "q3Jx0mZ9cT1vY8kL2pW5nB7dF4hS6aE0uR3iO9yG1tM"
    static let challenge2 = "Zt0bH6wQ1cJ8mV3xR5kP9nY2sL7aD4fG0uE6iT1oW3M"

    static func commonCryptoSHA256(_ text: String) -> Data {
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let bytes = Array(text.utf8)
        CC_SHA256(bytes, CC_LONG(bytes.count), &out)
        return Data(out)
    }

    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ])
    func matchesNISTVectors(_ input: String, _ expected: String) {
        #expect(AppAttestor.clientDataHash(input).hex == expected)
    }

    @Test(arguments: [challenge1, challenge2, "ä€😀", "a+b/c=="])
    func equalsCommonCryptoOnTheUTF8Bytes(_ challenge: String) {
        #expect(AppAttestor.clientDataHash(challenge) == Self.commonCryptoSHA256(challenge))
        #expect(AppAttestor.clientDataHash(challenge).count == 32)
    }

    @Test func theChallengeIsHashedAsReceivedNotDecoded() {
        // Base64 text is not decoded first: the bytes of the string itself.
        #expect(AppAttestor.clientDataHash("YWJj") != AppAttestor.clientDataHash("abc"))
        #expect(AppAttestor.clientDataHash("YWJj") == Self.commonCryptoSHA256("YWJj"))
    }
}
