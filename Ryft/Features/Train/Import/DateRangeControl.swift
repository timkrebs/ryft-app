import SwiftUI

/// Step 3's history range (ui.md §6): a menu of presets, From and Until for a custom range (limited to the file's first
/// and last day), and the result in figures underneath. Dates are the file's days in the flow's zone.
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
        VStack(alignment: .leading, spacing: 10) {
            Picker(selection: $preset) {
                ForEach(ImportSelection.RangePreset.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Range", comment: "Training import, step 3: the history range picker.")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .frame(minHeight: 44)
            .accessibilityValue(Text(verbatim: "\(preset.title), \(result)"))
            .accessibilityIdentifier("import.range")
            if preset == .custom {
                VStack(spacing: 4) {
                    DatePicker(selection: binding($from), in: dateLimits, displayedComponents: .date) {
                        Text("From").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    }
                    DatePicker(selection: binding($to), in: dateLimits, displayedComponents: .date) {
                        Text("Until")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .environment(\.timeZone, zone)
                .transition(.opacity)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Theme.warning)
                        .accessibilityHidden(true)
                }
                Text(verbatim: result)
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: preset)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: result)
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
    return SchemePair { Demo() }
}
