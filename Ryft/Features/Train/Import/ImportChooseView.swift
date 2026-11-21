import SwiftUI

/// Step 3 (ui.md §6): the plan or plans, the workout history and its range, and whether an imported plan becomes the
/// active one. Importing never changes someone's training silently: with a plan already active, "make active" starts off.
/// Look (PR 6 C §4.14): two grouped cards of switch rows; what's off and why is the pinned bar's caption.
struct ImportChooseView: View {
    @Bindable var model: ImportFlowModel

    var body: some View {
        ImportStepScaffold(model: model, step: .choose) {
            if let bundle = model.detection.bundle, let selection = model.selection {
                if !bundle.plans.isEmpty { planGroup(bundle, selection: selection) }
                if !bundle.sessions.isEmpty { historyGroup(bundle) }
            }
        } bottom: {
            if let reason = blockReason { ImportBarCaption(text: reason) }
            ImportPrimaryButton(title: String(localized: "Continue"), isEnabled: model.selectionBlock == nil) {
                model.continueFromChoose()
            }
        }
    }

    private var blockReason: String? {
        switch model.selectionBlock {
        case .nothingSelected:
            String(localized: "Turn on at least one to continue.", comment: "Training import C3: plan and history are off.")
        case .emptyRange:
            String(localized: "Widen the range or turn history off.", comment: "Training import C4: no workout in the range.")
        case nil: nil
        }
    }

    // MARK: Plan

    /// "Plan": a switch per plan (its name over its weeks and days), what an existing copy means, and "Make this my active
    /// plan" (one plan) or the active plan's menu (several). The footer says what making it active replaces.
    private func planGroup(_ bundle: ImportBundle, selection: ImportSelection) -> some View {
        let title = bundle.plans.count > 1 ? Text("Plans") : Text("Plan", comment: "Training import, step 3: the plan toggle.")
        let showsActive = !selection.importedPlans.isEmpty
        return GroupedCard(title, footer: showsActive ? activeFooter(on: selection.activePlan != nil) : nil) {
            ForEach(Array(bundle.plans.enumerated()), id: \.offset) { index, plan in
                planRows(index: index, plan: plan)
            }
            if showsActive { activeChoice(bundle, selection: selection) }
        }
    }

    @ViewBuilder
    private func planRows(index: Int, plan: ImportedPlan) -> some View {
        let choice = model.selection?.plans[safe: index]
        let state = choice?.state ?? .importable
        GroupedRow.toggle(Text(verbatim: plan.name), detail: Text(verbatim: ImportChooseText.planSubtitle(plan, includeName: false)),
                          identifier: "import.plan.\(index)",
                          isOn: Binding(get: { choice?.isOn ?? false }, set: { model.selection?.setPlan(index, on: $0) }))
            .disabled(!state.canImport)
        switch state {
        case .importable:
            EmptyView()
        case .alreadyInRYFT(replace: false):
            ImportCardNote(systemImage: "checkmark.circle",
                           text: String(localized: "Already in RYFT", comment: "Training import, step 3: the plan exists."))
            GroupedRow.action(Text("Replace with the file's version", comment: "Training import, step 3: import the plan over RYFT's copy."),
                              systemImage: "arrow.triangle.2.circlepath", identifier: "import.replace.\(index)") {
                model.selection?.replaceExisting(index)
            }
        case .alreadyInRYFT(replace: true):
            ImportCardNote(systemImage: "arrow.triangle.2.circlepath",
                           text: String(localized: "This replaces your copy, including edits.",
                                        comment: "Training import, step 3: after Replace with the file's version."))
        case let .tooManyDays(days):
            ImportCardNote(systemImage: "exclamationmark.circle",
                           text: String(localized: "This plan has \(days) days. RYFT plans have at most 7.",
                                        comment: "Training import, step 3: why a plan can't be imported."),
                           attention: true)
        }
    }

    @ViewBuilder
    private func activeChoice(_ bundle: ImportBundle, selection: ImportSelection) -> some View {
        if bundle.plans.count == 1, let only = selection.importedPlans.first {
            GroupedRow.toggle(Text("Make this my active plan", comment: "Training import, step 3: enrol in the imported plan."),
                              identifier: "import.makeActive",
                              isOn: Binding(get: { model.selection?.activePlan == only },
                                            set: { model.selection?.setActive($0 ? only : nil) }))
                .accessibilityHint(Text(verbatim: activeHelp(on: selection.activePlan != nil)))
        } else {
            let current = selection.activePlan.flatMap { bundle.plans[safe: $0]?.name }
            GroupedRow.menu(Text("Active plan", comment: "Training import, step 3: which imported plan becomes active."),
                            value: Text(verbatim: current ?? String(localized: "No plan",
                                                                    comment: "Training import, step 3: no imported plan becomes active.")),
                            identifier: "import.activePlan") {
                Picker(selection: Binding(get: { model.selection?.activePlan ?? -1 },
                                          set: { model.selection?.setActive($0 < 0 ? nil : $0) })) {
                    Text("No plan", comment: "Training import, step 3: no imported plan becomes active.").tag(-1)
                    ForEach(selection.importedPlans, id: \.self) { index in
                        Text(verbatim: bundle.plans[safe: index]?.name ?? "").tag(index)
                    }
                } label: {
                    Text("Active plan", comment: "Training import, step 3: which imported plan becomes active.")
                }
            }
        }
    }

    /// C2: what "make active" replaces, or that it can change later; when one will be active, when it starts.
    private func activeFooter(on: Bool) -> Text {
        let help = Text(verbatim: activeHelp(on: on))
        guard on else { return help }
        return help + Text(verbatim: " ") + Text("Starts today, at week 1.", comment: "Training import, step 3: when an imported plan starts.")
    }

