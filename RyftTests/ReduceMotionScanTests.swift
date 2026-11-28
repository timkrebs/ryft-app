import Foundation
import Testing

/// Reduce Motion across the app (Theme.Motion, C §2.8, B §12; PR 6 ui-validator S7, review code N3): a source scan of every
/// Swift file in `Ryft/`, comments left out, for each way SwiftUI starts motion.
/// - `withAnimation(…)` and `.animation(…)` take `Theme.Motion.respecting(<the reduce-motion value>, …)`,
///   `reduceMotion ? nil : …`, `nil`, or a local whose every declaration in the file is one of those; a bare
///   `withAnimation { }` animates with the system's default under Reduce Motion too.
/// - `withTransaction(…)` and `.transaction { }` set no animation, or one of those.
/// - `.contentTransition(…)` is `.opacity`, `.identity` or `reduceMotion ? .identity : …`.
/// - `.symbolEffect(…)` has an `isActive:` that's off under Reduce Motion (`… && !reduceMotion`).
/// - `TimelineView(.animation…)` is paused under Reduce Motion (`paused: reduceMotion || …`).
/// - `phaseAnimator` and `keyframeAnimator` (modifier or view) are always listed.
///
/// What the rules can't see (an `if reduceMotion` around the call, a ternary that picks a fade or one phase) is named in
/// `guarded`, file, call and count, each with its reason; an entry that matches nothing, or another count, fails too. The
/// planted cases below are the scan's own control.
@Suite("Reduce Motion: every animation in the app goes through the respecting helpers, or a guard named here")
struct ReduceMotionScanTests {
    /// One finding: the file under `Ryft/`, the line, the call as written (whitespace runs as one space).
    struct Finding: CustomStringConvertible, Equatable {
        let file: String
        let line: Int
        let call: String
        var description: String { "\(file):\(line) \(call)" }
    }

    /// A call the rules can't prove, guarded around it: `file` under `Ryft/`, `call` as the scan writes it, `count` of
    /// them in that file.
    struct Guarded: Equatable {
        let file: String
        let call: String
        var count = 1
        let reason: String
    }

    nonisolated static let guarded: [Guarded] = [
        Guarded(file: "App/LaunchHost.swift", call: "TimelineView(.animation(paused: !model.isAnimating)",
                reason: "The launch's clock: under Reduce Motion `LaunchSequence` plays `.reduced`, the last frame faded in and out."),
        Guarded(file: "Design/ChartStyle.swift", call: "withAnimation(ChartStyle.appear",
                reason: "`ChartAppear`: the `else` of `if reduceMotion { shown = true }`."),
        Guarded(file: "Design/DateStrip.swift", call: "withAnimation(animated ? Theme.Motion.respecting(reduceMotion) : nil",
                reason: "A ternary of the respecting animation and none."),
        Guarded(file: "Design/OrbitGauge.swift", call: "TimelineView(.animation(paused: frozenAt != nil || entranceDone)",
                reason: "The entrance's clock: under Reduce Motion (`reducesEntrance`) the stage is a cross-fade and nothing moves."),
        Guarded(file: "Design/OrbitGauge.swift", call: ".animation(reduceMotion ? Theme.Motion.quick : Theme.Motion.slow",
                reason: "Under Reduce Motion the drawing is replaced (`.id(mode)`, `.transition(.opacity)`): this times that cross-fade; no arc moves."),
        Guarded(file: "Design/OrbitGauge.swift", call: "withAnimation(.easeOut(duration: 0.06)",
                reason: "`stepFill`: after `guard steps`, and `steps` is `animatesFill && !reduceMotion`."),
        Guarded(file: "Design/OrbitGauge.swift", call: ".phaseAnimator(mode.isPending && breathes && !reduceMotion ? [1.0, 0.75] : [1.0]",
                reason: "One phase, so no motion, under Reduce Motion."),
        Guarded(file: "Design/RyftTabBar.swift", call: ".animation(Self.selectionAnimation(reduceMotion: reduceMotion)",
                reason: "`selectionAnimation(reduceMotion:)` is `Theme.Motion.respecting(reduceMotion)` (RyftTabBarTests)."),
        Guarded(file: "Features/Profile/DebugComponentCatalog.swift", call: "TimelineView(.animation",
                reason: "DEBUG only: the catalog's launch replay plays the variant its own Reduce Motion switch picks."),
        Guarded(file: "Features/Sleep/SleepView.swift", call: "withAnimation(Theme.ringAnimation",
                reason: "`if reduceMotion { shown = target } else { withAnimation … }`."),    ]

    /// A file naming none of these starts no motion the scan knows; the rest are scanned.
    nonisolated static let triggers = ["withAnimation", ".animation", ".contentTransition", "withTransaction", ".transaction",
                                       "Animator", ".symbolEffect", "TimelineView"]

