import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Draws the first-run spec's layouts (docs/work/2026-11-23-first-run/ui.md) from the real components and tokens, as PNGs, when
/// `FIRST_RUN_SPEC_DIR` is set; otherwise does nothing:
/// `TEST_RUNNER_FIRST_RUN_SPEC_DIR=<dir> xcodebuild … -only-testing:RyftTests/FirstRunSpecShotsTests test`.
/// The screens are *compositions* of `FirstRunStepRule`, `LockScreenMock` and the existing onboarding pieces, with the spec's
/// draft English as verbatim text; no feature view is changed and nothing is wired. Synthetic data only (the mock Today).
@MainActor
@Suite("First run spec shots", .serialized)
struct FirstRunSpecShotsTests {
    private struct Shot {
        let view: AnyView
        var typeSize = DynamicTypeSize.large
        var category = UIContentSizeCategory.large
        /// The whole page, joined; else the window as the phone shows it (a pinned bar once).
        var paged = false
    }

    nonisolated static let names = [
        "spec-step-rule", "spec-step-rule-in-context", "spec-lock-screen-mock", "spec-notification-primer",
        "spec-notification-primer-push-off", "spec-notification-primer-ax3", "spec-health-primer", "spec-today-first-import",
    ]

    @Test(arguments: names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["FIRST_RUN_SPEC_DIR"] else { return }
        let shot = try #require(Self.shot(name))
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: shot.typeSize, category: shot.category,
                                   shot.view.environment(\.locale, Locale(identifier: "en_US"))) { w in
            try await w.settle()
            let image = shot.paged ? try await PagedWindowShot.image(w) : Self.window(w)
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    /// The window as it is, at 2x.
    private static func window(_ w: HostedWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }

    private static func shot(_ name: String) -> Shot? {
        switch name {
        case "spec-step-rule":
            return Shot(view: AnyView(DarkPreview {
                VStack(alignment: .leading, spacing: 20) {
                    FirstRunStepRule(step: 1, count: 6)
                    FirstRunStepRule(step: 3, count: 7)
                    FirstRunStepRule(step: 8, count: 8)
                }
            }.frame(maxHeight: .infinity, alignment: .top)))
        case "spec-step-rule-in-context":
            return Shot(view: AnyView(SpecScreen(progress: (4, 7), title: "What do you wear?",
                                                 lead: "Pick your watch, tracker or ring. RYFT then shows how to get its data into Apple Health.") {
                VStack(spacing: 10) {
                    ForEach(["Apple Watch", "Garmin", "Oura"], id: \.self) { name in
                        Text(verbatim: name)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 16)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            } actions: {
                PillButton(Text(verbatim: "Continue")) {}.disabled(true)
                LaterButton(title: "Skip") {}
            }))
        case "spec-lock-screen-mock":
            return Shot(view: AnyView(DarkPreview {
                VStack(spacing: 24) {
                    Self.mock(.phone)
                    Self.mock(.card)
                }
            }.frame(maxHeight: .infinity, alignment: .top)))
        case "spec-notification-primer":
            return Shot(view: AnyView(notificationPrimer(journal: false)))
        case "spec-notification-primer-push-off":
            return Shot(view: AnyView(notificationPrimer(journal: true)))
        case "spec-notification-primer-ax3":
            return Shot(view: AnyView(notificationPrimer(journal: false)), typeSize: .accessibility3,
                        category: .accessibilityExtraLarge, paged: true)
        case "spec-health-primer":
            return Shot(view: AnyView(healthPrimer()))
        case "spec-today-first-import":
            return Shot(view: AnyView(todayFirstImport().previewEnvironment()))
        default:
            return nil
        }
    }

    // MARK: compositions

    private static let clock = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7, minute: 30)) ?? .now

    private static func mock(_ style: LockScreenMock.Style, title: String = "Your morning score is ready",
                             message: String = "Open RYFT to see how you recovered overnight.") -> LockScreenMock {
        LockScreenMock(style: style, clock: clock, title: title, message: message, timeLabel: "now",
                       accessibilityLabel: "Example notification from RYFT. \(title). \(message)")
    }

