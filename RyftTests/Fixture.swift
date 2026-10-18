import Foundation
@testable import Ryft

private final class BundleToken {}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    /// Decodes with the app's real decoder (snake_case, RFC3339 with fractions).
    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIClient.jsonDecoder.decode(T.self, from: data(name))
    }
}
