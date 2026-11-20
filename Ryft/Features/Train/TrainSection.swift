import SwiftUI

/// Strain → Train (Nocturne, design.md §P5-3.5; PR 6 B §3.1, `b-23`): the group "Train", 10 under it one light pill "Start
/// workout" (or the resume banner while a session runs), then the plan, My plans and History as activity rows with a
/// chevron, 12 apart. Each row keeps its destination (`TrainRoute`).
struct TrainSection: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator

    private var model: TrainTodayViewModel { screens.trainToday }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrainSectionTitle(title: "Train")
            VStack(spacing: StrainLayout.trainItemGap) {
                if let active = coordinator.active {
                    WorkoutInProgressBanner(session: active) { coordinator.resume() }
                } else {
                    PillButton(Text("Start workout"), systemImage: PillButton.Icon.start) {
                        coordinator.showsStart = true
                    }
                    .accessibilityIdentifier("train.start")
                }
                if let today = model.today, let title = model.todayLinkTitle {
                    link(TrainRoute.plan(today.enrollment.planId), title: title, detail: model.todayLinkDetail,
                         systemImage: "calendar", identifier: "train.today")
                }
                link(TrainRoute.plans, title: String(localized: "My plans"), detail: model.plansDetail,
                     systemImage: "list.bullet.rectangle", identifier: "train.plans")
                link(TrainRoute.history, title: String(localized: "History"), detail: model.historyDetail,
                     systemImage: "clock.arrow.circlepath", identifier: "train.history")
            }
            .padding(.top, StrainLayout.listTitleGap)
        }
    }

    private func link(_ route: TrainRoute, title: String, detail: String?, systemImage: String,
                      identifier: String) -> some View {
        let spoken = [title, detail].compactMap(\.self).joined(separator: ", ")
        return NavigationLink(value: route) {
            ActivityListRow(content: ActivityListRow.Content(systemImage: systemImage, title: title, meta: detail, value: nil,
                                                             spoken: spoken, showsValue: false),
                            accessory: .chevron)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

enum TodayPlanText {
    /// "5 exercises · ~55 min".
    static func detail(_ today: PlanToday) -> String {
        let exercises = String(localized: "\(today.day.exercises.count) exercises")
        return "\(exercises) · ~\(SessionEstimate.minutes(for: today.day.exercises)) min"
    }
}

/// The start sheet's option numbers (PR 6 B §3.3, `b-01`).
enum StartOptionSpec {
    /// 68 high at least, radius 22, 16 at the sides, 14 above and below, 12 between the parts.
    nonisolated static let minHeight: CGFloat = 68, radius: CGFloat = 22
    nonisolated static let sidePadding: CGFloat = 16, verticalPadding: CGFloat = 14, spacing: CGFloat = 12
    /// The prominent option's circles (the glyph's and the arrow's): 40.
    nonisolated static let circle: CGFloat = 40
    /// The title → the detail.
    nonisolated static let detailGap: CGFloat = 2
    /// Between the options, and the header → the first one.
    nonisolated static let optionGap: CGFloat = 12, headerGap: CGFloat = 8
    /// A plan day under "A day from …": 56 high, inset 24, `surface` at 60 %.
    nonisolated static let dayHeight: CGFloat = 56, dayInset: CGFloat = 24, dayFillOpacity = 0.6
    /// The detail at the default sizes: two lines (all from AX1, #115).
    nonisolated static let detailLines = 2
}

/// Start workout (PR 6 B §3.3, `b-01`): the sheet's own header (Close at the leading edge), then the options 12 apart: from
/// today's plan (the prominent one, an ink fill with a dark glyph circle and an arrow circle), repeat the last session, a
/// day from the plan (it opens its days inline), an empty session. Without a plan day the empty session is first and
/// prominent, so the sheet always has one primary. While the last session and the plan load, their rows are outlines.
struct StartWorkoutSheet: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDays = false
    @State private var loadingOptions = true

    private var model: TrainTodayViewModel { screens.trainToday }
    private var last: TrainSession? { model.lastSession }
    private var plan: Plan? { model.activePlan }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SheetHeader(Text("Start workout"))
                VStack(spacing: StartOptionSpec.optionGap) {
                    options
                }
                .padding(.top, StartOptionSpec.headerGap)
            }
            .padding(.horizontal, SheetHeaderSpec.sidePadding)
            .padding(.top, SheetHeaderSpec.topInset)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        // The last session to repeat, and the active plan's days for "A day from …".
        .task {
            await model.loadStartOptions()
            loadingOptions = false
        }
    }

    @ViewBuilder private var options: some View {
        if let todayText = model.todayText {
            option(title: String(localized: "From today's plan"), detail: todayText, systemImage: "calendar",
                   prominent: true, starts: true) {
                coordinator.startFromToday()
            }
            .accessibilityIdentifier("train.start.today")
        } else {
            emptySession(prominent: true)
        }
        if loadingOptions, last == nil, plan == nil {
            PlaceholderRow(height: StartOptionSpec.minHeight, radius: StartOptionSpec.radius)
            PlaceholderRow(height: StartOptionSpec.minHeight, radius: StartOptionSpec.radius)
        }
        if let last {
            option(title: String(localized: "Repeat last session"),
                   detail: "\(last.title) · \(Fmt.dayTitle(last.startedAt))",
                   systemImage: "arrow.clockwise", starts: true) {
                coordinator.repeatSession(last)
            }
        }
        if let plan, !plan.days.isEmpty {
            option(title: String(localized: "A day from \(plan.name)"),
                   detail: plan.days.map(\.name).joined(separator: " · "),
                   systemImage: "list.bullet", chevron: showsDays ? "chevron.up" : "chevron.down") {
                withAnimation(Theme.Motion.respecting(reduceMotion)) { showsDays.toggle() }
            }
            if showsDays {
                ForEach(model.planDays) { day in
                    planDay(day)
                }
            }
        }
        if model.todayText != nil {
            emptySession(prominent: false)
        }
    }

    private func emptySession(prominent: Bool) -> some View {
        option(title: String(localized: "Empty session"), detail: String(localized: "Add exercises as you go"),
               systemImage: "plus", prominent: prominent, starts: true) {
            coordinator.startEmpty()
        }
        .accessibilityIdentifier("train.start.empty")
    }

    private func planDay(_ day: PlanDay) -> some View {
        Button {
            coordinator.start(day: day)
        } label: {
            HStack(spacing: StartOptionSpec.spacing) {
                Text(day.week.map { String(localized: "Week \($0) · \(day.name)") } ?? day.name)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(day.exercises.count) · ~\(SessionEstimate.minutes(for: day.exercises)) min")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            .padding(.horizontal, StartOptionSpec.sidePadding)
            .frame(minHeight: StartOptionSpec.dayHeight)
            .background(Theme.surface.opacity(StartOptionSpec.dayFillOpacity),
                        in: RoundedRectangle(cornerRadius: StartOptionSpec.radius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.leading, StartOptionSpec.dayInset)
        .accessibilityHint(Text("Starts the workout", comment: "VoiceOver hint on a start sheet option: it starts the workout."))
    }

    /// One option: `[circle] 12 [title / detail] 12 [arrow circle | chevron]`. The prominent one is the light fill with dark
    /// circles; the others are `surface` rows with an outline disc.
    private func option(title: String, detail: String, systemImage: String, prominent: Bool = false, starts: Bool = false,
                        chevron: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: StartOptionSpec.spacing) {
                if prominent {
                    circle(systemImage)
                } else {
                    IconDisc(systemImage: systemImage)
                }
                VStack(alignment: .leading, spacing: StartOptionSpec.detailGap) {
                    Text(verbatim: title)
                        .font(.ryft(.headline))
                        .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Two lines at the default sizes. At the accessibility sizes two cut it short ("~…"): it takes what it needs.
                    Text(verbatim: detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(prominent ? Theme.background.opacity(0.62) : Theme.textTertiary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : StartOptionSpec.detailLines)
                        .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                }
                Spacer(minLength: 0)
                if prominent {
                    circle("arrow.right")
                } else if let chevron {
                    Image(systemName: chevron)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, StartOptionSpec.sidePadding)
            .padding(.vertical, StartOptionSpec.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: StartOptionSpec.minHeight, alignment: .leading)
            .background(prominent ? Theme.textPrimary : Theme.surface,
                        in: RoundedRectangle(cornerRadius: StartOptionSpec.radius, style: .continuous))
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(starts ? Text("Starts the workout", comment: "VoiceOver hint on a start sheet option: it starts the workout.")
                                  : Text(verbatim: ""))
    }

    /// The prominent option's 40 pt `background` circle with an ink glyph.
    private func circle(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: StartOptionSpec.circle, height: StartOptionSpec.circle)
            .background(Theme.background, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Today's Train card (PR 6 B §3.2, `b-17`): "Train" with its dumbbell, then today's plan and "Start strength workout"; without
/// a plan "Quick start" with "Empty workout" and "Repeat last" side by side (stacked from AX1) and the last session under them;
/// after a session "Done · load 84.6 · 2 PRs" (from AX1 one part per line); while one runs, the resume banner.
struct TrainTodayCard: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var typeSize

    private var model: TrainTodayViewModel { screens.trainToday }

    var body: some View {
        if let active = coordinator.active {
            WorkoutInProgressBanner(session: active) { coordinator.resume() }
        } else if let done = model.doneToday {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(done.title).ryftLabelStyle()
                        // From AX1 one part per line, as an activity row's meta (T5.8).
                        let lines = ActivityListRow.metaLines(TrainTodayViewModel.doneText(done),
                                                              stacked: typeSize.isAccessibilitySize)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line)
                                .font(.ryft(.callout))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if done.pendingCompletion { WillSyncNote() }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
        } else if let todayText = model.todayText {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text("Today: \(todayText)")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    PillButton(Text("Start strength workout"), systemImage: PillButton.Icon.start) {
                        await coordinator.quickStart(.auto)
                    }
                    .accessibilityIdentifier("today.train.start")
                }
            }
        } else {
            // No plan: start one anyway, empty or as last time.
            let last = model.historyDetail
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text("Quick start")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12))
                                                              : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        PillButton(Text("Empty workout")) {
                            await coordinator.quickStart(.empty)
                        }
                        .accessibilityIdentifier("today.train.empty")
                        if last != nil {
                            PillButton(Text("Repeat last"), style: .secondary) {
                                await coordinator.quickStart(.repeatLast)
                            }
                            .accessibilityIdentifier("today.train.repeat")
                        }
                    }
                    if let last {
                        Text(last)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Train")
                .ryftLabelStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - previews (dark only)

#Preview("Train section") {
    NavigationStack {
        ScrollView { TrainSection().padding(20) }
            .background(Theme.background)
            .trainDestinations()
    }
    .previewEnvironment()
}

#Preview("Start workout") {
    Text("").sheet(isPresented: .constant(true)) { StartWorkoutSheet().previewEnvironment().presentedRoot() }
        .previewEnvironment()
}

/// Each option's detail wraps whole.
#Preview("Start workout · AX3") {
    Text("").sheet(isPresented: .constant(true)) {
        StartWorkoutSheet().previewEnvironment().dynamicTypeSize(.accessibility3).presentedRoot()
    }
    .previewEnvironment()
}

#Preview("Today card", traits: .sizeThatFitsLayout) {
    DarkPreview { TrainTodayCard() }
        .previewEnvironment()
}
