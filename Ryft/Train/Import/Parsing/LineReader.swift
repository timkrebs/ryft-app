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

    /// A file's text as UTF-8, decided once per file: detection and parsing read the same bytes.
    struct DecodedText: Sendable {
        /// UTF-8 (a BOM, if the file had one, is kept; the line reader skips it).
        let utf8: Data
        /// The file was read as Windows-1252 (`.legacyEncoding`).
        let isLegacy: Bool
    }

    /// UTF-8 as it is, unless the file has no BOM and its invalid UTF-8 sequences outnumber its well-formed multi-byte
    /// ones (or it has invalid ones and no well-formed ones). Then it is a spreadsheet's Windows-1252 save and is read
    /// as that. One stray byte in a UTF-8 export stays a line-level `.invalidText`, so `·` and umlauts elsewhere survive.
    static func decode(_ data: Data) -> DecodedText {
        guard bomLength(data) == 0 else { return DecodedText(utf8: data, isLegacy: false) }
        let census = utf8Census(data)
        guard census.invalid > 0, census.wellFormedMultiByte == 0 || census.invalid > census.wellFormedMultiByte else {
            return DecodedText(utf8: data, isLegacy: false)
        }
        // Windows-1252 leaves five bytes undefined; Latin-1 reads every byte (those five become C1 controls, which the
        // field split strips).
        guard let text = String(bytes: data, encoding: .windowsCP1252) ?? String(bytes: data, encoding: .isoLatin1) else {
            return DecodedText(utf8: data, isLegacy: false)
        }
        return DecodedText(utf8: Data(text.utf8), isLegacy: true)
    }

    /// Well-formed multi-byte UTF-8 sequences and invalid bytes (a byte that starts no well-formed sequence counts once;
    /// overlong forms, surrogates and code points over U+10FFFF are invalid). One pass, no allocation.
    static func utf8Census(_ data: Data) -> (wellFormedMultiByte: Int, invalid: Int) {
        data.withUnsafeBytes { raw in
            var wellFormed = 0
            var invalid = 0
            var i = 0
            let n = raw.count
            while i < n {
                let lead = raw[i]
                if lead < 0x80 {
                    i += 1
                    continue
                }
                let length = sequenceLength(lead: lead, second: i + 1 < n ? raw[i + 1] : nil)
                var valid = length > 1 && i + length <= n
                var k = 2
                while valid, k < length {
                    let byte = raw[i + k]
                    valid = byte & 0xC0 == 0x80
                    k += 1
                }
                if valid {
                    wellFormed += 1
                    i += length
                } else {
                    invalid += 1
                    i += 1
                }
            }
            return (wellFormed, invalid)
        }
    }

    /// The length of the UTF-8 sequence a lead byte starts when its second byte is in range (RFC 3629's table), else 0.
    private static func sequenceLength(lead: UInt8, second: UInt8?) -> Int {
        guard let second else { return 0 }
        let range: ClosedRange<UInt8>
        let length: Int
        switch lead {
        case 0xC2...0xDF: (range, length) = (0x80...0xBF, 2)
        case 0xE0: (range, length) = (0xA0...0xBF, 3)
        case 0xE1...0xEC, 0xEE...0xEF: (range, length) = (0x80...0xBF, 3)
        case 0xED: (range, length) = (0x80...0x9F, 3)
        case 0xF0: (range, length) = (0x90...0xBF, 4)
        case 0xF1...0xF3: (range, length) = (0x80...0xBF, 4)
        case 0xF4: (range, length) = (0x80...0x8F, 4)
        default: return 0
        }
        return range.contains(second) ? length : 0
    }
}
