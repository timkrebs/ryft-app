import Foundation

/// The Sleep need card and sheet and the body-setting editors in the states their drafts show (Nocturne, PR 6 C §4.11–§4.12,
/// c-18…c-20): a night that needed 8:18 (7:30 baseline, +0:20 strain, +0:28 debt), the same with a 0:25 nap credit, and
/// Alex Doe's account with the baseline set by hand (RYFT learned 7:52) and the heart rate estimated from 1990. Synthetic data.
enum MockSleepNeedStates {
    /// c-18: 7:30 + 0:20 + 0:28 = 8:18.
    static let need = SleepNeed(base: 450, strain: 20, debt: 28, napCredit: 0, total: 498)
    /// The same night with a nap the day before: 8:18 − 0:25 = 7:53.
    static let needWithNap = SleepNeed(base: 450, strain: 20, debt: 28, napCredit: 25, total: 473)

    /// The account as the drafts show it: the baseline 7:30 set by hand (RYFT learned 7:52), max HR 190 estimated from 1990.
    static var user: User {
        let base = MockData.user
        return User(id: base.id, name: base.name, email: base.email, provider: base.provider, tz: base.tz, maxHr: 190,
                    sleepBaseMin: 450, sleepBaseSource: .manual, sleepBaseLearnedMin: 472,
                    sleepBaseLearnedAt: base.sleepBaseLearnedAt, notifications: base.notifications, consent: base.consent,
                    birthYear: 1990, maxHrSource: .estimated, sources: base.sources)
    }

    /// The preview state with `user` (or, `account: false`, none: a first launch whose account hasn't loaded).
    @MainActor
    static func state(account: Bool = true, online: Bool = true) -> AppState {
        guard account else { return AppState(env: .preview(online: online)) }
        let state = AppState.preview(online: online)
        state.user = user
        return state
    }
}
