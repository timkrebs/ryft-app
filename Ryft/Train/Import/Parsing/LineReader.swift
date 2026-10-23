import Foundation

/// One line of a file: its 1-based number and the range of its bytes, without the line end.
struct RawLine: Equatable, Sendable {
    let number: Int
    let bytes: Range<Int>
    /// Over `ImportLimits.maxLineBytes`: skipped without decoding (`.lineTooLong`).
    let isTooLong: Bool
}

/// The lines of a file, lazily (design §3): it never builds an array of lines or one big `String`. A UTF-8 BOM is
/// skipped; LF, CRLF and a lone CR each end a line; a last line without one is read; a final line end adds no line.
struct LineReader: Sequence, Sendable {
    let data: Data
    let maxLineBytes: Int

    init(_ data: Data, maxLineBytes: Int) {
        self.data = data
        self.maxLineBytes = maxLineBytes
    }

    func makeIterator() -> Iterator {
        Iterator(data: data, maxLineBytes: maxLineBytes, position: data.startIndex + ImportHygiene.bomLength(data))
    }

    struct Iterator: IteratorProtocol {
        let data: Data
        let maxLineBytes: Int
        var position: Int
        var number = 0

        mutating func next() -> RawLine? {
            let start = position
            let end = data.endIndex
            guard start < end else { return nil }
            // Scan to the next CR or LF. Every call consumes at least one byte, so the loop always ends.
            let lineEnd: Int = data.withUnsafeBytes { raw in
                var i = start - data.startIndex
                while i < raw.count {
                    let byte = raw[i]
                    if byte == 0x0A || byte == 0x0D { break }
                    i += 1
                }
                return i + data.startIndex
            }
            if lineEnd < end {
                let isCRLF = data[lineEnd] == 0x0D && lineEnd + 1 < end && data[lineEnd + 1] == 0x0A
                position = lineEnd + (isCRLF ? 2 : 1)
            } else {
                position = end
            }
            number += 1
            return RawLine(number: number, bytes: start..<lineEnd, isTooLong: lineEnd - start > maxLineBytes)
        }
    }

    /// A line's text. Invalid UTF-8 decodes lossily (U+FFFD) and says so; a stray BOM at its start is dropped.
    func text(of line: RawLine) -> (text: String, isInvalid: Bool) {
        let bytes = data[line.bytes.clamped(to: data.startIndex..<data.endIndex)]
        var isInvalid = false
        var text: String
        if let valid = String(bytes: bytes, encoding: .utf8) {
            text = valid
        } else {
            // Lossy on purpose (design §3): invalid bytes become U+FFFD and the line still gets read.
            // swiftlint:disable:next optional_data_string_conversion
            text = String(decoding: bytes, as: UTF8.self)
            isInvalid = true
        }
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        return (text, isInvalid)
    }
}

/// Whole-file checks shared by detection and parsing (design §3, file hygiene).
enum ImportHygiene {
    /// Detection reads at most this much.
    static let headBytes = 64 << 10

    /// 3 for a UTF-8 BOM at the start, else 0.
    static func bomLength(_ data: Data) -> Int {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    }

    /// A UTF-16 or UTF-32 BOM, or NUL bytes in the first 64 KiB: not UTF-8 text.
    static func isUnsupportedEncoding(_ data: Data) -> Bool {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return true }
        return data.prefix(headBytes).withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            return memchr(base, 0, raw.count) != nil
        }
    }

    /// The first 64 KiB, cut after the last line end in it (the whole of a shorter file).
    static func head(of data: Data) -> Data {
        guard data.count > headBytes else { return data }
        let prefix = data.prefix(headBytes)
        guard let lastEnd = prefix.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return prefix }
        return data[data.startIndex...lastEnd]
    }

    /// Nothing but a BOM and whitespace.
    static func isBlank(_ data: Data) -> Bool {
        data.dropFirst(bomLength(data)).allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }

    /// A whole file without a BOM that isn't valid UTF-8 is most likely a spreadsheet's Windows-1252 save: it is read as
    /// that, not lossily as UTF-8 (which would put U+FFFD into names). nil when the file is UTF-8 or has a UTF-8 BOM.
    static func legacyText(_ data: Data) -> Data? {
        guard bomLength(data) == 0, String(bytes: data, encoding: .utf8) == nil else { return nil }
        // Windows-1252 leaves five bytes undefined; Latin-1 reads every byte (those five become C1 controls, which the
        // field split strips).
        let text = String(bytes: data, encoding: .windowsCP1252) ?? String(bytes: data, encoding: .isoLatin1)
        return text.map { Data($0.utf8) }
    }
}
