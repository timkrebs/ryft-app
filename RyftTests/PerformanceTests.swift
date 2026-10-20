import XCTest
@testable import Ryft

/// Baselines for the two hot paths that grow with history: decoding a quarter of day
/// details (Trends, the 90-day backfill) and building one full upload page.
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
}
