// Wire types. Mirror backend/internal/model/model.go exactly — the JSON keys
// are snake_case there, so every struct here uses explicit CodingKeys or the
// shared decoder's .convertFromSnakeCase strategy (see APIClient.jsonDecoder).
import Foundation

enum SampleType: String, Codable, CaseIterable {
    case heartRate = "heart_rate"
    case hrvSDNN = "hrv_sdnn"
    case restingHR = "resting_hr"
    case respiratoryRate = "respiratory_rate"
    case spo2 = "spo2"
    case vo2max = "vo2max"
    case activeEnergy = "active_energy"
    case steps = "steps"
}

enum SleepStage: String, Codable {
    case inBed = "inbed", asleep, core, deep, rem, awake
}

struct Sample: Codable {
    let type: SampleType
    let start: Date
    let end: Date
    let value: Double
    let unit: String
    let source: String
}

struct SleepSegment: Codable {
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: String
}

struct Workout: Codable, Identifiable {
    let id: UUID
    let activity: String
    let start: Date
    let end: Date
    let avgHr: Double?
    let maxHr: Double?
    let energyKcal: Double?
    let distanceM: Double?
    let source: String
    var strain: Double?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SyncRequest: Codable {
    let deviceId: UUID
    let deviceName: String
    let samples: [Sample]
    let sleep: [SleepSegment]
    let workouts: [Workout]
}

struct SyncResponse: Codable {
    let samples: Int
    let sleep: Int
    let workouts: Int
    let daysTouched: [String]
}

struct DailyScore: Codable, Identifiable {
    let day: String // YYYY-MM-DD
    let recovery: Int?
    let strain: Double?
    let sleepPerformance: Int?
    let sleepNeedMin: Int?
    let sleepActualMin: Int?
    let sleepDebtMin: Int?
    let hrvMs: Double?
    let rhr: Double?
    let respRate: Double?
    let spo2: Double?
    let calibrating: Bool
    let computedAt: Date

    var id: String { day }

    var date: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: day) ?? .now
    }

    static func empty(day: String) -> DailyScore {
        DailyScore(day: day, recovery: nil, strain: nil, sleepPerformance: nil, sleepNeedMin: nil,
                   sleepActualMin: nil, sleepDebtMin: nil, hrvMs: nil, rhr: nil, respRate: nil,
                   spo2: nil, calibrating: true, computedAt: .now)
    }
}

struct DayDetail: Codable {
    let score: DailyScore
    let workouts: [Workout]
}

struct User: Codable {
    let id: UUID
    let name: String
    let tz: String
    let maxHr: Int
    let sleepBaseMin: Int
}

struct UserPatch: Codable {
    var tz: String? = nil
    var maxHr: Int? = nil
    var sleepBaseMin: Int? = nil
}

struct RecomputeRequest: Codable {
    let from: String
    let to: String
}
