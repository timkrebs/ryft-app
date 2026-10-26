import Foundation
import Observation

/// Add sleep (ui.md §3.7, design.md §7.4): a night the user types in when no tracker recorded it, for a wake day in
/// the last 14 days. Stored on this iPhone ("added by you") and uploaded; the tracker's night wins if it arrives.
@MainActor
@Observable
final class AddSleepModel: Identifiable {
    enum Issue: Hashable, Sendable {
        case wakeInFuture, wakeBeforeBed, length, tooFarBack
    }

    nonisolated static let minLength: TimeInterval = 3_600
    nonisolated static let maxLength: TimeInterval = 16 * 3_600
    /// Wake days up to this many days back (plan D2-1).
    nonisolated static let daysBack = 14

    let id = UUID()
    @ObservationIgnored private let env: AppEnvironment
    /// The night being edited, by its wake day; nil when adding.
    let editedDay: String?
    /// The platform already has a night for the day (S3): no form, the fact instead.
    let trackerHasNight: Bool

    var bed: Date
    var wake: Date
    private(set) var isSaving = false

    /// The night that ends on `day`: to bed at 23:00 the evening before, up at 07:00 (no later than now).
    init(env: AppEnvironment, day: Date, trackerHasNight: Bool = false) {
        self.env = env
        editedDay = nil
        self.trackerHasNight = trackerHasNight
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        let evening = DayFormat.shift(day, days: -1)
        bed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: evening) ?? evening
        let seven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
        let now = env.clock.now()
        wake = min(seven, Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60))
    }

    init(env: AppEnvironment, editing night: ManualSleepSnapshot) {
        self.env = env
        editedDay = night.day
        trackerHasNight = false
        bed = night.bed
        wake = night.wake
    }

    var isEditing: Bool { editedDay != nil }
    var title: String {
        isEditing ? String(localized: "Edit sleep", comment: "The sleep sheet's title when editing a night the user added.")
            : String(localized: "Add sleep")
    }

    var now: Date { env.clock.now() }
    /// The earliest wake the picker allows: 14 days back.
    var earliestWake: Date { DayFormat.shift(Calendar.current.startOfDay(for: now), days: -Self.daysBack) }
    var duration: TimeInterval { max(0, wake.timeIntervalSince(bed)) }
    var issues: [Issue] { Self.issues(bed: bed, wake: wake, now: now, earliestWake: earliestWake) }
    var canSave: Bool { issues.isEmpty && !isSaving && !trackerHasNight }

    /// The rules (ui.md S2): wake after bed, 1 to 16 hours, wake not in the future, within the last 14 days.
    nonisolated static func issues(bed: Date, wake: Date, now: Date, earliestWake: Date) -> [Issue] {
        var out: [Issue] = []
        if wake > now { out.append(.wakeInFuture) }
        if wake <= bed {
            out.append(.wakeBeforeBed)
        } else if !(minLength...maxLength).contains(wake.timeIntervalSince(bed)) {
            out.append(.length)
        }
        if wake < earliestWake { out.append(.tooFarBack) }
        return out
    }

    static func message(_ issue: Issue) -> String {
        switch issue {
        case .wakeInFuture: return String(localized: "Waking up can't be in the future.", comment: "Add sleep: the wake time is later than now.")
        case .wakeBeforeBed: return String(localized: "Waking up must be after going to bed.", comment: "Add sleep: wake before bed.")
        case .length: return String(localized: "Sleep can be 1 to 16 hours.")
        case .tooFarBack: return String(localized: "You can add sleep for the last 14 days.", comment: "Add sleep: the night is too far back.")
        }
    }

    /// Writes the night on this iPhone (by its wake day), then the uploader takes it. An edit that moved the night
    /// to another wake day deletes the old one.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        let day = DayFormat.string(from: wake)
        if let old = editedDay, old != day { env.uploader.sleepDeleted(day: old) }
        guard env.activities.saveSleep(day: day, bed: bed, wake: wake) != nil else { return false }
        env.uploader.sleepSaved(day: day)
        return true
    }

    /// Delete this entry (after the confirmation).
    func delete() {
        guard let editedDay else { return }
        env.uploader.sleepDeleted(day: editedDay)
    }
}
