import SwiftUI

/// Step 2's warnings (ui.md §5, D4): a disclosure row "3 lines couldn't be read" (notes on a second line), expanding to
/// "Line 41 · This line isn't recognised" rows. A warning is a line and a kind, never file text. At most 20 rows, then
/// "and N more". With several files, each file's name heads its lines. Look (PR 6 C §4.14): a surface card at the grouped
/// list's radius; the attention glyph in `warning` beside the words, never the colour alone.
struct ImportWarningsList: View {
    let detection: ImportDetection
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let shownRows = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.Motion.respecting(reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: GroupedListSpec.rowSpacing) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: GroupedListSpec.glyphSize, weight: .regular))
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                        Text(verbatim: title)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: subtitle)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: GroupedListSpec.chevronSize, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, GroupedListSpec.textPadding + 2)
                .frame(minHeight: GroupedListSpec.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("import.warnings")
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups, id: \.file) { group in
                        if detection.files.count > 1, let name = detection.name(ofFile: group.file) {
                            Text(verbatim: name)
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, warning in
                            row(warning)
                        }
                    }
                    if hiddenCount > 0 {
                        Text("and \(hiddenCount) more", comment: "Training import, step 2: warnings not listed.")
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, GroupedListSpec.rowInset - 4)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: GroupedListSpec.cardRadius, style: .continuous))
    }

    private func row(_ warning: ImportWarning) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Line \(warning.at.line)", comment: "Training import, step 2: a warning's line number.")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 64, alignment: .leading)
            Text(warning.message)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var problems: Int { detection.problems.count }
    private var notes: Int { detection.notes.count }

    /// Counts only warnings that dropped something; notes are the second line.
    private var title: String {
        if problems == 0 {
            return String(localized: "\(notes) notes", comment: "Training import, step 2: a count of notes (assumptions, no lost lines).")
        }
        return String(localized: "\(problems) lines couldn't be read", comment: "Training import, step 2: the warnings row.")
    }

    private var subtitle: String {
        let rest = String(localized: "The rest imports normally.", comment: "Training import, step 2: under the warnings row.")
        guard problems > 0, notes > 0 else { return rest }
        return String(localized: "The rest imports normally, and \(notes) notes.",
                      comment: "Training import, step 2: under the warnings row, when some lines couldn't be read and there are notes too. One sentence, so its word order is the language's.")
    }

    private var shown: [ImportWarning] {
        Array((detection.bundle?.warnings ?? []).prefix(Self.shownRows))
    }

    private var hiddenCount: Int {
        (detection.bundle?.warnings.count ?? 0) - shown.count + detection.suppressedWarnings
    }

    private var groups: [(file: Int, rows: [ImportWarning])] {
        var out: [(file: Int, rows: [ImportWarning])] = []
        for warning in shown {
            if out.last?.file == warning.at.file {
                out[out.count - 1].rows.append(warning)
            } else {
                out.append((warning.at.file, [warning]))
            }
        }
        return out
    }
}

#Preview("Warnings", traits: .sizeThatFitsLayout) {
    struct Demo: View {
        @State var open = false
        @State var expanded = true
        let detection = ImportDetection(files: ImportMockData.withWarnings(ImportMockData.bothFiles))
        var body: some View {
            VStack(spacing: 12) {
                ImportWarningsList(detection: detection, isExpanded: $open)
                ImportWarningsList(detection: detection, isExpanded: $expanded)
            }
        }
    }
    return DarkPreview { Demo() }
}
