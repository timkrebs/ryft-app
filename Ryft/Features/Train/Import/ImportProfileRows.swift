import SwiftUI

/// Profile → Data's import rows (ui.md §3.2): "Import training data" (behind `train.import`; it opens step 1, or step 6
/// while a job exists) and "Clear remembered matches" (only while this account has some). Between Devices and Export:
/// data moving in and out.
struct ImportProfileRows: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @State private var hasMatches = false
    @State private var confirmsClear = false

    private var importer: ImportCoordinator { screens.importer }

    var body: some View {
        Group {
            if importer.isEnabled {
                Button {
                    if importer.showsResumeRow { importer.resume() } else { importer.start() }
                } label: {
                    row(systemImage: "square.and.arrow.down",
                        title: String(localized: "Import training data", comment: "Training import: the flow's title, and Profile → Data's row."),
                        detail: ImportResumeText.profileDetail(importer.uploader.status))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.importTraining")
                if let name = importer.waitingFileName, let reason = importer.waitingFor {
                    ImportWaitingFileRow(name: name, reason: reason, canOpen: importer.canOpenWaitingFile,
                                         open: { Task { await importer.openWaitingFile() } }, viewProgress: { importer.resume() })
                }
            }
            if hasMatches {
                Button {
                    confirmsClear = true
                } label: {
                    row(systemImage: "eraser",
                        title: String(localized: "Clear remembered matches", comment: "Profile → Data: forget the import's exercise matches."),
                        detail: String(localized: "RYFT forgets how it matched imported exercises.",
                                       comment: "Profile → Data: under Clear remembered matches."),
                        chevron: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.clearMatches")
            }
        }
        // The binding the store reads: the account, or demo's own.
        .task(id: env.isDemo ? ImportMappingStore.demoAccount : env.auth.accountID) {
            hasMatches = ImportMappingStore(env: env).hasEntries
        }
        .alert(Text("Clear remembered matches?", comment: "Profile → Data: the confirmation's title."),
               isPresented: $confirmsClear) {
            Button(role: .destructive) {
                ImportMappingStore(env: env).clear()
                hasMatches = false
                AccessibilityNotification.Announcement(String(localized: "Remembered matches cleared",
                                                              comment: "VoiceOver: the import's matches were cleared.")).post()
            } label: {
                Text("Clear")
            }
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("Your next import asks about every exercise again. Imported workouts and plans stay as they are.",
                 comment: "Profile → Data: what clearing the remembered matches does.")
        }
    }

    private func row(systemImage: String, title: String, detail: String, chevron: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: detail)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile import rows · dark", traits: .sizeThatFitsLayout) {
    Card { VStack(alignment: .leading, spacing: 14) { ImportProfileRows() } }
        .padding()
        .previewEnvironment(AppState.preview(flags: [.trainImport: true]))
}

#Preview("Profile import rows · light", traits: .sizeThatFitsLayout) {
    Card { VStack(alignment: .leading, spacing: 14) { ImportProfileRows() } }
        .padding()
        .previewEnvironment(AppState.preview(flags: [.trainImport: true]), scheme: .light)
}
