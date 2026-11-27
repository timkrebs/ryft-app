import Foundation
import Testing
@testable import Ryft

@Suite("Home sync indicator")
struct SyncIndicatorStateTests {
    private let now = Date(timeIntervalSince1970: 1_795_763_520)

    private func input() throws -> SyncIndicatorState.Input {
        .init(lastUpload: now.addingTimeInterval(-1), status: try Fixture.decode(SyncStatus.self, "me_sync_current"),
              todayReloaded: true, now: now)
    }

    @Test func thirtyMinutesIsStale() throws {
        var facts = try input()
        // Move beyond the fixture's server timestamp so the local upload is the newer one.
        facts.now = try #require(facts.status?.lastSyncAt).addingTimeInterval(3600)
        facts.lastUpload = facts.now.addingTimeInterval(-1799)
        #expect(SyncIndicatorState.resolve(facts) == .upToDate)
        facts.lastUpload = facts.now.addingTimeInterval(-1800)
        #expect(SyncIndicatorState.resolve(facts) == .stale(.old))
    }

    @Test func offlineAndHTTPFailureHaveDifferentStates() throws {
        var facts = try input()
        facts.uploadFailure = .offline
        #expect(SyncIndicatorState.resolve(facts) == .stale(.offline))
        facts.uploadFailure = .server
        #expect(SyncIndicatorState.resolve(facts) == .error(.uploadFailed))
        facts.uploading = true
        #expect(SyncIndicatorState.resolve(facts) == .syncing)
        facts.uploading = false
        facts.uploadFailure = nil
        facts.scoringWaitStartedAt = now
        #expect(SyncIndicatorState.resolve(facts) == .syncing)
        facts.scoringWaitStartedAt = nil
        #expect(SyncIndicatorState.resolve(facts) == .upToDate)
    }

    @Test func missingPermissionAndSourceErrorTakePriorityOverScoring() throws {
        var facts = try input()
        facts.scoringWaitStartedAt = now
        facts.healthAccessMissing = true
        #expect(SyncIndicatorState.resolve(facts) == .error(.healthAccess))
        facts.healthAccessMissing = false
        facts.status = try Fixture.decode(SyncStatus.self, "me_sync_error")
        #expect(SyncIndicatorState.resolve(facts) == .error(.source))
    }

    @Test func pendingExpiresAtThreeMinutes() throws {
        var facts = try input()
        let status = try Fixture.decode(SyncStatus.self, "me_sync_pending")
        facts.status = status
        let pendingSince = try #require(status.scoresPendingSince)
        facts.now = pendingSince.addingTimeInterval(179)
        #expect(SyncIndicatorState.resolve(facts) == .syncing)
        facts.now = pendingSince.addingTimeInterval(180)
        #expect(SyncIndicatorState.resolve(facts) == .stale(.scoresPending))
    }

    @Test func onlyGreenAfterTodayReloaded() throws {
        var facts = try input()
        facts.todayReloaded = false
        #expect(SyncIndicatorState.resolve(facts) == .stale(.awaitingReload))
        facts.todayReloaded = true
        #expect(SyncIndicatorState.resolve(facts) == .upToDate)
    }

    @Test func legacyPendingUsesThirtyLocalDays() throws {
        let legacy = try Fixture.decode(SyncStatus.self, "me_sync_legacy")
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try #require(TimeZone(secondsFromGMT: 3600))
        let lastIncluded = try #require(local.date(from: DateComponents(year: 2026, month: 12, day: 26)))
        let firstExcluded = try #require(local.date(byAdding: .day, value: 1, to: lastIncluded))
        #expect(legacy.effectiveFreshness(now: lastIncluded, calendar: local) == .scoresPending)
        #expect(legacy.effectiveFreshness(now: firstExcluded, calendar: local) == .current)
    }
}
