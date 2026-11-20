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
                    ImportProfileRow(systemImage: "square.and.arrow.down",
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
                    ImportProfileRow(systemImage: "eraser",
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
}

/// One of Profile → Data's import rows: the glyph in a column of one width, so every title starts at the same x whatever
/// the glyph ("square.and.arrow.down" is 18 wide, "eraser" 19), the title and its detail 10 from the hairlines
/// above and below as a grouped row's text (`GroupedListSpec.textPadding`), the chevron at the end. Profile gives the row its
/// side inset, its 46 pt height and its hairline (T5.8 N10).
struct ImportProfileRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var chevron = true

    /// The glyph column: wider than either 15 pt glyph, which keeps its size at every text size.
    static let glyphColumn: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.glyphColumn)
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
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile import rows", traits: .sizeThatFitsLayout) {
    // As Profile lays them out: each row 16 in, at least 46 high, with the card's hairline.
    DarkPreview {
        GroupedCard(Text(verbatim: "Data")) {
            ImportProfileRows()
                .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
        }
    }
    .previewEnvironment(AppState.preview(flags: [.trainImport: true]))
}

#Preview("Profile import rows · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        GroupedCard(Text(verbatim: "Data")) {
            ImportProfileRow(systemImage: "square.and.arrow.down", title: "Import training data",
                             detail: "Import finished: 3 workouts")
                .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
            ImportProfileRow(systemImage: "eraser", title: "Clear remembered matches",
                             detail: "RYFT forgets how it matched imported exercises.", chevron: false)
                .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
