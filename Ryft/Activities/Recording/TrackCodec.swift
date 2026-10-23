import Foundation

/// The binary format of recording chunks (design §2.3): small, append-only, stable across versions.
///
/// Layout, little-endian throughout:
///
/// | Offset | Size | Field |
/// | --- | --- | --- |
/// | 0 | 3 | magic `RYT` |
/// | 3 | 1 | version (1) |
/// | 4 | 1 | kind: 1 profile, 2 route, 3 heart rate |
/// | 5 | 4 | record count, UInt32 |
/// | 9 | 8 | base time, Float64 seconds since 1970 (the first record's time; 0 when empty) |
/// | 17 | n × size | records |
///
/// Records start with their time as a Float32 offset from the base (a chunk spans one checkpoint, so the offset
/// is sub-millisecond exact). Absent values are NaN.
/// - profile, 16 B: time, distance (Float32 m), altitude (Float32 m), speed (Float32 m/s);
/// - route, 28 B: time, latitude (Float64°), longitude (Float64°), horizontal accuracy (Float32 m), altitude (Float32 m);
/// - heart rate, 6 B: time, bpm (UInt16).
///
/// Pure; the recorder actor encodes (design §3.8), and route and heart-rate chunks are sealed after encoding.
enum TrackCodec {
    enum Kind: UInt8, Codable, Sendable {
        case profile = 1
        case route = 2
        case heartRate = 3

        var recordSize: Int {
            switch self {
            case .profile: 16
            case .route: 28
            case .heartRate: 6
            }
        }
    }

    enum DecodingError: Error, Equatable {
        /// Shorter than the header.
        case tooShort
        case badMagic
        case unsupportedVersion(UInt8)
        case unknownKind(UInt8)
        case wrongKind(expected: Kind, found: Kind)
        /// Fewer bytes than the header's count promises: a partial write.
        case truncated(expectedBytes: Int, actualBytes: Int)
        /// More bytes than the header's count.
        case trailingBytes(expectedBytes: Int, actualBytes: Int)
    }

    struct Header: Equatable, Sendable {
        let version: UInt8
        let kind: Kind
        let count: Int
        let base: Date
    }

    static let magic: [UInt8] = [0x52, 0x59, 0x54] // "RYT"
    static let version: UInt8 = 1
    static let headerSize = 17

    // MARK: Encoding

    static func encode(_ points: [ProfilePoint]) -> Data {
        var w = Writer(kind: .profile, count: points.count, base: points.first?.time)
        for p in points {
            w.offset(p.time)
            w.float32(p.distanceM)
            w.float32(p.altitudeM)
            w.float32(p.speedMps)
        }
        return w.data
    }

    static func encode(_ points: [RoutePoint]) -> Data {
        var w = Writer(kind: .route, count: points.count, base: points.first?.time)
        for p in points {
            w.offset(p.time)
            w.float64(p.latitude)
            w.float64(p.longitude)
            w.float32(p.horizontalAccuracy)
            w.float32(p.altitude)
        }
        return w.data
    }

    static func encode(_ readings: [HeartRateReading]) -> Data {
        var w = Writer(kind: .heartRate, count: readings.count, base: readings.first?.timestamp)
        for r in readings {
            w.offset(r.timestamp)
            w.uint16(UInt16(clamping: r.bpm))
        }
        return w.data
    }

    // MARK: Decoding

    static func header(of data: Data) throws -> Header {
        let bytes = [UInt8](data.prefix(headerSize))
        guard bytes.count == headerSize else { throw DecodingError.tooShort }
        guard Array(bytes[0 ..< 3]) == magic else { throw DecodingError.badMagic }
        guard bytes[3] == version else { throw DecodingError.unsupportedVersion(bytes[3]) }
        guard let kind = Kind(rawValue: bytes[4]) else { throw DecodingError.unknownKind(bytes[4]) }
        var r = Reader(bytes: bytes, offset: 5)
        let count = Int(r.uint32())
        let base = Date(timeIntervalSince1970: r.float64())
        return Header(version: bytes[3], kind: kind, count: count, base: base)
    }

