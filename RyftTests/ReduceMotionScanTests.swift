import Foundation
import Testing

/// Reduce Motion in Train and Journal (Theme.Motion, C §2.8, B §12; PR 6 ui-validator S7): every `withAnimation(…)` and
/// `.animation(…)` there takes `Theme.Motion.respecting(reduceMotion, …)`, the older `reduceMotion ? nil : …`, or a local
/// (`motion`, `animation`) declared as one of them; a bare `withAnimation { }` animates with the system's default under
/// Reduce Motion too. A `.numericText()` content transition becomes `.identity` under Reduce Motion. History's press feedback
/// (`PressableButtonStyle` in `Design/Card.swift`) is scanned with them: the session detail's card copies it.
///
/// A source scan, with comments left out; the planted cases below are its own control.
@Suite("Reduce Motion: Train and Journal animate only through the respecting helpers")
struct ReduceMotionScanTests {
    /// One finding: the file, the line, the call as written.
    struct Finding: CustomStringConvertible, Equatable {
        let file: String
        let line: Int
        let call: String
        var description: String { "\(file):\(line) \(call)" }
    }

    nonisolated static let folders = ["Ryft/Features/Train", "Ryft/Features/Journal"]
    nonisolated static let extraFiles = ["Ryft/Design/Card.swift"]

    @Test("Train, Journal and the press feedback: no animation that plays under Reduce Motion")
    func noBareAnimation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var files: [URL] = Self.extraFiles.map { root.appendingPathComponent($0) }
        for folder in Self.folders {
            let enumerator = try #require(FileManager.default.enumerator(at: root.appendingPathComponent(folder),
                                                                         includingPropertiesForKeys: nil))
            files += enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        #expect(files.count >= 60, "the folders were found: \(files.count)")
        var seen = 0
        var findings: [Finding] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let scan = Self.scan(source, file: file.lastPathComponent)
            seen += scan.calls
            findings += scan.findings
        }
        #expect(findings.isEmpty, "\(findings.map(\.description).joined(separator: "\n"))")
        // The scan saw the session's, the strip's, the import's and the journal's animations.
        #expect(seen >= 40, "animation calls seen: \(seen)")
    }

    @Test("The scan's own control: each bare form is caught, each respecting form passes")
    func theScanCatchesABareAnimation() {
        let bare = [
            "withAnimation { proxy.scrollTo(id) }",
            "withAnimation(Theme.Motion.quick) { open.toggle() }",
            "withAnimation(.easeOut(duration: 0.2)) { x = 1 }",
            "Text(\"a\").animation(.default, value: x)",
            "Text(\"a\").animation(Theme.Motion.quick, value: x)",
            "Text(\"a\").contentTransition(.numericText())",
            // A local that isn't a respecting one.
            "let motion = Theme.Motion.quick\nwithAnimation(motion) { x = 1 }",
        ]
        for code in bare {
            #expect(Self.scan(code, file: "planted").findings.count == 1, "caught: \(code)")
        }
        let respecting = [
            "withAnimation(Theme.Motion.respecting(reduceMotion)) { x = 1 }",
            "withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) { x = 1 }",
            "withAnimation(reduceMotion ? nil : Theme.Motion.quick) { x = 1 }",
            "Text(\"a\").animation(Theme.Motion.respecting(reduceMotion), value: x)",
            "private var motion: Animation? { Theme.Motion.respecting(reduceMotion) }\nwithAnimation(motion) { x = 1 }",
            "let animation = Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)\nwithAnimation(animation) { x = 1 }",
            "Text(\"a\").contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))",
            "Text(\"a\").contentTransition(.opacity)",
            "// withAnimation { a comment }",
        ]
        for code in respecting {
            #expect(Self.scan(code, file: "planted").findings.isEmpty, "passes: \(code)")
        }
    }

    // MARK: the scan

    /// Every animation call in `source` and the ones that would play under Reduce Motion.
    static func scan(_ source: String, file: String) -> (calls: Int, findings: [Finding]) {
        // The code only, line by line so the numbers stay: a comment may name a bare animation to say why it isn't used.
        // `//` after a colon is a URL's.
        let lines = source.components(separatedBy: "\n").map { $0.replacing(#/(^|[^:])//.*/#) { String($0.output.1) } }
        let code = lines.joined(separator: "\n")
        var calls = 0
        var findings: [Finding] = []
        for match in code.matches(of: #/withAnimation\s*(\(|\{)|\.animation\(|\.contentTransition\(/#) {
            let line = code[..<match.range.lowerBound].filter { $0 == "\n" }.count + 1
            let call = String(code[match.range])
            calls += 1
            let argument = call.hasSuffix("{") ? nil : Self.firstArgument(code, from: match.range.upperBound)
            let fine: Bool
            if call.hasPrefix(".contentTransition") {
                fine = argument.map { !$0.contains("numericText") || $0.hasPrefix("reduceMotion ? .identity") } ?? true
            } else if let argument {
                fine = Self.isRespecting(argument, in: code)
            } else {
                fine = false
            }
            if !fine {
                findings.append(Finding(file: file, line: line, call: "\(call)\(argument ?? "")"))
            }
        }
        return (calls, findings)
    }

    /// The text of the call's first argument, up to the `,` or `)` that closes it at its own depth.
    static func firstArgument(_ code: String, from start: String.Index) -> String {
        var depth = 0
        var end = start
        while end < code.endIndex {
            let c = code[end]
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            if c == ")" || c == "]" || c == "}" {
                if depth == 0 { break }
                depth -= 1
            }
            if c == ",", depth == 0 { break }
            end = code.index(after: end)
        }
        return code[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `Theme.Motion.respecting(…)`, `reduceMotion ? nil : …`, `nil`, or a local declared as one of them in the same file.
    static func isRespecting(_ argument: String, in code: String) -> Bool {
        if argument.hasPrefix("Theme.Motion.respecting(") || argument.hasPrefix("reduceMotion ? nil :") || argument == "nil" {
            return true
        }
        guard argument.wholeMatch(of: #/[a-z][A-Za-z0-9]*/#) != nil else { return false }
        // `let animation = Theme.Motion.respecting(…)`, `private var motion: Animation? { Theme.Motion.respecting(…) }`.
        for match in code.matches(of: #/(?:let|var)\s+([a-z][A-Za-z0-9]*)\b[^\n=\{]*(?:=|\{)\s*([^\n]*)/#)
            where match.output.1 == argument {
            let value = match.output.2
            if value.hasPrefix("Theme.Motion.respecting(") || value.hasPrefix("reduceMotion ? nil :") { return true }
        }
        return false
    }
}
