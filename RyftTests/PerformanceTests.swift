import XCTest
@testable import Ryft

/// Baselines for the hot paths that grow with history: decoding a quarter of day
/// details (Trends, the 90-day backfill), building one full upload page, and parsing a
/// training export at the 8 MiB cap.
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

    /// The costliest lines per byte found in review: names of 4 000 digits, titles of hundreds of parts, quote runs.
    func testParsingAnEightMebibyteWorstCase() {
        let dot = " \u{00B7} "
        let lines = "\"" + String(repeating: "1", count: 4_000) + "\"\n"
            + "\"A\(dot)" + Array(repeating: "Day 1", count: 400).joined(separator: dot) + "\";\"2026-01-05 10:00\";\"30 min\"\n"
            + String(repeating: "\"", count: 4_000) + "\n"
        measureParse(of: filled(with: lines)) { bundle in
            XCTAssertGreaterThan(bundle.lineCount, 0)
        }
    }

    private func filled(with unit: String) -> Data {
        let bytes = Array(unit.utf8)
        var data = Data()
        data.reserveCapacity(ImportLimits.standard.maxFileBytes)
        while data.count + bytes.count <= ImportLimits.standard.maxFileBytes { data.append(contentsOf: bytes) }
        return data
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
