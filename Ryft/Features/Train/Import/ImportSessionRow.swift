import SwiftUI

/// One imported workout in step 5's history (ui.md §8.1): its day, title and counts, and a 44 pt include control. A
/// workout that looks like one already logged says so in words and starts off; one already imported has no control.
/// The row opens its sets; VoiceOver reads the control as one switch with the whole sentence. Look (PR 6 C §4.14): a row of
/// its month's grouped card; the include control is the ink check (filled when included, an outline circle when not) and
/// says "Included" or "Skipped" to VoiceOver, never colour alone.
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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ImportLayout.lineGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GroupedListSpec.rowSpacing))
        layout {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: GroupedListSpec.rowSpacing) {
                    if isDuplicate {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: GroupedListSpec.checkmarkSize, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                        Text(verbatim: ImportPreviewText.dayAndTitle(preview, zone: zone))
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: ImportPreviewText.counts(preview))
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
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
                // The row's padding is inside the button, so the whole row's height opens it (44 pt and more).
                .padding(.vertical, GroupedListSpec.textPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: ImportPreviewText.dayAndTitle(preview, zone: zone)))
            .accessibilityHint(Text("Shows its exercises and sets", comment: "Training import, step 5, VoiceOver: a workout row."))
            control
        }
        .padding(.leading, GroupedListSpec.rowInset)
        .padding(.trailing, preview.verdict.isToggleable && !typeSize.isAccessibilitySize ? GroupedListSpec.rowInset - 10 : GroupedListSpec.rowInset)
        .padding(.bottom, typeSize.isAccessibilitySize ? GroupedListSpec.textPadding : 0)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
    }

    private struct Note: Hashable {
        let text: String
        let strong: Bool
    }

    private var notes: [Note] {
        var out: [Note] = []
        if preview.skippedSetCount > 0 {
            out.append(Note(text: String(localized: "\(preview.skippedSetCount)\u{00A0}sets skipped",
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
                Image(systemName: "checkmark").accessibilityHidden(true)
                Text("Already imported", comment: "Training import, step 5: the workout's id is already in RYFT.")
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize()
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
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(isIncluded ? Theme.textPrimary : Theme.textTertiary)
                }
                .frame(minWidth: Theme.Metrics.minHitTarget, minHeight: Theme.Metrics.minHitTarget)
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
                     String(localized: "\(preview.setCount)\u{00A0}sets", comment: "Training import: a count of sets.")]
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
    return DarkPreview {
        GroupedCard {
            ForEach(Array(build.sessions.prefix(4).enumerated()), id: \.offset) { index, preview in
                ImportSessionRow(preview: preview, isIncluded: build.defaultIncluded.contains(preview.id), index: index,
                                 zone: ImportMockData.zone, onToggle: { _ in }, onOpen: {})
            }
        }
    }
}

#Preview("Session rows · AX3", traits: .sizeThatFitsLayout) {
    let build = ImportMockData.build()
    return DarkPreview {
        GroupedCard {
            ForEach(Array(build.sessions.prefix(2).enumerated()), id: \.offset) { index, preview in
                ImportSessionRow(preview: preview, isIncluded: build.defaultIncluded.contains(preview.id), index: index,
                                 zone: ImportMockData.zone, onToggle: { _ in }, onOpen: {})
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
