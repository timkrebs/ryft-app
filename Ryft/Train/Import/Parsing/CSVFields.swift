import Foundation

/// A line split at `;` (design §3, file hygiene). Keeps at most `CSVFields.maxFields` fields; `hasMore` says a
/// further non-empty one followed. Trailing empty fields (a trailing `;`) are dropped; fields are trimmed and hold no
/// control or format characters except tab.
struct CSVLine: Equatable, Sendable {
    var fields: [String]
    /// Per field: it was written in double quotes.
    var quoted: [Bool]
    var hasMore: Bool
    /// Bytes the split looked at: the measure of its work (`ParseStats.visited`).
    var visited = 0

    var count: Int { fields.count }
    var isEmpty: Bool { fields.isEmpty && !hasMore }

    /// The field at `index`, or nil past the end.
    func field(_ index: Int) -> String? {
        index >= 0 && index < fields.count ? fields[index] : nil
    }

    /// The field at `index` was written in double quotes.
    func isQuoted(_ index: Int) -> Bool {
        index >= 0 && index < quoted.count ? quoted[index] : false
    }
}

enum CSVFields {
    /// Every line the format knows has at most three fields.
    static let maxFields = 3
    private static let separator = UInt8(ascii: ";")
    private static let quote = UInt8(ascii: "\"")

    /// `"…"` may contain `;` and `""`; text after a closing quote is kept as written; an unclosed quote takes the
    /// rest of the line. Quotes never span lines (the caller passes one line). Linear in the line's length.
    static func split(_ line: String, maxFields: Int = CSVFields.maxFields) -> CSVLine {
        let bytes = Array(line.utf8)
        let n = bytes.count
        var fields: [String] = []
        var quoted: [Bool] = []
        var hasMore = false
        var visited = 0
        var i = 0
        while true {
            var j = i
            while j < n, bytes[j] == 0x20 || bytes[j] == 0x09 { j += 1 }
            var value: [UInt8] = []
            var isQuoted = false
            if j < n, bytes[j] == quote {
                isQuoted = true
                j += 1
                var closed = false
                while j < n {
                    if bytes[j] == quote {
                        if j + 1 < n, bytes[j + 1] == quote {
                            value.append(quote)
                            j += 2
                            continue
                        }
                        j += 1
                        closed = true
                        break
                    }
                    value.append(bytes[j])
                    j += 1
                }
                if closed {
                    while j < n, bytes[j] != separator {
                        value.append(bytes[j])
                        j += 1
                    }
                }
            } else {
                while j < n, bytes[j] != separator {
                    value.append(bytes[j])
                    j += 1
                }
            }
            visited += j - i + 1
            let text = cleaned(value, visited: &visited)
            if fields.count < maxFields {
                fields.append(text)
                quoted.append(isQuoted)
            } else if !text.isEmpty {
                hasMore = true
                break
            }
            // `j` is at a separator or the end; every pass moves past one separator, so the loop ends.
            guard j < n else { break }
            i = j + 1
        }
        while let last = fields.last, last.isEmpty, !hasMore {
            fields.removeLast()
            quoted.removeLast()
        }
        return CSVLine(fields: fields, quoted: quoted, hasMore: hasMore, visited: visited)
    }

    /// A field's parts at the inner separator ` · ` (U+00B7 with whitespace on both sides, a no-break space too),
    /// trimmed. A bare `A·B` stays one part.
    static func parts(_ field: String) -> [String] {
        var parts: [String] = []
        var start = field.startIndex
        var index = field.startIndex
        var previousIsWhitespace = false
        while index < field.endIndex {
            let character = field[index]
            let next = field.index(after: index)
            if character == "\u{00B7}", previousIsWhitespace, next < field.endIndex, field[next].isWhitespace {
                parts.append(field[start..<index].trimmingCharacters(in: .whitespaces))
                start = next
            }
            previousIsWhitespace = character.isWhitespace
            index = next
        }
        parts.append(field[start...].trimmingCharacters(in: .whitespaces))
        return parts
    }

    /// The field's text, trimmed, without control (Cc) or format (Cf) characters other than tab: no NUL, no U+001F
    /// (the id separator, ADR 0007), no bidi overrides or zero-width characters reach names, mapping or ids.
    private static func cleaned(_ value: [UInt8], visited: inout Int) -> String {
        // The bytes are a valid line cut at ASCII `;` and `"`, so decoding can't fail.
        // swiftlint:disable:next optional_data_string_conversion
        var text = String(decoding: value, as: UTF8.self)
        if value.contains(where: { ($0 < 0x20 && $0 != 0x09) || $0 >= 0x7F }) {
            visited += value.count
            text.unicodeScalars.removeAll { scalar in
                scalar != "\t" && [.control, .format].contains(scalar.properties.generalCategory)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
