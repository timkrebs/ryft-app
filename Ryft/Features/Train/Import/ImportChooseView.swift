import SwiftUI

/// Step 3 (ui.md §6): the plan or plans, the workout history and its range, and whether an imported plan becomes the
/// active one. Importing never changes someone's training silently: with a plan already active, "make active" starts off.
struct ImportChooseView: View {
    @Bindable var model: ImportFlowModel

    var body: some View {
        ImportStepScaffold(model: model, step: .choose) {
            if let bundle = model.detection.bundle, model.selection != nil {
                if !bundle.plans.isEmpty { planCard(bundle) }
                if !bundle.sessions.isEmpty { historyCard(bundle) }
                if model.selection?.includesHistory == true {
                    Text("Imported workouts count towards strain on their days. Past strain can change once.",
                         comment: "Training import, step 3: the footnote while history is on.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private func planCard(_ bundle: ImportBundle) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bundle.plans.enumerated()), id: \.offset) { index, plan in
                    planRow(index: index, plan: plan, several: bundle.plans.count > 1)
                }
                if let selection = model.selection, !selection.importedPlans.isEmpty {
                    Divider().overlay(Theme.separator)
                    activeChoice(bundle, selection: selection)
                }
            }
        }
    }

    @ViewBuilder
    private func planRow(index: Int, plan: ImportedPlan, several: Bool) -> some View {
        let choice = model.selection?.plans[safe: index]
        let state = choice?.state ?? .importable
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { choice?.isOn ?? false }, set: { model.selection?.setPlan(index, on: $0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: several ? plan.name : String(localized: "Plan", comment: "Training import, step 3: the plan toggle."))
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: ImportChooseText.planSubtitle(plan, includeName: !several))
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .disabled(!state.canImport)
            .accessibilityIdentifier("import.plan.\(index)")
            switch state {
            case .importable:
                EmptyView()
            case .alreadyInRYFT(replace: false):
                ImportNoteLine(systemImage: "checkmark.circle",
                               text: String(localized: "Already in RYFT", comment: "Training import, step 3: the plan exists."))
                ImportTextButton(title: String(localized: "Replace with the file's version",
                                               comment: "Training import, step 3: import the plan over RYFT's copy.")) {
                    model.selection?.replaceExisting(index)
                }
            case .alreadyInRYFT(replace: true):
                ImportNoteLine(systemImage: "arrow.triangle.2.circlepath",
                               text: String(localized: "This replaces your copy, including edits.",
                                            comment: "Training import, step 3: after Replace with the file's version."))
            case let .tooManyDays(days):
                ImportNoteLine(systemImage: "exclamationmark.circle",
                               text: String(localized: "This plan has \(days) days. RYFT plans have at most 7.",
                                            comment: "Training import, step 3: why a plan can't be imported."))
            }
        }
    }

    @ViewBuilder
    private func activeChoice(_ bundle: ImportBundle, selection: ImportSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if bundle.plans.count == 1, let only = selection.importedPlans.first {
                Toggle(isOn: Binding(get: { model.selection?.activePlan == only },
                                     set: { model.selection?.setActive($0 ? only : nil) })) {
                    Text("Make this my active plan", comment: "Training import, step 3: enrol in the imported plan.")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .accessibilityHint(Text(verbatim: activeHelp(on: selection.activePlan != nil)))
                .accessibilityIdentifier("import.makeActive")
            } else {
                Picker(selection: Binding(get: { model.selection?.activePlan ?? -1 },
                                          set: { model.selection?.setActive($0 < 0 ? nil : $0) })) {
                    Text("No plan", comment: "Training import, step 3: no imported plan becomes active.").tag(-1)
                    ForEach(selection.importedPlans, id: \.self) { index in
                        Text(verbatim: bundle.plans[safe: index]?.name ?? "").tag(index)
                    }
                } label: {
                    Text("Active plan", comment: "Training import, step 3: which imported plan becomes active.")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .frame(minHeight: 44)
            }
            Text(verbatim: activeHelp(on: selection.activePlan != nil))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if selection.activePlan != nil {
                Text("Starts today, at week 1.", comment: "Training import, step 3: when an imported plan starts.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
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

    private func historyCard(_ bundle: ImportBundle) -> some View {
        let today = model.today
        let zone = model.deps.zone
        let all = bundle.sessions.filter { $0.start.date <= today }
        let inRange = model.selection?.sessions(in: bundle, today: today, zone: zone) ?? []
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { model.selection?.includesHistory ?? false },
                                     set: { model.selection?.includesHistory = $0 })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workout history", comment: "Training import, step 3: the history toggle.")
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                        Text(verbatim: ImportChooseText.counts(workouts: all.count, sets: ImportSelection.performedSets(in: all)))
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .accessibilityIdentifier("import.history")
                if model.selection?.includesHistory == true, let first = bundle.sessions.map(\.start.date).min(),
                   let last = bundle.sessions.map(\.start.date).max() {
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

#Preview("Step 3 · both on · dark") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose, enrolled: false)) }
        .previewEnvironment()
}

#Preview("Step 3 · existing active plan · light · AX3") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.setActive(0) }) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 3 · history off · light") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.includesHistory = false }) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 3 · empty range · dark") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.preset = .custom
            $0.selection?.from = ImportMockData.day(2026, 4, 28)
        })
    }
    .previewEnvironment()
}

#Preview("Step 3 · nothing selected · light") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.setPlan(0, on: false)
            $0.selection?.includesHistory = false
        })
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 3 · plan already in RYFT · dark") {
    NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose) { $0.selection?.markExisting([true]) }) }
        .previewEnvironment()
}

#Preview("Step 3 · plan with 9 days · light") {
    NavigationStack {
        ImportChooseView(model: ImportMockData.flow(.choose) {
            $0.selection?.plans[0] = ImportSelection.PlanChoice(isOn: false, state: .tooManyDays(9))
            $0.selection?.activePlan = nil
        })
    }
    .previewEnvironment(scheme: .light)
}
