import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes area A's screens (signed out, onboarding, splash, the misconfigured build and the Details sheet) as 3x PNGs, whole
/// pages (`PagedWindowShot`), at the default size and at AX3, when `A_SCREENS_DIR` is set; otherwise does nothing. Run it
/// before and after a change with `TEST_RUNNER_A_SCREENS_DIR=<dir> xcodebuild … -only-testing:RyftTests/SignedOutOnboardingShotsTests
/// test-without-building` and compare the sets with the approved drafts (`a-*.jpg`). A page that scrolls also gets an
/// `-end` shot, the window at the page's end. Drawn from a real window
/// (`drawHierarchy`); for comparing, not a golden-file test. Synthetic data only (Alex Doe, alex@example.com).
@MainActor
@Suite("PR 6 A: signed out and onboarding, shots", .serialized)
struct SignedOutOnboardingShotsTests {
    /// A screen: its name, the page, a label prefix to wait for (empty: settle only), and what to do once it settled (an
    /// error a screen clears on appear is set here, after it).
    private struct Screen {
        let name: String
        let view: AnyView
        var ready = ""
        var after: (@MainActor () -> Void)?
    }

    /// The screens' names, one test case each (each case has the plan's time allowance to itself).
    nonisolated static let names = [
        "a-01-welcome", "a-02-welcome-notice", "a-03-login", "a-03-login-error", "a-03-login-busy", "a-04-create-account",
        "a-05-reset-password", "a-06-check-inbox", "a-07-set-new-password", "a-07-change-password-busy", "a-08-invite",
        "a-09-consent", "a-10-about-you", "a-10-about-you-saved", "a-11-apple-health", "a-12-wear", "a-13-tracker-setup",
        "a-14-account-hint", "a-15-splash", "a-15-splash-waiting", "a-16-misconfigured", "a-18-details-sheet",
        "a-18-details-sheet-no-id",
    ]

