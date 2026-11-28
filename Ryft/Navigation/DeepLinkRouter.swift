import Foundation
import Observation

/// Opens an `AppRoute`: selects the tab and tells that tab's view model what to
/// show. Universal links, `ryft://` URLs and notification taps all come here.
/// A link that needs an account waits in `pending` until someone is signed in.
@MainActor
@Observable
final class DeepLinkRouter {
    private let state: AppState
    private let sleep: SleepViewModel
    private let strain: StrainViewModel
    private let insights: InsightsViewModel
    private let onboarding: OnboardingCoordinator?
    private(set) var pending: AppRoute?
    /// Today's target: the journal sheet on this day (`/journal/<day>`, the journal reminder's tap). Today opens it and
    /// sets it back to nil (`journalOpened()`).
    private(set) var requestedJournalDay: String?
    /// The Profile sheet (`app.structure_v2`) is on screen, from its appearance to its `onDismiss`.
    @ObservationIgnored private var profileIsPresented = false
    /// A link that arrived over the Profile sheet: routed once it has gone (Today's journal sheet can't open under it).
    @ObservationIgnored private var afterProfileDismissal: AppRoute?
    /// Something is over the Profile sheet that a link mustn't take away (a gate's sheet, the import): the sheet stays
    /// and the link waits for the person's Done. `ScreenModels` connects it.
    @ObservationIgnored var holdsProfile: @MainActor () -> Bool = { false }

    init(state: AppState, sleep: SleepViewModel, strain: StrainViewModel, insights: InsightsViewModel,
         onboarding: OnboardingCoordinator? = nil) {
        self.state = state
        self.sleep = sleep
        self.strain = strain
        self.insights = insights
        self.onboarding = onboarding
        // A journal day asked for (a notification's tap) is the account's: it doesn't open for the next one. Nor does
        // the Profile sheet, or a link waiting for it to close.
        state.forgetsAccountState { [weak self, weak state] in
            self?.requestedJournalDay = nil
            self?.afterProfileDismissal = nil
            self?.profileIsPresented = false
            state?.showsProfile = false
        }
    }

    /// `false` when the URL isn't one of ours.
    @discardableResult
    func open(_ url: URL) async -> Bool {
        guard let link = AppRoute(url: url) else { return false }
        await open(link)
        return true
    }

    func open(_ link: AppRoute) async {
        // An auth callback navigates nowhere: the Profile sheet stays.
        if case .authCallback(let url) = link {
            _ = await state.env.auth.handle(url)
            return
        }
        guard canNavigate else {
            pending = link
            return
        }
        route(link)
    }

    /// After sign-in: the link that arrived before it.
    func openPending() {
        guard canNavigate, let link = pending else { return }
        pending = nil
        route(link)
    }

    private var canNavigate: Bool { state.env.isDemo || state.env.auth.isSignedIn }

    /// Today showed the journal sheet `requestedJournalDay` asked for (or chose not to).
    func journalOpened() {
        requestedJournalDay = nil
    }

    func profileAppeared() { profileIsPresented = true }

    func profileDismissed() {
        profileIsPresented = false
        guard let link = afterProfileDismissal else { return }
        afterProfileDismissal = nil
        if canNavigate { route(link) } else { pending = link }
    }

    private func route(_ link: AppRoute) {
        // Over the Profile sheet: it closes (unless a gate or the import is over it) and the link waits for its
        // dismissal, so the tab and Today's journal sheet show on top.
        if state.showsProfile, !holdsProfile() { state.showsProfile = false }
        if profileIsPresented {
            afterProfileDismissal = link
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: state.env.clock.now())
        switch link {
        case .today:
            state.selectedTab = .today
        case .day(let day):
            // Today's scores live on Today; an earlier day on Strain's week strip.
            if day >= today {
                state.selectedTab = .today
            } else {
                strain.select(day)
                state.selectedTab = .strain
            }
        case .sleep(let night):
            sleep.show(night: night)
            state.selectedTab = .sleep
        case .sleepPlan:
            sleep.showPlanner()
            state.selectedTab = .sleep
        case .insightsBehaviors:
            insights.focusesBehaviors = true
            state.selectedTab = .insights
        case .journal(let day):
            requestedJournalDay = DayFormat.string(from: day)
            state.selectedTab = .today
        case .trainExercise(let id):
            strain.requestedRoute = .exercise(id)
            state.selectedTab = .strain
        case .trainHistory:
            strain.requestedRoute = .history
            state.selectedTab = .strain
        case .insights(let metric):
            insights.focusedMetric = metric
            state.selectedTab = .insights
        case .trainSession(let id):
            strain.requestedRoute = .session(id)
            state.selectedTab = .strain
        case .trainPlan(let id):
            strain.requestedRoute = .plan(id)
            state.selectedTab = .strain
        case .invite(let code):
            // Filled in for when the invite step shows; with access already, nothing to do.
            onboarding?.inviteCode = code
            onboarding?.show(.invite)
        case .authCallback:
            break
        }
    }
}
