import Foundation
import Testing
@testable import Ryft

/// "Export my data" with activities (design.md §8.7, privacy S-4): the platform's copies, what this iPhone hasn't
/// had confirmed, and the nights the user added; never a route or heart-rate samples (none in A2: list reads carry
/// none, R16; A5 adds trimmed routes, R14).
@Suite("Export: activities and manual sleep")
@MainActor
struct ActivityExportTests {
    /// The archive as `DataExport.write` encodes it (the same settings, without a file in the shared tmp folder).
    private static func json(_ archive: DataExport.Archive) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func text<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// A ride the platform holds, recorded 200 days ago (the second 180-day chunk), with a route and samples.
    private static func ride(_ h: UploadHarness) -> SportActivity {
        let end = DayFormat.shift(h.clock.now(), days: -200)
        return SportActivity(id: UUID(), sport: .cycling, origin: .recorded, start: end.addingTimeInterval(-3_600),
                             end: end, movingSec: 3_500, distanceM: 24_000,
                             splits: [ActivitySplit(index: 1, distanceM: 1_000, durationSec: 140, ascentM: 4)],
                             route: "_p~iF~ps|U_ulLnnqC", hrSamples: [HRPoint(t: end, bpm: 141)], clientUpdatedAt: end)
    }

    @Test func theArchiveHoldsThePlatformsCopiesTheUnconfirmedRowsAndTheNights() async throws {
        let h = UploadHarness()
        h.platform.answersWithTrack = true // a platform that ignores R16: still nothing of the track goes out
        let ride = Self.ride(h)
        _ = try await h.platform.putActivity(ride)
        // Confirmed: an activity and last night.
        let confirmed = try #require(h.save(minutesAgo: 400))
        let night = h.night()
        h.store.saveSleep(day: night.day, bed: night.bed, wake: night.wake)
        await h.uploader.flush()
        // Refused by the platform.
        let refused = try #require(h.save(minutesAgo: 200))
        h.api.failNext = APIError.http(422, "invalid")
        await h.uploader.flush()
        // Not sent yet: an activity and the night before.
        let pending = try #require(h.save(minutesAgo: 100, notes: "Hill reps"))
        let earlierWake = night.wake.addingTimeInterval(-86_400)
        h.store.saveSleep(day: DayFormat.string(from: earlierWake), bed: earlierWake.addingTimeInterval(-7 * 3_600),
                          wake: earlierWake)

        let archive = try await DataExport.archive(source: h.api, train: h.api, activities: h.api, onPhone: h.store,
                                                   now: h.clock.now())
        // The platform's copies, each once, without route or samples, with splits.
        let ids = archive.activities.map(\.id)
        #expect(Set(ids) == [ride.id, confirmed])
        #expect(ids.count == Set(ids).count)
        let noTrack = archive.activities.allSatisfy { $0.route == nil && $0.hrSamples == nil }
        #expect(noTrack)
        #expect(archive.activities.first { $0.id == ride.id }?.splits?.count == 1)
        // What this iPhone hasn't had confirmed, by state; confirmed rows aren't repeated.
        let states = Dictionary(uniqueKeysWithValues: archive.unconfirmedActivities.map { ($0.activity.id, $0.state) })
        #expect(states == [refused: "refused", pending: "pending"])
        #expect(archive.unconfirmedActivities.first { $0.activity.id == pending }?.activity.notes == "Hill reps")
        // The nights.
        #expect(archive.manualSleep.map(\.state) == ["pending", "confirmed"])
        #expect(archive.manualSleep.last?.day == night.day)

        let object = try Self.json(archive)
        #expect(object["activities"] != nil && object["unconfirmed_activities"] != nil && object["manual_sleep"] != nil)
        // The activities' parts of the file: no route, no samples, under any key or value.
        let text = try Self.text(archive.activities) + Self.text(archive.unconfirmedActivities)
        #expect(!text.contains("route") && !text.contains("hr_samples") && !text.contains("_p~iF"))
        #expect(text.contains("moving_sec") && text.contains("\"state\""))
    }

    @Test func aTombstoneTheDeleteHasntReachedIsExportedAsDeleting() async throws {
        let h = UploadHarness()
        let id = try #require(h.save())
        await h.uploader.flush()
        h.api.failure = APIError.http(503, "busy")
        h.uploader.deleted(id)
        await h.uploader.flush()
        h.api.failure = nil
        let archive = try await DataExport.archive(source: h.api, train: h.api, activities: h.api, onPhone: h.store,
                                                   now: h.clock.now())
        #expect(archive.unconfirmedActivities.map(\.state) == ["deleting"])
        #expect(archive.activities.map(\.id) == [id]) // the platform still has it
    }

    @Test func beforeTheContractThePlatformIsntAskedAndTheRowsAreThere() async throws {
        let h = UploadHarness()
        h.platform.publishesActivities = false
        let id = try #require(h.save())
        let archive = try await DataExport.archive(source: h.api, train: h.api, activities: h.api, onPhone: h.store,
                                                   now: h.clock.now())
        #expect(h.api.count("activities") == 0)
        #expect(archive.activities.isEmpty)
        #expect(archive.unconfirmedActivities.map(\.activity.id) == [id])
    }

    @Test func theChunksCoverEveryInstantOnceFromMidnightToMidnight() async throws {
        let h = UploadHarness()
        _ = try await DataExport.archive(source: h.api, train: h.api, activities: h.api, now: h.clock.now())
        let ranges = h.platform.listed
        #expect(ranges.count >= 2)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: h.clock.now()))
        #expect(ranges.first?.end == tomorrow)
        for (newer, older) in zip(ranges, ranges.dropFirst()) {
            #expect(older.end == newer.start) // no gap, no overlap
        }
        let fromMidnight = ranges.allSatisfy { calendar.startOfDay(for: $0.start) == $0.start }
        #expect(fromMidnight)
    }
}
