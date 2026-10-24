import XCTest
@testable import Ryft

/// Baselines for the hot paths that grow with history: decoding a quarter of day
/// details (Trends, the 90-day backfill), building one full upload page, parsing a
/// training export at the 8 MiB cap, and the cached reads views decode on the main
/// actor (`DateParsing.canonical`'s reason).
/// XCTest because XCTMetric has no Swift Testing equivalent; runs in the `Full` test
/// plan only (nightly), never on pull requests (docs/CI.md → Test plans).
final class PerformanceTests: XCTestCase {
    /// 90 copies of the `GET /v1/days/{day}` fixture as one JSON array.
    private func ninetyDays() throws -> Data {
        let one = try Fixture.data("day_detail")
        var body = Data("[".utf8)
        for i in 0..<90 {
            if i > 0 { body.append(Data(",".utf8)) }
            body.append(one)
        }
        body.append(Data("]".utf8))
        return body
    }

    func testDecodingNinetyDaysOfDayDetail() throws {
        let body = try ninetyDays()
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            do {
                let days = try APIClient.jsonDecoder.decode([DayDetail].self, from: body)
                XCTAssertEqual(days.count, 90)
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    /// The read-model cache's shape: what `Repository` stores (`WireCoding`, `.iso8601`, whole seconds)
    /// and a view decodes after any write of its kind.
    private func cached(_ value: some Encodable) throws -> Data {
        try APIClient.jsonEncoder.encode(value)
    }

    /// 100 decodes per iteration, so the block is long enough to time.
    private func measureDecoding<T: Decodable>(_ type: T.Type, from body: Data) {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            do {
                for _ in 0..<100 {
                    _ = try APIClient.jsonDecoder.decode(T.self, from: body)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    /// `Repository.day`: the `GET /v1/days/{day}` fixture as the cache holds it (17 dates).
    func testDecodingACachedDayDetail() throws {
        let body = try cached(Fixture.decode(DayDetail.self, "day_detail"))
        measureDecoding(DayDetail.self, from: body)
    }

    /// A day's list as the cache holds it: 50 workouts (100 dates).
    func testDecodingFiftyCachedWorkouts() throws {
        let workouts = try Fixture.decode([Workout].self, "workouts")
        let body = try cached((0..<50).map { workouts[$0 % workouts.count] })
        measureDecoding([Workout].self, from: body)
    }

    /// A full page (`HealthKitManager.pageSize`, 20 000 records) as SyncService
    /// uploads it: request built and encoded with the app's encoder.
    func testBuildingAFullSyncPage() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let samples = (0..<20_000).map { i in
            Sample(type: SampleType.allCases[i % SampleType.allCases.count],
                   start: start.addingTimeInterval(Double(i) * 60),
                   end: start.addingTimeInterval(Double(i) * 60 + 5),
                   value: 50 + Double(i % 40), unit: "count/min", source: "com.apple.health")
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let request = SyncRequest(deviceId: UUID(), deviceName: "iPhone",
                                      samples: samples, sleep: [], workouts: [])
            do {
                let body = try APIClient.jsonEncoder.encode(request)
                XCTAssertGreaterThan(body.count, 1_000_000)
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    /// An Alpha Progression export at the 8 MiB cap: 10 000 workouts (the session cap) of one exercise and a set table.
    func testParsingAnEightMebibyteExport() {
        let block = "\"A \u{00B7} Standalone workout\";\"2026-01-05 10:00\";\"30 min\"\n"
            + "\"1. Floor Press \u{00B7} Barbell \u{00B7} 8 reps\"\n#;KG;REPS\n1;60;10\n2;62,5;8\n3;-;-\n\n"
        measureParse(of: filled(with: block)) { bundle in
            XCTAssertEqual(bundle.sessions.count, ImportLimits.standard.maxSessions)
        }
    }

    /// The worst case below (`worstCaseLines`) at the cap.
    func testParsingAnEightMebibyteWorstCase() {
        measureParse(of: filled(with: Self.worstCaseLines)) { bundle in
            XCTAssertGreaterThan(bundle.lineCount, 0)
        }
    }

    /// Superlinear work inside a helper isn't in `ParseStats.visited`, so it is caught as time, by two ratios measured
    /// in one run (no baseline needed):
    /// - the worst case at 8 MiB against 1 MiB (linear: about 8×; at most 12×): work that grows with the file;
    /// - 1 MiB of 4 KiB workout titles against 1 MiB of 130-byte ones, per byte (linear: about 1×; at most 1.6×): work
    ///   that grows with a line, which the first ratio can't see. A part split that rescans its field gave 2.2–5.3×.
    func testParseTimeGrowsLinearly() {
        let perByteBySize = perByteRatio(filled(with: Self.worstCaseLines), filled(with: Self.worstCaseLines, bytes: 1 << 20),
                                         repeats: 8)
        XCTAssertLessThanOrEqual(perByteBySize * 8, 12, "8 MiB took \(perByteBySize * 8)× as long as 1 MiB")
        let perByteByLine = perByteRatio(filled(with: Self.title(parts: 400), bytes: 1 << 20),
                                         filled(with: Self.title(parts: 10), bytes: 1 << 20), repeats: 1)
        XCTAssertLessThanOrEqual(perByteByLine, 1.6, "Long lines took \(perByteByLine)× as long per byte as short ones")
    }

    /// The costliest lines per byte found in review: names of 4 000 digits, titles of hundreds of parts, quote runs.
    private static let worstCaseLines = "\"" + String(repeating: "1", count: 4_000) + "\"\n" + title(parts: 400)
        + String(repeating: "\"", count: 4_000) + "\n"

    private static func title(parts: Int) -> String {
        let dot = " \u{00B7} "
        return "\"A\(dot)" + Array(repeating: "Day 1", count: parts).joined(separator: dot) + "\";\"2026-01-05 10:00\";\"30 min\"\n"
    }

    private func filled(with unit: String, bytes: Int = ImportLimits.standard.maxFileBytes) -> Data {
        let unitBytes = Array(unit.utf8)
        var data = Data()
        data.reserveCapacity(bytes)
        while data.count + unitBytes.count <= bytes { data.append(contentsOf: unitBytes) }
        return data
    }

    /// Parse time per byte of `a` over that of `b` (`b` parsed `repeats` times per round, so both sides take about as
    /// long). Three interleaved rounds, the fastest of each side: other work on the machine slows both alike.
    private func perByteRatio(_ a: Data, _ b: Data, repeats: Int) -> Double {
        let clock = ContinuousClock()
        var fastestA = Duration.seconds(3_600)
        var fastestB = Duration.seconds(3_600)
        for _ in 0..<3 {
            fastestA = min(fastestA, clock.measure { _ = try? AlphaProgressionFormat().parse(a, limits: .standard) })
            fastestB = min(fastestB, clock.measure {
                for _ in 0..<repeats { _ = try? AlphaProgressionFormat().parse(b, limits: .standard) }
            })
        }
        return seconds(fastestA) / seconds(fastestB) * Double(b.count * repeats) / Double(a.count)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Clock and memory per parse (compared across nightly runs, never asserted), and the work bound the fuzz test
    /// uses: every byte and line visited a small, fixed number of times.
    private func measureParse(of data: Data, check: (ImportBundle) -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            var stats = ParseStats()
            do {
                let bundle = try AlphaProgressionFormat().parse(data, limits: .standard, stats: &stats)
                check(bundle)
                XCTAssertLessThanOrEqual(stats.visited, 24 * data.count + 24 * stats.lines + 64)
            } catch {
                XCTFail("\(error)")
            }
        }
    }
}
