import Foundation
import Testing
@testable import Ryft

@Suite("Track codec")
struct TrackCodecTests {
    static let base = Date(timeIntervalSince1970: 1_781_420_400.25)

    static let profile: [ProfilePoint] = (0 ..< 30).map(profilePoint)
    static let route: [RoutePoint] = (0 ..< 30).map(routePoint)

    static func profilePoint(_ i: Int) -> ProfilePoint {
        let altitude: Double? = i % 7 == 0 ? nil : 412.5 + Double(i) / 10
        let speed: Double? = i == 3 ? nil : 3.1
        return ProfilePoint(time: base.addingTimeInterval(Double(i)), distanceM: 3.1 * Double(i), altitudeM: altitude,
                            speedMps: speed)
    }

    static func routePoint(_ i: Int) -> RoutePoint {
        let offset = Double(i) * 1e-5
        let altitude: Double? = i == 0 ? nil : 38.25
        return RoutePoint(time: base.addingTimeInterval(Double(i) * 1.02), latitude: 52.473_137_24 + offset,
                          longitude: -13.401_510_65 - offset, horizontalAccuracy: 4.5, altitude: altitude)
    }

    static let heartRate = (0 ..< 30).map { HeartRateReading(timestamp: base.addingTimeInterval(Double($0)), bpm: 120 + $0) }

    @Test func profileRoundTrips() throws {
        let data = TrackCodec.encode(Self.profile)
        #expect(data.count == TrackCodec.headerSize + 30 * 16)
        let decoded = try TrackCodec.decodeProfile(data)
        #expect(decoded.count == 30)
        for (a, b) in zip(Self.profile, decoded) {
            #expect(abs(a.time.timeIntervalSince(b.time)) < 1e-5)
            #expect(abs(a.distanceM - b.distanceM) < 1e-3)
            #expect((a.altitudeM == nil) == (b.altitudeM == nil))
            #expect(abs((a.altitudeM ?? 0) - (b.altitudeM ?? 0)) < 1e-3)
            #expect(a.speedMps.map { abs($0 - (b.speedMps ?? .nan)) < 1e-5 } ?? (b.speedMps == nil))
        }
    }

    @Test func routeRoundTripsWithFullCoordinatePrecision() throws {
        let data = TrackCodec.encode(Self.route)
        #expect(data.count == TrackCodec.headerSize + 30 * 28)
        let decoded = try TrackCodec.decodeRoute(data)
        for (a, b) in zip(Self.route, decoded) {
            #expect(a.latitude == b.latitude && a.longitude == b.longitude)
            #expect(abs(a.time.timeIntervalSince(b.time)) < 1e-5)
            #expect(abs(a.horizontalAccuracy - b.horizontalAccuracy) < 1e-6)
            #expect(a.altitude == b.altitude)
        }
    }

    @Test func heartRateRoundTrips() throws {
        let data = TrackCodec.encode(Self.heartRate)
        #expect(data.count == TrackCodec.headerSize + 30 * 6)
        let decoded = try TrackCodec.decodeHeartRate(data)
        #expect(decoded.map(\.bpm) == Self.heartRate.map(\.bpm))
        #expect(zip(decoded, Self.heartRate).allSatisfy { abs($0.timestamp.timeIntervalSince($1.timestamp)) < 1e-5 })
    }

    @Test func emptyChunksRoundTrip() throws {
        #expect(try TrackCodec.decodeProfile(TrackCodec.encode([ProfilePoint]())).isEmpty)
        #expect(try TrackCodec.decodeRoute(TrackCodec.encode([RoutePoint]())).isEmpty)
        #expect(TrackCodec.encode([HeartRateReading]()).count == TrackCodec.headerSize)
    }

    @Test func headerLayout() throws {
        let bytes = [UInt8](TrackCodec.encode(Self.route))
        #expect(Array(bytes[0 ..< 3]) == Array("RYT".utf8))
        #expect(bytes[3] == 1) // version
        #expect(bytes[4] == 2) // kind: route
        #expect(Array(bytes[5 ..< 9]) == [30, 0, 0, 0]) // count, little-endian
        let base = bytes[9 ..< 17].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        #expect(Double(bitPattern: base) == Self.base.timeIntervalSince1970)
        let header = try TrackCodec.header(of: Data(bytes))
        #expect(header == TrackCodec.Header(version: 1, kind: .route, count: 30, base: Self.base))
    }

    @Test func anotherVersionIsRefused() {
        var bytes = [UInt8](TrackCodec.encode(Self.profile))
        bytes[3] = 2
        #expect(throws: TrackCodec.DecodingError.unsupportedVersion(2)) { try TrackCodec.decodeProfile(Data(bytes)) }
    }

    @Test func badMagicAndKindsAreRefused() {
        var bytes = [UInt8](TrackCodec.encode(Self.profile))
        bytes[0] = 0x00
        #expect(throws: TrackCodec.DecodingError.badMagic) { try TrackCodec.decodeProfile(Data(bytes)) }
        #expect(throws: TrackCodec.DecodingError.wrongKind(expected: .route, found: .profile)) {
            try TrackCodec.decodeRoute(TrackCodec.encode(Self.profile))
        }
        var unknown = [UInt8](TrackCodec.encode(Self.profile))
        unknown[4] = 9
        #expect(throws: TrackCodec.DecodingError.unknownKind(9)) { try TrackCodec.decodeProfile(Data(unknown)) }
    }

    @Test func truncationIsDetected() {
        let data = TrackCodec.encode(Self.route)
        let expected = TrackCodec.headerSize + 30 * 28
        #expect(throws: TrackCodec.DecodingError.truncated(expectedBytes: expected, actualBytes: expected - 1)) {
            try TrackCodec.decodeRoute(data.dropLast())
        }
        #expect(throws: TrackCodec.DecodingError.tooShort) { try TrackCodec.decodeRoute(data.prefix(16)) }
        #expect(throws: TrackCodec.DecodingError.trailingBytes(expectedBytes: expected, actualBytes: expected + 1)) {
            try TrackCodec.decodeRoute(data + Data([0]))
        }
    }

    /// Design §2.3: 2 h at 1 Hz is about 115 KB of profile and 200 KB of route.
    @Test func twoHoursAtOneHertzFitTheBudget() {
        let n = 7200
        let profile = (0 ..< n).map { ProfilePoint(time: Self.base.addingTimeInterval(Double($0)), distanceM: 0, altitudeM: nil, speedMps: nil) }
        #expect(TrackCodec.encode(profile).count == 17 + n * 16) // 115 217 B
        #expect(TrackCodec.Kind.route.recordSize * n + 17 == 201_617)
    }
}
