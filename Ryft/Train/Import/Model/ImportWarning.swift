import Foundation

/// Something in a file that was skipped, assumed or adjusted. It carries a line and a kind, never file text, so it
/// localises, logs and tests safely (design §2, §10).
struct ImportWarning: Equatable, Sendable {
    let at: SourceLine
    let kind: Kind

    enum Kind: Hashable, Sendable {
        // The parser (I2).
        case unrecognisedLine, lineTooLong, invalidText, outsideBlock, missingTableHeader(assumed: WeightUnit)
        case unsupportedColumns, unreadableNumber, implausibleValue, unreadableDate, unreadableDuration
        case meridiemConflict, duplicateInFiles, limitReached
        // The builder (I5).
        case nonexistentLocalTime, repeatedLocalTime, durationAssumed, overPlatformLimit, assistedLoad
    }

    /// The reason, for the row after "Line N" in step 2 (ui.md §5). No line number and no file text.
    var message: LocalizedStringResource { kind.message }

    /// Sorted by file and line; warnings on one line keep their order.
    static func sorted(_ warnings: [ImportWarning]) -> [ImportWarning] {
        warnings.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }
}

extension ImportWarning.Kind {
    /// A stable identifier for logs and diagnostics (`.public`: it holds no personal data).
    var name: String {
        switch self {
        case .unrecognisedLine: "unrecognisedLine"
        case .lineTooLong: "lineTooLong"
        case .invalidText: "invalidText"
        case .outsideBlock: "outsideBlock"
        case let .missingTableHeader(unit): "missingTableHeader.\(unit.rawValue)"
        case .unsupportedColumns: "unsupportedColumns"
        case .unreadableNumber: "unreadableNumber"
        case .implausibleValue: "implausibleValue"
        case .unreadableDate: "unreadableDate"
        case .unreadableDuration: "unreadableDuration"
        case .meridiemConflict: "meridiemConflict"
        case .duplicateInFiles: "duplicateInFiles"
        case .limitReached: "limitReached"
        case .nonexistentLocalTime: "nonexistentLocalTime"
        case .repeatedLocalTime: "repeatedLocalTime"
        case .durationAssumed: "durationAssumed"
        case .overPlatformLimit: "overPlatformLimit"
        case .assistedLoad: "assistedLoad"
        }
    }

    /// A note, not a problem: an assumption, an adjustment or a stated limit. Step 2 counts notes on their own line
    /// (ui.md §5); the rest are lines that couldn't be read.
    var isNote: Bool {
        switch self {
        case .missingTableHeader, .meridiemConflict, .duplicateInFiles, .nonexistentLocalTime, .repeatedLocalTime,
             .durationAssumed, .assistedLoad, .overPlatformLimit, .limitReached:
            true
        case .unrecognisedLine, .lineTooLong, .invalidText, .outsideBlock, .unsupportedColumns, .unreadableNumber,
             .implausibleValue, .unreadableDate, .unreadableDuration:
            false
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unrecognisedLine:
            LocalizedStringResource("This line isn't recognised", comment: "Import warning, after \"Line N\".")
        case .lineTooLong:
            LocalizedStringResource("This line is too long to read", comment: "Import warning, after \"Line N\".")
        case .invalidText:
            LocalizedStringResource("Some characters in this line couldn't be read",
                                    comment: "Import warning, after \"Line N\": the file isn't valid UTF-8 there.")
        case .outsideBlock:
            LocalizedStringResource("This line isn't in a plan or workout, so it was skipped",
                                    comment: "Import warning, after \"Line N\".")
        case .missingTableHeader(.kg):
            LocalizedStringResource("No kg or lb header here: RYFT assumed kg", comment: "Import warning, after \"Line N\".")
        case .missingTableHeader(.lb):
            LocalizedStringResource("No kg or lb header here: RYFT assumed lb", comment: "Import warning, after \"Line N\".")
        case .unsupportedColumns:
            LocalizedStringResource("RYFT can't read these columns yet, so this exercise's sets were skipped",
                                    comment: "Import warning, after \"Line N\": a set table with other columns than weight and reps.")
        case .unreadableNumber:
            LocalizedStringResource("A number here couldn't be read and was left out", comment: "Import warning, after \"Line N\".")
        case .implausibleValue:
            LocalizedStringResource("A value here is too large to be right and was left out",
                                    comment: "Import warning, after \"Line N\": over 1,000 kg, 1,000 reps or 24 hours.")
        case .unreadableDate:
            LocalizedStringResource("The date or time here couldn't be read", comment: "Import warning, after \"Line N\".")
        case .unreadableDuration:
            LocalizedStringResource("The duration here couldn't be read", comment: "Import warning, after \"Line N\".")
        case .meridiemConflict:
            LocalizedStringResource("A 24-hour time with am or pm: RYFT used the 24-hour time",
                                    comment: "Import warning, after \"Line N\", e.g. for 16:41 pm.")
        case .duplicateInFiles:
            LocalizedStringResource("This workout is in another picked file too and is imported once",
                                    comment: "Import warning, after \"Line N\".")
        case .limitReached:
            LocalizedStringResource("Some items were left out: this file is over RYFT's import limits",
                                    comment: "Import warning, after \"Line N\".")
        case .nonexistentLocalTime:
            LocalizedStringResource("This time didn't exist in your time zone, so RYFT used the next valid time",
                                    comment: "Import note, after \"Line N\": a workout on the spring clock change.")
        case .repeatedLocalTime:
            LocalizedStringResource("This time occurred twice in your time zone, so RYFT used the first",
                                    comment: "Import note, after \"Line N\": a workout on the autumn clock change.")
        case .durationAssumed:
            LocalizedStringResource("No duration: 60 min assumed", comment: "Import note, after \"Line N\".")
        case .overPlatformLimit:
            LocalizedStringResource("Some items were left out: RYFT limits a workout to 50 exercises and 50 sets per exercise",
                                    comment: "Import note, after \"Line N\".")
        case .assistedLoad:
            LocalizedStringResource("Assisted weight isn't imported, reps are",
                                    comment: "Import note, after \"Line N\": a negative load such as -20.")
        }
    }
}
