import SwiftUI

/// Step 2 (ui.md §5): what RYFT found, before it asks anything. Counts first, then the files and the warnings, then the
/// time zone the file's times will be read in.
struct ImportDetectedView: View {
    @Bindable var model: ImportFlowModel

    private var detection: ImportDetection { model.detection }

    var body: some View {
        ImportStepScaffold(model: model, step: .detected) {
            switch detection.state {
            case .reading:
                VStack(spacing: 10) {
                    ForEach(model.files) { ImportFileSlot(state: $0.slotState) }
                }
            case .detected, .mixedApps:
                detected
            case .nothingInFile:
                InlineMessage(message: String(localized: "The file is valid but has no plan and no workouts.",
                                              comment: "Training import D7."),
                              systemImage: "doc")
                fileList
            case let .notSupported(name):
                unsupported(name: name)
                if model.files.count > 1 { fileList }
            case let .failed(problem, name):
                let message = problem.message(name: name)
                InlineMessage(message: message.text, systemImage: message.systemImage, caption: message.caption)
            }
        } bottom: {
            if detection.canContinue || detection.state == .reading || detection.state == .mixedApps {
                ImportPrimaryButton(title: String(localized: "Continue"),
                                    isEnabled: detection.canContinue) {
                    model.continueFromDetected()
                }
            } else {
                ImportPrimaryButton(title: String(localized: "Choose another file", comment: "Training import: pick a different file."),
                                    identifier: "import.chooseAnother") {
                    model.chooseFiles()
                }
            }
        }
    }

    @ViewBuilder
    private var detected: some View {
        if let summary = detection.summary {
            ImportSummaryCard(summary: summary, zone: model.deps.zone)
        }
        if detection.state == .mixedApps {
            InlineMessage(message: String(localized: "These files come from different apps. Import one at a time.",
                                          comment: "Training import D6: two supported formats."),
                          systemImage: "exclamationmark.circle")
        }
        if detection.isWeak {
            InlineMessage(message: String(localized: "RYFT only partly recognised this file. Some lines weren't recognised; the rest is imported.",
                                          comment: "Training import D8."),
                          systemImage: "questionmark.circle")
        }
        if detection.isPlanOnly {
            InlineMessage(message: String(localized: "No workouts file. Add it if you also want your workout history.",
                                          comment: "Training import D2."),
                          systemImage: "info.circle",
                          action: (String(localized: "Add workouts file", comment: "Training import D2: opens the picker."),
                                   { model.chooseFiles() }))
        }
        if detection.isWorkoutsOnly {
            InlineMessage(message: String(localized: "No plan file. Your workouts import as standalone sessions.",
                                          comment: "Training import D3."),
                          systemImage: "info.circle",
                          action: (String(localized: "Add plan file", comment: "Training import D3: opens the picker."),
                                   { model.chooseFiles() }))
        }
        if detection.showsFileList { fileList }
        if detection.hasWarnings {
            ImportWarningsList(detection: detection, isExpanded: $model.showsWarnings)
        }
        if detection.hasWorkouts {
            ImportNoteLine(systemImage: "clock", text: String(
                localized: "The file has no time zone. RYFT keeps its times as written and applies this iPhone's time zone, \(model.deps.zone.identifier).",
                comment: "Training import, step 2: the zone the file's times are read in; its identifier, e.g. Europe/Berlin."))
        }
    }

    /// D6: one row per file with what it holds or why it failed, a ✕ to remove it, and "Add another file".
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrainSectionTitle(title: LocalizedStringKey(String(localized: "Files", comment: "Training import, step 2: the files section.")))
            ForEach(model.files) { file in
                ImportFileSlot(state: file.slotState) { model.removeFile(file.id) }
            }
            ImportTextButton(title: String(localized: "Add another file", comment: "Training import, step 2: opens the picker."),
                             systemImage: "plus", identifier: "import.addFile") {
                model.chooseFiles()
            }
        }
    }

    /// D5: replaces the card; there is no Continue.
    private func unsupported(name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("This isn't a supported format", comment: "Training import D5: the headline.")
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("import.unsupported")
            let message = ImportFileProblem.notSupported.message(name: name)
            Text(verbatim: message.text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption = message.caption {
                Text(verbatim: caption)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Step 2 · both · dark") {
    NavigationStack { ImportDetectedView(model: ImportMockData.flow(.detected)) }
        .previewEnvironment()
}

#Preview("Step 2 · both · light · AX3") {
    NavigationStack { ImportDetectedView(model: ImportMockData.flow(.detected)) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 2 · plan only · light") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: [ImportMockData.file(0, "Plans.csv", ImportMockData.plans)]))
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 2 · workouts only · dark") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: [ImportMockData.file(0, "Workouts.csv", ImportMockData.workouts)]))
    }
    .previewEnvironment()
}

#Preview("Step 2 · warnings expanded · dark") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: ImportMockData.withWarnings(ImportMockData.bothFiles)) {
            $0.showsWarnings = true
        })
    }
    .previewEnvironment()
}

#Preview("Step 2 · partly recognised · light") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: ImportMockData.withWarnings(
            [ImportMockData.file(0, "Workouts.csv", ImportMockData.workouts, confidence: .weak)])) { $0.showsWarnings = true })
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 2 · not supported · dark") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: [
            ImportPickedFile(id: 0, name: "notes.txt", status: .failed(.notSupported)),
        ]))
    }
    .previewEnvironment()
}

#Preview("Step 2 · mixed · light") {
    NavigationStack {
        ImportDetectedView(model: ImportMockData.flow(.detected, files: ImportMockData.bothFiles + [
            ImportPickedFile(id: 2, name: "notes.txt", status: .failed(.notSupported)),
        ]))
    }
    .previewEnvironment(scheme: .light)
}