    @Test("Every Swift file in Ryft/: no animation that plays under Reduce Motion but the guarded ones named here")
    func noBareAnimation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ryft")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }
        #expect(paths.count >= 300, "Ryft/ was found: \(paths.count) files")
        var seen = 0
        var findings: [Finding] = []
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            guard Self.triggers.contains(where: { source.contains($0) }) else { continue }
            let scan = Self.scan(source, file: path)
            seen += scan.calls
            findings += scan.findings
        }
        let applied = Self.apply(Self.guarded, to: findings)
        #expect(applied.left.isEmpty, "\(applied.left.map(\.description).joined(separator: "\n"))")
        #expect(applied.unmatched.isEmpty,
                "entries without their findings: \(applied.unmatched.map { "\($0.file) \($0.call) ×\($0.count)" })")
        // The app's own (Today, Sleep, the gauges, onboarding), Train's and the journal's: 109 once the gate deleted
        // `MetricGauge` and `ScoreRing`.
        #expect(seen >= 105, "animation calls seen: \(seen)")
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
            // The helper, but not told about Reduce Motion.
            "withAnimation(Theme.Motion.respecting(false)) { x = 1 }",
            "withAnimation(Theme.Motion.respecting(isOpen, Theme.Motion.quick)) { x = 1 }",
            // The same name respecting in one view and not in another: the scan can't tell scopes, so it's listed.
            "struct A { var motion: Animation? { Theme.Motion.respecting(reduceMotion) } }\n"
                + "struct B { let motion = Theme.Motion.quick\n func f() { withAnimation(motion) { x = 1 } } }",
            "Text(\"a\").contentTransition(.interpolate)",
            "withTransaction(Transaction(animation: .default)) { x = 1 }",
            "withTransaction(\\.animation, .spring) { x = 1 }",
            "withTransaction(transaction) { x = 1 }",
            "Text(\"a\").transaction { $0.animation = .default }",
            "Text(\"a\").transaction(value: x) { t in t.animation = Theme.Motion.quick }",
            "Text(\"a\").phaseAnimator([0.0, 1.0]) { v, p in v.opacity(p) }",
            "PhaseAnimator([0.0, 1.0]) { p in Text(\"a\").opacity(p) }",
            "Text(\"a\").keyframeAnimator(initialValue: 0.0) { v, k in v.opacity(k) } keyframes: { _ in LinearKeyframe(1.0, duration: 1) }",
            "KeyframeAnimator(initialValue: 0.0) { k in Text(\"a\").opacity(k) } keyframes: { _ in LinearKeyframe(1.0, duration: 1) }",
            "Image(systemName: \"a\").symbolEffect(.pulse)",
            "Image(systemName: \"a\").symbolEffect(.pulse, isActive: busy)",
            "Image(systemName: \"a\").symbolEffect(.pulse, isActive: busy || !reduceMotion)",
            "TimelineView(.animation) { c in Text(c.date, style: .time) }",
            "TimelineView(.animation(paused: done)) { c in Text(c.date, style: .time) }",
            "TimelineView(.animation(paused: done && reduceMotion)) { c in Text(c.date, style: .time) }",
        ]
        for code in bare {
            #expect(Self.scan(code, file: "planted").findings.count == 1, "caught: \(code)")
        }
        let respecting = [
            "withAnimation(Theme.Motion.respecting(reduceMotion)) { x = 1 }",
            "withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) { x = 1 }",
            "withAnimation(Theme.Motion.respecting(forcedReduceMotion ?? systemReduceMotion)) { x = 1 }",
            "withAnimation(reduceMotion ? nil : Theme.Motion.quick) { x = 1 }",
            "Text(\"a\").animation(Theme.Motion.respecting(reduceMotion), value: x)",
            "private var motion: Animation? { Theme.Motion.respecting(reduceMotion) }\nwithAnimation(motion) { x = 1 }",
            "let animation = Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)\nwithAnimation(animation) { x = 1 }",
            "Text(\"a\").contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))",
            "Text(\"a\").contentTransition(.opacity)",
            "// withAnimation { a comment }",
            "withTransaction(Transaction(animation: Theme.Motion.respecting(reduceMotion))) { x = 1 }",
            "withTransaction(\\.disablesAnimations, true) { x = 1 }",
            "withTransaction(\\.animation, reduceMotion ? nil : .default) { x = 1 }",
            "Text(\"a\").transaction { $0.animation = nil }",
            "Text(\"a\").transaction { $0.disablesAnimations = true }",
            "Text(\"a\").transaction(value: x) { t in t.animation = Theme.Motion.respecting(reduceMotion) }",
            "Image(systemName: \"a\").symbolEffect(.pulse, options: .repeating, isActive: busy && !reduceMotion)",
            "TimelineView(.animation(paused: reduceMotion || done)) { c in Text(c.date, style: .time) }",
            "TimelineView(.everyMinute) { c in Text(c.date, style: .time) }",
        ]
        for code in respecting {
            #expect(Self.scan(code, file: "planted").findings.isEmpty, "passes: \(code)")
        }
    }

    @Test("The allowlist's own control: a guarded call is taken off; an entry that matches nothing, or another count, is named")
    func theAllowlistNamesWhatItDoesntMatch() {
        let findings = [Finding(file: "Design/A.swift", line: 3, call: "withAnimation(Theme.ringAnimation"),
                        Finding(file: "Design/A.swift", line: 9, call: "withAnimation(Theme.ringAnimation"),
                        Finding(file: "Design/B.swift", line: 1, call: ".phaseAnimator([1.0]")]
        let twice = Guarded(file: "Design/A.swift", call: "withAnimation(Theme.ringAnimation", count: 2, reason: "planted")
        let applied = Self.apply([twice], to: findings)
        #expect(applied.left == [findings[2]] && applied.unmatched.isEmpty)
        // Once where the file has it twice, and a file that has it not at all: both findings stay, both entries are named.
        let once = Guarded(file: "Design/A.swift", call: "withAnimation(Theme.ringAnimation", reason: "planted")
        let stale = Guarded(file: "Design/C.swift", call: "withAnimation(Theme.ringAnimation", reason: "planted")
        let named = Self.apply([once, stale], to: findings)
        #expect(named.left == findings)
        #expect(named.unmatched == [once, stale])
    }

    // MARK: the scan

    /// Every animation call in `source` and the ones that would play under Reduce Motion.
    static func scan(_ source: String, file: String) -> (calls: Int, findings: [Finding]) {
        // The code only, line by line so the numbers stay: a comment may name a bare animation to say why it isn't used.
        // `//` after a colon is a URL's.
        let lines = source.components(separatedBy: "\n").map { $0.replacing(#/(^|[^:])//.*/#) { String($0.output.1) } }
        let code = lines.joined(separator: "\n")
        // `TimelineView(.animation…)` first: its `.animation` isn't the modifier.
        let pattern = #/
            TimelineView\s*\(\s*\.animation\b
            | withAnimation\s*(?:\(|\{) | withTransaction\s*\( | \.transaction\s*(?:\(|\{)
            | \.animation\( | \.contentTransition\(
            | (?:\.phaseAnimator|PhaseAnimator|\.keyframeAnimator|KeyframeAnimator)\s*\( | \.symbolEffect\s*\(
            /#
        var calls = 0
        var findings: [Finding] = []
        // A call's own arguments aren't scanned again (`.contentTransition(.symbolEffect(…))` is one call).
        var scanned = code.startIndex
        for match in code.matches(of: pattern) {
            guard match.range.lowerBound >= scanned else { continue }
            calls += 1
            let verdict = judge(String(code[match.range]), in: code, from: match.range.upperBound)
            scanned = verdict.end
            if !verdict.fine {
                let line = code[..<match.range.lowerBound].filter { $0 == "\n" }.count + 1
                findings.append(Finding(file: file, line: line, call: verdict.call.replacing(#/\s+/#, with: " ")))
            }
        }
        return (calls, findings)
    }

    /// Whether the call `token` (its arguments from `start`) stays still under Reduce Motion; the finding's text; where its
    /// arguments end.
    static func judge(_ token: String, in code: String, from start: String.Index) -> (fine: Bool, call: String, end: String.Index) {
        let call = token.filter { !$0.isWhitespace }
        if call.hasPrefix("TimelineView") {
            guard start < code.endIndex, code[start] == "(" else { return (false, call, start) }
            let list = argumentList(code, from: code.index(after: start))
            let paused = topLevel(list.text).first { $0.hasPrefix("paused:") }.map { String($0.dropFirst("paused:".count)) }
            let fine = paused.map { $0.components(separatedBy: "||").map(trimmed).contains("reduceMotion") } ?? false
            return (fine, "\(call)(\(list.text))", list.end)
        }
        if call == "withAnimation{" { return (false, "withAnimation {", start) }
        if call == ".transaction{" {
            let body = argumentList(code, from: start)
            return (setsNoMotion(body.text, in: code), "\(call) \(body.text.prefix(60))", body.end)
        }
        let list = argumentList(code, from: start)
        let arguments = topLevel(list.text)
        let first = arguments.first ?? ""
        switch call {
        case "withAnimation(", ".animation(":
            return (isRespecting(first, in: code), call + first, list.end)
        case ".contentTransition(":
            let fine = first == ".opacity" || first == ".identity" || first.hasPrefix("reduceMotion ? .identity :")
            return (fine, call + first, list.end)
        case "withTransaction(":
            let fine: Bool
            if first.hasPrefix("\\.animation") {
                fine = arguments.count > 1 && isRespecting(arguments[1], in: code)
            } else if first.hasPrefix("\\.") {
                fine = true
            } else if let value = first.wholeMatch(of: #/(?:Transaction|\.init)\(animation:\s*(.*)\)/#)?.output.1 {
                fine = isRespecting(String(value), in: code)
            } else {
                fine = false
            }
            return (fine, call + first, list.end)
        case ".transaction(":
            // `.transaction(value: x) { … }`: the closure after the parentheses, or the one inside them.
            let rest = code[list.end...]
            guard let open = rest.firstIndex(where: { !$0.isWhitespace }), code[open] == "{" else {
                return (setsNoMotion(list.text, in: code), call + list.text, list.end)
            }
            let body = argumentList(code, from: code.index(after: open))
            return (setsNoMotion(body.text, in: code), "\(call)\(list.text)) \(body.text.prefix(60))", body.end)
        case ".symbolEffect(":
            let active = arguments.first { $0.hasPrefix("isActive:") }.map { String($0.dropFirst("isActive:".count)) }
            let fine = active.map { !$0.contains("||") && $0.components(separatedBy: "&&").map(trimmed).contains("!reduceMotion") }
            return (fine ?? false, call + list.text, list.end)
        default:
            // `phaseAnimator`, `keyframeAnimator`: their phases or keyframes are code the scan can't read.
            return (false, call + first, list.end)
        }
    }

    /// The text from `start` to the `)`, `]` or `}` that closes it at its own depth, and the index after that closer.
    static func argumentList(_ code: String, from start: String.Index) -> (text: String, end: String.Index) {
        var depth = 0
        var index = start
        while index < code.endIndex {
            let c = code[index]
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            if c == ")" || c == "]" || c == "}" {
                if depth == 0 { return (trimmed(String(code[start..<index])), code.index(after: index)) }
                depth -= 1
            }
            index = code.index(after: index)
        }
        return (trimmed(String(code[start...])), code.endIndex)
    }

    /// `text` split at the commas at its own depth, each part trimmed.
    static func topLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for c in text {
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            if c == ")" || c == "]" || c == "}" { depth -= 1 }
            if c == ",", depth == 0 {
                parts.append(trimmed(current))
                current = ""
            } else {
                current.append(c)
            }
        }
        parts.append(trimmed(current))
        return parts
    }

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A transaction's closure: every animation it sets is a respecting one (`nil` included), or it sets none.
    static func setsNoMotion(_ body: String, in code: String) -> Bool {
        body.matches(of: #/\.animation\s*=(?!=)\s*([^\n;}]*)/#).allSatisfy { isRespecting(String($0.output.1), in: code) }
    }

    /// `Theme.Motion.respecting(…)` told about Reduce Motion, `reduceMotion ? nil : …`, `nil`, or a local whose every
    /// declaration in the file is one of the first two (the scan can't tell one view's `motion` from another's).
    static func isRespecting(_ argument: String, in code: String) -> Bool {
        let argument = trimmed(argument)
        if argument == "nil" || isRespectingValue(argument) { return true }
        guard argument.wholeMatch(of: #/[a-z][A-Za-z0-9]*/#) != nil else { return false }
        // `let animation = Theme.Motion.respecting(…)`, `private var motion: Animation? { Theme.Motion.respecting(…) }`.
        let values = code.matches(of: #/(?:let|var)\s+([a-z][A-Za-z0-9]*)\b[^\n=\{]*(?:=|\{)\s*([^\n]*)/#)
            .filter { $0.output.1 == argument }
            .map { String($0.output.2) }
        return !values.isEmpty && values.allSatisfy(isRespectingValue)
    }

    /// `reduceMotion ? nil : …`, or `Theme.Motion.respecting(…)` whose first argument is a reduce-motion value.
    static func isRespectingValue(_ value: String) -> Bool {
        if value.hasPrefix("reduceMotion ? nil :") { return true }
        let head = "Theme.Motion.respecting("
        guard value.hasPrefix(head) else { return false }
        let list = argumentList(value, from: value.index(value.startIndex, offsetBy: head.count))
        return (topLevel(list.text).first ?? "").range(of: "reducemotion", options: .caseInsensitive) != nil
    }

    /// The findings no entry covers, and the entries that don't match exactly their count of findings.
    static func apply(_ entries: [Guarded], to findings: [Finding]) -> (left: [Finding], unmatched: [Guarded]) {
        var left = findings
        var unmatched: [Guarded] = []
        for entry in entries {
            let covers = { (finding: Finding) in finding.file == entry.file && finding.call == entry.call }
            if findings.filter(covers).count == entry.count {
                left.removeAll(where: covers)
            } else {
                unmatched.append(entry)
            }
        }
        return (left, unmatched)
    }
}
