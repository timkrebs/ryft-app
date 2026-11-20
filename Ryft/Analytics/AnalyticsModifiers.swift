import SwiftUI

extension View {
    /// `screen_viewed` each time this screen appears (pushed or presented; the tabs are RyftApp's).
    func analyticsScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen))
    }

    /// `error_shown` when this error card appears, and again only when its status bucket or code changes (a retry
    /// failing the same way isn't a new event).
    func analyticsError(_ error: ResourceError) -> some View {
        modifier(AnalyticsErrorModifier(event: .errorShown(for: error)))
    }
}

private struct AnalyticsScreenModifier: ViewModifier {
    let screen: AnalyticsScreen
    @Environment(\.appEnvironment) private var env

    func body(content: Content) -> some View {
        content.onAppear { env.analytics.track(.screenViewed(screen)) }
    }
}

private struct AnalyticsErrorModifier: ViewModifier {
    let event: AnalyticsEvent
    @Environment(\.appEnvironment) private var env

    func body(content: Content) -> some View {
        content.task(id: event) { env.analytics.track(event) }
    }
}
