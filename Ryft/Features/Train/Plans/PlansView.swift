import SwiftUI

extension PlanExercise {
    /// "4 × 5 @ 80 kg", "3 × 10–12 @ RPE 8", "6 × 2 @ 75 % 1RM".
    var targetText: String {
        let base = Fmt.prescription(sets: sets, repsMin: repsMin, repsMax: repsMax)
        guard let v = targetValue else { return targetKind == .bodyweight ? "\(base) · \(TargetKind.bodyweight.title)" : base }
        switch targetKind {
        case .kg: return "\(base) @ \(Fmt.kg(v))"
        case .rpe: return "\(base) @ RPE \(Fmt.kgNumber(v))"
        case .pct1rm: return "\(base) @ \(Fmt.kgNumber(v)) % 1RM"
        case .bodyweight: return "\(base) · BW + \(Fmt.kg(v))"
        }
    }
}

/// "Hypertrophy · 4 days/week · repeating", joined as My Day's and Strain's meta lines (`MyDayText.join`): a plan row
/// (`ActivityListRow`) stands its parts one per line from AX1, and no line ends on a lone "·" before that.
private func planSummaryText(goal: PlanGoal, daysPerWeek: Int, weeks: Int?) -> String {
    let length = weeks.map { String(localized: "\($0) weeks") } ?? String(localized: "repeating")
    return MyDayText.join([goal.title, String(localized: "\(daysPerWeek) days/week"), length])
}

extension PlanSummary {
    var summaryText: String { planSummaryText(goal: goal, daysPerWeek: daysPerWeek, weeks: weeks) }
}

extension Plan {
    var summaryText: String { planSummaryText(goal: goal, daysPerWeek: daysPerWeek, weeks: weeks) }

    static func blank() -> Plan {
        Plan(name: "", goal: .general, weeks: nil, daysPerWeek: 3, description: "", progression: .linear,
             isBuiltin: false, days: [PlanDay(dayIndex: 0, name: String(localized: "Day A"), exercises: [])])
    }

    /// An editable copy with fresh ids (for "Copy and edit" on a built-in).
    func copy() -> Plan {
        Plan(name: String(localized: "\(name) (copy)"), goal: goal, weeks: weeks, daysPerWeek: daysPerWeek,
             description: description, progression: progression, isBuiltin: false,
             days: days.map { d in
                 PlanDay(week: d.week, dayIndex: d.dayIndex, name: d.name, exercises: d.exercises.map { e in
                     PlanExercise(exercise: e.exercise, position: e.position, sets: e.sets, repsMin: e.repsMin,
                                  repsMax: e.repsMax, targetKind: e.targetKind, targetValue: e.targetValue,
                                  restSec: e.restSec, supersetGroup: e.supersetGroup, notes: e.notes)
                 })
             })
    }
}

/// Plans' and a plan page's numbers (PR 6 B §6.1, §6.2; `b-10`, `b-25`, `b-11`).
enum PlansLayout {
    /// The header → the first block.
    nonisolated static let headerGap: CGFloat = 20
    /// Between the sections (the tile, Built-in, My plans, New plan): the grouped list's 18.
    nonisolated static let sectionSpacing = GroupedListSpec.groupSpacing
    /// Between the plan rows, and the group title → its first row.
    nonisolated static let rowSpacing: CGFloat = 8
    /// The plan tile: 176 high at least, radius 28 (the glow panel's), its head → the name 8, the name → "Next" 2, the text →
    /// the pill 14. The paused outline: 1 pt ink at 16 %.
    nonisolated static let tileMinHeight: CGFloat = 176, tileRadius: CGFloat = 28
    nonisolated static let tileNameGap: CGFloat = 8, tileNextGap: CGFloat = 2, tilePillGap: CGFloat = 14
    nonisolated static let pausedOutlineOpacity = 0.16
    /// Under "New plan" ("Plans you make or copy appear here."), and under the page's last block.
    nonisolated static let footnoteGap: CGFloat = 8, bottomPadding: CGFloat = 32
    /// The plan page: the description → "Progression · …" 6, the text → the first pill 16, the pills 12 apart, the pills →
    /// the first day 20, the days 12 apart.
    nonisolated static let progressionGap: CGFloat = 6, actionsGap: CGFloat = 16, pillSpacing: CGFloat = 12
    nonisolated static let daysGap: CGFloat = 20, daySpacing: CGFloat = 12
    /// A day card: its head row at least 40 high, an exercise row 10 above and below its text, the Start pill 12 under the last
    /// row and 16 above the card's edge.
    nonisolated static let dayHeadHeight: CGFloat = 40, exerciseRowPadding: CGFloat = 10
    nonisolated static let startTopGap: CGFloat = 12, startBottomGap: CGFloat = 16
    /// A superset member's `link` glyph: 12 pt at 62 % before the name.
    nonisolated static let supersetGlyph: CGFloat = 12
    /// The plan page's day placeholders while the detail loads.
    nonisolated static let dayPlaceholderHeight: CGFloat = 180
}

