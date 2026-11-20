import SwiftUI

/// Step 3's history range (ui.md §6; PR 6 C §4.14) as rows of the history group: a menu row of presets with the result in
/// figures on its detail line ("10 workouts from 2 Mar to 27 Apr 2026", or "0 workouts in this range" after the attention
/// glyph), and for a custom range From and Until with compact date pickers (limited to the file's first and last day).
/// Dates are the file's days in the flow's zone. At accessibility sizes the menu row's value goes under its title.
struct DateRangeControl: View {
    @Binding var preset: ImportSelection.RangePreset
    @Binding var from: LocalDate
    @Binding var to: LocalDate
    /// The file's first and last day.
    let limits: ClosedRange<LocalDate>
    let zone: TimeZone
    /// "10 workouts from 2 Mar to 27 Apr 2026", or "0 workouts in this range".
    let result: String
    let isEmpty: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GroupedRow.menu(Text("Range", comment: "Training import, step 3: the history range picker."),
                        value: Text(verbatim: preset.title), detail: resultText, identifier: "import.range") {
            Picker(selection: $preset) {
                ForEach(ImportSelection.RangePreset.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Range", comment: "Training import, step 3: the history range picker.")
            }
        }
        // What the row says: the preset and the result's words; the empty range's glyph is drawn, not read.
        .accessibilityValue(Text(verbatim: "\(preset.title), \(result)"))
        .animation(Theme.Motion.respecting(reduceMotion), value: result)
        if preset == .custom {
            dateRow(Text("From"), day: $from)
            dateRow(Text("Until"), day: $to)
        }
    }

    /// The result, after the attention glyph when the range holds no workout (the words say it too, so VoiceOver gets the
    /// words alone: see the row's value).
    private var resultText: Text {
        guard isEmpty else { return Text(verbatim: result) }
        return Text(Image(systemName: "exclamationmark.circle")).foregroundStyle(Theme.warning) + Text(verbatim: " \(result)")
    }

    private func dateRow(_ title: Text, day: Binding<LocalDate>) -> some View {
        GroupedRow.custom(title) {
            DatePicker(selection: binding(day), in: dateLimits, displayedComponents: .date) { title }
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, zone)
        }
        .transition(.opacity)
    }

    private var dateLimits: ClosedRange<Date> {
        limits.lowerBound.date(in: zone)...max(limits.lowerBound.date(in: zone), limits.upperBound.date(in: zone))
    }

    private func binding(_ day: Binding<LocalDate>) -> Binding<Date> {
        Binding(get: { day.wrappedValue.date(in: zone) },
                set: { if let new = LocalDate($0, in: zone) { day.wrappedValue = new } })
    }
}

#Preview("Date range", traits: .sizeThatFitsLayout) {
    struct Demo: View {
        @State var preset = ImportSelection.RangePreset.custom
        @State var from = ImportMockData.day(2026, 3, 2)
        @State var to = ImportMockData.day(2026, 4, 27)
        var body: some View {
            DateRangeControl(preset: $preset, from: $from, to: $to,
                             limits: ImportMockData.day(2026, 3, 2)...ImportMockData.day(2026, 4, 27),
                             zone: ImportMockData.zone, result: "10 workouts from 2 Mar to 27 Apr 2026", isEmpty: false)
        }
    }
    return DarkPreview { GroupedCard { Demo() } }
}

#Preview("Date range · AX5", traits: .sizeThatFitsLayout) {
    struct Demo: View {
        @State var preset = ImportSelection.RangePreset.allTime
        @State var from = ImportMockData.day(2026, 3, 2)
        @State var to = ImportMockData.day(2026, 4, 27)
        var body: some View {
            DateRangeControl(preset: $preset, from: $from, to: $to,
                             limits: ImportMockData.day(2026, 3, 2)...ImportMockData.day(2026, 4, 27),
                             zone: ImportMockData.zone, result: "10 workouts from 2 Mar to 27 Apr 2026", isEmpty: false)
        }
    }
    return DarkPreview { GroupedCard { Demo() } }
        .environment(\.dynamicTypeSize, .accessibility5)
}