    /// §4: after Apple Health. `journal`: `push.enabled` is off, so the example is a notification that does arrive.
    private static func notificationPrimer(journal: Bool) -> some View {
        SpecScreen(progress: (6, 7), title: "Hear from RYFT when it matters",
                   lead: journal
                       ? "RYFT can remind you to log your day, and tell you when your data stops syncing. You choose which in Profile."
                       : "RYFT can tell you when your morning score is ready, and when your data stops syncing. You choose which in Profile.") {
            VStack(alignment: .leading, spacing: OnboardingSpec.actionGap) {
                if journal {
                    mock(.phone, title: "How was yesterday?",
                         message: "A few taps, and RYFT shows how your habits change the morning after.")
                } else {
                    mock(.phone)
                }
                Text(verbatim: "An example. What your lock screen shows follows your iOS setting for previews. "
                    + "Change what RYFT sends in Profile → Notifications.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            PillButton(Text(verbatim: "Continue")) {}
            LaterButton(title: "Not now") {}
        }
    }

    /// §2: what the system sheet will ask, in RYFT's components.
    private static func healthPrimer() -> some View {
        SpecScreen(progress: (5, 7), title: "Connect Apple Health", showsIllustration: true,
                   lead: "RYFT turns what your watch writes to Apple Health into recovery, strain and sleep scores.") {
            VStack(alignment: .leading, spacing: 0) {
                GroupedCard(Text(verbatim: "On the next screen")) {
                    OnboardingPoint(symbol: "switch.2", title: "Tap Turn On All",
                                    text: "It is at the top of the list and switches on all ten kinds of data below.")
                    OnboardingPoint(symbol: "checkmark.circle", title: "Then tap Allow",
                                    text: "That is all RYFT needs. You can change any of them later in the Health app.")
                }
                GroupedCard(Text(verbatim: "The ten kinds of data")) {
                    OnboardingPoint(symbol: "figure.walk", title: "Activity",
                                    text: "Active Energy, Steps, Workouts")
                    OnboardingPoint(symbol: "heart", title: "Heart",
                                    text: "Heart Rate, Heart Rate Variability, Resting Heart Rate, Cardio Fitness (VO₂ max)")
                    OnboardingPoint(symbol: "lungs", title: "Respiratory", text: "Respiratory Rate, Blood Oxygen")
                    OnboardingPoint(symbol: "bed.double", title: "Sleep", text: "Sleep")
                }
                .padding(.top, GroupedListSpec.groupSpacing)
                Text(verbatim: "RYFT writes nothing to Apple Health. Your data goes to your RYFT account, "
                    + "where the scores are calculated. Never sold, never used for advertising.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OnboardingSpec.actionGap)
                Button {} label: { Text(verbatim: "Privacy Policy") }.ryftLink()
            }
        } actions: {
            PillButton(Text(verbatim: "Continue")) {}
            LaterButton(title: "Not now") {}
        }
    }

    /// §5: the first import, with the empty orbit holding the gauge's place and no push question in the card.
    private static func todayFirstImport() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    WordmarkLockup()
                    Spacer()
                }
                .frame(height: ScreenHeaderSpec.height)
                VStack(alignment: .leading, spacing: TodayLayout.greetingToSubLine) {
                    Text(verbatim: "Good morning, Alex")
                        .font(.ryft(.title))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: "Monday, Nov 23 · Your history is on its way.")
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                    Label { Text(verbatim: "Uploading 12,400 readings") } icon: { Image(systemName: "arrow.up.circle") }
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, TodayLayout.subLineToStatus)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TodayLayout.headerToGreeting)
                OrbitGauge(mode: .scored(.empty), size: .hero, showsCaption: false, animatesFill: false, breathes: false)
                    .frame(width: TodayLayout.heroFrame, height: TodayLayout.heroFrame)
                    .padding(.top, TodayLayout.statusToGauge)
                ImportCard(progress: TodayStates.progress(TodayScenario.importing.apply(to: TodaySyncFacts(now: .now))),
                           asksForPush: false)
                    .padding(.top, TodayLayout.cardGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// A first-run screen as the spec lays it out: `OnboardingScreen`'s frame (lock-up row, title, lead, content), with the step
/// rule 12 under the lock-up row when there is progress, and the actions pinned below the accessibility sizes, inline from them.
private struct SpecScreen<Content: View, Actions: View>: View {
    var progress: (step: Int, count: Int)?
    let title: String
    let lead: String
    var showsIllustration = false
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @Environment(\.dynamicTypeSize) private var typeSize

    init(progress: (step: Int, count: Int)? = nil, title: String, showsIllustration: Bool = false, lead: String,
         @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.progress = progress
        self.title = title
        self.lead = lead
        self.showsIllustration = showsIllustration
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        let inline = typeSize.isAccessibilitySize
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WordmarkLockup()
                    .frame(height: OnboardingSpec.headerHeight)
                if let progress {
                    FirstRunStepRule(step: progress.step, count: progress.count)
                        .padding(.top, FirstRunStepRuleSpec.topGap)
                }
                if showsIllustration {
                    HealthIllustration()
                        .padding(.top, progress == nil ? OnboardingSpec.titleGap : FirstRunStepRuleSpec.titleGap)
                }
                ScreenHeaderTitle(text: Text(verbatim: title))
                    .padding(.top, showsIllustration ? 20 : progress == nil ? OnboardingSpec.titleGap : FirstRunStepRuleSpec.titleGap)
                Text(verbatim: lead)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OnboardingSpec.leadGap)
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.top, OnboardingSpec.contentGap)
                if inline {
                    VStack(spacing: PinnedBarSpec.spacing) { actions }
                        .padding(.top, OnboardingSpec.primaryGap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: OnboardingSpec.maxWidth)
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, OnboardingSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !inline { PinnedActionBar { actions } }
        }
    }
}
