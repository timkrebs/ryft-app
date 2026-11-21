import Foundation
import Testing

/// PR 6 security review N-4: whatever the app copies (Copy details, Copy request ID, Copy message, Copy diagnostics) stays on
/// this iPhone and expires (`LocalPasteboard`: not Handoff's universal clipboard, gone after ten minutes). The options can't be
/// read back from the pasteboard, so the sources are the check: no code but `LocalPasteboard` touches `UIPasteboard`.
struct LocalPasteboardTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("Every copy goes through LocalPasteboard: no other code in the app writes to UIPasteboard")
    func everyCopyIsLocal() throws {
        var found: [String] = []
        var keeper = 0
        let files = try #require(FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            // The code only: a comment may name it. `//` after a colon is a URL's.
            var code = source.replacing(#/(^|[^:])//.*/#) { String($0.output.1) }
            // `LocalPasteboard` itself, up to the closing brace of its enum.
            if let start = code.range(of: "enum LocalPasteboard {"),
               let end = code.range(of: "\n}\n", range: start.upperBound..<code.endIndex) {
                keeper += 1
                code.removeSubrange(start.lowerBound..<end.upperBound)
            }
            for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("UIPasteboard") {
                found.append("\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(keeper == 1, "LocalPasteboard is where it was looked for")
        #expect(found.isEmpty, "\(found)")
    }
}