    static func decodeProfile(_ data: Data) throws -> [ProfilePoint] {
        var r = try records(of: .profile, in: data)
        return (0 ..< r.count).map { _ in
            ProfilePoint(time: r.time(), distanceM: Double(r.float32()), altitudeM: r.optionalFloat32(),
                         speedMps: r.optionalFloat32())
        }
    }

    static func decodeRoute(_ data: Data) throws -> [RoutePoint] {
        var r = try records(of: .route, in: data)
        return (0 ..< r.count).map { _ in
            RoutePoint(time: r.time(), latitude: r.float64(), longitude: r.float64(),
                       horizontalAccuracy: Double(r.float32()), altitude: r.optionalFloat32())
        }
    }

    static func decodeHeartRate(_ data: Data) throws -> [HeartRateReading] {
        var r = try records(of: .heartRate, in: data)
        return (0 ..< r.count).map { _ in HeartRateReading(timestamp: r.time(), bpm: Int(r.uint16())) }
    }

    private static func records(of kind: Kind, in data: Data) throws -> Reader {
        let header = try header(of: data)
        guard header.kind == kind else { throw DecodingError.wrongKind(expected: kind, found: header.kind) }
        let expected = headerSize + header.count * kind.recordSize
        if data.count < expected { throw DecodingError.truncated(expectedBytes: expected, actualBytes: data.count) }
        if data.count > expected { throw DecodingError.trailingBytes(expectedBytes: expected, actualBytes: data.count) }
        var reader = Reader(bytes: [UInt8](data), offset: headerSize)
        reader.count = header.count
        reader.base = header.base
        return reader
    }

    // MARK: Bytes

    private struct Writer {
        private(set) var bytes: [UInt8]
        let base: Date

        init(kind: Kind, count: Int, base: Date?) {
            self.base = base ?? Date(timeIntervalSince1970: 0)
            bytes = []
            bytes.reserveCapacity(headerSize + count * kind.recordSize)
            bytes += magic
            bytes.append(version)
            bytes.append(kind.rawValue)
            uint32(UInt32(clamping: count))
            float64(self.base.timeIntervalSince1970)
        }

        var data: Data { Data(bytes) }

        mutating func offset(_ time: Date) { float32(time.timeIntervalSince(base)) }
        mutating func float32(_ value: Double?) { uint32(Float(value ?? .nan).bitPattern) }
        mutating func float64(_ value: Double) { uint64(value.bitPattern) }
        mutating func uint16(_ value: UInt16) { append(UInt64(value), bytes: 2) }
        mutating func uint32(_ value: UInt32) { append(UInt64(value), bytes: 4) }
        mutating func uint64(_ value: UInt64) { append(value, bytes: 8) }

        private mutating func append(_ value: UInt64, bytes count: Int) {
            for i in 0 ..< count { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(i)))) }
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int
        var count = 0
        var base = Date(timeIntervalSince1970: 0)

        mutating func time() -> Date { base.addingTimeInterval(Double(float32())) }
        mutating func float32() -> Float { Float(bitPattern: uint32()) }
        mutating func optionalFloat32() -> Double? {
            let value = float32()
            return value.isNaN ? nil : Double(value)
        }

        mutating func float64() -> Double { Double(bitPattern: read(8)) }
        mutating func uint16() -> UInt16 { UInt16(truncatingIfNeeded: read(2)) }
        mutating func uint32() -> UInt32 { UInt32(truncatingIfNeeded: read(4)) }

        private mutating func read(_ n: Int) -> UInt64 {
            var value: UInt64 = 0
            for i in 0 ..< n { value |= UInt64(bytes[offset + i]) << (8 * UInt64(i)) }
            offset += n
            return value
        }
    }
}
