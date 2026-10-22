import Foundation
import SwiftData

// The platform's read models, cached in SwiftData (the container Train already
// uses). Each row keeps the wire value as JSON (encoded with the app's own coder)
// plus when it was fetched; the Repository decides freshness from that. Only the
// Repository writes here; views and view models read through it.

/// One local day: its `DailyScore` (from `GET /v1/days`) and, once opened, its
/// `DayDetail` (`GET /v1/days/{day}`), each with its fetch time.
@Model
final class CachedDay {
    @Attribute(.unique) var day: String
    /// Start of the local day, for range queries.
    var date: Date
    var scoreData: Data?
    var scoreFetchedAt: Date?
    var detailData: Data?
    var detailFetchedAt: Date?

    init(day: String, date: Date) {
        self.day = day
        self.date = date
    }
}

/// `GET /v1/trends?metric&range`, keyed "metric-range".
@Model
final class CachedTrend {
    @Attribute(.unique) var key: String
    var data: Data
    var fetchedAt: Date

    init(key: String, data: Data, fetchedAt: Date) {
        self.key = key
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// One card from `GET /v1/insights`, in the platform's order.
@Model
final class CachedInsight {
    @Attribute(.unique) var id: String
    var position: Int
    var data: Data
    var fetchedAt: Date

    init(id: String, position: Int, data: Data, fetchedAt: Date) {
        self.id = id
        self.position = position
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// `GET /v1/me`: the signed-in user (one row).
@Model
final class CachedUser {
    @Attribute(.unique) var id: UUID
    var data: Data
    var fetchedAt: Date

    init(id: UUID, data: Data, fetchedAt: Date) {
        self.id = id
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// `GET /v1/sleep?range=week|month`.
@Model
final class CachedSleepRange {
    @Attribute(.unique) var kind: String
    var data: Data
    var fetchedAt: Date

    init(kind: String, data: Data, fetchedAt: Date) {
        self.kind = kind
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// `GET /v1/workouts/{id}`: the heart-rate curve and zones.
@Model
final class CachedWorkout {
    @Attribute(.unique) var id: UUID
    var data: Data
    var fetchedAt: Date

    init(id: UUID, data: Data, fetchedAt: Date) {
        self.id = id
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// Any other wire document worth keeping offline, keyed by name: Train's plans
/// overview, today's prescription, exercise histories, the sessions list.
@Model
final class CachedDocument {
    @Attribute(.unique) var key: String
    var data: Data
    var fetchedAt: Date

    init(key: String, data: Data, fetchedAt: Date) {
        self.key = key
        self.data = data
        self.fetchedAt = fetchedAt
    }
}

/// Encoding for cached wire values: the API's own coder, so a row decodes like a response.
enum WireCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? { try? APIClient.jsonEncoder.encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? APIClient.jsonDecoder.decode(T.self, from: $0) }
    }
}

extension TrainStore {
    /// The read-model tables (wiped on sign-out with the rest of the store).
    static let readModels: [any PersistentModel.Type] = [CachedDay.self, CachedTrend.self, CachedInsight.self,
                                                          CachedUser.self, CachedSleepRange.self, CachedWorkout.self,
                                                          CachedDocument.self]

    // MARK: documents

    func document<T: Decodable>(_ type: T.Type, key: String) -> T? {
        var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return WireCoding.decode(T.self, (try? context.fetch(d))?.first?.data)
    }

    func saveDocument<T: Encodable>(_ value: T, key: String, at date: Date = .now) {
        guard let data = WireCoding.encode(value) else { return }
        saveDocumentData(data, key: key, at: date)
    }

    func saveDocumentData(_ data: Data, key: String, at date: Date = .now) {
        var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        if let row = (try? context.fetch(d))?.first {
            row.data = data
            row.fetchedAt = date
        } else {
            context.insert(CachedDocument(key: key, data: data, fetchedAt: date))
        }
        save()
    }

    func removeDocument(key: String) {
        try? context.delete(model: CachedDocument.self, where: #Predicate { $0.key == key })
        save()
    }

    /// When the document under `key` was saved; `nil` without one.
    func documentFetchedAt(key: String) -> Date? {
        var d = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.fetchedAt
    }
}
