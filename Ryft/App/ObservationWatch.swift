import Observation

/// Calls `changed` after anything `read` reads changes, and keeps watching (`withObservationTracking` fires once per
/// registration). For a side effect whose inputs live in other `@Observable` stores, e.g. the readiness widget's
/// calibration, which decides from the tracker choice and `devices.setup` as well as the cached scores (F3 review):
/// neither of those writes passes through the `Repository`.
@MainActor
final class ObservationWatch {
    private let read: @MainActor () -> Void
    private let changed: @MainActor () -> Void

    init(read: @escaping @MainActor () -> Void, changed: @escaping @MainActor () -> Void) {
        self.read = read
        self.changed = changed
        track()
    }

    private func track() {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            // `onChange` runs before the new value is stored: act (and register again) on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.changed()
                self.track()
            }
        }
    }
}
