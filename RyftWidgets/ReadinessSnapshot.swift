import Foundation

/// What the readiness widget shows, written into the App Group container by the app.
/// Keep identical to `ReadinessSnapshot` in `Ryft/Persistence/Repository.swift` (its Codable
/// shape): the app encodes this JSON, the widget decodes it.
struct ReadinessSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        /// Today's readiness.
        case score
        /// The night is being scored.
        case pending
        /// No night has arrived for today.
        case waitingForSleep
        /// Fewer than 7 nights behind the baselines.
        case calibrating
    }

    /// The day it's about, `yyyy-MM-dd`; another day on the widget is "waiting for sleep".
    var day: String
    var kind: Kind
    var readiness: Int?
    /// The latest readiness before `day`, dimmed while the night isn't scored.
    var previousReadiness: Int?
    /// While calibrating.
    var baselineNights: Int?
    var updatedAt: Date
    /// Tonight's bedtime (Bedtime & wake): "Bed by 22:41" in the evening.
    var bedtime: Date?

    static let appGroup = "group.dev.timkrebs.ryft"
    static let widgetKind = "ReadinessWidget"
    static let baselineNightsRequired = 7

    static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("readiness.json")
    }

    /// What the app last wrote; `nil` without one (or without the App Group).
    static func load(from file: URL? = sharedFile) -> ReadinessSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReadinessSnapshot.self, from: data)
    }

    /// As of `date`: a snapshot of an earlier day is no score for today. Its readiness
    /// becomes the dimmed one, and the night is awaited.
    func asOf(_ date: Date) -> ReadinessSnapshot {
        guard day != Self.dayString(date) else { return self }
        return ReadinessSnapshot(day: Self.dayString(date), kind: .waitingForSleep, readiness: nil,
                                 previousReadiness: readiness ?? previousReadiness, baselineNights: nil,
                                 updatedAt: updatedAt, bedtime: nil)
    }

    /// "Bed by 22:41" from 17:00 the evening before until bedtime (00:30 too).
    func bedtimeShown(at date: Date, calendar: Calendar = .current) -> Date? {
        guard let bedtime, bedtime > date,
              let evening = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: bedtime.addingTimeInterval(-12 * 3_600)),
              date >= evening else { return nil }
        return bedtime
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