    @Test(arguments: names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["A_SCREENS_DIR"] else { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            // Built per size: a screen's models and clocks start fresh.
            guard let screen = Self.screens().first(where: { $0.name == name }) else { return }
            let view = screen.view.environment(\.locale, Locale(identifier: "en_US"))
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       view) { w in
                if !screen.ready.isEmpty {
                    try await w.wait(screen.ready) { w.nodes().contains { $0.label.hasPrefix(screen.ready) } }
                }
                try await w.settle()
                if let after = screen.after {
                    after()
                    try await w.settle()
                }
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(screen.name)-\(size).png"))
                // A page that scrolls also as the window shows its end: the joined parts draw a pinned bar once per part,
                // over the content under it.
                if let end = try await Self.endShot(w) {
                    try #require(end.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(screen.name)-\(size)-end.png"))
                }
            }
        }
    }

    /// The window scrolled to the page's end, at 3x; nil when the page doesn't scroll.
    private static func endShot(_ w: HostedWindow) async throws -> UIImage? {
        guard let scroll = w.pageScrollView() else { return nil }
        let inset = scroll.adjustedContentInset
        let end = scroll.contentSize.height + inset.bottom - scroll.bounds.height
        guard end > -inset.top + 0.5 else { return nil }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: end), animated: false)
        try await w.settle()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }

    private static func signedOut() -> AuthService { AuthService.preview(signedIn: false) }

    private static func pushed(_ view: some View) -> AnyView { AnyView(NavigationStack { view }) }

    private static func screens() -> [Screen] {
        let notice = signedOut()
        notice.signOutNotice = AuthService.SignOutReason.sessionExpired.notice
        let logInError = signedOut()
        let createError = signedOut()
        let inviteModel = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        let setupState = AppState.preview()
        let setup = OnboardingCoordinator(state: setupState, apiStatus: APIStatus()) {}
        setup.devices.stage(["garmin"])
        let wearState = AppState.preview()
        let wear = OnboardingCoordinator(state: wearState, apiStatus: APIStatus()) {}
        let hint = AccountHint(kind: "other_account_on_device", otherProvider: "email",
                               otherLastSync: Date(timeIntervalSince1970: 1_795_392_000))
        let splashClock = TestClock()
        let splashEnv = AppEnvironment.test(clock: splashClock)
        return [
            Screen(name: "a-01-welcome", view: AnyView(WelcomeView().environment(signedOut())), ready: "RYFT"),
            Screen(name: "a-02-welcome-notice",
                   view: AnyView(WelcomeView().environment(notice)
                       .environment(\.appEnvironment, AppEnvironment.previewWithParkedRows())), ready: "RYFT"),
            Screen(name: "a-03-login", view: AnyView(pushed(LogInView(path: .constant([]))).environment(signedOut())),
                   ready: "Log in"),
            Screen(name: "a-03-login-error", view: AnyView(pushed(LogInView(path: .constant([]))).environment(logInError)),
                   ready: "Log in", after: { logInError.errorMessage = String(localized: "Email or password is wrong.") }),
            Screen(name: "a-03-login-busy",
                   view: AnyView(pushed(LogInView(path: .constant([]), showsBusy: true)).environment(signedOut())),
                   ready: "Log in"),
            Screen(name: "a-04-create-account",
                   view: AnyView(pushed(CreateAccountView(path: .constant([]))).environment(createError)),
                   ready: "Create account"),
            Screen(name: "a-05-reset-password",
                   view: AnyView(pushed(ForgotPasswordView(path: .constant([]), email: "alex@example.com"))
                       .environment(signedOut())), ready: "Reset password"),
            Screen(name: "a-06-check-inbox",
                   view: AnyView(pushed(CheckInboxView(reason: .confirmSignUp, email: "alex@example.com"))
                       .environment(signedOut())), ready: "Check your inbox"),
            Screen(name: "a-07-set-new-password",
                   view: AnyView(SetNewPasswordView(mode: .recovery).environment(AuthService.preview())),
                   ready: "Set new password"),
            Screen(name: "a-07-change-password-busy",
                   view: AnyView(SetNewPasswordView(mode: .change, showsBusy: true).environment(AuthService.preview())),
                   ready: "Change password"),
            Screen(name: "a-08-invite", view: AnyView(OnboardingStepView(step: .invite, model: inviteModel)),
                   ready: "Enter your invite code"),
            Screen(name: "a-09-consent", view: AnyView(OnboardingStepPreview(step: .consent)),
                   ready: "Nothing is synced until you agree. Privacy policy version"),
            Screen(name: "a-10-about-you", view: AnyView(OnboardingStepPreview(step: .aboutYou)), ready: "About you"),
            Screen(name: "a-10-about-you-saved", view: AnyView(OnboardingStepPreview(step: .aboutYou, saved: true)),
                   ready: "Maximum heart rate"),
            Screen(name: "a-11-apple-health", view: AnyView(HealthPermissionView()), ready: "Connect Apple Health"),
            Screen(name: "a-12-wear",
                   view: AnyView(TrackerPickerView(model: wear, picked: ["garmin", "oura"]).previewEnvironment(wearState)),
                   ready: "What do you wear?"),
            Screen(name: "a-13-tracker-setup",
                   view: AnyView(TrackerSetupStepView(model: setup, checkOpen: false).previewEnvironment(setupState)),
                   ready: "Set up your tracker"),
            Screen(name: "a-14-account-hint", view: AnyView(AccountHintSheet(hint: hint, keep: {}, useOther: {})),
                   ready: "This is a new RYFT account"),
            // A clock that never moves: the shot is the mark alone, before the caption.
            Screen(name: "a-15-splash", view: AnyView(SplashView().environment(\.appEnvironment, AppEnvironment.test())),
                   ready: "RYFT"),
            Screen(name: "a-15-splash-waiting", view: AnyView(SplashView().environment(\.appEnvironment, splashEnv)),
                   ready: "RYFT", after: { splashClock.advance(by: SplashSpec.captionDelay) }),
            Screen(name: "a-16-misconfigured", view: AnyView(MisconfiguredBuildView(missing: ["RYFT_API_URL"])),
                   ready: "This build"),
            Screen(name: "a-18-details-sheet",
                   view: AnyView(RefreshDetailsSheet(issue: detailsIssue(requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c"))
                       .environment(\.reportProblemDestination) { _, _, _, _ in AnyView(Text(verbatim: "Report a problem")) }),
                   ready: "Details"),
            Screen(name: "a-18-details-sheet-no-id",
                   view: AnyView(RefreshDetailsSheet(issue: detailsIssue(requestID: nil))), ready: "Details"),
        ]
    }

    /// Three 503s on Today, data from 9:20 (the draft's); `requestID` nil: a proxy answered first.
    private static func detailsIssue(requestID: String?) -> RefreshIssue {
        let calendar = Calendar.current
        let at = { (h: Int, m: Int) in calendar.date(bySettingHour: h, minute: m, second: 12, of: .now) ?? .now }
        let error = ResourceError(kind: .transient, status: 503, code: "unavailable",
                                  requestID: requestID, transport: nil, attempts: 3, at: at(9, 41))
        return RefreshIssue(reason: .busy, resource: .today, dataFrom: at(9, 20), failures: 3, error: error)
    }
}
