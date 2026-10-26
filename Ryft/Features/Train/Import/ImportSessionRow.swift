import SwiftUI

/// One imported workout in step 5's history (ui.md §8.1): its day, title and counts, and a 44 pt include control. A
/// workout that looks like one already logged says so in words and starts off; one already imported has no control.
/// The row opens its sets; VoiceOver reads the control as one switch with the whole sentence.
struct ImportSessionRow: View {
    let preview: ImportSessionPreview
    let isIncluded: Bool
    let index: Int
    let zone: TimeZone
    let onToggle: (Bool) -> Void
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isDuplicate: Bool {
        if case .duplicate = preview.verdict { return true }
        return false
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 10) {
                    if isDuplicate {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: ImportPreviewText.dayAndTitle(preview, zone: zone))
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: ImportPreviewText.counts(preview))
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(notes, id: \.self) { note in
                            Text(verbatim: note.text)
                                .font(.ryft(.caption))
                                .monospacedDigit()
                                .foregroundStyle(note.strong ? Theme.textPrimary : Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: ImportPreviewText.dayAndTitle(preview, zone: zone)))
            .accessibilityHint(Text("Shows its exercises and sets", comment: "Training import, step 5, VoiceOver: a workout row."))
            control
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Note: Hashable {
        let text: String
        let strong: Bool
    }

    private var notes: [Note] {
        var out: [Note] = []
        if preview.skippedSetCount > 0 {
            out.append(Note(text: String(localized: "\(preview.skippedSetCount) sets skipped",
                                         comment: "Training import, step 5: sets with no weight or reps."), strong: false))
        }
        if isDuplicate {
            out.append(Note(text: String(localized: "Looks like a session you already logged",
                                         comment: "Training import, step 5: a likely duplicate (V2)."), strong: true))
            if isIncluded {
                out.append(Note(text: String(localized: "Will be imported next to your own session.",
                                             comment: "Training import, step 5: a duplicate turned on."), strong: false))
            }
        }
        if preview.clockChange != nil {
            out.append(Note(text: String(localized: "Clock change", comment: "Training import, step 5: the start fell on a DST change."),
                            strong: false))
        }
        return out
    }

    @ViewBuilder
    private var control: some View {
        if preview.verdict == .alreadyImported {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle").accessibilityHidden(true)
                Text("Already imported", comment: "Training import, step 5: the workout's id is already in RYFT.")
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
        } else if preview.verdict.isToggleable {
            Button {
                onToggle(!isIncluded)
            } label: {
                HStack(spacing: 6) {
                    if typeSize.isAccessibilitySize {
                        Text(verbatim: stateWord)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isIncluded ? Theme.accent : Theme.textTertiary)
                }
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: ImportPreviewText.spoken(preview, zone: zone, duplicate: isDuplicate)))
            .accessibilityValue(Text(verbatim: stateWord))
            .accessibilityAddTraits(.isToggle)
            .accessibilityIdentifier("import.session.\(index).toggle")
        }
    }

    private var stateWord: String {
        isIncluded ? String(localized: "Included", comment: "Training import, step 5: the workout is imported.")
            : String(localized: "Skipped", comment: "Training import, step 4: a row's status.")
    }
}

/// Step 5's words (ui.md §8.1, §11).
enum ImportPreviewText {
    /// "Sun 27 Apr · Upper".
    static func dayAndTitle(_ preview: ImportSessionPreview, zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        let day = preview.day.date(in: zone).formatted(Date.FormatStyle(locale: locale, timeZone: zone).weekday(.abbreviated).day().month(.abbreviated))
        guard let title = preview.session?.title, !title.isEmpty else { return day }
        return "\(day) · \(title)"
    }

    /// "9 exercises · 31 sets · 11,420 kg".
    static func counts(_ preview: ImportSessionPreview) -> String {
        var parts = [String(localized: "\(preview.exerciseCount) exercises"),
                     String(localized: "\(preview.setCount) sets", comment: "Training import: a count of sets.")]
        if preview.volumeKg > 0 { parts.append(Fmt.volume(preview.volumeKg)) }
        return parts.joined(separator: " · ")
    }

    /// "27 April, Upper, 3 exercises, 8 sets, 1,420 kg[, looks like a session you already logged]".
    static func spoken(_ preview: ImportSessionPreview, zone: TimeZone, duplicate: Bool) -> String {
        let day = preview.day.date(in: zone).formatted(Date.FormatStyle(timeZone: zone).day().month(.wide))
        var parts = [day]
        if let title = preview.session?.title, !title.isEmpty { parts.append(title) }
        parts.append(counts(preview).replacingOccurrences(of: " · ", with: ", "))
        if duplicate {
            parts.append(String(localized: "Looks like a session you already logged",
                                comment: "Training import, step 5: a likely duplicate (V2)."))
        }
        return parts.joined(separator: ", ")
    }

    /// "June 2026": the month groups, in the flow's zone.
    static func month(_ day: LocalDate, zone: TimeZone) -> String {
        day.date(in: zone).formatted(Date.FormatStyle(timeZone: zone).month(.wide).year())
    }
}

#Preview("Session rows", traits: .sizeThatFitsLayout) {
    let build = ImportMockData.build()
    return SchemePair {
        VStack(spacing: 0) {
            ForEach(Array(build.sessions.prefix(4).enumerated()), id: \.offset) { index, preview in
                ImportSessionRow(preview: preview, isIncluded: build.defaultIncluded.contains(preview.id), index: index,
                                 zone: ImportMockData.zone, onToggle: { _ in }, onOpen: {})
                Divider().overlay(Theme.separator)
            }
        }
    }
}

#Preview("Session rows · AX3", traits: .sizeThatFitsLayout) {
    let build = ImportMockData.build()
    return SchemePair {
        VStack(spacing: 0) {
            ForEach(Array(build.sessions.prefix(2).enumerated()), id: \.offset) { index, preview in
                ImportSessionRow(preview: preview, isIncluded: build.defaultIncluded.contains(preview.id), index: index,
                                 zone: ImportMockData.zone, onToggle: { _ in }, onOpen: {})
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
