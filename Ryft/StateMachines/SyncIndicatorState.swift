import Foundation

enum SyncIndicatorState: Equatable, Sendable {
    case syncing, upToDate, stale(StaleReason), error(ErrorReason)

    enum StaleReason: Equatable, Sendable {
        case old, neverSynced, offline, scoresPending, awaitingReload
    }

    enum ErrorReason: Equatable, Sendable {
        case uploadFailed, healthAccess, source
    }

    enum UploadFailure: Equatable, Sendable {
        case server, offline
    }

    static let freshnessLimit: TimeInterval = 30 * 60
    static let scoringLimit: TimeInterval = 3 * 60
    static let foregroundInterval: TimeInterval = 5 * 60
    static let minimumPollInterval: TimeInterval = 10

    struct Input: Sendable {
        var uploading = false
        var lastUpload: Date?
        var uploadFailure: UploadFailure?
        var healthAccessMissing = false
        var status: SyncStatus?
        var scoringWaitStartedAt: Date?
        var todayReloaded = false
        var online = true
        var now: Date
        var calendar: Calendar = .current

        var lastSync: Date? { [lastUpload, status?.lastSyncAt].compactMap { $0 }.max() }
    }

    static func resolve(_ input: Input) -> Self {
        if input.uploading { return .syncing }
        if input.uploadFailure == .server { return .error(.uploadFailed) }
        if input.healthAccessMissing { return .error(.healthAccess) }
        if input.status?.sources?.contains(where: { $0.status == .error }) == true { return .error(.source) }

        let freshness = input.status?.effectiveFreshness(now: input.now, calendar: input.calendar)
        let serverPendingSince = freshness == .scoresPending ? input.status?.scoresPendingSince : nil
        if [input.scoringWaitStartedAt, serverPendingSince].compactMap({ $0 }).contains(where: {
            input.now.timeIntervalSince($0) < scoringLimit
        }) { return .syncing }
        if input.uploadFailure == .offline || !input.online { return .stale(.offline) }
        if freshness == .scoresPending || input.scoringWaitStartedAt != nil { return .stale(.scoresPending) }
        guard let lastSync = input.lastSync else { return .stale(.neverSynced) }
        guard input.now.timeIntervalSince(lastSync) < freshnessLimit else { return .stale(.old) }
        return freshness == .current && input.todayReloaded ? .upToDate : .stale(.awaitingReload)
    }
}
