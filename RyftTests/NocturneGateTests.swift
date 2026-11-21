import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// The Nocturne gate's sweep (G1, docs/work/2026-11-20-nocturne-gate/design.md §5.1), without a window: no retired token left in
/// the app's sources, the insight tile's legend colour (D1), the recovery metrics' colour, and the range bar's good side.
/// The hosted checks (no teal on the swept screens, the pills, the prompt, the card radius) are `NocturneGateSweepHostedTests`.
@MainActor
@Suite("Nocturne gate G1: the sweep")
struct NocturneGateTests {
    // MARK: the source scan

    /// What the gate retires (§5.1): the old buttons, the teal tokens, the zones and stage colours, the light pair and the light
    /// and German previews. `PrimaryButton(` as a word (`ImportStepButton(` is not it); a `· light` or `· de` only in a preview's
    /// name (the strain band "of 21 · light" is a word on screen). Simple word boundaries: Unicode's would read
    /// "Theme.accent.opacity" as one word and miss it.
    nonisolated static let patterns = [
        #"\bPrimaryButton\("#, "TealButtonStyle", #"Theme\.(?:accent|onAccent|teal|zones)\b"#, #"Theme\.stage"#, "SchemePair",
        #"scheme: \.light"#, #"preferredColorScheme\(\.light\)"#, #"#Preview\("[^"]*· (?:light|de)\b"#,
    ]

    nonisolated static func retired() throws -> Regex<AnyRegexOutput> {
        try Regex(patterns.joined(separator: "|")).wordBoundaryKind(.simple)
    }

    /// The definitions that name what they define, until G4 deletes them (then this list is empty and the scan covers every
    /// file). `Theme.swift` needs no entry: it declares `static let accent`, never `Theme.accent`.
    nonisolated static let definitions = [
        "Ryft/Features/Profile/ProfileComponents.swift", "Ryft/Features/Train/TrainComponents.swift", "Ryft/Preview/PreviewSupport.swift",
    ]

    /// Files another gate ticket sweeps (design.md §6), each with its ticket. Remove an entry when that ticket lands: the next
    /// test fails for an entry whose file is gone or holds nothing retired any more, so the list can't outlive its reason.
    nonisolated static let otherTickets = [
        "Ryft/Features/Train/Session/SetColumnPreview.swift": "G4 deletes the light previews",
        "Ryft/Features/Train/Session/SessionPager.swift": "G4 deletes the light preview",
    ]

