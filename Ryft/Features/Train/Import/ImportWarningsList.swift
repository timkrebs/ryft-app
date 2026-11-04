import SwiftUI

/// Step 2's warnings (ui.md §5, D4): a disclosure row "3 lines couldn't be read" (notes on a second line), expanding to
/// "Line 41 · This line isn't recognised" rows. A warning is a line and a kind, never file text. At most 20 rows, then
/// "and N more". With several files, each file's name heads its lines.
struct ImportWarningsList: View {
    let detection: ImportDetection
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let shownRows = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: title)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: subtitle)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(14)
                .frame(minHeight: 44)
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
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
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
        return rest + " " + String(localized: "and \(notes) notes", comment: "Training import, step 2: notes after the warnings count.")
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
    return SchemePair { Demo() }
}
