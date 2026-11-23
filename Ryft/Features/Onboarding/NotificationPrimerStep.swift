import Observation
import SwiftUI

/// The first run's notification primer (first-run ui.md §4.4): Continue is the registrar's own ask (`PushRegistrar.accept`:
/// iOS's prompt, then APNs), "Not now" its own dismissal (`dismissPrompt`: Today's card comes back once, 14 days later) and
/// never prompts. Either answer marks the primer answered for the account, which ends the step. A failed prompt counts as
/// declined: the step goes on, with nothing to fix here.
@MainActor
@Observable
final class NotificationPrimerModel {
    private let push: PushRegistrar
    /// `onboarding_step` (first-run ui.md §8); it checks `analytics.enabled` and the opt-in itself.
    private let analytics: Analytics
    /// iOS's prompt is up: the pill is busy and "Not now" waits.
    private(set) var isAsking = false

    init(push: PushRegistrar, analytics: Analytics) {
        self.push = push
        self.analytics = analytics
    }

    /// Continue: the registrar's ask, once while it is out.
    @discardableResult
    func allow() async -> PushRegistrar.AskOutcome? {
        guard !isAsking else { return nil }
        isAsking = true
        defer { isAsking = false }
        let outcome = await push.accept()
        analytics.track(.onboardingStep(.notifications, .continued, OnboardingPermission(outcome)))
        push.markPrimerAnswered()
        return outcome
    }

    /// Not now: no prompt; the card on Today is the second chance.
    func notNow() {
        guard !isAsking else { return }
        push.dismissPrompt()
        analytics.track(.onboardingStep(.notifications, .skipped))
        push.markPrimerAnswered()
    }
}

/// "Hear from RYFT when it matters": after Apple Health and before tracker setup, while iOS can still ask
/// (`NotificationPrimerFacts.shows`). One concrete example on a lock screen (`LockScreenMock`), chosen so it is a notification
/// that will arrive (`NotificationPrimerExample.choose`), then the caption; Continue (busy while iOS asks: the pill's spinner,
/// the title stays; its hint says iOS asks next) and Not now pinned (from AX1 at the end of the page). Nothing teal or Volt:
/// the example reads as an example. VoiceOver: the title, "Step n of m", the lead, the mock as one sentence, the caption, Continue, Not now.
struct NotificationPrimerStep: View {
    @State var model: NotificationPrimerModel
    let example: NotificationPrimerExample
    /// The first run's step rule (nil: not counted).
    var progress: FirstRunProgress?
    /// Previews and tests: the busy state, which the model only enters while iOS asks.
    var showsBusy = false

    @Environment(\.appEnvironment) private var env

    private var isBusy: Bool { model.isAsking || showsBusy }

    var body: some View {
        OnboardingScreen(title: Text(NotificationPrimerExample.screenTitle), lead: Text(example.lead), showsLockup: true,
                         progress: progress) {
            LockScreenMock(style: .phone, clock: example.clock(on: env.clock.now()), title: example.title,
                           message: example.message, timeLabel: NotificationPrimerExample.timeLabel,
                           accessibilityLabel: example.accessibilityLabel)
                .accessibilityIdentifier("notifications.example")
            Text(NotificationPrimerExample.caption)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OnboardingSpec.actionGap)
        } actions: {
            PillButton(Text("Continue"), busy: isBusy) { await model.allow() }
                .accessibilityHint(Text("iOS asks next", comment: "First run, notification primer: VoiceOver hint on Continue."))
                .accessibilityIdentifier("notifications.continue")
            LaterButton(title: "Not now") { model.notNow() }
                .disabled(isBusy)
                .accessibilityIdentifier("notifications.notNow")
        }
    }
}

// MARK: - previews (dark only: ADR 0016, every colour is a one-value asset, so a light preview would be the same pixels)

@MainActor
private func primerPreview(_ example: NotificationPrimerExample = .morningScore, busy: Bool = false,
                           size: DynamicTypeSize = .large) -> some View {
    let env = AppEnvironment.preview()
    return NotificationPrimerStep(model: NotificationPrimerModel(push: PushRegistrar(env: env), analytics: env.analytics),
                                  example: example,
                                  progress: FirstRunProgress(step: 6, count: 7), showsBusy: busy)
        .environment(\.appEnvironment, env)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(size)
}

#Preview("Notification primer · morning score") { primerPreview() }
#Preview("Notification primer · journal (push off)") { primerPreview(.journal) }
#Preview("Notification primer · not syncing (push off, no journal)") { primerPreview(.syncStale) }
#Preview("Notification primer · busy") { primerPreview(busy: true) }
#Preview("Notification primer · AX3 (card alone)") { primerPreview(size: .accessibility3) }
#Preview("Notification primer · AX5") { primerPreview(size: .accessibility5) }
