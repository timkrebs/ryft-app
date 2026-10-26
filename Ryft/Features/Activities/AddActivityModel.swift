import Foundation
import Observation

/// Add activity and Edit activity (ui.md §3, design.md §7.3–§7.4): the form's values, their validation (pure:
/// `issues(…)`, `isTooFast(…)`), and the save through the store and the uploader. Edit follows the origin: a manual
/// activity changes every field; a recorded one its sport (same family), effort and notes; a merged one only its
/// effort and notes. The store enforces the same rules again.
@MainActor
@Observable
final class AddActivityModel: Identifiable {
    enum Mode: Equatable {
        case add
        case edit(UUID)
    }

    /// What keeps Save disabled, each with its sentence under its field (ui.md §3.5).
    enum Issue: Hashable, Sendable {
        case endInFuture, endBeforeStart, longerThanADay, startTooEarly, distanceInvalid, notesTooLong
    }

    /// Start up to this many days back (plan D2-1).
    nonisolated static let daysBack = 14
    nonisolated static let maxDuration: TimeInterval = 24 * 3_600
    nonisolated static let notesLimit = 500
    /// 0.01 to 1000 km (design.md §7.4).
    nonisolated static let distanceRange = 10.0...1_000_000.0
    /// Sports without a distance field (ui.md §3.1); "Other" keeps it, optional.
    nonisolated static let withoutDistance: Set<Sport> = [.strength, .yoga, .mobility, .hiit, .tennis, .padel, .football, .climbing]

    let id = UUID()
    let mode: Mode
    let origin: ActivityOrigin
    /// Times and distance came from a recording (or a merge): shown, not editable.
    let measured: Bool
    /// A merged activity: only its effort and notes change.
    let sportLocked: Bool
    @ObservationIgnored private let env: AppEnvironment
    /// The activity being edited, as shown (the platform's copy, or this iPhone's row).
    @ObservationIgnored private let original: SportActivity?

    var sport: Sport
    var start: Date
    var end: Date
    var distanceText: String
    var effort: Int?
    var notes: String {
        didSet { if notes.count > Self.notesLimit { notes = String(notes.prefix(Self.notesLimit)) } }
    }
    /// "Add here anyway" after the Strength suggestion (ui.md §3.4).
    var addsStrengthHere = false
    private(set) var isSaving = false

