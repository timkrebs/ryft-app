import Foundation
import Observation

/// The rating editor shared by workout detail and the optional Train summary row.
@MainActor
@Observable
final class SessionRPEModel {
    private let env: AppEnvironment
    private let owner: AccountBinding
    private let apiStatus: APIStatus
    private let repository: Repository?
    private let accountGeneration: Int?
    let workoutID: UUID
    private var unavailable = false
    private var hasWritten = false
    private(set) var rating: Double?
    private(set) var hasHeartRate: Bool
    private(set) var saving = false
    private(set) var error: RecoveryWriteError?

    init(env: AppEnvironment, workoutID: UUID, workout: Workout? = nil, repository: Repository? = nil,
         apiStatus: APIStatus? = nil) {
        self.env = env
        owner = AccountBinding(env)
        self.workoutID = workoutID
        self.repository = repository
        accountGeneration = repository?.accountGeneration
        self.apiStatus = apiStatus ?? .shared
        rating = workout?.sessionRpe
        hasHeartRate = workout?.avgHr != nil
    }

    private var ownsWorkout: Bool {
        owner.isCurrent(in: env) && repository?.accountGeneration == accountGeneration
    }

    var isVisible: Bool { !unavailable && ownsWorkout && env.recoveryCheckinEnabled }
    var showsPrompt: Bool { isVisible && !hasHeartRate && rating == nil }
    private var online: Bool { env.isDemo || env.connectivity.isOnline }

    func seed(from workout: Workout) {
        guard workout.id == workoutID, ownsWorkout else { return }
        hasHeartRate = workout.avgHr != nil
        if !hasWritten { rating = workout.sessionRpe }
    }

    func save(_ value: Int) async {
        guard (1...10).contains(value), rating != Double(value) else { return }
        await write(Double(value))
    }

    func clear() async {
        guard rating != nil else { return }
        await write(nil)
    }

    private func write(_ value: Double?) async {
        guard isVisible, !saving else { return }
        error = nil
        guard online else {
            error = Self.offlineError()
            return
        }

        let api = env.api
        saving = true
        defer { saving = false }
        do {
            let answer: Workout? = try await SettingsWrite.answer(in: env) {
                guard self.isVisible else { throw CancellationError() }
                guard self.online else { throw SettingsWrite.NoAnswer() }
                return try await APIClient.$recoveryRequestAllowed.withValue({ self.isVisible }) { () async throws -> Workout? in
                    if let value { return try await api.putWorkoutRPE(id: self.workoutID, WorkoutRPEPut(sessionRpe: value)) }
                    do {
                        try await api.deleteWorkoutRPE(id: self.workoutID)
                    } catch let error as APIError where error.status == 404 {
                        // A workout that no longer exists has no rating to clear.
                    }
                    return nil
                }
            }
            guard ownsWorkout else { return }
            hasWritten = true
            rating = answer?.sessionRpe
            repository?.storeWorkoutRating(id: workoutID, value: rating, load: answer?.sessionRpeLoad)
            if value != nil, isVisible { env.analytics.track(.featureUsed(.sessionRpeSaved)) }
        } catch {
            guard ownsWorkout, !error.isCancellation else { return }
            if (error as? APIError)?.status == 404 {
                unavailable = true
            } else if let gate = error.gate {
                if !(api is APIClient) { apiStatus.observe([gate], enforced: true) }
            } else {
                self.error = message(for: error)
            }
        }
    }

    private func message(for error: Error) -> RecoveryWriteError {
        if (error as? APIError)?.isFieldError == true {
            return .field(error, fallback: String(localized: "Choose a rating from 1 to 10 and try again.",
                                                  comment: "Workout effort: the server rejected a rating."))
        }
        let underlying: Error
        if case .transport(let cause)? = error as? APIError { underlying = cause } else { underlying = error }
        if !online || (underlying as? URLError)?.code == .notConnectedToInternet
            || (underlying as? URLError)?.code == .networkConnectionLost {
            return Self.offlineError()
        }
        if error is SettingsWrite.NoAnswer {
            return RecoveryWriteError(message: String(localized: "RYFT didn't answer in time. Try again.",
                                                       comment: "The workout effort write did not receive an answer."),
                                      details: nil)
        }
        return RecoveryWriteError(message: error.localizedDescription, details: error.diagnosticDetails)
    }

    private static func offlineError() -> RecoveryWriteError {
        RecoveryWriteError(message: String(localized: "You're offline, so this wasn't saved. Try again when you're back online."),
                           details: nil)
    }
}
