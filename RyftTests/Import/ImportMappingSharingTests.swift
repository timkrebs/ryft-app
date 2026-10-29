import Foundation
import Testing
@testable import Ryft

/// Step 4: two rows of the file on one RYFT exercise are legal, but each row says so (beta feedback 2, §4).
@Suite("Import mapping, one exercise for two rows")
struct ImportMappingSharingTests {
    static let fly = MappingFixture.exercise(1, "Pec deck", kind: .machine)
    static let reverse = MappingFixture.exercise(2, "Reverse pec deck", kind: .machine)

    static func row(_ name: String, _ decision: ImportMappingRow.Decision, suggestion: UUID?) -> ImportMappingRow {
        let key = SourceExerciseKey(name: name.lowercased(), equipment: "machine")
        return ImportMappingRow(source: ImportedExerciseSource(key: key, name: name, equipment: "Machine"),
                                match: ExerciseMatch(key: key, exerciseID: suggestion, tier: suggestion == nil ? nil : .fuzzy,
                                                     confidence: 0.6, alternatives: []),
                                decision: decision, bodyweight: nil, rememberedBodyweight: nil)
    }

    static func state() -> ImportMappingState {
        ImportMappingState(rows: [
            row("Fly", .check(fly.id), suggestion: fly.id),
            row("Reverse Fly", .matched(reverse.id), suggestion: reverse.id),
            row("Rear Fly", .skip, suggestion: reverse.id),
            row("Chest Fly", .create(ImportCustomDraft(name: "Chest Fly", kind: .machine, loadType: .weight, muscle: .chest)),
                suggestion: nil),
        ], exercises: [fly.id: fly, reverse.id: reverse])
    }

    @Test func distinctRowsShareNothing() {
        let state = Self.state()
        for row in state.rows { #expect(state.content(row).alsoUsedFor == []) }
    }

    /// Choosing the reverse fly's exercise for the fly row marks both, and the choice stands.
    @Test func bothRowsSayItAndTheChoiceStands() {
        var state = Self.state()
        let flyKey = state.rows[0].id
        state.choose(flyKey, Self.reverse)
        #expect(state.row(flyKey)?.decision == .chosen(Self.reverse.id))
        #expect(state.content(state.rows[0]).alsoUsedFor == ["Reverse Fly · Machine"])
        #expect(state.content(state.rows[1]).alsoUsedFor == ["Fly · Machine"])
        // Skipped and new rows never share; nothing blocks Continue because of it.
        #expect(state.content(state.rows[2]).alsoUsedFor == [])
        #expect(state.content(state.rows[3]).alsoUsedFor == [])
        #expect(state.leftToCheck == 0)
    }
}
