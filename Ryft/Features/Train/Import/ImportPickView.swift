import SwiftUI

/// Step 1 (ui.md §4): choose the plans file, the workouts file or both. Nothing is parsed before the files are read,
/// and the files are never uploaded or stored.
struct ImportPickView: View {
    let model: ImportFlowModel

    var body: some View {
        ImportStepScaffold(model: model, step: .pick) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Import a plan and your workout history", comment: "Training import, step 1: the headline.")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose the CSV files exported from Alpha Progression: the plans file, the workouts file, or both. RYFT reads them on this iPhone. The files themselves are never uploaded or stored.",
                     comment: "Training import, step 1. Alpha Progression is a data source, named factually.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            slots
            messages
        } bottom: {
            ImportPrimaryButton(title: String(localized: "Choose files", comment: "Training import, step 1: opens the file picker."),
                                identifier: "import.choose") {
                model.chooseFiles()
            }
            ImportBarCaption(text: String(localized: "Save the files from the other app to Files, then choose them here.",
                                          comment: "Training import, step 1: under Choose files."),
                             tertiary: true)
        }
    }

    /// Two hint slots (either opens the same picker; the content decides what a file is), or a row per file being read.
    @ViewBuilder
    private var slots: some View {
        VStack(spacing: 10) {
            if model.isReading {
                ForEach(model.files) { file in
                    ImportFileSlot(state: .reading(name: file.name, progress: nil))
                }
            } else {
                Button {
                    model.chooseFiles()
                } label: {
                    ImportFileSlot(state: .empty(title: String(localized: "Plans file", comment: "Training import, step 1: a slot."),
                                                 systemImage: "list.bullet.rectangle"))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(.isButton)
                Button {
                    model.chooseFiles()
                } label: {
                    ImportFileSlot(state: .empty(title: String(localized: "Workouts file", comment: "Training import, step 1: a slot."),
                                                 systemImage: "clock.arrow.circlepath"))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    /// P3 to P7: every file that couldn't be read, with its one action.
    @ViewBuilder
    private var messages: some View {
        if model.tooManyFiles {
            InlineMessage(message: String(localized: "Choose up to 6 files at a time.", comment: "Training import P7."),
                          systemImage: "doc.on.doc",
                          retryTitle: LocalizedStringKey(String(localized: "Choose files", comment: "Training import, step 1: opens the file picker.")),
                          retry: { model.chooseFiles() }, identifier: "import.tooMany")
        }
        ForEach(model.pickProblems) { file in
            if let problem = file.problem {
                let message = problem.message(name: file.name)
                InlineMessage(message: message.text, systemImage: message.systemImage,
                              retryTitle: LocalizedStringKey(message.retry), retry: { model.chooseFiles() },
                              caption: message.caption, identifier: "import.problem")
            }
        }
    }
}

#Preview("Step 1 · empty · dark") {
    NavigationStack { ImportPickView(model: ImportMockData.flow(.pick)) }
        .previewEnvironment()
}

#Preview("Step 1 · empty · light · AX3") {
    NavigationStack { ImportPickView(model: ImportMockData.flow(.pick)) }
        .previewEnvironment(scheme: .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Step 1 · reading 2 files · dark") {
    NavigationStack {
        ImportPickView(model: ImportMockData.flow(.pick, files: [
            ImportPickedFile(id: 0, name: "Upper-Lower_Plans.csv", status: .reading),
            ImportPickedFile(id: 1, name: "Upper-Lower_Workouts.csv", status: .reading),
        ]))
    }
    .previewEnvironment()
}

#Preview("Step 1 · P3 to P6 · light") {
    NavigationStack {
        ImportPickView(model: ImportMockData.flow(.pick, files: [
            ImportPickedFile(id: 0, name: "photo.heic", status: .failed(.notCSV)),
            ImportPickedFile(id: 1, name: "backup.csv", status: .failed(.tooLarge)),
            ImportPickedFile(id: 2, name: "Workouts.csv", status: .failed(.unreadable)),
            ImportPickedFile(id: 3, name: "blank.csv", status: .failed(.empty)),
        ]))
    }
    .previewEnvironment(scheme: .light)
}

#Preview("Step 1 · too many files · dark") {
    NavigationStack { ImportPickView(model: ImportMockData.flow(.pick) { $0.tooManyFiles = true }) }
        .previewEnvironment()
}
