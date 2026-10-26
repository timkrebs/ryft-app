import SwiftUI

/// Step 5 (ui.md §8.1): exactly what will be created, what is skipped and why, what looks like a duplicate, and the
/// one side effect (past strain is recalculated once). The last stop before anything leaves the iPhone.
struct ImportPreviewView: View {
    @Bindable var model: ImportFlowModel

    @State private var detail: ImportSessionPreview?
    /// "Review": only the workouts that look like ones already logged.
    @State private var onlyDuplicates = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ImportStepScaffold(model: model, step: .preview) {
            switch model.buildState {
            case .building:
                building
            case .failed:
                InlineMessage(message: String(localized: "RYFT couldn't prepare the preview.", comment: "Training import, step 5: the build failed."),
                              systemImage: "exclamationmark.circle", retry: { await model.prepareBuild() })
            case .ready:
                if let build = model.build, let totals = model.totals { content(build, totals) }
            }
        } bottom: {
            bottomBar
        }
        .sheet(item: $detail) { preview in
            ImportSessionDetailSheet(preview: preview, names: exerciseNames, zone: model.deps.zone)
        }
    }

    // MARK: States

    /// Outline rows while the build runs: no spinner.
    private var building: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline)
                    .frame(height: 56)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ build: ImportBuild, _ totals: ImportTotals) -> some View {
        summary(build, totals)
        let hasPlan = build.plans.contains { $0.willBeSent || $0.state == .cannotImport(.noExercises) }
        let hasHistory = build.sessions.contains { listed($0) }
        if hasPlan, hasHistory { segments }
        if hasPlan, !hasHistory || model.previewSegment == .plan {
            ForEach(build.plans.filter { $0.willBeSent || $0.state == .cannotImport(.noExercises) }) { plan in
                planSection(plan, build: build)
            }
        }
        if hasHistory, !hasPlan || model.previewSegment == .history {
            history(build, totals)
        }
        Text("Imported workouts count towards strain on their days, so past strain can change once. You won't get record notifications for them. RYFT sends only what's listed here. The file stays on your iPhone.",
             comment: "Training import, step 5: the footer.")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Numbers first (V1), or why nothing would be sent (V3, V4).
    @ViewBuilder
    private func summary(_ build: ImportBuild, _ totals: ImportTotals) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isAlreadyImported {
                Text("This file is already in RYFT. Nothing new to import.", comment: "Training import V4.")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if totals.isNothing {
                Text("Nothing to import", comment: "Training import V3.")
                    .font(.ryft(.metric))
                    .foregroundStyle(Theme.textPrimary)
                Text("All workouts are skipped or already imported.", comment: "Training import V3: the reason.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: ImportPreviewSummary.totals(totals))
                    .font(.ryft(.metric))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subline = ImportPreviewSummary.subline(totals, duplicatesChecked: build.duplicatesChecked) {
                    Text(verbatim: subline)
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.previewSummary")
    }

    @ViewBuilder
    private var segments: some View {
        let title: (ImportFlowModel.PreviewSegment) -> String = {
            $0 == .plan ? String(localized: "Plan", comment: "Training import, step 3: the plan toggle.")
                : String(localized: "History")
        }
        if typeSize.isAccessibilitySize {
            Picker(selection: $model.previewSegment) {
                Text(verbatim: title(.plan)).tag(ImportFlowModel.PreviewSegment.plan)
                Text(verbatim: title(.history)).tag(ImportFlowModel.PreviewSegment.history)
            } label: {
                Text(verbatim: title(model.previewSegment))
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        } else {
            SegmentedPicker(selection: $model.previewSegment, options: [.plan, .history], title: title)
        }
    }

    // MARK: Plan

    private func planSection(_ preview: ImportPlanPreview, build: ImportBuild) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TextField(text: Binding(get: { model.planName(preview) }, set: { model.setPlanName($0, for: preview) })) {
                    Text("Plan name")
                }
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(Text("Plan name"))
                .accessibilityIdentifier("import.planName")
                if preview.willBeSent, model.planName(preview).trimmingCharacters(in: .whitespaces).isEmpty {
                    ImportNoteLine(systemImage: "exclamationmark.circle",
                                   text: String(localized: "Give the plan a name."))
                }
                if let plan = preview.plan {
                    Text(verbatim: ImportPreviewSummary.planSummary(plan))
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if preview.state == .cannotImport(.noExercises) {
                ImportNoteLine(systemImage: "exclamationmark.circle",
                               text: String(localized: "The plan has no exercises left.", comment: "Training import, step 5."))
            }
            ForEach(preview.plan?.days ?? []) { day in
                dayCard(day, preview: preview, zone: build.zone)
            }
            if !preview.skippedExerciseNames.isEmpty {
                Text(verbatim: String(localized: "Not imported (\(preview.skippedExerciseNames.count)): \(preview.skippedExerciseNames.joined(separator: ", "))",
                                      comment: "Training import, step 5: plan exercises left out in step 4; their count and names."))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !preview.lastTime.isEmpty {
                Text("Last time comes from your imported workouts.", comment: "Training import, step 5: the help under the plan.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayCard(_ day: PlanDay, preview: ImportPlanPreview, zone: TimeZone) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: day.name)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                if day.exercises.isEmpty {
                    Text("No exercises (all skipped)", comment: "Training import, step 5: a plan day whose exercises were all left out.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(day.exercises.sorted { $0.position < $1.position }) { exercise in
                    let last = preview.lastTime[exercise.id]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: exercise.exercise.name)
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                        Text(verbatim: last == nil ? exercise.targetText : Fmt.prescription(sets: exercise.sets, repsMin: exercise.repsMin,
                                                                                            repsMax: exercise.repsMax))
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        if let last {
                            Text(verbatim: ImportPreviewSummary.lastTime(last, zone: zone))
                                .font(.ryft(.caption))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: History

    /// Rows in the list: what's sent or could be, and what's already in RYFT. The rest is counted.
    private func listed(_ preview: ImportSessionPreview) -> Bool {
        switch preview.verdict {
        case .new, .duplicate, .alreadyImported: true
        case .outsideRange, .inFuture, .empty, .historyOff: false
        }
    }

    @ViewBuilder
    private func history(_ build: ImportBuild, _ totals: ImportTotals) -> some View {
        let duplicates = build.sessions.filter { if case .duplicate = $0.verdict { true } else { false } }.count
        if !build.duplicatesChecked {
            InlineMessage(message: String(localized: "You're offline, so RYFT couldn't check for duplicates yet.",
                                          comment: "Training import, step 5: the duplicate check needs the network."),
                          systemImage: "wifi.exclamationmark",
                          caption: String(localized: "It checks again before uploading. Workouts that look like ones you already logged are skipped and listed on the result screen, where you can import them anyway.",
                                          comment: "Training import, step 5: the offline duplicate check."))
        } else if duplicates > 0 {
            InlineMessage(message: String(localized: "\(duplicates) workouts look like ones you already logged. They're skipped unless you turn them on.",
                                          comment: "Training import V2: the duplicates banner."),
                          systemImage: "rectangle.on.rectangle",
                          action: (onlyDuplicates ? String(localized: "Show all", comment: "Training import, step 5: leave the duplicates filter.")
                                                  : String(localized: "Review"), { onlyDuplicates.toggle() }))
        }
        VStack(alignment: .leading, spacing: 6) {
            ImportNoteLine(systemImage: "clock", text: String(
                localized: "Times are kept as written in the file and shown in \(build.zone.identifier).",
                comment: "Training import, step 5: the zone; its identifier, e.g. Europe/Berlin."))
            if totals.clockChanges > 0 {
                ImportNoteLine(systemImage: "clock.badge.exclamationmark", text: String(
                    localized: "\(totals.clockChanges) workouts fall on a clock change. RYFT used the next valid time for a time that didn't exist and the first for one that occurred twice.",
                    comment: "Training import, step 5: workouts whose start a DST change moved."))
            }
            if totals.inFuture > 0 {
                ImportNoteLine(systemImage: "calendar", text: String(localized: "\(totals.inFuture) workouts in the future left out",
                                                                     comment: "Training import, step 5."))
            }
            if totals.outsideRange > 0 {
                ImportNoteLine(systemImage: "calendar", text: String(localized: "\(totals.outsideRange) workouts are outside your chosen range",
                                                                     comment: "Training import, step 5."))
            }
        }
        let rows = build.sessions.filter(listed).filter { preview in
            guard onlyDuplicates else { return true }
            if case .duplicate = preview.verdict { return true }
            return false
        }
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(months(rows), id: \.title) { month in
                Section {
                    ForEach(month.rows) { preview in
                        ImportSessionRow(preview: preview, isIncluded: model.included.contains(preview.id), index: preview.index,
                                         zone: build.zone, onToggle: { model.setIncluded(preview.id, $0) },
                                         onOpen: { detail = preview })
                        Divider().overlay(Theme.separator)
                    }
                } header: {
                    TrainSectionTitle(title: LocalizedStringKey(month.title))
                        .padding(.vertical, 6)
                        .background(Theme.background)
                }
            }
        }
        if rows.contains(where: { $0.skippedSetCount > 0 }) {
            Text("Skipped sets have no weight or no reps. They are counted, not imported as zero.",
                 comment: "Training import, step 5: the history footer.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Newest first, grouped by month in the flow's zone.
    private func months(_ rows: [ImportSessionPreview]) -> [(title: String, rows: [ImportSessionPreview])] {
        var out: [(title: String, rows: [ImportSessionPreview])] = []
        for preview in rows.sorted(by: { $0.startedAt > $1.startedAt }) {
            let title = ImportPreviewText.month(preview.day, zone: model.deps.zone)
            if out.last?.title == title {
                out[out.count - 1].rows.append(preview)
            } else {
                out.append((title, [preview]))
            }
        }
        return out
    }

    private var exerciseNames: [UUID: String] {
        var names = (model.mapping?.exercises ?? [:]).mapValues(\.name)
        for exercise in model.build?.customExercises ?? [] { names[exercise.id] = exercise.name }
        return names
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottomBar: some View {
        if model.isAlreadyImported {
            ImportPrimaryButton(title: String(localized: "Done"), identifier: "import.done") { model.finish(.close) }
        } else if !model.uploadsAvailable, model.buildState == .ready {
            InlineMessage(message: String(localized: "Uploads aren't available yet.", comment: "Training import V5."),
                          systemImage: "icloud.slash",
                          caption: String(localized: "RYFT can keep this import on your iPhone and upload it when importing is switched on for your account.",
                                          comment: "Training import V5."))
            ImportPrimaryButton(title: String(localized: "Keep on this iPhone", comment: "Training import V5: store the import to upload later."),
                                identifier: "import.keep", isEnabled: model.canImport) {
                Task { await model.startImport() }
            }
        } else {
            if model.startRefused {
                ImportBarCaption(text: String(localized: "An import is in progress. Finish it before starting another.",
                                              comment: "Training import: one import at a time."))
            }
            ImportPrimaryButton(title: model.totals.map(ImportPreviewSummary.importTitle)
                                    ?? String(localized: "Import", comment: "Training import: step 6's title, and step 5's button without counts."),
                                identifier: "import.import", isEnabled: model.canImport) {
                Task { await model.startImport() }
            }
        }
    }
}

/// Step 5's words (ui.md §11): parts with one plural each.
enum ImportPreviewSummary {
    /// "1 plan · 12 workouts · 31 sets · 9,420 kg".
    static func totals(_ totals: ImportTotals) -> String {
        var parts: [String] = []
        if totals.plans > 0 { parts.append(String(localized: "\(totals.plans) plans", comment: "Training import: a count of plans.")) }
        if totals.sessions > 0 {
            parts.append(String(localized: "\(totals.sessions) workouts", comment: "Training import: a count of workouts."))
            parts.append(String(localized: "\(totals.sets) sets", comment: "Training import: a count of sets."))
        }
        if totals.volumeKg > 0 { parts.append(Fmt.volume(totals.volumeKg)) }
        return parts.joined(separator: " · ")
    }

    /// "3 sets skipped · 1 workout looks like one you already logged"; the duplicates part only once checked.
    static func subline(_ totals: ImportTotals, duplicatesChecked: Bool) -> String? {
        var parts: [String] = []
        if totals.skippedSets > 0 {
            parts.append(String(localized: "\(totals.skippedSets) sets skipped", comment: "Training import, step 5: sets with no weight or reps."))
        }
        if duplicatesChecked, totals.duplicatesOff > 0 {
            parts.append(String(localized: "\(totals.duplicatesOff) workouts look like ones you already logged",
                                comment: "Training import, step 5: duplicates left off."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Import 1 plan and 12 workouts".
    static func importTitle(_ totals: ImportTotals) -> String {
        var parts: [String] = []
        if totals.plans > 0 { parts.append(String(localized: "\(totals.plans) plans", comment: "Training import: a count of plans.")) }
        if totals.sessions > 0 {
            parts.append(String(localized: "\(totals.sessions) workouts", comment: "Training import: a count of workouts."))
        }
        guard let first = parts.first else {
            return String(localized: "Import", comment: "Training import: step 6's title, and step 5's button without counts.")
        }
        let what = parts.count > 1
            ? String(localized: "\(first) and \(parts[1])", comment: "Training import: two counts, e.g. 1 plan and 12 workouts.")
            : first
        return String(localized: "Import \(what)", comment: "Training import, step 5: the button, e.g. Import 1 plan and 12 workouts.")
    }

    /// "6 weeks · 2 days/week".
    static func planSummary(_ plan: Plan) -> String {
        var parts: [String] = []
        if let weeks = plan.weeks { parts.append(String(localized: "\(weeks) weeks")) }
        parts.append(String(localized: "\(plan.daysPerWeek) days/week"))
        return parts.joined(separator: " · ")
    }

    /// "Starts at 60 kg · last time, 27 Apr".
    static func lastTime(_ last: ImportLastTime, zone: TimeZone) -> String {
        let day = last.day.date(in: zone).formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
        return String(localized: "Starts at \(Fmt.kg(last.kg)) · last time, \(day)",
                      comment: "Training import, step 5: a plan exercise's first target from the imported history.")
    }
}

#Preview("Step 5 · plan with last time · dark") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow()) }
        .previewEnvironment()
}

#Preview("Step 5 · plan · light · AX3") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow()) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 5 · history with a duplicate · light") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow { $0.previewSegment = .history }) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 5 · history · dark · AX3") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow { $0.previewSegment = .history }) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 5 · offline duplicate check · dark") {
    NavigationStack {
        ImportPreviewView(model: ImportMockData.previewFlow(ImportMockData.build(duplicatesChecked: false)) {
            $0.previewSegment = .history
        })
    }
    .previewEnvironment()
}

#Preview("Step 5 · nothing to import · light") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow(ImportMockData.build(sendsPlan: false)) { $0.included = [] }) }
        .previewEnvironment(scheme: .light)
}

#Preview("Step 5 · already in RYFT · dark") {
    NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow(ImportMockData.build(alreadyImportedAll: true))) }
        .previewEnvironment()
}

#Preview("Step 5 · uploads not available · light") {
    NavigationStack {
        ImportPreviewView(model: ImportMockData.previewFlow(uploader: ImportMockData.uploader(nil, available: false)))
    }
    .previewEnvironment(scheme: .light)
}
