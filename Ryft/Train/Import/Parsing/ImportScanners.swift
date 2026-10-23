import Foundation

/// What a scanner made of a field.
enum ImportScanResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    /// Empty, `-` or `–`: nothing written (a set not done).
    case absent
    /// Not a number the format writes (`1.234,5`, `7e2`, `nan`, Arabic-Indic digits, more than 9 digits).
    case unreadable
    /// Readable but not believable: over 1 000 kg, 1 000 reps or 24 h.
    case implausible
}

/// Hand-written scanners (design §3): ASCII digits only, at most 9 per number, no regex and no `Double(String)`,
/// which accepts `1e309`, `nan` and `inf`. Each is linear in its input and never traps.
enum ImportScan {
    static let maxDigits = 9
    static let maxKilograms = 1_000.0
    static let maxReps = 1_000
    static let maxMinutes = 24 * 60

    // MARK: Numbers

    /// 1–9 ASCII digits and nothing else.
    static func integer(_ text: some StringProtocol) -> Int? {
        var value = 0
        var digits = 0
        for scalar in text.unicodeScalars {
            guard let digit = asciiDigit(scalar), digits < maxDigits else { return nil }
            value = value * 10 + digit
            digits += 1
        }
        return digits > 0 ? value : nil
    }

    /// `[0-9]{1,9}([.,][0-9]{1,3})?`. The field separator is `;`, so a comma is always a decimal comma.
    static func decimal(_ text: some StringProtocol) -> Double? {
        var whole = 0
        var wholeDigits = 0
        var fraction = 0
        var fractionDigits = 0
        var seenSeparator = false
        for scalar in text.unicodeScalars {
            if let digit = asciiDigit(scalar) {
                if seenSeparator {
                    guard fractionDigits < 3 else { return nil }
                    fraction = fraction * 10 + digit
                    fractionDigits += 1
                } else {
                    guard wholeDigits < maxDigits else { return nil }
                    whole = whole * 10 + digit
                    wholeDigits += 1
                }
            } else if scalar == "." || scalar == ",", !seenSeparator, wholeDigits > 0 {
                seenSeparator = true
            } else {
                return nil
            }
        }
        guard wholeDigits > 0, !seenSeparator || fractionDigits > 0 else { return nil }
        let scale: Double = switch fractionDigits {
        case 0: 1
        case 1: 10
        case 2: 100
        default: 1_000
        }
        return Double(whole) + Double(fraction) / scale
    }

    /// Leading ASCII digits (1–9) and what follows them.
    static func leadingInteger(_ text: Substring) -> (value: Int, rest: Substring)? {
        var value = 0
        var digits = 0
        var index = text.startIndex
        while index < text.endIndex, let scalar = text[index].unicodeScalars.first,
              text[index].unicodeScalars.count == 1, let digit = asciiDigit(scalar) {
            guard digits < maxDigits else { return nil }
            value = value * 10 + digit
            digits += 1
            index = text.index(after: index)
        }
        return digits > 0 ? (value, text[index...]) : nil
    }

    static func asciiDigit(_ scalar: Unicode.Scalar) -> Int? {
        scalar.value >= 0x30 && scalar.value <= 0x39 ? Int(scalar.value - 0x30) : nil
    }

    /// `true` for nothing written: empty, `-`, `–` or `—`.
    static func isAbsent(_ field: String) -> Bool {
        field.isEmpty || field == "-" || field == "\u{2013}" || field == "\u{2014}"
    }

    // MARK: Sets

    /// A set's load: `60` · `62.5` · `62,5` → `.weight`, `+60` → `.plus`, `-20` → `.minus`; pounds to kg, rounded to
    /// 0.01 kg.
    static func load(_ field: String, unit: WeightUnit) -> ImportScanResult<ImportedLoad> {
        if isAbsent(field) { return .absent }
        var body = Substring(field)
        var kind = 0 // 0 weight, 1 plus, 2 minus
        if body.first == "+" {
            kind = 1
            body = body.dropFirst()
        } else if body.first == "-" || body.first == "\u{2212}" {
            kind = 2
            body = body.dropFirst()
        }
        guard let value = decimal(body) else { return .unreadable }
        let kg = unit == .lb ? (value * WeightUnit.kilogramsPerPound * 100).rounded() / 100 : value
        guard kg <= maxKilograms else { return .implausible }
        return switch kind {
        case 1: .value(.plus(kg: kg))
        case 2: .value(.minus(kg: kg))
        default: .value(.weight(kg: kg))
        }
    }

    static func reps(_ field: String) -> ImportScanResult<Int> {
        if isAbsent(field) { return .absent }
        guard let reps = integer(field) else { return .unreadable }
        return reps <= maxReps ? .value(reps) : .implausible
    }

    // MARK: Dates and times

    /// `YYYY-MM-DD` or `DD.MM.YYYY`.
    static func date(_ text: some StringProtocol) -> LocalDate? {
        if let (year, month, day) = triple(text, separator: "-", widths: (4...4, 1...2, 1...2)) {
            return LocalDate(year: year, month: month, day: day)
        }
        if let (day, month, year) = triple(text, separator: ".", widths: (1...2, 1...2, 4...4)) {
            return LocalDate(year: year, month: month, day: day)
        }
        return nil
    }

