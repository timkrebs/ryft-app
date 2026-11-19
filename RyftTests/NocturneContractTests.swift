import Foundation
import Testing
@testable import Ryft

// What PR 4 promises about the string catalog and the wire models (docs/work/2026-11-16-nocturne/design.md §P4-11 tests 34 and
// 50): every key of §P4-9 is in `Localizable.xcstrings` with a comment for the translator and the removed ones are gone;
// `strain_target_*` and `sleep_need_met` are not decoded, because nothing in `Models.swift` changes in this PR (they are
// requests R-N1 and R-N3 in `docs/API_REQUESTS.md`; R-N2, an editable name, is a PATCH the app has no model for. The `name` that
// `GET /v1/me` already sends is decoded since PR 1 and is the greeting's). `make lint` checks the catalog's shape; this checks its content.

struct NocturneStringsTests {
    private struct Entry: Decodable {
        let comment: String?
        let extractionState: String?
    }

    private struct Catalog: Decodable {
        let strings: [String: Entry]
    }

    private func catalog() throws -> [String: Entry] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ryft/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).strings
    }

    /// §P4-9's table, by the keys the code uses. Where the table writes "…" for a sentence built from parts (the neutral
    /// tiles' VoiceOver), the parts are listed.
    static let keys: [String] = [
        // Today
        "Good morning, %@", "Good afternoon, %@", "Good evening, %@", "Good morning", "Good afternoon", "Good evening",
        "Readiness · %@", "today.ruler.low", "today.ruler.moderate", "today.ruler.high", "Calendar", "Opens My Day",
        "Readiness scale", "%lld, %@, on a scale from 0 to 100", "%lld, on a scale from 0 to 100",
        "No readiness yet, on a scale from 0 to 100",
        "of 21", "of 21 · light", "of 21 · moderate", "of 21 · high", "of 21 · all out", "Strain · %@", "Strain scale",
        "%1$@, %2$@, on a scale from 0 to 21. The moderate range is 10 to 14.",
        "HRV %lld milliseconds, lowest %lld and highest %lld over the last 7 days",
        "Slept enough on %lld of the last 7 nights; the last is the night shown",
        "Slept enough on %lld of the last 7 nights; the last is the night shown; %lld nights have no data",
        // Sleep
        "Last night · %@", "Yesterday · %@", "Asleep · %lld %% of your need", "%lld percent of your need", "Asleep",
        "Sleep duration scale", "0 h", "need %@", "10 h", "%@, on a scale from 0 to 10 hours. Your need is %@.", "h",
        "Deep + REM", "No newer night to show", "No older night to show", "Loading this night",
        "The timeline isn't available for this night.", "Hypnogram, %@ to %@",
        // The neutral tiles' sentences, from their parts.
        "%lld of the last 7 nights were regular", "%lld percent of the target", "%@ of deep and REM sleep",
        "down %@ from the night before", "up %@ from the night before",
        // Profile → Hero numbers (PR 5's list has no "Display" heading, T5.4)
        "Hero numbers", "Dots", "Thin", "Large numbers on Today, Sleep and Strain.",
    ]

    /// The keys the spec removes, with no other caller after the change.
    static let removed: [String] = [
        "Total sleep", "Performance", "asleep in bed", "of your need", "last 7 nights", "deep + REM",
        "Good morning,", "Good afternoon,", "Good evening,", "in bed %@ to %@",
        // PR 5 (T5.4): Profile's list drops the Display heading.
        "Display",
    ]

    /// Kept on purpose (§P4-9, last paragraph).
    static let kept: [String] = [
        "Overall readiness", "Quality", "Efficiency", "Restorative", "Consistency", "Sleep debt", "None", "Previous night",
        "Next night", "vs 7 d", "Last night",
    ]

    @Test("§P4-9: every key is in the catalog", arguments: keys)
    func theKeyIsThere(_ key: String) throws {
        let entry = try catalog()[key]
        #expect(entry != nil, "\(key)")
    }

    @Test("§P4-9: every key carries a comment for the translator")
    func everyKeyHasAComment() throws {
        let strings = try catalog()
        let bare = Self.keys.filter { strings[$0]?.comment?.isEmpty != false }
        #expect(bare == [], "keys without a comment: \(bare)")
    }

    @Test("§P4-9: the removed keys are gone", arguments: removed)
    func theKeyIsRemoved(_ key: String) throws {
        let entry = try catalog()[key]
        #expect(entry == nil, "\(key)")
    }

    @Test("§P4-9: the kept keys are still there", arguments: kept)
    func theKeyIsKept(_ key: String) throws {
        let entry = try catalog()[key]
        #expect(entry != nil, "\(key)")
    }

    @Test("No key is left stale by the change")
    func noStaleKeys() throws {
        let stale = try catalog().filter { $0.value.extractionState == "stale" }.map(\.key)
        #expect(stale.isEmpty, "\(stale.sorted())")
    }
}

struct NocturneNotDecodedTests {
    /// API.md's `GET /v1/days/{day}` score with what the platform has not shipped yet written in: the fields requests R-N1 and
    /// R-N3 would add.
    private let day = #"""
    {"day":"2026-11-15","readiness":84,"state":"balanced","recovery":82,"strain":12.4,"sleep_need_min":498,
     "sleep_actual_min":468,"baseline_days":30,"calibrating":false,"computed_at":"2026-11-15T06:45:00Z","scoring_state":"scored",
     "strain_target_min":10,"strain_target_max":14,"sleep_need_met":true}
    """#

    @Test("A day with strain_target_* and sleep_need_met decodes, and nothing of them is kept")
    func theDayIgnoresWhatIsNotInModels() throws {
        let score = try APIClient.jsonDecoder.decode(DailyScore.self, from: Data(day.utf8))
        #expect(score.readiness == 84 && score.sleepNeedMin == 498)
        let echoed = try JSONEncoder().encode(score)
        let keys = try #require(JSONSerialization.jsonObject(with: echoed) as? [String: Any]).keys
        #expect(!keys.contains { $0.contains("strain_target") || $0.contains("strainTarget") || $0.contains("need_met") || $0.contains("NeedMet") },
                "\(keys.sorted())")
        let fields = Mirror(reflecting: score).children.compactMap(\.label)
        #expect(!fields.contains { $0.lowercased().contains("target") || $0.lowercased().contains("needmet") }, "\(fields)")
    }
}
