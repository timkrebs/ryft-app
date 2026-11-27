import Foundation
import Observation

@MainActor
@Observable
final class CheckinSheetModel: Identifiable {
    let id = UUID()
    let store: RecoveryCheckinStore
    let owner: RecoveryCheckinStore.Owner
    let wakeDay: String
    let canSkip: Bool
    private let timeZone: TimeZone
    private let original: RecoveryCheckin?
    private let initialBed: Int
    private let initialWake: Int

    var bed: Int
    var wake: Int
    var quality: Int?
    var freshness: Int?
    var soreness: Bool
    private(set) var saving = false
    private(set) var error: RecoveryWriteError?
    private(set) var consentNotice: String?

    init(store: RecoveryCheckinStore, status: RecoveryStatus, canSkip: Bool, timeZone: TimeZone = .current) {
        self.store = store
        owner = store.owner
        wakeDay = status.date
        self.canSkip = canSkip
        let checkin = status.checkin
        original = checkin
        // An edit is shown, composed and sent on the check-in's own clock (`SleepDialMath.clock`): editing in another
        // time zone never moves the times to this one's.
        self.timeZone = checkin.map {
            SleepDialMath.clock(ofCheckinOffset: $0.tzOffsetSec, wakeTime: $0.wakeTime, current: timeZone)
        } ?? timeZone
        if let checkin {
            let clock = self.timeZone
            initialBed = SleepDialMath.minutes(of: checkin.bedtime, timeZone: clock)
            initialWake = SleepDialMath.minutes(of: checkin.wakeTime, timeZone: clock)
        } else {
            initialBed = status.suggestedBedtime.flatMap(SleepDialMath.parse) ?? SleepDialMath.defaultBed
            initialWake = Self.prefilledWake(status.suggestedWakeTime.flatMap(SleepDialMath.parse) ?? SleepDialMath.defaultWake,
                                             wakeDay: status.date, now: store.now, timeZone: timeZone)
        }
        bed = initialBed
        wake = initialWake
        quality = checkin?.perceivedSleepQuality
        freshness = checkin?.perceivedFreshness
        soreness = checkin?.soreness ?? false
    }

    /// A suggested wake time still ahead of the clock (opened at 06:20, suggested 07:00) would open the sheet refused as
    /// "in the future": it starts at now instead, rounded down to the dial's step.
    static func prefilledWake(_ suggested: Int, wakeDay: String, now: Date, timeZone: TimeZone) -> Int {
        guard let wakeTime = SleepDialMath.compose(wakeDay: wakeDay, bed: suggested, wake: suggested, timeZone: timeZone)?.wakeTime,
              wakeTime.timeIntervalSince(now) > 5 * 60,
              SleepDialMath.pathDate(now, tzOffsetSec: timeZone.secondsFromGMT(for: now)) == wakeDay else { return suggested }
        let current = SleepDialMath.minutes(of: now, timeZone: timeZone)
        return current - current % SleepDialMath.step
    }

    private var times: (bedtime: Date, wakeTime: Date)? {
        // Editing the answers alone keeps both instants as stored.
        if let original, bed == initialBed, wake == initialWake {
            return (original.bedtime, original.wakeTime)
        }
        return SleepDialMath.compose(wakeDay: wakeDay, bed: bed, wake: wake, timeZone: timeZone)
    }

    var duration: Int {
        guard let times else { return SleepDialMath.duration(bed: bed, wake: wake) }
        return Int((times.wakeTime.timeIntervalSince(times.bedtime) / 60).rounded())
    }

    var validation: SleepDialMath.Validation? {
        guard let times else { return nil }
        return SleepDialMath.validate(bedtime: times.bedtime, wakeTime: times.wakeTime, now: store.now)
    }

    private var body: RecoveryCheckinPut? {
        guard let quality, let freshness, (1...10).contains(quality), (1...10).contains(freshness), let times else { return nil }
        let offset = SleepDialMath.tzOffset(for: times.wakeTime, timeZone: timeZone)
        guard SleepDialMath.pathDate(times.wakeTime, tzOffsetSec: offset) == wakeDay else { return nil }
        return RecoveryCheckinPut(bedtime: times.bedtime, wakeTime: times.wakeTime, tzOffsetSec: offset,
                                 perceivedSleepQuality: quality, perceivedFreshness: freshness, soreness: soreness)
    }

    var canSave: Bool {
        !saving && !store.isSending && consentNotice == nil && validation == nil && body != nil && store.owns(owner)
    }

    func opened() { store.opened(as: owner) }

    func skip() {
        guard canSkip, !saving, store.owns(owner) else { return }
        store.skip()
    }

    /// Returns true when the draft can close.
    func save() async -> Bool {
        guard canSave, let body else { return false }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if try await store.save(date: wakeDay, body: body, as: owner) == .consentRequired {
                consentNotice = String(localized: "RYFT needs your consent first.",
                                       comment: "Morning check-in saved locally while consent is required.")
            }
            return true
        } catch where error.isCancellation {
            return !store.owns(owner)
        } catch {
            self.error = error as? RecoveryWriteError ?? RecoveryWriteError(message: error.localizedDescription,
                                                                           details: error.diagnosticDetails)
            return false
        }
    }

    func clearError() { error = nil }

    static func qualityWord(_ value: Int) -> String {
        switch value {
        case ...2: return String(localized: "Very poorly", comment: "Morning check-in sleep quality 1–2.")
        case 3...4: return String(localized: "Poorly", comment: "Morning check-in sleep quality 3–4.")
        case 5...6: return String(localized: "Okay", comment: "Morning check-in sleep quality or freshness 5–6.")
        case 7...8: return String(localized: "Well", comment: "Morning check-in sleep quality 7–8.")
        default: return String(localized: "Very well", comment: "Morning check-in sleep quality 9–10.")
        }
    }

    static func freshnessWord(_ value: Int) -> String {
        switch value {
        case ...2: return String(localized: "Exhausted", comment: "Morning check-in freshness 1–2.")
        case 3...4: return String(localized: "Tired", comment: "Morning check-in freshness 3–4.")
        case 5...6: return String(localized: "Okay", comment: "Morning check-in sleep quality or freshness 5–6.")
        case 7...8: return String(localized: "Fresh", comment: "Morning check-in freshness 7–8.")
        default: return String(localized: "Fully fresh", comment: "Morning check-in freshness 9–10.")
        }
    }
}