    /// C2: what "make active" replaces, or that it can change later.
    private func activeHelp(on: Bool) -> String {
        guard model.hasEnrollment else {
            return String(localized: "You can change this later in Plans.", comment: "Training import, step 3: no plan is active now.")
        }
        if model.currentPlanIsPaused {
            return String(localized: "Your current plan is paused. Making this one active replaces it.",
                          comment: "Training import, step 3: the current plan is paused.")
        }
        guard on, let name = model.currentPlanName else {
            return String(localized: "You can change this later in Plans.", comment: "Training import, step 3: no plan is active now.")
        }
        let week = model.currentWeek ?? 1
        return String(localized: "This replaces your current plan, “\(name)”, which is in week \(week). It stays in My Plans and you can switch back.",
                      comment: "Training import, step 3 (C2): the active plan's name and its current week.")
    }

    // MARK: History

    /// "Workout history": the switch with the file's counts, then the range (a menu row with the result under it, and From
    /// and Until for a custom range). The footer says what history does to strain.
    private func historyGroup(_ bundle: ImportBundle) -> some View {
        let today = model.today
        let zone = model.deps.zone
        let all = bundle.sessions.filter { $0.start.date <= today }
        let inRange = model.selection?.sessions(in: bundle, today: today, zone: zone) ?? []
        let on = model.selection?.includesHistory == true
        let footer = on ? Text("Imported workouts count towards strain on their days. Past strain can change once.",
                               comment: "Training import, step 3: the footnote while history is on.") : nil
        return GroupedCard(nil, footer: footer) {
            GroupedRow.toggle(Text("Workout history", comment: "Training import, step 3: the history toggle."),
                              detail: Text(verbatim: ImportChooseText.counts(workouts: all.count, sets: ImportSelection.performedSets(in: all))),
                              identifier: "import.history",
                              isOn: Binding(get: { model.selection?.includesHistory ?? false },
                                            set: { model.selection?.includesHistory = $0 }))
            if on, let first = bundle.sessions.map(\.start.date).min(), let last = bundle.sessions.map(\.start.date).max() {
                DateRangeControl(
                    preset: Binding(get: { model.selection?.preset ?? .allTime }, set: { model.selection?.preset = $0 }),
                    from: Binding(get: { model.selection?.from ?? first }, set: { model.selection?.from = $0 }),
                    to: Binding(get: { model.selection?.to ?? last }, set: { model.selection?.to = $0 }),
                    limits: first...max(first, min(last, today)), zone: zone,
                    result: ImportChooseText.rangeResult(inRange, zone: zone), isEmpty: inRange.isEmpty)
            }
        }
    }
}

/// Step 3's words (ui.md §11): parts with one plural each, joined with " · ".
enum ImportChooseText {
    /// "Upper/Lower · 6 weeks · 2 days".
    static func planSubtitle(_ plan: ImportedPlan, includeName: Bool) -> String {
        var parts: [String] = includeName ? [plan.name] : []
        if let weeks = plan.weeks { parts.append(String(localized: "\(weeks) weeks")) }
        parts.append(String(localized: "\(plan.days.count) days", comment: "Training import: a count of plan days."))
        return parts.joined(separator: " · ")
    }

    /// "10 workouts · 31 sets".
    static func counts(workouts: Int, sets: Int) -> String {
        [String(localized: "\(workouts) workouts", comment: "Training import: a count of workouts."),
         String(localized: "\(sets) sets", comment: "Training import: a count of sets.")].joined(separator: " · ")
    }

    /// "10 workouts from 2 Mar to 27 Apr 2026", or "0 workouts in this range".
    static func rangeResult(_ sessions: [ImportedSession], zone: TimeZone) -> String {
        guard let first = sessions.map(\.start.date).min(), let last = sessions.map(\.start.date).max() else {
            return String(localized: "0 workouts in this range", comment: "Training import C4.")
        }
        let count = String(localized: "\(sessions.count) workouts", comment: "Training import: a count of workouts.")
        return String(localized: "\(count) from \(ImportDateText.range(first, last, zone: zone))",
                      comment: "Training import, VoiceOver: 12 workouts from 8 June to 5 July 2026.")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview("Step 3 · both on") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose, enrolled: false)) }
        .previewEnvironment()
        .toggleStyle(.ryft)
}

#Preview("Step 3 · existing active plan · AX3") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.setActive(0) }) }
        .previewEnvironment()
        .toggleStyle(.ryft)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 3 · history off") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.includesHistory = false }) }
        .previewEnvironment()
        .toggleStyle(.ryft)
}

#Preview("Step 3 · empty range") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.preset = .custom
            $0.selection?.from = ImportMockData.day(2026, 4, 28)
        })
    }
    .previewEnvironment()
    .toggleStyle(.ryft)
}

#Preview("Step 3 · nothing selected") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.setPlan(0, on: false)
            $0.selection?.includesHistory = false
        })
    }
    .previewEnvironment()
    .toggleStyle(.ryft)
}

#Preview("Step 3 · plan already in RYFT") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.markExisting([true]) }) }
        .previewEnvironment()
        .toggleStyle(.ryft)
}

#Preview("Step 3 · plan with 9 days") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.plans[0] = ImportSelection.PlanChoice(isOn: false, state: .tooManyDays(9))
            $0.selection?.activePlan = nil
        })
    }
    .previewEnvironment()
    .toggleStyle(.ryft)
}
