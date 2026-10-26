import Foundation
import Observation

/// Add sleep (ui.md §3.7, design.md §7.4): a night the user types in when no tracker recorded it, for a wake day in
/// the last 14 days. Stored on this iPhone ("added by you") and uploaded; the tracker's night wins if it arrives.
@MainActor
@Observable
final class AddSleepModel: Identifiable {
    enum Issue: Hashable, Sendable {
        case wakeInFuture, wakeBeforeBed, length, tooFarBack
        /// The wake day already has a night the user added on this iPhone (not the one being edited).
        case nightAdded
        /// The platform already has a night for the wake day: a tracker's, or one added on another device (until
        /// R11 gives nights an origin).
        case nightRecorded
        /// The wake day's detail isn't on this iPhone, so its night can't be checked (offline): Save waits.
        case nightUnchecked
    }

    /// What a wake day already has (`MyDayViewModel.night(on:)`: the cached day and this iPhone's nights).
    enum Night: Equatable, Sendable {
        case none
        /// A night the user added, saved on this iPhone.
        case added
        /// The platform's night: a tracker's, or one added on another device.
        case recorded
        /// The day's detail isn't cached: `checkDay` loads it.
        case unknown
    }

    nonisolated static let minLength: TimeInterval = 3_600
    nonisolated static let maxLength: TimeInterval = 16 * 3_600
    /// Wake days up to this many days back (plan D2-1).
    nonisolated static let daysBack = 14

    let id = UUID()
    @ObservationIgnored private let env: AppEnvironment
    /// What a wake day (`yyyy-MM-dd`) already has.
    @ObservationIgnored private let night: (String) -> Night
    /// Loads a wake day's detail when `night` says `unknown` (the sheet asks as the wake day changes).
    @ObservationIgnored private let checkDay: (String) async -> Void
    /// The night being edited, by its wake day; nil when adding.
    let editedDay: String?
    /// The night being edited, as it was.
    private let original: ManualSleepSnapshot?
    /// The platform already has a night for the day (S3): no form, the fact instead.
    let trackerHasNight: Bool

    var bed: Date
    var wake: Date
    private(set) var isSaving = false

    /// The night that ends on `day`: to bed at 23:00 the evening before, up at 07:00 (no later than now). `night`
    /// says what a wake day already has, so a night isn't added twice or over a tracker's.
    init(env: AppEnvironment, day: Date, night: @escaping (String) -> Night = { _ in .none },
         checkDay: @escaping (String) async -> Void = { _ in }) {
        self.env = env
        self.night = night
        self.checkDay = checkDay
        editedDay = nil
        original = nil
        trackerHasNight = night(DayFormat.string(from: day)) == .recorded
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        let evening = DayFormat.shift(day, days: -1)
        bed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: evening) ?? evening
        let seven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
        let now = env.clock.now()
        wake = min(seven, Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60))
    }

    init(env: AppEnvironment, editing edited: ManualSleepSnapshot, night: @escaping (String) -> Night = { _ in .none },
         checkDay: @escaping (String) async -> Void = { _ in }) {
        self.env = env
        self.night = night
        self.checkDay = checkDay
        editedDay = edited.day
        original = edited
        trackerHasNight = false
        bed = edited.bed
        wake = edited.wake
    }

    var isEditing: Bool { editedDay != nil }
    var title: String {
        isEditing ? String(localized: "Edit sleep", comment: "The sleep sheet's title when editing a night the user added.")
            : String(localized: "Add sleep")
    }

    var now: Date { env.clock.now() }
    /// The earliest wake the picker allows: 14 days back, or the night's own day when it's older (an edit).
    var earliestWake: Date {
        let calendar = Calendar.current
        let limit = DayFormat.shift(calendar.startOfDay(for: now), days: -Self.daysBack)
        guard let original else { return limit }
        return min(limit, calendar.startOfDay(for: original.wake))
    }
    var duration: TimeInterval { max(0, wake.timeIntervalSince(bed)) }
    /// The wake day the night is saved under.
    var targetDay: String { DayFormat.string(from: wake) }
    var issues: [Issue] {
        // The night being edited doesn't count against its own day.
        let existing = targetDay == editedDay ? Night.none : night(targetDay)
        return Self.issues(bed: bed, wake: wake, now: now, earliestWake: earliestWake, existing: existing)
    }
    var canSave: Bool { issues.isEmpty && !isSaving && !trackerHasNight }

    /// Loads the wake day's detail when it isn't on this iPhone, so its night can be checked (the sheet runs this
    /// whenever the wake day changes). Offline it stays unchecked, and Save waits.
    func checkTargetDay() async {
        let day = targetDay
        guard day != editedDay, night(day) == .unknown else { return }
        await checkDay(day)
    }

    /// The rules (ui.md S2): wake after bed, 1 to 16 hours (elapsed, whatever the clocks did), wake not in the
    /// future, within the last 14 days, and a wake day without a night already (`existing`).
    nonisolated static func issues(bed: Date, wake: Date, now: Date, earliestWake: Date, existing: Night = .none) -> [Issue] {
        var out: [Issue] = []
        if wake > now { out.append(.wakeInFuture) }
        if wake <= bed {
            out.append(.wakeBeforeBed)
        } else if !(minLength...maxLength).contains(wake.timeIntervalSince(bed)) {
            out.append(.length)
        }
        if wake < earliestWake { out.append(.tooFarBack) }
        switch existing {
        case .none: break
        case .added: out.append(.nightAdded)
        case .recorded: out.append(.nightRecorded)
        case .unknown: out.append(.nightUnchecked)
        }
        return out
    }

    static func message(_ issue: Issue) -> String {
        switch issue {
        case .wakeInFuture: return String(localized: "Waking up can't be in the future.", comment: "Add sleep: the wake time is later than now.")
        case .wakeBeforeBed: return String(localized: "Waking up must be after going to bed.", comment: "Add sleep: wake before bed.")
        case .length: return String(localized: "Sleep can be 1 to 16 hours.")
        case .tooFarBack: return String(localized: "You can add sleep for the last 14 days.", comment: "Add sleep: the night is too far back.")
        case .nightAdded:
            return String(localized: "You already added a night for that day.",
                          comment: "Add or edit sleep: the wake day already has a night the user added.")
        case .nightRecorded:
            return String(localized: "A night is already recorded for that day.",
                          comment: "Add or edit sleep: the platform already has a night for the wake day (a tracker's or another device's).")
        case .nightUnchecked:
            return String(localized: "Couldn't check that day's sleep yet.",
                          comment: "Add or edit sleep: the wake day isn't loaded (offline), so Save waits.")
        }
    }

    /// Writes the night on this iPhone (by its wake day), then the uploader takes it. An edit that moved the night
    /// to another wake day deletes the old one, only once the new one is saved: a failed save loses nothing.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        let day = targetDay
        guard env.activities.saveSleep(day: day, bed: bed, wake: wake) != nil else { return false }
        if let old = editedDay, old != day { env.uploader.sleepDeleted(day: old) }
        env.uploader.sleepSaved(day: day)
        return true
    }

    /// Delete this entry (after the confirmation).
    func delete() {
        guard let editedDay else { return }
        env.uploader.sleepDeleted(day: editedDay)
    }
}
