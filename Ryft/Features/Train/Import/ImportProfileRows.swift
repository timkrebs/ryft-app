import SwiftUI

/// Profile → Data's import rows (ui.md §3.2; PR 6 C §4.14, c-16): "Import training data" (behind `train.import`; it opens
/// step 1, or step 6 while a job exists) and "Clear remembered matches" (only while this account has some). Between Devices
/// and Export: data moving in and out. Drawn as the grouped list's rows (`GroupedRowLabel`'s type and accessories): Profile
/// gives each one its side inset, its height and its hairline, so a row here has none of its own.
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
                    row(title: String(localized: "Import training data", comment: "Training import: the flow's title, and Profile → Data's row."),
                        detail: ImportResumeText.profileDetail(importer.uploader.status), accessory: "chevron.right")
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
                    row(title: String(localized: "Clear remembered matches", comment: "Profile → Data: forget the import's exercise matches."),
                        detail: String(localized: "RYFT forgets how it matched imported exercises.",
                                       comment: "Profile → Data: under Clear remembered matches."),
                        accessory: "eraser")
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

    /// A push row (the chevron at 35 % ink) or an action row (its glyph at 55 %): the title 15 pt, the detail 12 pt
    /// `textTertiary` under it, 10 above and below.
    private func row(title: String, detail: String, accessory: String) -> some View {
        let isChevron = accessory == "chevron.right"
        return HStack(alignment: .center, spacing: GroupedListSpec.rowSpacing) {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: detail)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: accessory)
                .font(.system(size: isChevron ? GroupedListSpec.chevronSize : GroupedListSpec.glyphSize,
                              weight: isChevron ? .semibold : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(isChevron ? GroupedListSpec.accessoryOpacity : GroupedListSpec.actionGlyphOpacity))
                .accessibilityHidden(true)
        }
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(minHeight: GroupedListSpec.rowMinHeight)
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
