import SwiftUI

/// A file in the import's first two steps (ui.md §4, §5, §9; PR 6 C §4.14, c-23): step 1's outline slot to choose into
/// ("Plans file · Optional"), or a file being read (a bare 2 pt track under its name, never a spinner). A 1 pt outline at the
/// card's radius, 64 high; the glyph at 55 % ink. At accessibility sizes the text stacks under the glyph. Step 2's read files
/// are `ImportFileRow`s in the Files group.
struct ImportFileSlot: View {
    enum State: Equatable {
        /// Step 1's hint: "Plans file · Optional".
        case empty(title: String, systemImage: String)
        case reading(name: String, progress: String?)
    }

    let state: State

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ImportLayout.lineGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GroupedListSpec.rowSpacing))
        layout {
            Image(systemName: glyph)
                .font(.system(size: ImportLayout.slotGlyph, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.actionGlyphOpacity))
                .frame(width: IconDisc.regularDiameter)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .reading = state {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(ImportProgressBarSpec.trackOpacity))
                        .frame(height: 2)
                        .padding(.vertical, 4)
                }
                Text(verbatim: caption)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(maxWidth: .infinity, minHeight: ImportLayout.slotHeight, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
        .contentShape(RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(caption)"))
    }

    private var glyph: String {
        switch state {
        case let .empty(_, systemImage): systemImage
        case .reading: "doc.text"
        }
    }

    private var title: String {
        switch state {
        case let .empty(title, _): title
        case let .reading(name, _): name
        }
    }

    private var caption: String {
        switch state {
        case .empty: String(localized: "Optional")
        case let .reading(_, progress):
            progress ?? String(localized: "Reading…", comment: "Training import: a file is being read.")
        }
    }
}

/// A file in step 2's Files group (D6; c-23b): the document in an icon disc, the name, what it holds or why it failed on the
/// detail line, and a 44 × 44 ✕ that removes it. A failed file's disc shows the attention glyph in `warning`, with the
/// reason in words. At accessibility sizes the disc goes above the text and the ✕ under it.
struct ImportFileRow: View {
    let file: ImportPickedFile
    let onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ImportLayout.lineGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GroupedListSpec.rowSpacing))
        layout {
            disc
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                Text(verbatim: file.name)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: file.rowDetail)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(file.name), \(file.rowDetail)"))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: GroupedListSpec.checkmarkSize, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.actionGlyphOpacity))
                    .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, typeSize.isAccessibilitySize ? 0 : -GroupedListSpec.textPadding)
            .padding(.leading, typeSize.isAccessibilitySize ? -GroupedListSpec.textPadding : 0)
            .accessibilityLabel(Text("Remove file", comment: "Training import, step 2: remove a file from the import."))
            .accessibilityValue(Text(verbatim: file.name))
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var disc: some View {
        if file.problem != nil {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: IconDisc.glyphSize, weight: .light))
                .foregroundStyle(Theme.warning)
                .frame(width: IconDisc.regularDiameter, height: IconDisc.regularDiameter)
                .overlay { Circle().strokeBorder(Theme.textPrimary.opacity(IconDisc.ringOpacity), lineWidth: IconDisc.ringWidth) }
                .accessibilityHidden(true)
        } else {
            IconDisc(systemImage: "doc.text")
        }
    }
}

extension ImportPickedFile {
    /// A file row's detail (D6): what the file holds, in the summary's words ("1 plan · 2 days · 6 exercises", "4 workouts"),
    /// or why it failed.
    var rowDetail: String {
        switch status {
        case .reading: String(localized: "Reading…", comment: "Training import: a file is being read.")
        case let .read(bundle, _): Self.holds(ImportSummary(bundle))
        case let .failed(problem): problem.shortReason
        }
    }

    private static func holds(_ summary: ImportSummary) -> String {
        var parts: [String] = []
        if let plans = ImportSummaryText.plans(summary) { parts.append(plans) }
        if summary.workouts > 0 {
            parts.append(String(localized: "\(summary.workouts) workouts", comment: "Training import: a count of workouts."))
        }
        return parts.isEmpty
            ? String(localized: "No plan and no workouts", comment: "Training import, step 2: a recognised file that holds nothing.")
            : parts.joined(separator: " · ")
    }
}

extension ImportFileProblem {
    /// A file row's reason in step 2.
    var shortReason: String {
        switch self {
        case .notCSV: String(localized: "Not a CSV file", comment: "Training import, step 2: why a file can't be read.")
        case .tooLarge: String(localized: "Larger than 8 MB", comment: "Training import, step 2: why a file can't be read.")
        case .unreadable: String(localized: "Couldn't be read", comment: "Training import, step 2: why a file can't be read.")
        case .empty: String(localized: "Empty", comment: "Training import, step 2: why a file can't be read.")
        case .notSupported: String(localized: "Not a supported format", comment: "Training import, step 2: why a file can't be read.")
        }
    }

    /// The message for a file (ui.md P3 to P6): the headline with the file's name, a caption, and the one action.
    func message(name: String) -> (text: String, caption: String?, systemImage: String, retry: String) {
        let another = String(localized: "Choose another file", comment: "Training import: pick a different file.")
        switch self {
        case .notCSV:
            return (String(localized: "“\(name)” isn't a CSV file.", comment: "Training import P3; the file's name."),
                    String(localized: "RYFT can read CSV and plain text files.", comment: "Training import P3."),
                    "doc.badge.ellipsis", another)
        case .tooLarge:
            return (String(localized: "“\(name)” is larger than 8 MB.", comment: "Training import P4; the file's name."),
                    String(localized: "Training exports are usually well under 1 MB. Is this the right file?",
                           comment: "Training import P4."),
                    "doc.badge.ellipsis", another)
        case .unreadable:
            return (String(localized: "RYFT couldn't read “\(name)”.", comment: "Training import P5; the file's name."),
                    String(localized: "If it's in iCloud Drive, open Files and let it finish downloading, then try again.",
                           comment: "Training import P5."),
                    "exclamationmark.circle",
                    String(localized: "Try again"))
        case .empty:
            return (String(localized: "“\(name)” is empty.", comment: "Training import P6; the file's name."), nil,
                    "doc", another)
        case .notSupported:
            return (String(localized: "RYFT can import exports from Alpha Progression. “\(name)” doesn't look like one.",
                           comment: "Training import D5; the file's name. Alpha Progression is a data source, named factually."),
                    String(localized: "More apps may come. Nothing was imported.", comment: "Training import D5."),
                    "questionmark.folder", another)
        }
    }
}

#Preview("File slots and rows", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: ImportLayout.slotSpacing) {
            ImportFileSlot(state: .empty(title: "Plans file", systemImage: "list.bullet.rectangle"))
            ImportFileSlot(state: .reading(name: "Upper-Lower_Workouts.csv", progress: nil))
            GroupedCard(Text(verbatim: "Files")) {
                ForEach(ImportMockData.bothFiles + [ImportPickedFile(id: 2, name: "notes.txt", status: .failed(.notSupported))]) {
                    ImportFileRow(file: $0) {}
                }
            }
        }
    }
}

#Preview("File slots and rows · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: ImportLayout.slotSpacing) {
            ImportFileSlot(state: .empty(title: "Workouts file", systemImage: "clock.arrow.circlepath"))
            GroupedCard(Text(verbatim: "Files")) {
                ForEach(ImportMockData.bothFiles) { ImportFileRow(file: $0) {} }
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
