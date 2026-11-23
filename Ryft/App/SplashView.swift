import SwiftUI

/// The splash's numbers (PR 6 A §A-14, first-run ui.md §7).
enum SplashSpec {
    /// The mark: 64, centred, as on the launch screen, so nothing jumps between the two.
    static let markSide: CGFloat = 64
    /// Restoring a session: "Checking your account…" appears once the wait has lasted this long (a restore usually takes
    /// under a second).
    static let captionDelay: Duration = .seconds(3)
    /// The first run's wait for the platform (up to the coordinator's `checkTimeout`, 10 s): the caption comes sooner,
    /// and a second one says it is slow.
    static let firstRunCaptionDelay: Duration = .seconds(1)
    static let slowAfter: Duration = .seconds(5)
    /// The caption's top edge 50 below the mark's centre: its first line centres about 58 below it. The mark never moves.
    static let captionTop: CGFloat = 50
}

/// What the splash says under the mark, by how long it has waited (first-run ui.md §7). No count, no spinner, no countdown:
/// the wait ends when the platform answers or at the timeout, and nothing says which, so a number would suggest progress the
/// app doesn't have.
enum SplashCaption: Equatable, Sendable {
    case none, checking, slow

    /// Restoring: nothing before 3 s, then "Checking your account…". The first run: nothing before 1 s, "Checking your
    /// account…" until 5 s, then "Taking longer than usual…" until the wait ends.
    static func at(elapsed: Duration, firstRun: Bool) -> Self {
        guard firstRun else { return elapsed < SplashSpec.captionDelay ? .none : .checking }
        if elapsed < SplashSpec.firstRunCaptionDelay { return .none }
        return elapsed < SplashSpec.slowAfter ? .checking : .slow
    }

    /// When each caption after `.none` begins, in order.
    static func schedule(firstRun: Bool) -> [(at: Duration, caption: SplashCaption)] {
        firstRun ? [(SplashSpec.firstRunCaptionDelay, .checking), (SplashSpec.slowAfter, .slow)]
            : [(SplashSpec.captionDelay, .checking)]
    }

    var text: String? {
        switch self {
        case .none: return nil
        case .checking: return String(localized: "Checking your account…")
        case .slow:
            return String(localized: "Taking longer than usual. RYFT carries on by itself in a few seconds.",
                          comment: "Splash, the first run's wait for the platform after 5 s; it goes on by itself at 10 s.")
        }
    }
}

/// While the SDK reads the Keychain, and while the first run waits for the platform's answer: the mark on `background`,
/// like the launch screen. A caption says why it is still here (`SplashCaption`: after 3 s restoring; after 1 s on the first
/// run, and a second one at 5 s), 13 pt `textSecondary`, faded in with `Theme.Motion.quick` (at once under Reduce Motion)
/// and announced. The wait is the environment's clock, so a test decides when it ends.
struct SplashView: View {
    /// The first run's wait (`OnboardingCoordinator.holdsFirstRun`), not a restore.
    var firstRun = false

    @Environment(\.appEnvironment) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caption = SplashCaption.none

    var body: some View {
        RyftMark()
            .frame(width: SplashSpec.markSide, height: SplashSpec.markSide)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "RYFT"))
            .accessibilityIdentifier("splash.mark")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // An overlay, so the caption takes no part in the mark's layout: the mark stays where the launch screen put it.
            // The lower half starts at the mark's centre; the caption hangs 50 below that.
            .overlay {
                VStack(spacing: 0) {
                    Color.clear
                    Color.clear.overlay(alignment: .top) {
                        if let text = caption.text {
                            Text(text)
                                .font(.ryft(.label))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Metrics.screenPadding)
                                .padding(.top, SplashSpec.captionTop)
                                .id(caption)
                                .transition(.opacity)
                                .accessibilityIdentifier("splash.caption")
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .background(Theme.background.ignoresSafeArea())
            .task {
                var waited = Duration.zero
                for step in SplashCaption.schedule(firstRun: firstRun) {
                    do { try await env.clock.sleep(for: step.at - waited) } catch { return }
                    waited = step.at
                    withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) { caption = step.caption }
                    if let text = step.caption.text { AccessibilityNotification.Announcement(text).post() }
                }
            }
    }
}

// Dark only (NOCTURNE_STYLE §1, ADR 0016: a light preview would be the same pixels). Restoring: the caption after 3 s; the
// first run: after 1 s, the second one at 5 s.
#Preview("Splash") {
    SplashView()
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
}

#Preview("Splash · first run") {
    SplashView(firstRun: true)
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
}

#Preview("Splash · AX3") {
    SplashView()
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Splash · first run · AX5") {
    SplashView(firstRun: true)
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
