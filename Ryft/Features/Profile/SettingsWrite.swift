import Foundation

/// How a settings page waits for a write it sends: the body-setting editors (`PATCH /v1/me`), Notifications
/// (`PATCH /v1/me/notifications`) and Journal's habits (`PATCH`, `POST`, `DELETE /v1/behaviors`). The same lost connection
/// reads the same on every page (C3 review 2, item 2; PR 6 C review S3):
/// - One attempt (`APIClient.singleAttempt`): the fail-fast session, no waiting for a network, no `429` or `503` retry
///   loop. A `429` comes back at once (`SettingsWriteFailure.busy`).
/// - An answer within `deadline`, or none: then the request is cancelled and the caller says it may not have saved
///   (`NoAnswer`, which `SettingsWriteFailure` judges `noAnswer`). The request's own limits are for uploads, not for a page
///   the user is looking at.
/// - The network going while the write is out is no answer at once: the request would only wait. Demo data answers on the
///   phone, with no network to lose.
/// The caller still guards offline before it sends (nothing leaves the phone), and its account (`AccountBinding`) before
/// and after.
enum SettingsWrite {
    /// How long a write waits for its answer before the page stops waiting.
    nonisolated static let deadline: Duration = .seconds(25)

    /// No answer within `deadline`, or the iPhone went offline while the write was out: it may have saved.
    struct NoAnswer: Error, Equatable {}

    /// `send`'s answer, as one attempt, within `deadline`. Throws `NoAnswer` when none came in time or the network went
    /// first (the request is cancelled then), `send`'s own failure, or `CancellationError` when the caller is cancelled.
    @MainActor
    static func answer<T: Sendable>(in env: AppEnvironment, _ send: @escaping @MainActor () async throws -> T) async throws -> T {
        let first = FirstOutcome<T>()
        let request = Task { @MainActor in
            do {
                first.finish(.success(try await APIClient.$singleAttempt.withValue(true) { try await send() }))
            } catch {
                first.finish(.failure(error))
            }
        }
        let timer = Task { @MainActor [clock = env.clock] in
            guard (try? await clock.sleep(for: Self.deadline)) != nil else { return }
            first.finish(.failure(NoAnswer()))
        }
        let offline = env.isDemo ? nil : ObservationWatch(read: { [env] in _ = env.connectivity.isOnline }, changed: { [env] in
            if !env.connectivity.isOnline { first.finish(.failure(NoAnswer())) }
        })
        defer {
            timer.cancel()
            withExtendedLifetime(offline) {}
        }
        do {
            return try await withTaskCancellationHandler {
                try await first.value()
            } onCancel: {
                request.cancel()
                Task { @MainActor in first.finish(.failure(CancellationError())) }
            }
        } catch let none as NoAnswer {
            request.cancel()
            throw none
        }
    }
}

/// The first of a write's outcomes (`SettingsWrite.answer`): its answer, its failure, or none in time. Later ones are
/// dropped.
@MainActor
private final class FirstOutcome<T: Sendable> {
    private var outcome: Result<T, Error>?
    private var waiting: CheckedContinuation<T, Error>?

    func finish(_ result: Result<T, Error>) {
        guard outcome == nil else { return }
        outcome = result
        waiting?.resume(with: result)
        waiting = nil
    }

    func value() async throws -> T {
        if let outcome { return try outcome.get() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
}