    struct Clock: Equatable, Sendable {
        let hour: Int
        let minute: Int
        /// `16:41 pm`: a 24-hour time with am/pm; the 24-hour reading is kept.
        let meridiemConflict: Bool
    }

    /// `h:mm am/pm` (12 am = 0, 12 pm = 12) or 24 h `HH:mm`, optionally with seconds (ignored) and a 24-hour suffix.
    static func clock(_ text: some StringProtocol, tokens: AlphaProgressionTokens) -> Clock? {
        let trimmed = Substring(text).trimmingCharacters(in: .whitespaces)
        guard let (hour, afterHour) = leadingInteger(Substring(trimmed)), afterHour.first == ":" else { return nil }
        let minuteText = afterHour.dropFirst().prefix { $0.isASCII && $0.isNumber }
        guard minuteText.count == 2, let minute = integer(minuteText) else { return nil }
        var rest = afterHour.dropFirst().dropFirst(2)
        if rest.first == ":" {
            let seconds = rest.dropFirst().prefix { $0.isASCII && $0.isNumber }
            guard seconds.count == 2 else { return nil }
            rest = rest.dropFirst(3)
        }
        let suffix = rest.trimmingCharacters(in: .whitespaces).lowercased()
        guard minute <= 59 else { return nil }
        if suffix.isEmpty || tokens.clockSuffix.contains(suffix) {
            return hour <= 23 ? Clock(hour: hour, minute: minute, meridiemConflict: false) : nil
        }
        let isAM = tokens.am.contains(suffix)
        guard isAM || tokens.pm.contains(suffix) else { return nil }
        if (1...12).contains(hour) {
            let hour24 = isAM ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)
            return Clock(hour: hour24, minute: minute, meridiemConflict: false)
        }
        return hour <= 23 ? Clock(hour: hour, minute: minute, meridiemConflict: true) : nil
    }

    enum DateTime: Equatable, Sendable {
        case dateTime(LocalDateTime, meridiemConflict: Bool)
        case dateOnly(LocalDate)
        case unreadable
    }

    /// A date, then optionally a clock after a space, comma or `T`.
    static func dateTime(_ text: String, tokens: AlphaProgressionTokens) -> DateTime {
        let trimmed = Substring(text.trimmingCharacters(in: .whitespaces))
        let datePart = trimmed.prefix { $0 != " " && $0 != "," && $0 != "T" }
        guard let date = date(datePart) else { return .unreadable }
        let rest = trimmed.dropFirst(datePart.count).drop { $0 == " " || $0 == "," || $0 == "T" }
        if rest.isEmpty { return .dateOnly(date) }
        guard let clock = clock(rest, tokens: tokens),
              let start = LocalDateTime(date: date, hour: clock.hour, minute: clock.minute) else { return .unreadable }
        return .dateTime(start, meridiemConflict: clock.meridiemConflict)
    }

    // MARK: Durations

    /// `N min`, `h:mm hr`, `N hr`, `N hr M min` (and the token table's other spellings), in whole minutes.
    static func duration(_ text: String, tokens: AlphaProgressionTokens) -> ImportScanResult<Int> {
        if isAbsent(text) { return .absent }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace)
        var total = 0
        var sawHours = false
        var sawMinutes = false
        var index = 0
        while index < words.count {
            let word = words[index]
            index += 1
            guard let (first, afterFirst) = leadingInteger(word) else { return .unreadable }
            var clockMinutes: Int?
            var unitText = afterFirst
            if afterFirst.first == ":" {
                let minuteText = afterFirst.dropFirst().prefix { $0.isASCII && $0.isNumber }
                guard minuteText.count == 2, let minutes = integer(minuteText), minutes < 60 else { return .unreadable }
                clockMinutes = minutes
                unitText = afterFirst.dropFirst(3)
            }
            if unitText.isEmpty {
                guard index < words.count else { return .unreadable }
                unitText = words[index]
                index += 1
            }
            let unit = String(unitText)
            if tokens.hours.contains(unit), !sawHours {
                sawHours = true
                total += first * 60 + (clockMinutes ?? 0)
            } else if tokens.minutes.contains(unit), !sawMinutes, clockMinutes == nil {
                sawMinutes = true
                total += first
            } else {
                return .unreadable
            }
            if total > maxMinutes { return .implausible }
        }
        return total > 0 || sawHours || sawMinutes ? .value(total) : .unreadable
    }

    // MARK: Helpers

    /// Three ASCII-digit groups at `separator`, each within its width.
    private static func triple(_ text: some StringProtocol, separator: Character,
                               widths: (ClosedRange<Int>, ClosedRange<Int>, ClosedRange<Int>)) -> (Int, Int, Int)? {
        let groups = text.split(separator: separator, maxSplits: 3, omittingEmptySubsequences: false)
        guard groups.count == 3, let a = groups.first, let c = groups.last, let b = groups.dropFirst().first,
              widths.0.contains(a.count), widths.1.contains(b.count), widths.2.contains(c.count),
              let x = integer(a), let y = integer(b), let z = integer(c) else { return nil }
        return (x, y, z)
    }
}
