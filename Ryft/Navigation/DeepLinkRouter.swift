import Foundation
import Observation

/// Opens a `DeepLink`: selects the tab and tells that tab's view model what to
/// show. Universal links, `ryft://` URLs and notification taps all come here.
/// A link that needs an account waits in `pending` until someone is signed in.
@MainActor
@Observable
final class DeepLinkRouter {
    private let state: AppState
    private let sleep: SleepViewModel
    private let strain: StrainViewModel
    private let insights: InsightsViewModel
    private(set) var pending: DeepLink?

    init(state: AppState, sleep: SleepViewModel, strain: StrainViewModel, insights: InsightsViewModel) {
        self.state = state
        self.sleep = sleep
        self.strain = strain
        self.insights = insights
    }

    /// `false` when the URL isn't one of ours.
    @discardableResult
    func open(_ url: URL) async -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        await open(link)
        return true
    }

    func open(_ link: DeepLink) async {
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

    private func route(_ link: DeepLink) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: state.env.clock.now())
        switch link {
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
        case .insights(let metric):
            insights.focusedMetric = metric
            state.selectedTab = .insights
        case .trainSession(let id):
            strain.requestedRoute = .session(id)
            state.selectedTab = .strain
        case .trainPlan(let id):
            strain.requestedRoute = .plan(id)
            state.selectedTab = .strain
        case .authCallback:
            break
        }
    }
}
