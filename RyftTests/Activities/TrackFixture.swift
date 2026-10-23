import Foundation
@testable import Ryft

/// A synthetic track from `scripts/make-tracks.py` (design §11.2): fixes, barometer samples and ground truth.
struct TrackFixture {
    struct Truth: Decodable {
        let distanceM: Double
        let ascentM: Double
        let descentM: Double
        let splitTimes: [Double]
        let stops: [[Double]]
        let constantSpeed: [[Double]]
    }

    struct Expected: Decodable {
        let fixes: Int
        let accuracyRejections: Int
    }

    struct Faults: Decodable {
        let outliers: [Int]
        let multipath: [Int]
        let gaps: [[Double]]
    }

    private struct File: Decodable {
        let name: String
        let start: Double
        let truth: Truth
        let expected: Expected
        let faults: Faults
        let fixes: [[Double]]
        let altimeter: [[Double]]?
    }

    let name: String
    let start: Date
    let truth: Truth
    let expected: Expected
    let faults: Faults
    let fixes: [LocationFix]
    let altimeter: [AltitudeSample]

    static func load(_ name: String) throws -> TrackFixture {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: Fixture.data(name))
        let start = Date(timeIntervalSince1970: file.start)
        return TrackFixture(
            name: file.name, start: start, truth: file.truth, expected: file.expected, faults: file.faults,
            fixes: file.fixes.map { row in
                LocationFix(timestamp: start.addingTimeInterval(row[0]), latitude: row[1], longitude: row[2],
                            altitude: row[3], horizontalAccuracy: row[4], verticalAccuracy: row[5],
                            isStationary: row[6] != 0)
            },
            altimeter: (file.altimeter ?? []).map {
                AltitudeSample(timestamp: start.addingTimeInterval($0[0]), relativeAltitude: $0[1])
            }
        )
    }

    var splitTimes: [Date] { truth.splitTimes.map(Date.init(timeIntervalSince1970:)) }
    var stops: [DateInterval] {
        truth.stops.map { DateInterval(start: Date(timeIntervalSince1970: $0[0]), end: Date(timeIntervalSince1970: $0[1])) }
    }

    var constantSpeed: [(window: DateInterval, speed: Double)] {
        truth.constantSpeed.map {
            (DateInterval(start: Date(timeIntervalSince1970: $0[0]), end: Date(timeIntervalSince1970: $0[1])), $0[2])
        }
    }

    /// The raw sum of the steps between fixes the accuracy gate keeps: what the pipeline improves on.
    var rawDistance: Double {
        let kept = fixes.filter { $0.horizontalAccuracy <= 25 }
        return zip(kept, kept.dropFirst()).reduce(0) { $0 + Geodesy.distance($1.0.coordinate, $1.1.coordinate) }
    }
}

/// One run of a fixture through a pipeline: Start at the first fix, barometer samples interleaved by time, Finish
/// at the last fix.
struct TrackReplay {
    private(set) var pipeline: TrackPipeline
    /// The events of each fix, by fix index.
    private(set) var events: [[PipelineEvent]] = []
    private(set) var finishEvents: [PipelineEvent] = []
    /// After each fix: its time, the distance so far, the current pace, and the clock a screen shows.
    private(set) var trace: [(time: Date, distance: Double, pace: Double?, shownMovingSec: Double, held: Bool)] = []

    init(_ fixture: TrackFixture, _ configuration: TrackPipeline.Configuration) {
        pipeline = TrackPipeline(configuration: configuration)
        guard let first = fixture.fixes.first, let last = fixture.fixes.last else { return }
        pipeline.start(at: first.timestamp)
        var next = 0
        for fix in fixture.fixes {
            while next < fixture.altimeter.count, fixture.altimeter[next].timestamp <= fix.timestamp {
                pipeline.ingest(fixture.altimeter[next])
                next += 1
            }
            events.append(pipeline.ingest(fix))
            let snapshot = pipeline.snapshot(at: fix.timestamp)
            trace.append((fix.timestamp, pipeline.distanceM, pipeline.currentPace, snapshot.movingSec,
                          snapshot.state == .recording && snapshot.movingAnchor == nil))
        }
        finishEvents = pipeline.finish(at: last.timestamp)
    }

    var allEvents: [PipelineEvent] { events.flatMap { $0 } + finishEvents }

    func rejection(at index: Int) -> FixRejection? {
        for case let .rejected(reason) in events[index] { return reason }
        return nil
    }

    var splits: [TrackSplit] { allEvents.compactMap { if case let .split(s) = $0 { s } else { nil } } }
    var autoPauses: [Date] { allEvents.compactMap { if case let .autoPaused(since) = $0 { since } else { nil } } }
    var autoResumes: [Date] { allEvents.compactMap { if case let .autoResumed(since) = $0 { since } else { nil } } }
    var gaps: [(seconds: Double, bridged: Bool)] {
        allEvents.compactMap { if case let .gap(seconds, bridged) = $0 { (seconds, bridged) } else { nil } }
    }

    /// The distance recorded up to `time` (the last fix at or before it).
    func distance(at time: Date) -> Double {
        trace.last { $0.time <= time }?.distance ?? 0
    }

    /// Relative error of the final distance against ground truth.
    func distanceError(_ fixture: TrackFixture) -> Double {
        (pipeline.distanceM - fixture.truth.distanceM) / fixture.truth.distanceM
    }
}

/// Noiseless 1 Hz fixes along a straight line (bearing 60° from a public park in Berlin), from speed segments.
enum SyntheticTrack {
    static let t0 = Date(timeIntervalSince1970: 1_781_420_400)
    static let origin = Coordinate(latitude: 52.4731, longitude: 13.4015)

    struct Segment {
        let seconds: Int
        let speed: Double
        var stationary = false
    }

    /// One fix per second, the first at `start`; each second moves at its segment's speed.
    static func fixes(_ segments: [Segment], accuracy: Double = 5, start: Date = t0,
                      from origin: Coordinate = origin, bearing: Double = 60) -> [LocationFix] {
        var fixes: [LocationFix] = []
        var along = 0.0, t = 0
        func emit(stationary: Bool) {
            let c = Geodesy.destination(from: origin, bearing: bearing, distance: along)
            fixes.append(LocationFix(timestamp: start.addingTimeInterval(Double(t)), latitude: c.latitude,
                                     longitude: c.longitude, horizontalAccuracy: accuracy, isStationary: stationary))
        }
        emit(stationary: segments.first?.stationary ?? false)
        for segment in segments {
            for _ in 0 ..< segment.seconds {
                along += segment.speed
                t += 1
                emit(stationary: segment.stationary)
            }
        }
        return fixes
    }

    static func distance(_ segments: [Segment]) -> Double {
        segments.reduce(0) { $0 + Double($1.seconds) * $1.speed }
    }

    /// Feeds `fixes` to a started pipeline and returns every event.
    static func run(_ pipeline: inout TrackPipeline, _ fixes: [LocationFix]) -> [PipelineEvent] {
        fixes.flatMap { pipeline.ingest($0) }
    }
}