    /// Add activity on `day` (today: the last hour, ending now, but never before midnight; a past day: 12:00–13:00),
    /// the most recent sport.
    init(env: AppEnvironment, day: Date) {
        self.env = env
        mode = .add
        origin = .manual
        measured = false
        sportLocked = false
        original = nil
        let now = env.clock.now()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: day)
        if day >= today {
            let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
            // In the day's first minute the rounded end would be midnight itself: end now, so the window isn't empty.
            let end = minute > today ? minute : now
            self.end = end
            // Just after midnight the hour would start yesterday, and the activity land there.
            start = max(today, end.addingTimeInterval(-3_600))
        } else {
            start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            end = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day) ?? day.addingTimeInterval(3_600)
        }
        sport = ActivityPreferences(env: env).recentSports.first ?? .running
        distanceText = ""
        effort = nil
        notes = ""
    }

    /// Edit `activity`. `merged`: the platform merged it with a tracker's workout (only effort and notes).
    init(env: AppEnvironment, editing activity: SportActivity, merged: Bool) {
        self.env = env
        mode = .edit(activity.id)
        origin = activity.origin
        measured = activity.origin == .recorded || merged
        sportLocked = merged
        original = activity
        sport = activity.sport
        start = activity.start
        end = activity.end
        distanceText = ActivityFormat.input(fromMeters: activity.distanceM)
        effort = activity.perceivedEffort
        notes = activity.notes ?? ""
    }

    // MARK: what the form shows

    var title: String {
        // Their own keys: the sheet's title sits between Cancel and Save, so German needs shorter words than the
        // buttons that open it.
        mode == .add
            ? String(localized: "addActivity.title", defaultValue: "Add activity",
                     comment: "The Add activity sheet's title, between Cancel and Save: keep it short.")
            : String(localized: "editActivity.title", defaultValue: "Edit activity",
                     comment: "The edit sheet's title, between Cancel and Save: keep it short.")
    }

    var now: Date { env.clock.now() }

    /// The earliest start the pickers allow: 14 days back, or the activity's own day when it's older (an edit).
    var earliest: Date {
        let calendar = Calendar.current
        let limit = DayFormat.shift(calendar.startOfDay(for: now), days: -Self.daysBack)
        guard let original else { return limit }
        return min(limit, calendar.startOfDay(for: original.start))
    }

    var showsDistance: Bool { measured ? original?.distanceM != nil : !Self.withoutDistance.contains(sport) }
    /// The Strength suggestion (ui.md §3.4): adding, until "Add here anyway".
    var suggestsTrain: Bool { mode == .add && sport == .strength && !addsStrengthHere }
    /// Sports the picker offers: any; for a recorded activity only its family (the store refuses another).
    var sports: [Sport] {
        origin == .recorded ? Sport.allCases.filter { $0.family == (original?.sport ?? sport).family } : Sport.allCases
    }

    /// The picker's "Recent" section (`ActivityPreferences`).
    var recents: [Sport] { ActivityPreferences(env: env).recentSports }

    var distanceM: Double? { ActivityFormat.meters(fromInput: distanceText) }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var crossesMidnight: Bool { !Calendar.current.isDate(start, inSameDayAs: end) }

    var issues: [Issue] {
        Self.issues(start: start, end: end, now: now, earliest: earliest, distanceText: showsDistance && !measured ? distanceText : "",
                    notes: notes, checksTimes: !measured)
    }

    var isTooFast: Bool {
        guard showsDistance, !measured else { return false }
        return Self.isTooFast(sport: sport, distanceM: distanceM, duration: duration)
    }

    var canSave: Bool { issues.isEmpty && !isSaving }

    var draft: ActivityDraft {
        let distance = measured ? original?.distanceM : (showsDistance ? distanceM : nil)
        return ActivityDraft(sport: sport, start: measured ? original?.start ?? start : start,
                             end: measured ? original?.end ?? end : end, distanceM: distance,
                             perceivedEffort: effort, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: rules (pure)

    /// Everything that keeps Save disabled (ui.md §3.5, design.md §7.4). `checksTimes` is false when the times
    /// were measured (a recorded activity).
    nonisolated static func issues(start: Date, end: Date, now: Date, earliest: Date, distanceText: String, notes: String,
                                   checksTimes: Bool = true) -> [Issue] {
        var out: [Issue] = []
        if checksTimes {
            if end > now { out.append(.endInFuture) }
            if end <= start { out.append(.endBeforeStart) }
            if end.timeIntervalSince(start) > maxDuration { out.append(.longerThanADay) }
            if start < earliest { out.append(.startTooEarly) }
            let trimmed = distanceText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let meters = ActivityFormat.meters(fromInput: trimmed)
                if meters.map({ !distanceRange.contains($0) }) ?? true { out.append(.distanceInvalid) }
            }
        }
        if notes.count > notesLimit { out.append(.notesTooLong) }
        return out
    }

    /// Faster on average than the sport allows (its GPS speed gate, or a plain ceiling for the ones without GPS):
    /// a warning, Save stays enabled (ui.md §3.5).
    nonisolated static func isTooFast(sport: Sport, distanceM: Double?, duration: TimeInterval) -> Bool {
        guard let distanceM, distanceM > 0, duration > 0, let ceiling = speedCeiling(sport) else { return false }
        return distanceM / duration > ceiling
    }

    /// m/s.
    nonisolated static func speedCeiling(_ sport: Sport) -> Double? {
        if let gate = sport.maxSpeed { return gate }
        switch sport {
        case .indoorRunning: return 9
        case .indoorCycling: return 25
        case .rowing: return 6
        case .swimming: return 2.5
        default: return nil
        }
    }

    /// The sentence under a field.
    static func message(_ issue: Issue) -> String {
        switch issue {
        case .endInFuture: return String(localized: "End can't be in the future.")
        case .endBeforeStart: return String(localized: "End must be after start.")
        case .longerThanADay: return String(localized: "An activity can be at most 24 hours.")
        case .startTooEarly:
            return String(localized: "An activity can start at most 14 days ago.",
                          comment: "Add activity: the start is further back than the app allows.")
        case .distanceInvalid:
            return String(localized: "Enter a distance above 0.", comment: "Add activity: the distance can't be read or is out of range.")
        case .notesTooLong: return String(localized: "Notes can be 500 characters.")
        }
    }

    // MARK: save

    /// Writes on this iPhone first, then the uploader takes it (ui.md §3.6: "Saved" is a local fact). False when
    /// nothing could be written (signed out, a read-only activity).
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        switch mode {
        case .add:
            guard let saved = env.activities.save(manual: draft) else { return false }
            env.uploader.saved(saved.id)
            ActivityPreferences(env: env).noteUsed(sport)
        case .edit(let id):
            // One of the platform's activities this iPhone has no row for becomes the account's row first.
            if env.activities.snapshot(id: id) == nil {
                guard let original, env.activities.adopt(original) != nil else { return false }
            }
            guard env.activities.update(id, draft) != nil else { return false }
            env.uploader.saved(id)
        }
        return true
    }
}
