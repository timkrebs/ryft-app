// Contract check (docs/CI.md → Contract): decodes every example extract.py pulled out
// of the platform's API.md with the app's own models and the app's decoder settings.
// Compiled together with Ryft/Networking/Models.swift by scripts/contract/run.sh.
import Foundation

/// The push example is the whole APNs payload; the app reads `userInfo["ryft"]`.
struct PushPayload: Decodable {
    let ryft: RyftPushInfo
}

/// The same settings as `APIClient.jsonDecoder` (that file pulls in URLSession and
/// Supabase, so it isn't compiled here).
let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .custom { decoder in
        let s = try decoder.singleValueContainer().decode(String.self)
        if let date = DateParsing.rfc3339(s) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
    }
    return d
}()

let types: [String: (Data) throws -> Void] = [
    "SyncResponse": { _ = try decoder.decode(SyncResponse.self, from: $0) },
    "User": { _ = try decoder.decode(User.self, from: $0) },
    "AccountDeleted": { _ = try decoder.decode(AccountDeleted.self, from: $0) },
    "RemoteConfig": { _ = try decoder.decode(RemoteConfig.self, from: $0) },
    "SyncStatus": { _ = try decoder.decode(SyncStatus.self, from: $0) },
    "ModelInfo": { _ = try decoder.decode(ModelInfo.self, from: $0) },
    "NotificationPrefs": { _ = try decoder.decode(NotificationPrefs.self, from: $0) },
    "PushPayload": { _ = try decoder.decode(PushPayload.self, from: $0) },
    "DailyScore": { _ = try decoder.decode(DailyScore.self, from: $0) },
    "SleepDetail": { _ = try decoder.decode(SleepDetail.self, from: $0) },
    "DayStrain": { _ = try decoder.decode(DayStrain.self, from: $0) },
    "SleepRange": { _ = try decoder.decode(SleepRange.self, from: $0) },
    "SleepPlan": { _ = try decoder.decode(SleepPlan.self, from: $0) },
    "WorkoutDetail": { _ = try decoder.decode(WorkoutDetail.self, from: $0) },
    "TrendSeries": { _ = try decoder.decode(TrendSeries.self, from: $0) },
    "[Insight]": { _ = try decoder.decode([Insight].self, from: $0) },
    "[Exercise]": { _ = try decoder.decode([Exercise].self, from: $0) },
    "ExerciseHistory": { _ = try decoder.decode(ExerciseHistory.self, from: $0) },
    "Plan": { _ = try decoder.decode(Plan.self, from: $0) },
    "TrainSession": { _ = try decoder.decode(TrainSession.self, from: $0) },
    "[SessionSummary]": { _ = try decoder.decode([SessionSummary].self, from: $0) },
    "[Behavior]": { _ = try decoder.decode([Behavior].self, from: $0) },
    "JournalDay": { _ = try decoder.decode(JournalDay.self, from: $0) },
    "BehaviorImpacts": { _ = try decoder.decode(BehaviorImpacts.self, from: $0) },
]

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let manifest = try String(contentsOf: dir.appendingPathComponent("manifest.tsv"), encoding: .utf8)
var failures = 0
for line in manifest.split(separator: "\n") {
    let cols = line.split(separator: "\t").map(String.init)
    let (type, name, action) = (cols[0], cols[1], cols[2])
    guard action == "decode" else {
        print("skip  \(type): \(cols[3])")
        continue
    }
    guard let decode = types[type] else {
        print("FAIL  \(type): no decoder registered in scripts/contract/main.swift")
        failures += 1
        continue
    }
    do {
        try decode(Data(contentsOf: dir.appendingPathComponent("\(name).json")))
        print("ok    \(type)")
    } catch {
        print("FAIL  \(type): \(error)")
        failures += 1
    }
}
exit(failures == 0 ? 0 : 1)
