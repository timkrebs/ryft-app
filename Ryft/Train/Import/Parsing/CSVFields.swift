import Foundation

/// A line split at `;` (design §3, file hygiene). Keeps at most `CSVFields.maxFields` fields; `hasMore` says a
/// further non-empty one followed. Trailing empty fields (a trailing `;`) are dropped; fields are trimmed.
struct CSVLine: Equatable, Sendable {
    var fields: [String]
    /// Per field: it was written in double quotes.
    var quoted: [Bool]
    var hasMore: Bool

    var count: Int { fields.count }
    var isEmpty: Bool { fields.isEmpty && !hasMore }

    /// The field at `index`, or nil past the end.
    func field(_ index: Int) -> String? {
        index >= 0 && index < fields.count ? fields[index] : nil
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
            // The bytes are a valid line cut at ASCII `;` and `"`, so decoding can't fail.
            // swiftlint:disable:next optional_data_string_conversion
            let text = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .whitespaces)
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
        return CSVLine(fields: fields, quoted: quoted, hasMore: hasMore)
    }

    /// A field's parts at the inner separator ` · ` (U+00B7 with spaces), trimmed.
    static func parts(_ field: String) -> [String] {
        field.components(separatedBy: " \u{00B7} ").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