/// Built-in templates, the user's plans and the active (or paused) enrolment.
struct PlansView: View {
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        PlansScreen(model: PlansViewModel(library: library))
    }
}

/// The pushed page (PR 6 B §6.1): Back and "Plans", the import rows (area C's), the active plan as the screen's one glow tile
/// or the paused plan as an outline, the built-in plans and the user's own, and New plan. Layout only; the first model handed
/// in is kept for the screen's lifetime.
private struct PlansScreen: View {
    @State var model: PlansViewModel
    @State private var editing: Plan?
    @Environment(ScreenModels.self) private var screens

    private var importer: ImportCoordinator { screens.importer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PushedHeader(Text("Plans"), identifierPrefix: "plans")
                VStack(alignment: .leading, spacing: PlansLayout.sectionSpacing) {
                    if importer.isEnabled { importRows }
                    if let tile = model.tile {
                        PlanTile(content: tile, working: model.working) { Task { await model.togglePause() } }
                    }
                    if let error = model.error {
                        InlineMessage(message: error, details: model.errorDetails, retry: { await model.refresh() })
                    }
                    if model.isLoading {
                        placeholders
                    } else if model.isOffline {
                        offline
                    } else {
                        section(Text("Built-in"), rows: model.builtinRows)
                        section(Text("My plans"), rows: model.mineRows)
                    }
                    newPlanBlock
                }
                .padding(.top, PlansLayout.headerGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, PlansLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
        .sheet(item: $editing) { PlanBuilderView(plan: $0).presentedRoot() }
    }

    /// New plan, and under it, once the plans are known and none is the user's own, where they will appear.
    private var newPlanBlock: some View {
        VStack(alignment: .leading, spacing: PlansLayout.footnoteGap) {
            newPlan
            if model.hasCatalog, model.mine.isEmpty {
                Text("Plans you make or copy appear here.",
                     comment: "Plans, under New plan while the user has no plans of their own.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// `train.import` off: the button. On: a menu, Start from scratch or Import from file (ui.md §3.1), drawn as the same
    /// secondary pill.
    @ViewBuilder
    private var newPlan: some View {
        if importer.isEnabled {
            Menu {
                Button {
                    editing = .blank()
                } label: {
                    Label(String(localized: "Start from scratch", comment: "My Plans → New plan: the plan builder."),
                          systemImage: "square.and.pencil")
                }
                Button {
                    importer.start()
                } label: {
                    Label(String(localized: "Import from file", comment: "My Plans → New plan: the training import."),
                          systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("plans.import")
            } label: {
                // The pill's look; the menu is the button.
                PillButton(Text("New plan"), style: .secondary) {}
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .menuStyle(.button)
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("New plan"))
            .accessibilityIdentifier("plans.newPlan")
        } else {
            PillButton(Text("New plan"), style: .secondary) { editing = .blank() }
                .accessibilityIdentifier("plans.newPlan")
        }
    }

    /// The import job (E3) and a file waiting to be opened (E7, E9), above the active plan.
    @ViewBuilder
    private var importRows: some View {
        if importer.showsResumeRow, let status = importer.uploader.status {
            ImportResumeRow(status: status, open: { importer.resume() },
                            dismiss: status.isFinished && !status.hasRejected ? { importer.dismissFinished() } : nil)
        }
        if let name = importer.waitingFileName, let reason = importer.waitingFor {
            ImportWaitingFileRow(name: name, reason: reason, canOpen: importer.canOpenWaitingFile,
                                 open: { Task { await importer.openWaitingFile() } }, viewProgress: { importer.resume() })
        }
    }

    /// The first load with nothing cached: three outline rows; VoiceOver hears it once.
    private var placeholders: some View {
        VStack(spacing: PlansLayout.rowSpacing) {
            ForEach(0..<3, id: \.self) { _ in ActivityListRowPlaceholder() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading plans", comment: "VoiceOver: Plans' outline rows while the plans load the first time."))
        .accessibilityIdentifier("plans.loading")
    }

    /// Nothing cached and no load running (offline, or the reads wait to retry): a calm line instead of outlines that
    /// would never fill. Try again, or pull, loads again.
    private var offline: some View {
        InlineMessage(message: String(localized: "Plans appear once you're online.",
                                      comment: "Plans, with no plans saved on this iPhone and no connection to load them."),
                      systemImage: "wifi.slash", retry: { await model.refresh() }, identifier: "plans.offline",
                      announces: false)
    }

    @ViewBuilder
    private func section(_ title: Text, rows: [PlanRowContent]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: PlansLayout.rowSpacing) {
                GroupTitle(title)
                ForEach(rows) { row in
                    NavigationLink(value: TrainRoute.plan(row.id)) {
                        ActivityListRow(content: row.row, accessory: .chevron)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint(Text("Opens the plan", comment: "VoiceOver hint of a plan's row or tile on Plans."))
                }
            }
        }
    }
}

/// The plan the user is on (F18): active, the strain-glow tile (the screen's one glow: a training object, its hero); paused,
/// the same layout in a 1 pt outline ("not now"). The text opens the plan; the pill pauses or resumes.
private struct PlanTile: View {
    let content: PlanTileContent
    let working: Bool
    let toggle: () -> Void

    var body: some View {
        switch content.state {
        case .active:
            GlowTile(Theme.metricStrain, kind: .panel, minHeight: PlansLayout.tileMinHeight) { inner }
        case .paused:
            let shape = RoundedRectangle(cornerRadius: PlansLayout.tileRadius, style: .continuous)
            inner
                .padding(GlowTileSpec.padding(for: .panel))
                .frame(maxWidth: .infinity, minHeight: PlansLayout.tileMinHeight, alignment: .topLeading)
                .overlay {
                    shape.strokeBorder(Theme.textPrimary.opacity(PlansLayout.pausedOutlineOpacity),
                                       lineWidth: Theme.Metrics.hairline)
                }
                .accessibilityElement(children: .contain)
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: TrainRoute.plan(content.planID)) { text }
                .buttonStyle(PressableButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: content.spoken))
                .accessibilityHint(Text("Opens the plan", comment: "VoiceOver hint of a plan's row or tile on Plans."))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("plans.current")
            pill
                .padding(.top, PlansLayout.tilePillGap)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                quiet(Text(verbatim: content.stateText), style: .label)
                Spacer(minLength: 0)
                if let week = content.weekText {
                    quiet(Text(verbatim: week), style: .caption)
                        .monospacedDigit()
                }
            }
            Text(verbatim: content.name)
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PlansLayout.tileNameGap)
            if let next = content.nextText {
                quiet(Text(verbatim: next), style: .label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PlansLayout.tileNextGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The tile's small words: the glow label's ink in the glow tile, `textSecondary` in the paused outline.
    @ViewBuilder
    private func quiet(_ text: Text, style: RyftTextStyle) -> some View {
        switch content.state {
        case .active: text.ryftGlowLabelStyle(style)
        case .paused: text.font(.ryft(style)).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var pill: some View {
        switch content.state {
        case .active:
            PillButton(Text("Pause"), style: .secondary, busy: working, action: toggle)
                .accessibilityIdentifier("plans.pause")
        case .paused:
            PillButton(Text("Resume"), systemImage: PillButton.Icon.start, busy: working, action: toggle)
                .accessibilityIdentifier("plans.resume")
        }
    }
}

/// A plan's weeks → days → exercises, and enrol / switch / pause.
struct PlanDetailView: View {
    let planID: UUID
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        PlanDetailScreen(model: PlanDetailViewModel(planID: planID, library: library))
    }
}

/// What the plan page loads for: the plan, and again when the iPhone goes online (or offline, which ends at once).
private struct PlanLoadKey: Equatable {
    let plan: UUID
    let online: Bool
}

/// The pushed page (PR 6 B §6.2, `b-11`): Back, the plan's name over its summary; the description and its progression; the
/// one primary action (Switch to / Start this plan, or Resume) or the active plan's week with Pause; Copy and edit (built-in)
/// or Edit (mine); the weeks; a card per day with its exercises and its own Start; Delete at the end of the user's own.
/// Layout only; the first model handed in is kept for the screen's lifetime.
private struct PlanDetailScreen: View {
    @State var model: PlanDetailViewModel
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.appEnvironment) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Plan?
    @State private var confirmSwitch = false
    @State private var confirmDelete = false

    private var plan: Plan? { model.plan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let plan {
                    about(plan)
                        .padding(.top, PlansLayout.headerGap)
                    actions(plan)
                        .padding(.top, PlansLayout.actionsGap)
                    if model.weeks.count > 1 {
                        SegmentedPicker(selection: Bindable(model).week, options: model.weeks) {
                            String(localized: "Week \($0)")
                        }
                        .padding(.top, PlansLayout.daysGap)
                    }
                    VStack(spacing: PlansLayout.daySpacing) {
                        ForEach(model.shownDays) { dayCard($0) }
                    }
                    .padding(.top, PlansLayout.daysGap)
                    if !plan.isBuiltin {
                        PillButton(Text("Delete plan"), style: .destructive) { confirmDelete = true }
                            .disabled(model.working)
                            .accessibilityIdentifier("plan.delete")
                            .padding(.top, PlansLayout.daysGap)
                    }
                } else if let failure = model.failure {
                    InlineMessage(message: failure, details: model.errorDetails, retry: { await model.load(userInitiated: true) },
                                  identifier: "plan.loadError")
                        .padding(.top, PlansLayout.headerGap)
                } else if model.isOffline {
                    // Not cached and nothing could be sent: Plans' calm line, not outlines that would never fill.
                    InlineMessage(message: String(localized: "Plans appear once you're online.",
                                                  comment: "Plans, with no plans saved on this iPhone and no connection to load them."),
                                  systemImage: "wifi.slash", retry: { await model.load(userInitiated: true) },
                                  identifier: "plan.offline", announces: false)
                        .padding(.top, PlansLayout.headerGap)
                } else {
                    loading
                        .padding(.top, PlansLayout.headerGap)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, PlansLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .task(id: PlanLoadKey(plan: model.planID, online: env.connectivity.isOnline)) { await model.load() }
        .sheet(item: $editing, onDismiss: { Task { await model.load() } }) {
            PlanBuilderView(plan: $0).presentedRoot()
        }
        .confirmationDialog("Switch to \(plan?.name ?? "")?", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("Switch plan") { Task { await model.enroll() } }
        } message: {
            Text("\(model.currentPlanName) is paused; this one starts at week 1. Logged workouts stay.")
        }
        .confirmationDialog("Delete \(plan?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) {
                Task {
                    if await model.delete() { dismiss() }
                }
            }
        } message: {
            Text("Logged workouts stay.")
        }
    }

    /// Back · the name over "Strength · 3 days/week · 12 weeks" (VoiceOver: "Strength, 3 days a week, 12 weeks").
    private var header: some View {
        PushedHeader(Text(verbatim: model.name ?? ""),
                     subtitle: plan.map { Text(verbatim: $0.summaryText) },
                     spokenSubtitle: plan.map { Text(verbatim: PlanSpeech.summary(goal: $0.goal, daysPerWeek: $0.daysPerWeek,
                                                                                  weeks: $0.weeks)) },
                     identifierPrefix: "plan")
    }

    /// The description, and "Progression · Linear +2.5 kg" 6 under it.
    private func about(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: PlansLayout.progressionGap) {
            if !p.description.isEmpty {
                Text(verbatim: p.description)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Progression · \(p.progressionType.title)",
                 comment: "A plan's page, under its description: how the weights move (\"Progression · Linear +2.5 kg\").")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: PlansLayout.pillSpacing) {
            if model.isCurrent {
                if model.isPaused {
                    PillButton(Text("Resume plan"), systemImage: PillButton.Icon.start, busy: model.working) {
                        Task { await model.togglePause() }
                    }
                    .accessibilityIdentifier("plan.togglePause")
                } else {
                    if let week = model.activeWeek {
                        Text("Active · week \(week)",
                             comment: "A plan's page, the plan the user is on: its state and week (\"Active · week 6\").")
                            .ryftLabelStyle()
                            .monospacedDigit()
                    }
                    PillButton(Text("Pause plan"), style: .secondary, busy: model.working) {
                        Task { await model.togglePause() }
                    }
                    .accessibilityIdentifier("plan.togglePause")
                }
            } else {
                PillButton(model.hasEnrollment ? Text("Switch to this plan") : Text("Start this plan"),
                           systemImage: PillButton.Icon.forward, busy: model.working) {
                    if model.hasEnrollment { confirmSwitch = true } else { Task { await model.enroll() } }
                }
                .accessibilityIdentifier("plan.enroll")
            }
            // While enrolling, pausing or resuming, that pill is busy (it ignores taps itself); the others are off.
            Group {
                if p.isBuiltin {
                    PillButton(Text("Copy and edit"), style: .secondary) { editing = p.copy() }
                        .accessibilityIdentifier("plan.copy")
                } else {
                    PillButton(Text("Edit"), style: .secondary) { editing = p }
                        .accessibilityIdentifier("plan.edit")
                }
            }
            .disabled(model.working)
            if let error = model.error {
                InlineMessage(message: error, details: model.errorDetails)
            }
        }
    }

    /// While the detail loads (not cached): two day cards' outlines; VoiceOver hears it once.
    private var loading: some View {
        VStack(spacing: PlansLayout.daySpacing) {
            ForEach(0..<2, id: \.self) { _ in PlaceholderRow(height: PlansLayout.dayPlaceholderHeight) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading the plan", comment: "VoiceOver: a plan page's outline cards while its days load."))
        .accessibilityIdentifier("plan.loading")
    }

    /// "Day A ~55 min", the exercises between hairlines, and the day's own Start (`b-11`). One container, "Day A, about 55
    /// minutes".
    private func dayCard(_ day: PlanDay) -> some View {
        let minutes = SessionEstimate.minutes(for: day.exercises)
        return GroupedCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: day.name)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(verbatim: String(localized: "~\(minutes) min"))
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, PlansLayout.exerciseRowPadding)
            .frame(maxWidth: .infinity, minHeight: PlansLayout.dayHeadHeight, alignment: .leading)
            ForEach(day.exercises.sorted { $0.position < $1.position }) { exerciseRow($0) }
            PillButton(Text("Start \(day.name)"), style: .secondary) { coordinator.start(day: day) }
                .disabled(coordinator.active != nil)
                .accessibilityIdentifier("plan.startDay.\(day.dayIndex)")
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.top, PlansLayout.startTopGap - PlansLayout.exerciseRowPadding)
                .padding(.bottom, PlansLayout.startBottomGap)
        }
        .accessibilityLabel(Text(verbatim: PlanSpeech.day(day.name, minutes: minutes)))
    }

    /// "Back squat" over "5 × 5 @ 100 kg · rest 3:00"; a superset member has `link` before its name.
    private func exerciseRow(_ e: PlanExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if e.supersetGroup != nil {
                Image(systemName: "link")
                    .font(.system(size: PlansLayout.supersetGlyph, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text(verbatim: e.exercise.name)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(e.targetText) · rest \(Fmt.clock(TimeInterval(e.restSec)))")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                if !e.notes.isEmpty {
                    Text(verbatim: e.notes)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, PlansLayout.exerciseRowPadding)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PlanSpeech.exercise(e)))
    }
}

// MARK: - previews (dark only)

@MainActor
private enum PlansPreview {
    /// A library whose cached overview is `catalog`, restored as the app restores it (the paused plan's outline, no plans of
    /// the user's own).
    static func library(_ catalog: PlansOverview) -> TrainLibrary {
        let store = TrainStore(inMemory: true)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        store.saveDocument(catalog, key: "train.plans")
        if catalog.active?.status == .active { store.saveDocument(MockTrain.planToday, key: "train.today") }
        let outbox = TrainSyncService.preview(store: store)
        return TrainLibrary(store: store, remote: { MockTrainSource.shared }, outbox: { outbox }, restore: true)
    }

    /// Paused as the platform reports it: no enrolment in `GET /v1/plans`, the plan remembered on this iPhone.
    static func pausedLibrary() -> TrainLibrary {
        UserDefaults.standard.set(MockTrain.upperLower.id.uuidString, forKey: "train.pausedPlanID")
        return library(MockTrain.catalog(enrolled: false, mine: false))
    }
}

#Preview("Plans · active") {
    NavigationStack { PlansView().trainDestinations() }
        .previewEnvironment()
}

#Preview("Plans · paused, no plans of your own") {
    // Inside `previewEnvironment`: the nearer library wins.
    NavigationStack { PlansView().trainDestinations() }
        .environment(PlansPreview.pausedLibrary())
        .previewEnvironment()
}

#Preview("Plans · import menu") {
    NavigationStack { PlansView().trainDestinations() }
        .previewEnvironment(AppState.preview(flags: [.trainImport: true]))
}

#Preview("Plans · AX3") {
    NavigationStack { PlansView().trainDestinations() }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Plan detail · built-in") {
    NavigationStack { PlanDetailView(planID: MockTrain.fullBody.id) }
        .previewEnvironment()
}

#Preview("Plan detail · active") {
    NavigationStack { PlanDetailView(planID: MockTrain.upperLower.id) }
        .previewEnvironment()
}

#Preview("Plan detail · weeks") {
    NavigationStack { PlanDetailView(planID: MockTrain.weightlifting.id) }
        .previewEnvironment()
}

#Preview("Plan detail · mine, AX3") {
    NavigationStack { PlanDetailView(planID: MockTrain.homeDumbbells.id) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
