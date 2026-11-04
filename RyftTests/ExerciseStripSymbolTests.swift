import Testing
import UIKit
@testable import Ryft

/// design.md §4b: every glyph the strip and the exercise page draw exists as an SF Symbol, and on the deployment target
/// (iOS 17), not just on the runtime that runs the test. A runtime newer than the target answers `UIImage(systemName:)`
/// for symbols the target lacks, so the existence check alone can't prove the second half: `introduced` carries the
/// release each symbol shipped in (the Mac's `CoreGlyphs` `name_availability.plist`, year to iOS version).
struct ExerciseStripSymbolTests {
    static let deploymentTarget = 17.0

    /// Symbol name -> the iOS release that introduced it.
    static let introduced: [String: Double] = [
        "figure.strengthtraining.traditional": 16.0,
        "dumbbell.fill": 16.0,
        "figure.strengthtraining.functional": 16.0,
        "figure.arms.open": 16.0,
        "gearshape.2.fill": 14.0,
        "figure.rower": 16.0,
        "figure.run": 16.0,
        "plus": 13.0,
        "checkmark": 13.0,
        "chevron.right": 13.0,
        "chevron.down": 13.0,
        "ellipsis": 13.0,
        "link": 13.0,
        "note.text": 14.0,
        "flame": 13.0,
        "arrow.triangle.2.circlepath": 14.0,
        "timer": 13.0,
        "pencil": 13.0,
    ]

    /// The names the strip draws: one per kind, the + tile and the done badge.
    private static var stripSymbols: [String] { ExerciseKind.allCases.map(\.tileSymbol) + ["plus", "checkmark"] }

    /// The page's own: title chevron, menu, superset line, notes, warm-up pill, chips.
    private static let pageSymbols = ["chevron.right", "ellipsis", "link", "note.text", "flame", "chevron.down",
                                      "arrow.triangle.2.circlepath", "timer", "pencil"]

    @Test(arguments: ExerciseKind.allCases)
    func everyKindHasAGlyphThatExists(_ kind: ExerciseKind) {
        #expect(UIImage(systemName: kind.tileSymbol) != nil, "\(kind.rawValue): \(kind.tileSymbol) isn't an SF Symbol")
    }

    @Test func everyKindHasItsOwnGlyph() {
        let symbols = ExerciseKind.allCases.map(\.tileSymbol)
        #expect(Set(symbols).count == symbols.count, "\(symbols)")
    }

    @Test func aKindThatDecodesFromAnUnknownNameStillHasAGlyph() throws {
        let kind = try JSONDecoder().decode(ExerciseKind.self, from: Data(#""resistance_band""#.utf8))
        #expect(UIImage(systemName: kind.tileSymbol) != nil)
    }

    @Test func theStripsSymbolsExist() {
        for name in Self.stripSymbols + Self.pageSymbols {
            #expect(UIImage(systemName: name) != nil, "\(name) isn't an SF Symbol")
        }
    }

    @Test func noSymbolNeedsAnOsNewerThanTheDeploymentTarget() {
        for name in Set(Self.stripSymbols + Self.pageSymbols) {
            guard let release = Self.introduced[name] else {
                Issue.record("\(name) has no release in the table: add it from name_availability.plist")
                continue
            }
            #expect(release <= Self.deploymentTarget, "\(name) needs iOS \(release)")
        }
    }
}
