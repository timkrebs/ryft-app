import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import Ryft

/// Writes Profile's subpages (PR 6 C §4.3, §4.7–§4.9: Report a problem and its results, Notifications, Journal and Add a
/// habit, Sign-in methods, Licences) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at AX3, when
/// `SUBPAGE_SHOTS_DIR` is set; otherwise does nothing. Run it with `TEST_RUNNER_SUBPAGE_SHOTS_DIR=<dir> xcodebuild …
/// -only-testing:RyftTests/ProfileSubpagesShotsTests test-without-building` and compare the set with the drafts (c-03…c-13).
/// Drawn from a real window; for comparing, not a golden-file test. Synthetic data only (Alex Doe).
@MainActor
@Suite("C1: Profile subpages, shots", .serialized)
struct ProfileSubpagesShotsTests {
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["SUBPAGE_SHOTS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            // A list page draws in one window (`PagedWindowShot` pages scroll views, not lists): tall enough for AX3.
            let height: CGFloat = name.hasPrefix("journal") ? (size == "ax3" ? 2_400 : 1_400) : 844
            try await HostedWindow.run(width: 390, height: height, bottomInset: 34, typeSize: typeSize, category: category,
                                       SubpageShotScreen.view(name)) { w in
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }

    nonisolated static let names = [
        "report-empty", "report-filled", "report-included", "report-limited", "report-sending", "report-sent", "report-queued",
        "notifications-allowed", "notifications-quiet-on", "notifications-rollout", "notifications-denied", "notifications-not-asked",
        "journal", "add-habit", "sign-in-email", "sign-in-both", "licences",
    ]
}

/// One subpage in one state, pushed on a stack as Profile pushes it, on the preview's mock data.
@MainActor
enum SubpageShotScreen {
    static let message = "Today shows 'Updating…' for hours and my Garmin night never arrives."

    static func view(_ name: String) -> AnyView {
        switch name {
        case "report-empty": return report { _ in }
        case "report-filled": return report { $0.stage(message: message, category: .data, includeDiagnostics: false) }
        case "report-included":
            return report(context: .preview, showsIncluded: true) {
                $0.stage(message: message, category: .data, context: .preview)
            }
        case "report-limited": return report { $0.stage(message: message, category: .data, result: .rateLimited) }
        case "report-sending":
            return report { $0.stage(message: message, category: .data, includeDiagnostics: false, sending: true) }
        case "report-sent": return report { $0.stage(result: .sent) }
        case "report-queued": return report { $0.stage(result: .queued, waiting: 1) }
        case "notifications-allowed": return notifications(.authorized)
        case "notifications-quiet-on": return notifications(.authorized, quietHours: true)
        case "notifications-rollout": return notifications(.authorized, rolledOut: false)
        case "notifications-denied": return notifications(.denied)
        case "notifications-not-asked": return notifications(.notDetermined)
        case "journal":
            let state = AppState.preview()
            return pushed(state) { JournalSettingsView(store: journalPreviewStore(state)) }
        case "add-habit": return addHabit(name: "Evening walk")
        case "sign-in-email": return signIn(apple: false)
        case "sign-in-both": return signIn(apple: true)
        default: return pushed(AppState.preview()) { LicensesView() }
        }
    }

    static func report(context: ReportContext? = nil, showsIncluded: Bool = false,
                       _ stage: (ReportProblemModel) -> Void) -> AnyView {
        let state = AppState.preview()
        let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { FeedbackSync() }
        stage(model)
        return pushed(state) { ReportProblemView(model: model, context: context, showsIncluded: showsIncluded) }
    }

    /// `quietHours`: the account has them on, 22:30 to 07:00 (From and Until show).
    static func notifications(_ status: UNAuthorizationStatus, rolledOut: Bool = true, quietHours: Bool = false) -> AnyView {
        let notifier = MockNotifier()
        notifier.status = status
        let state = AppState.preview(flags: rolledOut ? [.pushEnabled: true] : [:], notifier: notifier)
        if quietHours, let user = state.user {
            state.user?.notifications = NotificationPrefs(categories: user.notifications.categories,
                                                          quietHours: NotificationSettingsViewModel.defaultQuietHours)
        }
        return pushed(state) { NotificationSettingsView() }
    }

    static func signIn(apple: Bool) -> AnyView {
        let client = MockAuthClient(session: .preview(email: "alex@example.com", provider: "email"))
        if apple { client.methods.append(SignInMethod(provider: "apple", email: "alex@example.com", addedAt: nil)) }
        let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                               wipeLocalData: { _ in true },
                               deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        let state = AppState.preview(auth: auth)
        return pushed(state) { SignInMethodsView() }
    }

    /// Add a habit as its sheet shows it, `name` typed.
    static func addHabit(name: String) -> AnyView {
        let state = AppState.preview()
        return AnyView(AddBehaviorSheet(store: journalPreviewStore(state), name: name)
            .previewEnvironment(state).toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US")))
    }

    /// `page` pushed on a stack (Back shows), in the app's environment: the root's toggle style and tint, US English.
    static func pushed<Page: View>(_ state: AppState, @ViewBuilder _ page: @escaping () -> Page) -> AnyView {
        AnyView(PushedShot(page: page)
            .previewEnvironment(state)
            .toggleStyle(.ryft)
            .environment(\.locale, Locale(identifier: "en_US")))
    }

    private struct PushedShot<Page: View>: View {
        let page: () -> Page
        @State private var path: [Int] = []

        var body: some View {
            NavigationStack(path: $path) {
                Color.clear.navigationDestination(for: Int.self) { _ in page() }
            }
            .onAppear { path = [1] }
        }
    }
}
