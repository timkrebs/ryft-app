import Foundation
import Testing
@testable import Ryft

@Suite("Import warnings")
struct ImportWarningTests {
    @Test func everyKindHasAnEnglishAndAGermanReason() {
        for kind in ImportFixture.allKinds {
            var english = kind.message
            english.locale = Locale(identifier: "en")
            var german = kind.message
            german.locale = Locale(identifier: "de")
            let en = String(localized: english)
            let de = String(localized: german)
            #expect(!en.isEmpty, "\(kind.name)")
            #expect(de != en, "\(kind.name) has no German")
        }
    }

    @Test func reasonsCarryNoFileText() {
        // Static text only: no format arguments, so nothing from a file can reach the screen or a log.
        for kind in ImportFixture.allKinds {
            #expect(!kind.message.key.contains("%"), "\(kind.name)")
        }
    }

    @Test func namesAreStableAndUnique() {
        let names = ImportFixture.allKinds.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(ImportWarning.Kind.missingTableHeader(assumed: .lb).name == "missingTableHeader.lb")
    }

    @Test func notesAreTheKindsUiMdNames() {
        let notes = ImportFixture.allKinds.filter(\.isNote).map(\.name)
        #expect(notes == ["missingTableHeader.kg", "missingTableHeader.lb", "meridiemConflict", "duplicateInFiles",
                          "limitReached", "nonexistentLocalTime", "repeatedLocalTime", "durationAssumed",
                          "overPlatformLimit", "assistedLoad"])
    }

    @Test func sortingIsByFileThenLineAndStable() {
        let warnings = [
            ImportWarning(at: SourceLine(file: 1, line: 2), kind: .unrecognisedLine),
            ImportWarning(at: SourceLine(file: 0, line: 9), kind: .meridiemConflict),
            ImportWarning(at: SourceLine(file: 0, line: 9), kind: .unreadableDuration),
            ImportWarning(at: SourceLine(file: 0, line: 3), kind: .outsideBlock),
        ]
        #expect(ImportWarning.sorted(warnings).map(\.kind) == [.outsideBlock, .meridiemConflict, .unreadableDuration,
                                                               .unrecognisedLine])
    }

    @Test func theSourceAppIsNamedFactually() {
        #expect(String(localized: AlphaProgressionFormat().displayName) == "Alpha Progression")
    }
}
