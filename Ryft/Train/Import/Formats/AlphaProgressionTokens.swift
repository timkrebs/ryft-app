import Foundation

/// The words of Alpha Progression's exports, as data (design §3, tokens): matched case-insensitively, with an
/// optional space between a number and its word. English was seen in an export; German is a guess until a German
/// export confirms it (Q1), so a wrong German token costs warnings, never a crash.
struct AlphaProgressionTokens: Sendable {
    /// `Day 1` (plan days and plan sessions).
    var day: Set<String>
    /// `Week 4` (plan sessions).
    var week: Set<String>
    /// `6 weeks` (plan length).
    var weeks: Set<String>
    /// `4 sets` (plan exercises).
    var sets: Set<String>
    /// `10 reps`, `8-12 reps` (targets).
    var reps: Set<String>
    /// The table header's reps column (`#;KG;REPS`).
    var repsHeader: Set<String>
    /// The table header's unit column.
    var units: [String: WeightUnit]
    /// `Upper · Standalone workout`.
    var standalone: Set<String>
    var minutes: Set<String>
    var hours: Set<String>
    var am: Set<String>
    var pm: Set<String>
    /// A word after a 24-hour time (`16:41 Uhr`).
    var clockSuffix: Set<String>

    static let standard = AlphaProgressionTokens(
        day: ["day", "tag"],
        week: ["week", "woche"],
        weeks: ["week", "weeks", "woche", "wochen"],
        sets: ["set", "sets", "satz", "sätze", "saetze"],
        reps: ["rep", "reps", "wdh", "wdh.", "wiederholung", "wiederholungen"],
        repsHeader: ["rep", "reps", "wdh", "wdh.", "wiederholungen"],
        units: ["kg": .kg, "kgs": .kg, "lb": .lb, "lbs": .lb],
        standalone: ["standalone workout", "einzelnes training", "freies training"],
        minutes: ["min", "min.", "mins", "minute", "minutes", "minuten"],
        hours: ["h", "hr", "hrs", "hour", "hours", "std", "std.", "stunde", "stunden"],
        am: ["am", "a.m.", "a. m."],
        pm: ["pm", "p.m.", "p. m."],
        clockSuffix: ["uhr", "h"]
    )

    // MARK: Matching

    /// No token is longer: text around a number that is longer can't be one, so it isn't lowercased or looked up.
    static let maxWordBytes = 40

    /// `N <token>` (`6 weeks`, `6weeks`): the number, if the rest is one of `tokens`.
    func count(_ part: String, _ tokens: Set<String>) -> Int? {
        guard let (value, rest) = ImportScan.leadingInteger(Substring(part)), rest.utf8.count <= Self.maxWordBytes,
              tokens.contains(rest.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
        return value
    }

    /// `<token> N` (`Day 1`, `Woche 4`, `Day1`): the number, if the text before it is one of `tokens`. Looks at no
    /// more than 10 scalars from the end for the digits.
    func numbered(_ part: String, _ tokens: Set<String>) -> Int? {
        let scalars = part.unicodeScalars
        var start = scalars.endIndex
        var digits = 0
        while start > scalars.startIndex, digits < 10 {
            let previous = scalars.index(before: start)
            guard ImportScan.asciiDigit(scalars[previous]) != nil else { break }
            start = previous
            digits += 1
        }
        guard digits > 0, let value = ImportScan.integer(Substring(scalars[start...])) else { return nil }
        let word = Substring(scalars[..<start])
        guard word.utf8.count <= Self.maxWordBytes else { return nil }
        return tokens.contains(word.trimmingCharacters(in: .whitespaces).lowercased()) ? value : nil
    }

    /// `N[-–N] <reps>`: nil when the part isn't written that way (then it belongs to a name); otherwise the range
    /// (low first) or `.implausible`.
    func targetReps(_ part: String) -> ImportScanResult<ClosedRange<Int>>? {
        guard let (low, afterLow) = ImportScan.leadingInteger(Substring(part)) else { return nil }
        var rest = afterLow.drop { $0 == " " }
        var high = low
        if let dash = rest.first, dash == "-" || dash == "\u{2013}" || dash == "\u{2014}" {
            guard let (value, afterHigh) = ImportScan.leadingInteger(rest.dropFirst().drop { $0 == " " }) else { return nil }
            high = value
            rest = afterHigh
        }
        guard rest.utf8.count <= Self.maxWordBytes, reps.contains(rest.trimmingCharacters(in: .whitespaces).lowercased()) else {
            return nil
        }
        guard low <= ImportScan.maxReps, high <= ImportScan.maxReps else { return .implausible }
        return .value(min(low, high)...max(low, high))
    }

    /// `N. name`: the number and the trimmed rest, which isn't empty.
    func ordered(_ field: String) -> (order: Int, rest: String)? {
        guard let (order, afterOrder) = ImportScan.leadingInteger(Substring(field)), afterOrder.first == "." else { return nil }
        let rest = afterOrder.dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (order, rest)
    }

    func isStandalone(_ part: String) -> Bool { standalone.contains(part.lowercased()) }
}
