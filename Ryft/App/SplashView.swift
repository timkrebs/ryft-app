import SwiftUI

/// The splash's numbers (PR 6 A §A-14).
enum SplashSpec {
    /// The mark: 64, centred, as on the launch screen, so nothing jumps between the two.
    static let markSide: CGFloat = 64
    /// "Checking your account…" appears once the wait has lasted this long (a restore usually takes under a second; the first
    /// run waits up to the coordinator's `checkTimeout`).
    static let captionDelay: Duration = .seconds(3)
    /// The caption's top edge 50 below the mark's centre: its first line centres about 58 below it. The mark never moves.
    static let captionTop: CGFloat = 50
}

/// While the SDK reads the Keychain, and while the first run waits for the platform's answer: the mark on `background`,
/// like the launch screen. After 3 s a caption says why it is still here ("Checking your account…", 13 pt
/// `textSecondary`, faded in with `Theme.Motion.quick`, at once under Reduce Motion, and announced). The wait is the
/// environment's clock, so a test decides when it ends.
struct SplashView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waiting = false

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
                        if waiting {
                            Text("Checking your account…")
                                .font(.ryft(.label))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Metrics.screenPadding)
                                .padding(.top, SplashSpec.captionTop)
                                .transition(.opacity)
                                .accessibilityIdentifier("splash.caption")
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .background(Theme.background.ignoresSafeArea())
            .task {
                do { try await env.clock.sleep(for: SplashSpec.captionDelay) } catch { return }
                withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) { waiting = true }
                AccessibilityNotification.Announcement(String(localized: "Checking your account…")).post()
            }
    }
}

// Dark only (NOCTURNE_STYLE §1). The caption appears after 3 s.
#Preview("Splash") {
    SplashView()
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
}

#Preview("Splash · AX3") {
    SplashView()
        .environment(\.appEnvironment, .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
