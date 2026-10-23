import Foundation
@testable import Ryft

private final class BundleToken {}

enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: name, withExtension: "json") { return try Data(contentsOf: url) }
        // A fixture not yet in the test target's resources (the project file lists them until RyftTests is a
        // synchronized folder): read it from the source tree.
        let source = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: source)
    }

    /// Decodes with the app's real decoder (snake_case, RFC3339 with fractions).
    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIClient.jsonDecoder.decode(T.self, from: data(name))
    }
}
