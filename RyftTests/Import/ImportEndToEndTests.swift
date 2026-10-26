import Foundation
import Testing
@testable import Ryft

/// A synthetic Alpha Progression workout export of any length (invented workouts, generic exercise names), newest
/// first as the app writes it. For the large-file test here and for performance-profiler's measurements
/// (signposts `read`, `parse`, `build`, `encode-job`, `encode-batch`, `upload-batch` in the `import` category).
enum ImportSyntheticExport {
    static let exercises = ["Deadlift · Barbell", "Goblet Squat · Kettlebell", "Hip Thrust · Barbell"]

    static func csv(workouts: Int) -> String {
        var lines: [String] = []
        lines.reserveCapacity(workouts * 14)
        let start = ImportTimeResolver.daysFromCivil(year: 2020, month: 1, day: 1)
        for n in (0..<workouts).reversed() {
            let (year, month, day) = civil(start + n)
            let hour = 6 + n % 12
            let date = "\(year)-\(pad(month))-\(pad(day)) \(hour > 12 ? hour - 12 : hour):\(pad(n % 60)) \(hour >= 12 ? "pm" : "am")"
            lines.append("\"Workout \(n % 7) · Standalone workout\";\"\(date)\";\"\(40 + n % 30) min\"")
            for (index, exercise) in exercises.enumerated() {
                lines.append("\"\(index + 1). \(exercise) · 8 reps\"")
                lines.append("#;KG;REPS")
                for set in 1...3 { lines.append("\(set);\(40 + (n + set) % 50);\(6 + set)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\r\n")
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    /// The civil date of a day number (H. Hinnant's `civil_from_days`).
    private static func civil(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

/// The data side end to end in demo mode (the fake platform): read, check, build, upload, and a re-import.
@Suite("Import end to end (demo)")
@MainActor
struct ImportEndToEndTests {
    @Test func theFixturesImportOnceAndAReimportCreatesNothing() async throws {
        let h = ImportUploadHarness(demo: true)
        let files = try [ImportFixture.file("ap-plans"), ImportFixture.file("ap-workouts")]
        let bundle = try await TrainImportReader.read(files)
        let decisions = ImportBuildFixture.decisions(account: h.account, enrol: 0)
        let query = ImportBuilder.query(for: bundle, decisions: decisions)
        let existing = await h.uploader.checkExisting(query)
        #expect(existing.checked)
        let build = try await ImportBuilder.build(bundle, decisions: decisions, existing: existing, now: ImportBuildFixture.now)
        let plan = build.uploadPlan(including: build.defaultIncluded)
        #expect(plan.plans.count == 1 && plan.sessions.count == 6 && plan.enrolPlanID != nil)
        #expect(await h.run(plan))
        let status = try #require(h.uploader.status)
        #expect(status.phase == .finished && status.sessions.done == 6 && status.plans.done == 1)
        #expect(status.enrolledPlanID == plan.enrolPlanID)
        #expect(h.demoAPI.trainImportSource.sessions.count == 6 && h.live.calls.isEmpty)
        // The demo's history lists them.
        let listed = try await h.demoAPI.sessions(from: .distantPast, to: .distantFuture).map(\.id)
        #expect(Set(plan.sessions.map(\.id)).isSubset(of: listed))

        // The same files again: everything is already there.
        let again = await h.uploader.checkExisting(query)
        let rebuilt = try await ImportBuilder.build(bundle, decisions: decisions, existing: again, now: ImportBuildFixture.now)
        let second = rebuilt.uploadPlan(including: rebuilt.defaultIncluded)
        #expect(second.sessions.isEmpty && second.plans.isEmpty && second.skipped.alreadyImported == 6)
        // A newer export with one more workout: exactly one is new.
        let newer = try await TrainImportReader.read([ImportFixture.file("ap-plans"), ImportFixture.file("ap-workouts-plus1")])
        let newerQuery = ImportBuilder.query(for: newer, decisions: decisions)
        let newerBuild = try await ImportBuilder.build(newer, decisions: decisions, existing: await h.uploader.checkExisting(newerQuery),
                                                       now: ImportBuildFixture.now)
        #expect(newerBuild.uploadPlan(including: newerBuild.defaultIncluded).sessions.count == 1)
    }

    /// A large export (1,200 workouts): read, built and uploaded in 24 requests, nothing lost.
    @Test func aLargeExportGoesUpInBatches() async throws {
        let workouts = 1_200
        let text = ImportSyntheticExport.csv(workouts: workouts)
        let bundle = try await TrainImportReader.read([ImportFile(name: "large.csv", data: Data(text.utf8))])
        #expect(bundle.sessions.count == workouts && bundle.warnings.isEmpty)
        let h = ImportUploadHarness(demo: true)
        let decisions = ImportBuildFixture.decisions(account: h.account, zone: TimeZone(identifier: "UTC") ?? .gmt)
        let build = try await ImportBuilder.build(bundle, decisions: decisions, existing: .unchecked, now: ImportBuildFixture.now)
        let plan = build.uploadPlan(including: build.defaultIncluded)
        #expect(plan.sessions.count == workouts)
        #expect(plan.sessions.flatMap(\.exercises).flatMap(\.sets).count == workouts * 9)
        #expect(await h.run(plan, duplicatesChecked: true))
        let requests = h.demoAPI.trainImportSource.requests
        #expect(requests.count == workouts / 50)
        #expect(Set(requests.flatMap(\.sessionIDs)).count == workouts)
        #expect(h.uploader.status?.phase == .finished)
    }
}