    /// The repository, symlinks resolved: the enumerator hands back resolved paths (`/private/tmp/…` for `/tmp/…`).
    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
    }

    /// Every Swift file of the app, the widget and the shared folder, as repository paths.
    private static func sources() throws -> [String] {
        var found: [String] = []
        for folder in ["Ryft", "RyftWidgets", "Shared"] {
            let url = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                let path = file.resolvingSymlinksInPath().path
                guard path.hasPrefix(root.path + "/") else { continue }
                found.append(String(path.dropFirst(root.path.count + 1)))
            }
        }
        return found.sorted()
    }

    /// The lines of `path` that name a retired token, as "path:line: text".
    private static func hits(_ path: String) throws -> [String] {
        let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let pattern = try Self.retired()
        return source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            line.firstMatch(of: pattern) == nil ? nil : "\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
        }
    }

    @Test("§5.1: no retired token in Ryft/, RyftWidgets/ or Shared/ outside the definitions and the other tickets' files")
    func noRetiredTokensRemain() throws {
        let files = try Self.sources()
        #expect(files.count > 300, "the sources were found: \(files.count)")
        let skipped = Set(Self.definitions).union(Self.otherTickets.keys)
        let found = try files.filter { !skipped.contains($0) }.flatMap(Self.hits)
        #expect(found.isEmpty, "\(found.count) retired uses:\n\(found.joined(separator: "\n"))")
    }

    @Test("§5.1: every file the scan skips still exists and still names a retired token (else its entry goes)")
    func skippedFilesStillNeedSkipping() throws {
        for path in Self.definitions + Self.otherTickets.keys.sorted() {
            let exists = FileManager.default.fileExists(atPath: Self.root.appendingPathComponent(path).path)
            #expect(exists, "\(path) is gone (\(Self.otherTickets[path] ?? "G4")): remove its entry")
            if exists { #expect(try !Self.hits(path).isEmpty, "\(path) names nothing retired any more: remove its entry") }
        }
    }

    @Test("The scan's pattern: the retired names match; ImportStepButton, accentSecondary and an on-screen \"· light\" don't")
    func thePatternMatchesWhatItShould() throws {
        let pattern = try Self.retired()
        let caught = ["PrimaryButton(title: \"x\")", ".buttonStyle(TealButtonStyle())", "Theme.accent)", "Theme.accent.opacity(0.14)",
                      "Theme.onAccent", "Theme.teal,",
                      "Theme.zones[i]", "Theme.stageDeep", "SchemePair {", "previewEnvironment(scheme: .light)",
                      ".preferredColorScheme(.light)", "#Preview(\"Pager · light\") {", "#Preview(\"Error card · de · AX3\") {"]
        let passed = ["ImportStepButton(title: \"x\")", "Theme.accentSecondary", "Theme.recovery",
                      "String(localized: \"of 21 · light\")", "#Preview(\"Error card · AX3\") {", ".preferredColorScheme(.dark)"]
        for line in caught { #expect(line.firstMatch(of: pattern) != nil, "\(line)") }
        for line in passed { #expect(line.firstMatch(of: pattern) == nil, "\(line)") }
    }

    // MARK: D1: the insight tile's colour

    @Test("D1: the insight takes its metric's legend colour (TrendCardStyle's legend); no legend colour, no metric: the neutral tile",
          arguments: TrendMetric.allCases)
    func insightTint(_ metric: TrendMetric) {
        let expected: Color? = switch metric {
        case .readiness, .recovery, .hrv: Theme.recovery
        case .sleep, .sleepMin, .sleepQuality, .sleepConsistency, .napMin: Theme.metricSleep
        case .strain, .strengthMin, .volumeKg: Theme.metricStrain
        case .rhr, .steps, .activeKcal: nil
        }
        let insight = Insight(id: "x", severity: .info, title: "x", body: "", metric: metric.rawValue)
        #expect(InsightTile.tint(for: insight) == expected, "\(metric)")
    }

    @Test("D1: an insight with no metric, or one the app doesn't know, is the neutral tile")
    func insightWithoutAMetric() {
        #expect(InsightTile.tint(for: Insight(id: "x", severity: .info, title: "x", body: "")) == nil)
        #expect(InsightTile.tint(for: Insight(id: "x", severity: .info, title: "x", body: "", metric: "vo2max")) == nil)
    }

    // MARK: the recovery metrics and the range bar

    @Test("§5.1: readiness, recovery and HRV are drawn in Theme.recovery, the legend's teal")
    func recoveryMetricsAreRecovery() {
        #expect(MetricSpec.readiness.color == Theme.recovery)
        #expect(MetricSpec.recovery.color == Theme.recovery)
        #expect(MetricSpec.hrv.color == Theme.recovery)
    }

    @Test("The range bar's word: the good side recovery, the bad side alert, in range or without a direction textSecondary")
    func rangeBarStatusColour() {
        #expect(RangeBar.statusColor(.above, polarity: .higherIsBetter) == Theme.recovery)
        #expect(RangeBar.statusColor(.below, polarity: .lowerIsBetter) == Theme.recovery)
        #expect(RangeBar.statusColor(.below, polarity: .higherIsBetter) == Theme.alert)
        #expect(RangeBar.statusColor(.above, polarity: .lowerIsBetter) == Theme.alert)
        #expect(RangeBar.statusColor(.inRange, polarity: .higherIsBetter) == Theme.textSecondary)
        #expect(RangeBar.statusColor(.above, polarity: .neutral) == Theme.textSecondary)
        #expect(RangeBar.statusColor(nil, polarity: .higherIsBetter) == Theme.textSecondary)
    }
}
