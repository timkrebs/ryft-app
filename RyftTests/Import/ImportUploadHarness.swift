import Auth
import Foundation
import SwiftData
@testable import Ryft

/// The import's uploader on the test clock: a real `AuthService` on `MockAuthClient` (its wipe works on the test
/// store), separate fake platforms for the account and for demo data, a Demo data switch of its own (never
/// `Settings.shared`), `train.import` on and the gate open unless a test says otherwise.
@MainActor
final class ImportUploadHarness {
    nonisolated static let a = UUID(uuidString: "0000000A-0000-4000-8000-00000000000A") ?? UUID()
    nonisolated static let b = UUID(uuidString: "0000000B-0000-4000-8000-00000000000B") ?? UUID()

    let clock = TestClock()
    let live = MockPlatformAPI(train: MockTrainSource())
    let demoAPI = MockPlatformAPI(train: MockTrainSource())
    let persistence = TrainStore(inMemory: true)
    let settings: Settings
    let client: MockAuthClient
    let auth: AuthService
    let flags: StaticFlags
    let connectivity: ConnectivityMonitor
    let env: AppEnvironment
    private(set) var uploader: TrainImportUploader
    /// What the gate answers (nil: open).
    var gate: UploadGate?

    init(signedInAs account: UUID? = ImportUploadHarness.a, demo: Bool = false, flag: Bool = true, online: Bool = true) {
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        settings = Settings(defaults: defaults)
        settings.demoMode = demo
        client = MockAuthClient(session: account.map { .preview(id: $0) })
        let persistence = persistence, clock = clock
        auth = AuthService(client: client, settings: settings, defaults: defaults,
                           wipeLocalData: { wipe in persistence.wipe(parkingActivitiesOf: wipe.parking, at: clock.now()) },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
        flags = StaticFlags([.trainImport: flag])
        connectivity = .preview(online: online)
        live.now = { clock.now() }
        demoAPI.now = { clock.now() }
        env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: live, demoAPI: demoAPI, auth: auth,
                             persistence: persistence, clock: clock, notifier: MockNotifier(), flags: flags,
                             connectivity: connectivity, defaults: defaults, demoOverride: nil)
        uploader = TrainImportUploader(env: env)
        uploader = make()
    }

    /// A new uploader on the same store: the app after a relaunch.
    @discardableResult
    func relaunch() -> TrainImportUploader {
        uploader = make()
        return uploader
    }

    private func make() -> TrainImportUploader {
        let made = TrainImportUploader(env: env)
        made.gate = { [weak self] _ in self?.gate }
        made.random = { $0.lowerBound }
        return made
    }

    var account: String { uploader.currentAccount ?? "" }

    func signIn(_ id: UUID) async {
        client.signInSession = .preview(id: id)
        _ = await auth.logIn(email: "tim@example.com", password: "0123456789")
    }

    func jobs() -> [PendingImport] { (try? persistence.context.fetch(FetchDescriptor<PendingImport>())) ?? [] }

    /// Requests that reached the account's platform.
    var requests: [MockTrainImportSource.Request] { live.trainImportSource.requests }

    @discardableResult
    func start(_ plan: ImportUploadPlan, account: String? = nil, duplicatesChecked: Bool = true) async -> Bool {
        await uploader.start(plan, account: account ?? self.account, source: .alphaProgression,
                             zone: ImportBuildFixture.berlin, duplicatesChecked: duplicatesChecked)
    }

    /// Started, and its first pass awaited.
    @discardableResult
    func run(_ plan: ImportUploadPlan, duplicatesChecked: Bool = true) async -> Bool {
        let started = await start(plan, duplicatesChecked: duplicatesChecked)
        await uploader.resume()
        return started
    }

    // MARK: plans

    nonisolated static let deadlift = ImportBuildFixture.exercise("Deadlift")

    /// `count` completed sessions a day apart from 1 Feb 2026, oldest first, each with one exercise of `sets` sets.
    static func sessions(_ count: Int, exercise: Exercise = deadlift, exercises perSession: Int = 1, sets: Int = 3,
                         from first: Int = 0) -> [TrainSession] {
        (first..<(first + count)).map { n in
            let start = Date(timeIntervalSince1970: 1_769_940_000 + Double(n) * 86_400)
            let rows = (0..<perSession).map { position in
                SessionExercise(id: UUID(), exerciseId: exercise.id, position: position, sets: (0..<sets).map { index in
                    let at = start.addingTimeInterval(Double(60 * (index + 1)))
                    return SessionSet(id: UUID(), setIndex: index, reps: 5, weightKg: 100, completedAt: at, updatedAt: at)
                })
            }
            return TrainSession(id: ImportBuildFixture.id(10_000 + n), title: "Pull", startedAt: start,
                                endedAt: start.addingTimeInterval(3_600), status: .completed, exercises: rows)
        }
    }

    static func plan(_ n: Int, exercise: Exercise = deadlift) -> Plan {
        let row = PlanExercise(id: ImportBuildFixture.id(30_000 + n), exercise: exercise, position: 0, sets: 3, repsMin: 5,
                               repsMax: 5, targetKind: .rpe, targetValue: 8, restSec: 180)
        return Plan(id: ImportBuildFixture.id(20_000 + n), name: "Plan \(n)", goal: .general, weeks: 6, daysPerWeek: 1,
                    description: "", progression: .linear, isBuiltin: false,
                    days: [PlanDay(id: ImportBuildFixture.id(40_000 + n), dayIndex: 0, name: "A", exercises: [row])])
    }

    static func custom(_ n: Int) -> Exercise {
        Exercise(id: ImportBuildFixture.id(50_000 + n), slug: "custom-\(n)", name: "Custom \(n)", kind: .machine,
                 primaryMuscles: [.quads], isCustom: true)
    }
}
